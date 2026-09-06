#!/usr/bin/env bash
#
# K3s cluster installer (DevSecOps module, CN1 / CN2 on AWS)
#
# Installs K3s via the official installer at https://get.k3s.io. The installer
# bundles containerd, so it works on any systemd-based Linux without a distro
# package manager. Kubernetes role names are used (control plane / worker);
# K3s' own "server / agent" wording is mapped internally.
#
#   Control plane (CN1):  sudo ./install-k3s.sh --control-plane
#   Worker       (CN2):   sudo ./install-k3s.sh --worker \
#                             --url https://<control-plane-ip>:6443 --token <token>
#
# kubeadm alternative: see install-k8s.sh
# Run as root.
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

# ============================================================================
# Usage
# ============================================================================

Show-Usage() {
    cat <<'EOF'
Usage: install-k3s.sh <role> [options]

Roles:
  --control-plane   Install the first K3s node (control plane, CN1)
  --worker          Join this node to the cluster as a worker (CN2)

Options (worker):
  --url URL         Control-plane API URL, or a bare IP/host (-> https://IP:6443)
  --token VALUE     Join value from the control plane
                    (/var/lib/rancher/k3s/server/node-token)

Other:
  -h, --help        Show this help

After a --control-plane install the summary prints the join value and the
exact --worker command to run on CN2.

Examples:
  sudo ./install-k3s.sh --control-plane
  sudo ./install-k3s.sh --worker --url https://10.0.0.1:6443 --token K10abc...
EOF
}

# === Settings ===
LOG_FILE="/tmp/k3s_install_$(date +%Y%m%d_%H%M%S).log"

# K3s release to install. get.k3s.io reads INSTALL_K3S_VERSION; override with
# INSTALL_K3S_VERSION= to track latest stable. Bump this manually.
K3S_VERSION="${INSTALL_K3S_VERSION:-v1.36.4+k3s1}"

# === Commands ===

# Usage: Install-ControlPlane
Install-ControlPlane() {
    Write-Log INFO "Installing K3s ${K3S_VERSION:-latest} (control plane)"

    # get.k3s.io is Rancher's official install path; it is a remote script.
    Write-Log WARN "Fetching and running the official installer from https://get.k3s.io"
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - server >> "$LOG_FILE" 2>&1 || \
        Stop-Script "K3s install failed. Check log: $LOG_FILE"
    Invoke-Cmd systemctl enable k3s

    Write-Log INFO "Waiting for the node to become Ready..."
    local _
    for _ in $(seq 1 45); do
        k3s kubectl get node 2>/dev/null | grep -q ' Ready ' && break
        sleep 2
    done
    k3s kubectl get node || Write-Log WARN "Node not Ready yet; re-check with 'sudo k3s kubectl get node'."

    local node_ip node_join k3s_ver
    node_ip=$(hostname -I | awk '{print $1}')
    node_join=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || true)
    k3s_ver=$(k3s --version 2>/dev/null | head -n1) || k3s_ver="N/A"

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "K3s control plane ready!"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}K3s:${NC}          ${GREEN}${k3s_ver}${NC}"
    echo -e "${BLUE}API URL:${NC}      ${GREEN}https://${node_ip}:6443${NC}"
    echo -e "${BLUE}kubeconfig:${NC}   ${GREEN}/etc/rancher/k3s/k3s.yaml${NC}"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Join a worker (run on CN2)${NC}"
    echo -e "  sudo ./install-k3s.sh --worker \\"
    echo -e "      --url https://${node_ip}:6443 --token ${node_join:-(see /var/lib/rancher/k3s/server/node-token)}"
    echo ""
    echo -e "${YELLOW}AWS:${NC} allow node-to-node traffic in the security group (self-referencing"
    echo -e "     'All traffic' rule), plus TCP 30000 inbound for the app NodePort."
}

# Usage: Install-Worker <server-url-or-ip> <join-value>
Install-Worker() {
    local url=$1 join=$2

    [[ -n "$url"  ]] || Stop-Script "Worker needs --url https://<control-plane-ip>:6443"
    [[ -n "$join" ]] || Stop-Script "Worker needs --token <value from the control plane>"
    [[ "$url" == https://* ]] || url="https://${url}:6443"
    [[ "$join" =~ ^[A-Za-z0-9:._-]+$ ]] || Stop-Script "The --token value has unexpected characters."

    Write-Log INFO "Installing K3s ${K3S_VERSION:-latest} (worker), joining ${url}"

    # get.k3s.io is Rancher's official install path; it is a remote script.
    Write-Log WARN "Fetching and running the official installer from https://get.k3s.io"
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" K3S_URL="$url" K3S_TOKEN="$join" \
        sh -s - agent >> "$LOG_FILE" 2>&1 || \
        Stop-Script "K3s agent install failed. Check log: $LOG_FILE"
    Invoke-Cmd systemctl enable k3s-agent

    local k3s_ver
    k3s_ver=$(k3s --version 2>/dev/null | head -n1) || k3s_ver="N/A"

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "K3s worker joined!"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}K3s:${NC}          ${GREEN}${k3s_ver}${NC}"
    echo -e "${BLUE}Joined:${NC}       ${GREEN}${url}${NC}"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Verify on the control plane (CN1)${NC}"
    echo -e "  sudo k3s kubectl get node        # this node should be Ready within ~30s"
}

# ============================================================================
# Main Entry Point
# ============================================================================

ROLE=""
SERVER_URL=""
JOIN_VALUE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --control-plane)
            ROLE="control-plane"; shift ;;
        --worker)
            ROLE="worker"; shift ;;
        --url)
            SERVER_URL=${2:-}
            [[ -n "$SERVER_URL" ]] || Stop-Script "--url requires a value"
            shift 2 ;;
        --token)
            JOIN_VALUE=${2:-}
            [[ -n "$JOIN_VALUE" ]] || Stop-Script "--token requires a value"
            shift 2 ;;
        -h|--help)
            Show-Usage; exit 0 ;;
        *)
            Write-Log ERROR "Unknown argument: $1"; Show-Usage; exit 1 ;;
    esac
done

Test-Root
[[ -d /run/systemd/system ]] || Stop-Script "K3s requires a systemd-based system."

if command -v k3s &>/dev/null; then
    Write-Log WARN "K3s is already installed: $(k3s --version | head -n1)"
    Write-Log INFO "Remove it first: k3s-uninstall.sh (control plane) or k3s-agent-uninstall.sh (worker)."
    exit 0
fi

case "$ROLE" in
    control-plane) Install-ControlPlane ;;
    worker)        Install-Worker "$SERVER_URL" "$JOIN_VALUE" ;;
    *)             Show-Usage; Stop-Script "Pass --control-plane or --worker." ;;
esac
