#!/usr/bin/env bash
#
# K3s cluster installer (DevSecOps module, CN1 / CN2 on AWS)
#
#   Control plane (CN1):  sudo ./install-k3s.sh --control-plane
#   Worker       (CN2):   sudo ./install-k3s.sh --worker \
#                             --url https://<control-plane-ip>:6443 --token <token>
#
# --control-plane prints the join URL, the node token and the exact worker
# command. Kubernetes terminology (control plane / worker) is used throughout;
# K3s' own "server / agent" wording is mapped internally.
#
# kubeadm alternative: see install-k8s.sh
#

set -euo pipefail

# ============================================================================
# Common Helper Functions
# The same helpers are used in every bash script in this repo, so the
# scripts stay consistent while remaining standalone single-file downloads.
# Function names follow the PowerShell Verb-Noun convention.
# ============================================================================

# shellcheck disable=SC2034  # not every script uses every color
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' \
         BLUE='\033[0;34m' PURPLE='\033[0;35m' BOLD='\033[1m' NC='\033[0m'

# Optional plain-text logfile; set LOG_FILE after this block to enable.
LOG_FILE="${LOG_FILE:-}"

# Usage: Write-Log <INFO|SUCCESS|WARN|ERROR|STEP> "message"
Write-Log() {
    local level=$1; shift
    local color=$NC
    case $level in
        INFO)    color=$BLUE ;;
        SUCCESS) color=$GREEN ;;
        WARN)    color=$YELLOW ;;
        ERROR)   color=$RED ;;
        STEP)    color=$PURPLE ;;
    esac
    if [[ $level == ERROR ]]; then
        echo -e "${color}[$level]${NC} $*" >&2
    else
        echo -e "${color}[$level]${NC} $*"
    fi
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$level] $*" >> "$LOG_FILE"
    fi
}

# Usage: Stop-Script "fatal message"
Stop-Script() {
    Write-Log ERROR "$1"
    exit 1
}

# Usage: Test-Root  (exits unless running as root)
Test-Root() {
    [[ $EUID -eq 0 ]] || Stop-Script "Run as root (sudo)."
}

# Usage: mgr=$(Get-PkgMgr)  ->  apt | dnf | pacman | unknown
Get-PkgMgr() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Usage: os_id=$(Get-OsId)  ->  lowercase /etc/os-release ID (ubuntu, debian,
# fedora, arch, ...) or "unknown". Call in $(...) so sourcing stays contained.
Get-OsId() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        local os_id="${ID:-unknown}"
        echo "${os_id,,}"
    else
        echo "unknown"
    fi
}

# Usage: Invoke-Cmd command [args...]
# Logs the command, sends its output to LOG_FILE when set, aborts on failure.
Invoke-Cmd() {
    Write-Log INFO "Executing: $*"
    if [[ -n "$LOG_FILE" ]]; then
        "$@" >> "$LOG_FILE" 2>&1 || Stop-Script "Command failed: '$*'. Check log: $LOG_FILE"
    else
        "$@" || Stop-Script "Command failed: '$*'"
    fi
}

# === Settings ===
LOG_FILE="/tmp/k3s_install_$(date +%Y%m%d_%H%M%S).log"
INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}"  # optional pin, e.g. v1.36.4+k3s1
export INSTALL_K3S_VERSION

ROLE=""
SERVER_URL=""
JOIN_TOKEN=""

# === Usage ===
Show-Usage() {
    cat <<EOF
Usage: $0 --control-plane
       $0 --worker --url https://<control-plane-ip>:6443 --token <token>

  --control-plane   Install the first K3s node (control plane).
  --worker          Join this node to the cluster as a worker.
  --url <url>       Worker only: control-plane API URL (or a bare IP/host).
  --token <token>   Worker only: node token from the control plane.
  -h, --help        Show this help.
EOF
}

