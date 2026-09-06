#!/usr/bin/env bash
#
# Kubernetes cluster installer - kubeadm + containerd (DevSecOps module, CN1 / CN2)
#
# Both roles get the same node prep (swap off, kernel modules, sysctl,
# containerd, kubeadm/kubelet/kubectl). --control-plane then runs "kubeadm
# init" + a Flannel CNI and prints the join command; --worker runs the --join
# command you pass, or prints what to do next.
#
#   Control plane (CN1):  sudo ./install-k8s.sh --control-plane
#   Worker       (CN2):   sudo ./install-k8s.sh --worker --join "kubeadm join ..."
#
# Targets Ubuntu/Debian. K3s alternative: see install-k3s.sh
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
Usage: install-k8s.sh <role> [options]

Roles:
  --control-plane   Prep the node, run "kubeadm init" and install Flannel (CN1)
  --worker          Prep the node; run --join if given, else print next steps (CN2)

Options (worker):
  --join CMD        The full "kubeadm join ..." line from the control plane
                    (quote it)

Other:
  -h, --help        Show this help

Targets Ubuntu/Debian.

Examples:
  sudo ./install-k8s.sh --control-plane
  sudo ./install-k8s.sh --worker --join "kubeadm join 10.0.0.1:6443 --token ..."
EOF
}

# === Settings ===
LOG_FILE="/tmp/k8s_install_$(date +%Y%m%d_%H%M%S).log"

K8S_VERSION="${K8S_VERSION:-v1.37.0}"
# pkgs.k8s.io repos are per minor version (v1.37), not per patch release.
K8S_CHANNEL="${K8S_VERSION%.*}"
K8S_APT_URL="https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
FLANNEL_MANIFEST="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"

# === Commands ===

# Usage: Initialize-Node
# Shared node prep for both roles. No-op if kubeadm is already installed.
Initialize-Node() {
    local distro
    distro=$(Get-OsId)
    case "$distro" in
        ubuntu|debian) : ;;
        *) Stop-Script "This script targets Ubuntu/Debian. Detected: ${distro}. Use install-k3s.sh instead." ;;
    esac
    Write-Log INFO "Detected distribution: ${distro}"

    if command -v kubeadm &>/dev/null; then
        Write-Log WARN "kubeadm already installed ($(kubeadm version -o short 2>/dev/null)); skipping node prep."
        return 0
    fi

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
    curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>>"$LOG_FILE" || \
        Stop-Script "Failed to add Docker GPG key."
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${distro} $(lsb_release -cs) stable" \
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
}

# Usage: Install-ControlPlane
Install-ControlPlane() {
    Initialize-Node

    Write-Log STEP "Running kubeadm init (pod CIDR ${POD_CIDR})"
    Invoke-Cmd kubeadm init --pod-network-cidr="${POD_CIDR}"

    # Make kubectl work for the invoking user and for root.
    local target_user target_home
    target_user="${SUDO_USER:-root}"
    target_home=$(getent passwd "$target_user" | cut -d: -f6)
    install -d -m 0755 -o "$target_user" "${target_home}/.kube"
    install -m 0600 -o "$target_user" /etc/kubernetes/admin.conf "${target_home}/.kube/config"
    export KUBECONFIG=/etc/kubernetes/admin.conf

    Write-Log STEP "Installing the Flannel CNI"
    Invoke-Cmd kubectl apply -f "${FLANNEL_MANIFEST}"

    local join_line kubeadm_ver
    join_line=$(kubeadm token create --print-join-command 2>>"$LOG_FILE")
    kubeadm_ver=$(kubeadm version -o short 2>/dev/null) || kubeadm_ver="N/A"

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "Kubernetes control plane ready!"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}kubeadm:${NC}      ${GREEN}${kubeadm_ver}${NC}"
    echo -e "${BLUE}kubeconfig:${NC}   ${GREEN}${target_home}/.kube/config${NC}"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Join a worker (run on CN2)${NC}"
    echo -e "  sudo ./install-k8s.sh --worker --join \"${join_line}\""
    echo ""
    echo -e "${YELLOW}AWS:${NC} allow node-to-node traffic in the security group (self-referencing"
    echo -e "     'All traffic' rule), plus TCP 30000 inbound for the app NodePort."
}

# Usage: Install-Worker [kubeadm-join-command]
Install-Worker() {
    local join_cmd=$1
    Initialize-Node

    local msg
    if [[ -n "$join_cmd" ]]; then
        Write-Log STEP "Joining the cluster"
        # shellcheck disable=SC2086  # the join command is a full command line
        Invoke-Cmd $join_cmd
        msg="Worker joined the cluster."
    else
        msg="Node prepared. Run the 'kubeadm join ...' line from the control plane (or re-run with --join)."
    fi

    echo -e "\n${GREEN}==============================================================${NC}"
    Write-Log SUCCESS "$msg"
    echo -e "${GREEN}==============================================================${NC}\n"
    echo -e "${BLUE}Log:${NC}          ${GREEN}${LOG_FILE}${NC}"
    echo ""
    echo -e "${BOLD}Verify on the control plane (CN1)${NC}"
    echo -e "  kubectl get node"
}

# ============================================================================
# Main Entry Point
# ============================================================================

ROLE=""
JOIN_CMD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --control-plane)
            ROLE="control-plane"; shift ;;
        --worker)
            ROLE="worker"; shift ;;
        --join)
            JOIN_CMD=${2:-}
            [[ -n "$JOIN_CMD" ]] || Stop-Script "--join requires a value"
            shift 2 ;;
        -h|--help)
            Show-Usage; exit 0 ;;
        *)
            Write-Log ERROR "Unknown argument: $1"; Show-Usage; exit 1 ;;
    esac
done

Test-Root

case "$ROLE" in
    control-plane) Install-ControlPlane ;;
    worker)        Install-Worker "$JOIN_CMD" ;;
    *)             Show-Usage; Stop-Script "Pass --control-plane or --worker." ;;
esac
