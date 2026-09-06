#!/usr/bin/env bash
#
# K3s Masternode Installer (CN1 / control-plane)
#
# Installs a K3s server node, waits for it to become Ready and prints the
# join details (server URL + node token) plus the exact one-liner to run
# on each workernode. Run as root on CN1.
#
# Handleiding "DevSecOps module launch environment", p.4:
#   curl -sfL https://get.k3s.io | sh -
#   sudo k3s kubectl get node
#   sudo cat /var/lib/rancher/k3s/server/node-token
#
# Workernode: see install-k3s-worker.sh
# kubeadm alternative: see install-kubeadm.sh
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
LOG_FILE="/tmp/k3s_master_install_$(date +%Y%m%d_%H%M%S).log"
INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}"  # optional pin, e.g. v1.31.4+k3s1
export INSTALL_K3S_VERSION

# === Root check ===
Test-Root

# === Already installed? ===
if command -v k3s &>/dev/null; then
    Write-Log WARN "K3s is already installed: $(k3s --version | head -n1)"
    Write-Log INFO "Uninstall with: /usr/local/bin/k3s-uninstall.sh"
    exit 0
fi

# === Install K3s (server) ===
# get.k3s.io is Rancher's official install path; it is a remote script.
Write-Log WARN "Fetching and running the official installer from https://get.k3s.io"
Write-Log STEP "Installing K3s server"
curl -sfL https://get.k3s.io | sh - >> "$LOG_FILE" 2>&1 || \
    Stop-Script "K3s install failed. Check log: $LOG_FILE"

Invoke-Cmd systemctl enable k3s

# === Wait for the node to be Ready (~30s) ===
Write-Log INFO "Waiting for the node to become Ready..."
for _ in $(seq 1 45); do
    k3s kubectl get node 2>/dev/null | grep -q ' Ready ' && break
    sleep 2
done
k3s kubectl get node || Write-Log WARN "Node not Ready yet; re-check with 'sudo k3s kubectl get node'."

# === Join details ===
NODE_IP=$(hostname -I | awk '{print $1}')
NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "unavailable")
K3S_VER=$(k3s --version 2>/dev/null | head -n1) || K3S_VER="N/A"

# === Summary ===
echo -e "\n${GREEN}==============================================================${NC}"
Write-Log SUCCESS "K3s masternode (CN1) ready!"
echo -e "${GREEN}==============================================================${NC}\n"
echo -e "${BLUE}K3s:${NC}          ${GREEN}${K3S_VER}${NC}"
echo -e "${BLUE}Server URL:${NC}   ${GREEN}https://${NODE_IP}:6443${NC}"
echo -e "${BLUE}Node token:${NC}   ${GREEN}${NODE_TOKEN}${NC}"
echo -e "${BLUE}kubeconfig:${NC}   ${GREEN}/etc/rancher/k3s/k3s.yaml${NC}"
echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
echo ""
echo -e "${BOLD}Run this on each workernode (CN2)${NC}"
echo -e "  sudo K3S_URL=https://${NODE_IP}:6443 K3S_TOKEN=${NODE_TOKEN} ./install-k3s-worker.sh"
echo ""
echo -e "${BOLD}Use kubectl${NC}"
echo -e "  sudo k3s kubectl get node        # or: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
echo ""
echo -e "${YELLOW}AWS:${NC} open TCP 6443 (cluster API) and 30000 (app NodePort) inbound in the security group."
