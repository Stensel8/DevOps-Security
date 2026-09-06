#!/usr/bin/env bash
#
# Kubernetes cluster installer - kubeadm + containerd (DevSecOps module, CN1 / CN2)
#
#   Control plane (CN1):  sudo ./install-k8s.sh --control-plane
#   Worker       (CN2):   sudo ./install-k8s.sh --worker
#                         sudo ./install-k8s.sh --worker --join "kubeadm join 10.0.0.1:6443 --token ..."
#
# Both roles get the same node prep (swap off, kernel modules, sysctl,
# containerd, kubeadm/kubelet/kubectl). --control-plane then runs
# "kubeadm init" + a Flannel CNI and prints the join command. --worker either
# runs the --join command you pass or prints what to do next.
#
# Targets Ubuntu/Debian. K3s alternative: see install-k3s.sh
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
LOG_FILE="/tmp/k8s_install_$(date +%Y%m%d_%H%M%S).log"

K8S_VERSION="${K8S_VERSION:-v1.37.0}"
# pkgs.k8s.io repos are per minor version (v1.37), not per patch release.
K8S_CHANNEL="${K8S_VERSION%.*}"
K8S_APT_URL="https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
FLANNEL_MANIFEST="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"

ROLE=""
JOIN_CMD=""

# === Usage ===
Show-Usage() {
    cat <<EOF
Usage: $0 --control-plane
       $0 --worker [--join "kubeadm join ..."]

  --control-plane   Prep the node, run "kubeadm init" and install Flannel.
  --worker          Prep the node; run --join if given, else print next steps.
  --join <cmd>      Worker only: the full "kubeadm join ..." line from the
                    control plane (quote it).
  -h, --help        Show this help.
EOF
}

# === Parse arguments ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        --control-plane) ROLE="control-plane"; shift ;;
        --worker)        ROLE="worker"; shift ;;
        --join)          JOIN_CMD="${2:-}"; shift 2 ;;
        -h|--help)       Show-Usage; exit 0 ;;
        *)               Show-Usage; Stop-Script "Unknown argument: $1" ;;
    esac
done

[[ -n "$ROLE" ]] || { Show-Usage; Stop-Script "Pass --control-plane or --worker."; }

# === Root check ===
Test-Root

# === Distro check ===
DISTRO=$(Get-OsId)
case "$DISTRO" in
    ubuntu|debian) : ;;
    *) Stop-Script "This script targets Ubuntu/Debian. Detected: ${DISTRO}. Use install-k3s.sh instead." ;;
esac
Write-Log INFO "Detected distribution: ${DISTRO}"

# === Node prep (skip if kubeadm is already present) ===
if command -v kubeadm &>/dev/null; then
    Write-Log WARN "kubeadm already installed ($(kubeadm version -o short 2>/dev/null)); skipping node prep."
else
    Write-Log STEP "Disabling swap"
    swapoff -a
    sed -i.bak '/\sswap\s/s/^\(.*\)$/#\1/' /etc/fstab

    Write-Log STEP "Loading kernel modules (overlay, br_netfilter)"
    cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
    modprobe overlay
    modprobe br_netfilter

    Write-Log STEP "Applying sysctl settings"
    cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sysctl --system >> "$LOG_FILE" 2>&1

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
fi

if [[ "$ROLE" == "control-plane" ]]; then
    # === kubeadm init ===
    Write-Log STEP "Running kubeadm init (pod CIDR ${POD_CIDR})"
    Invoke-Cmd kubeadm init --pod-network-cidr="${POD_CIDR}"

    # Make kubectl work for the invoking user and for root.
    TARGET_USER="${SUDO_USER:-root}"
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    install -d -m 0755 -o "$TARGET_USER" "${TARGET_HOME}/.kube"
    install -m 0600 -o "$TARGET_USER" /etc/kubernetes/admin.conf "${TARGET_HOME}/.kube/config"
    export KUBECONFIG=/etc/kubernetes/admin.conf

    Write-Log STEP "Installing the Flannel CNI"
    Invoke-Cmd kubectl apply -f "${FLANNEL_MANIFEST}"

    JOIN_LINE=$(kubeadm token create --print-join-command 2>>"$LOG_FILE")
    KUBEADM_VER=$(kubeadm version -o short 2>/dev/null) || KUBEADM_VER="N/A"

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "Kubernetes control plane ready!"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}kubeadm:${NC}      ${GREEN}${KUBEADM_VER}${NC}"
    echo -e "${BLUE}kubeconfig:${NC}   ${GREEN}${TARGET_HOME}/.kube/config${NC}"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Join a worker (run on CN2)${NC}"
    echo -e "  sudo ./install-k8s.sh --worker --join \"${JOIN_LINE}\""
    echo ""
    echo -e "${YELLOW}AWS:${NC} open TCP 6443 (API) and 30000 (app NodePort) inbound in the security group."
else
    # === Worker ===
    if [[ -n "$JOIN_CMD" ]]; then
        Write-Log STEP "Joining the cluster"
        # shellcheck disable=SC2086  # the join command is a full command line
        Invoke-Cmd $JOIN_CMD
        MSG="Worker joined the cluster."
    else
        MSG="Node prepared. Run the 'kubeadm join ...' line from the control plane (or re-run with --join)."
    fi

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "$MSG"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Verify on the control plane (CN1)${NC}"
    echo -e "  kubectl get node"
fi
