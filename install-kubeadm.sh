#!/usr/bin/env bash
#
# kubeadm Installer Script (full Kubernetes + containerd)
#
# Prepares an Ubuntu/Debian node for a kubeadm-based cluster: disables swap,
# loads the required kernel modules, installs containerd and the
# kubeadm/kubelet/kubectl toolchain. Run on every node (master and workers).
# Does NOT run "kubeadm init" / "kubeadm join" - the summary prints the
# commands to run next. Run as root.
#
# See install-k3s-master.sh / install-k3s-worker.sh for the K3s alternative.
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
LOG_FILE="/tmp/kubeadm_install_$(date +%Y%m%d_%H%M%S).log"

K8S_VERSION="${K8S_VERSION:-v1.37.0}"
# pkgs.k8s.io repos are per minor version (v1.37), not per patch release.
K8S_CHANNEL="${K8S_VERSION%.*}"
K8S_APT_URL="https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

# === Root check ===
Test-Root

# === Distro check ===
DISTRO=$(Get-OsId)
case "$DISTRO" in
    ubuntu|debian) : ;;
    *) Stop-Script "This script targets Ubuntu/Debian. Detected: ${DISTRO}. Use the install-k3s-*.sh scripts instead." ;;
esac
Write-Log INFO "Detected distribution: ${DISTRO}"

# === Already installed? ===
if command -v kubeadm &>/dev/null; then
    Write-Log WARN "kubeadm is already installed: $(kubeadm version -o short 2>/dev/null)"
    exit 0
fi

# === 1. Disable swap ===
Write-Log STEP "Disabling swap"
swapoff -a
sed -i.bak '/\sswap\s/s/^\(.*\)$/#\1/' /etc/fstab

# === 2. Kernel modules ===
Write-Log STEP "Loading kernel modules (overlay, br_netfilter)"
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# === 3. sysctl (CNI prerequisites) ===
Write-Log STEP "Applying sysctl settings"
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >> "$LOG_FILE" 2>&1

# === 4. containerd runtime ===
# containerd.io ships from the Docker apt repo; Docker itself is not installed.
Write-Log STEP "Installing containerd"
Invoke-Cmd apt-get update -y
Invoke-Cmd apt-get install -y ca-certificates curl gnupg lsb-release

install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>>"$LOG_FILE" || \
    Stop-Script "Failed to add Docker GPG key."
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO} $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

Invoke-Cmd apt-get update -y
Invoke-Cmd apt-get install -y containerd.io

Write-Log INFO "Configuring containerd with the systemd cgroup driver"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
Invoke-Cmd systemctl restart containerd
Invoke-Cmd systemctl enable containerd

# === 5. kubeadm, kubelet, kubectl ===
Write-Log STEP "Installing kubeadm/kubelet/kubectl (${K8S_CHANNEL})"
curl -fsSL "${K8S_APT_URL}Release.key" | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>>"$LOG_FILE" || \
    Stop-Script "Failed to download the Kubernetes signing key."
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${K8S_APT_URL} /" \
    > /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

Invoke-Cmd apt-get update -y
Invoke-Cmd apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl >> "$LOG_FILE" 2>&1

systemctl daemon-reload
Invoke-Cmd systemctl enable --now kubelet

# === Summary ===
KUBEADM_VER=$(kubeadm version -o short 2>/dev/null) || KUBEADM_VER="N/A"

echo -e "\n${GREEN}==============================================================${NC}"
Write-Log SUCCESS "Node prepared for kubeadm!"
echo -e "${GREEN}==============================================================${NC}\n"
echo -e "${BLUE}kubeadm:${NC}      ${GREEN}${KUBEADM_VER}${NC}"
echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
echo ""
echo -e "${BOLD}Next steps${NC}"
echo -e "  On the master (CN1):"
echo -e "    kubeadm init --pod-network-cidr=${POD_CIDR}"
echo -e "    mkdir -p \$HOME/.kube && cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo -e "    chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo -e "    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
echo -e "  On each worker (CN2): run the 'kubeadm join ...' line that 'kubeadm init' printed."