# === Parse arguments ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        --control-plane) ROLE="control-plane"; shift ;;
        --worker)        ROLE="worker"; shift ;;
        --url)           SERVER_URL="${2:-}"; shift 2 ;;
        --token)         JOIN_TOKEN="${2:-}"; shift 2 ;;
        -h|--help)       Show-Usage; exit 0 ;;
        *)               Show-Usage; Stop-Script "Unknown argument: $1" ;;
    esac
done

[[ -n "$ROLE" ]] || { Show-Usage; Stop-Script "Pass --control-plane or --worker."; }

# === Root check ===
Test-Root

# === Already installed? ===
if command -v k3s &>/dev/null; then
    Write-Log WARN "K3s is already installed: $(k3s --version | head -n1)"
    Write-Log INFO "Uninstall with k3s-uninstall.sh (control plane) or k3s-agent-uninstall.sh (worker)."
    exit 0
fi

# get.k3s.io is Rancher's official install path; it is a remote script.
Write-Log WARN "Fetching and running the official installer from https://get.k3s.io"

if [[ "$ROLE" == "control-plane" ]]; then
    # === Control plane ===
    Write-Log STEP "Installing K3s control plane"
    curl -sfL https://get.k3s.io | sh - >> "$LOG_FILE" 2>&1 || \
        Stop-Script "K3s install failed. Check log: $LOG_FILE"
    Invoke-Cmd systemctl enable k3s

    Write-Log INFO "Waiting for the node to become Ready..."
    for _ in $(seq 1 45); do
        k3s kubectl get node 2>/dev/null | grep -q ' Ready ' && break
        sleep 2
    done
    k3s kubectl get node || Write-Log WARN "Node not Ready yet; re-check with 'sudo k3s kubectl get node'."

    NODE_IP=$(hostname -I | awk '{print $1}')
    NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "unavailable")
    K3S_VER=$(k3s --version 2>/dev/null | head -n1) || K3S_VER="N/A"

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "K3s control plane ready!"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}K3s:${NC}          ${GREEN}${K3S_VER}${NC}"
    echo -e "${BLUE}API URL:${NC}      ${GREEN}https://${NODE_IP}:6443${NC}"
    echo -e "${BLUE}Node token:${NC}   ${GREEN}${NODE_TOKEN}${NC}"
    echo -e "${BLUE}kubeconfig:${NC}   ${GREEN}/etc/rancher/k3s/k3s.yaml${NC}"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Join a worker (run on CN2)${NC}"
    echo -e "  sudo ./install-k3s.sh --worker \\"
    echo -e "      --url https://${NODE_IP}:6443 --token ${NODE_TOKEN}"
    echo ""
    echo -e "${YELLOW}AWS:${NC} open TCP 6443 (API) and 30000 (app NodePort) inbound in the security group."
else
    # === Worker ===
    [[ -n "$SERVER_URL"  ]] || Stop-Script "Worker needs --url https://<control-plane-ip>:6443"
    [[ -n "$JOIN_TOKEN"  ]] || Stop-Script "Worker needs --token <node token from the control plane>"
    [[ "$SERVER_URL" == https://* ]] || SERVER_URL="https://${SERVER_URL}:6443"

    Write-Log STEP "Joining ${SERVER_URL} as a worker"
    curl -sfL https://get.k3s.io | K3S_URL="$SERVER_URL" K3S_TOKEN="$JOIN_TOKEN" sh - >> "$LOG_FILE" 2>&1 || \
        Stop-Script "K3s worker install failed. Check log: $LOG_FILE"
    Invoke-Cmd systemctl enable k3s-agent

    K3S_VER=$(k3s --version 2>/dev/null | head -n1) || K3S_VER="N/A"

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "K3s worker joined!"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}K3s:${NC}          ${GREEN}${K3S_VER}${NC}"
    echo -e "${BLUE}Joined:${NC}       ${GREEN}${SERVER_URL}${NC}"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Verify on the control plane (CN1)${NC}"
    echo -e "  sudo k3s kubectl get node        # this node should be Ready within ~30s"
fi
