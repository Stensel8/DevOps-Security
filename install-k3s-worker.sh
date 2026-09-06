#!/usr/bin/env bash
#
# K3s Workernode Installer (CN2 / agent)
#
# Joins a node to an existing K3s cluster as an agent. Run as root on CN2.
#
# Pass the master's server URL and node token (both printed by
# install-k3s-master.sh) as environment variables or positional arguments:
#
#   sudo K3S_URL=https://<master-ip>:6443 K3S_TOKEN=<token> ./install-k3s-worker.sh
#   sudo ./install-k3s-worker.sh <master-ip> <token>
#
# Handleiding "DevSecOps module launch environment", p.5:
#   curl -sfL https://get.k3s.io | K3S_URL=https://<ip>:6443 K3S_TOKEN=<token> sh -
#
# Masternode: see install-k3s-master.sh
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
LOG_FILE="/tmp/k3s_worker_install_$(date +%Y%m%d_%H%M%S).log"
INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}"  # optional pin, e.g. v1.31.4+k3s1
export INSTALL_K3S_VERSION

# Positional args override the environment: $1 = master URL or IP, $2 = token.
K3S_URL="${1:-${K3S_URL:-}}"
K3S_TOKEN="${2:-${K3S_TOKEN:-}}"

# Accept a bare IP/host and turn it into the full server URL.
if [[ -n "$K3S_URL" && "$K3S_URL" != https://* ]]; then
    K3S_URL="https://${K3S_URL}:6443"
fi

# === Root check ===
Test-Root

# === Validate join details ===
[[ -n "$K3S_URL"   ]] || Stop-Script "Missing master URL. Pass K3S_URL=https://<master-ip>:6443 or as arg 1."
[[ -n "$K3S_TOKEN" ]] || Stop-Script "Missing node token. Pass K3S_TOKEN=<token> or as arg 2 (from install-k3s-master.sh)."
export K3S_URL K3S_TOKEN

# === Already installed? ===
if command -v k3s &>/dev/null; then
    Write-Log WARN "K3s is already installed: $(k3s --version | head -n1)"
    Write-Log INFO "Uninstall with: /usr/local/bin/k3s-agent-uninstall.sh"
    exit 0
fi

# === Install K3s (agent) ===
# get.k3s.io is Rancher's official install path; it is a remote script.
Write-Log WARN "Fetching and running the official installer from https://get.k3s.io"
Write-Log STEP "Joining cluster ${K3S_URL} as an agent"
curl -sfL https://get.k3s.io | sh - >> "$LOG_FILE" 2>&1 || \
    Stop-Script "K3s agent install failed. Check log: $LOG_FILE"

Invoke-Cmd systemctl enable k3s-agent

# === Summary ===
K3S_VER=$(k3s --version 2>/dev/null | head -n1) || K3S_VER="N/A"

echo -e "\n${GREEN}==============================================================${NC}"
Write-Log SUCCESS "K3s workernode joined!"
echo -e "${GREEN}==============================================================${NC}\n"
echo -e "${BLUE}K3s:${NC}          ${GREEN}${K3S_VER}${NC}"
echo -e "${BLUE}Joined:${NC}       ${GREEN}${K3S_URL}${NC}"
echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
echo ""
echo -e "${BOLD}Verify on the masternode (CN1)${NC}"
echo -e "  sudo k3s kubectl get node        # this node should show up as Ready within ~30s"
