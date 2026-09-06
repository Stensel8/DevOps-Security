#!/usr/bin/env bash
#
# Kubernetes "light" Installer Script (K3s)
#
# Installs K3s, the single-binary Kubernetes distribution used in the
# DevSecOps module handleiding. Run as root on each node.
#
#   Master  (CN1):  ./install-k8s-light.sh server
#   Worker  (CN2):  K3S_URL=https://<master-ip>:6443 K3S_TOKEN=<token> \
#                       ./install-k8s-light.sh agent
#
# After a server install the summary prints the node token and the exact
# agent command to run on the workers.
#
# See install-k8s-full.sh for the kubeadm + containerd alternative.
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
LOG_FILE="/tmp/k8s_light_install_$(date +%Y%m%d_%H%M%S).log"

ROLE="${1:-server}"                       # server (master) | agent (worker)
K3S_URL="${K3S_URL:-}"                    # agent only: https://<master-ip>:6443
K3S_TOKEN="${K3S_TOKEN:-}"                # agent only: node-token from the master
INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}"  # pin a release, e.g. v1.31.4+k3s1
export INSTALL_K3S_VERSION

# === Root check ===
Test-Root

case "$ROLE" in
    server|agent) : ;;
    *) Stop-Script "Unknown role '${ROLE}'. Use 'server' (master) or 'agent' (worker)." ;;
esac

# === Already installed? ===
if command -v k3s &>/dev/null; then
    Write-Log WARN "K3s is already installed: $(k3s --version | head -n1)"
    exit 0
fi

# === Agent prerequisites ===
if [[ "$ROLE" == "agent" ]]; then
    [[ -n "$K3S_URL"   ]] || Stop-Script "Agent role needs K3S_URL=https://<master-ip>:6443"
    [[ -n "$K3S_TOKEN" ]] || Stop-Script "Agent role needs K3S_TOKEN=<node-token from the master>"
    export K3S_URL K3S_TOKEN
fi

# === Install K3s ===
# get.k3s.io is Rancher's official install path; it is a remote script.
Write-Log WARN "Fetching and running the official installer from https://get.k3s.io"
Write-Log STEP "Installing K3s (role: ${ROLE})"
curl -sfL https://get.k3s.io | sh -s - "$ROLE" >> "$LOG_FILE" 2>&1 || \
    Stop-Script "K3s install failed. Check log: $LOG_FILE"

SERVICE="k3s"
[[ "$ROLE" == "agent" ]] && SERVICE="k3s-agent"
Invoke-Cmd systemctl enable "$SERVICE"

# === Verify ===
if [[ "$ROLE" == "server" ]]; then
    Write-Log INFO "Waiting for the node to become Ready (~30s)..."
    for _ in $(seq 1 30); do
        k3s kubectl get nodes 2>/dev/null | grep -q ' Ready ' && break
        sleep 2
    done
    k3s kubectl get nodes || Write-Log WARN "Node not Ready yet; check 'k3s kubectl get nodes' shortly."

    NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "unavailable")
    NODE_IP=$(hostname -I | awk '{print $1}')
fi

# === Summary ===
K3S_VER=$(k3s --version 2>/dev/null | head -n1) || K3S_VER="N/A"

echo -e "\n${GREEN}==============================================================${NC}"
Write-Log SUCCESS "K3s ${ROLE} installed!"
echo -e "${GREEN}==============================================================${NC}\n"
echo -e "${BLUE}K3s:${NC}          ${GREEN}${K3S_VER}${NC}"
echo -e "${BLUE}kubeconfig:${NC}   ${GREEN}/etc/rancher/k3s/k3s.yaml${NC}"
echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
echo ""

if [[ "$ROLE" == "server" ]]; then
    echo -e "${BOLD}Join a worker (run on CN2)${NC}"
    echo -e "  K3S_URL=https://${NODE_IP}:6443 K3S_TOKEN=${NODE_TOKEN} \\"
    echo -e "      ./install-k8s-light.sh agent"
    echo ""
    echo -e "${BOLD}Use kubectl${NC}"
    echo -e "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml   # or: k3s kubectl ..."
    echo ""
    echo -e "${YELLOW}AWS:${NC} open TCP 6443 (cluster API) and 30000 (app NodePort) in the security group."
fi
