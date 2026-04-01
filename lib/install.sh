# =============================================================================
# INSTALLATION UTILITIES - Runtime, Tools, System Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# System Prerequisites
# -----------------------------------------------------------------------------

# Load required kernel modules
load_kernel_modules() {
  log_info "Loading required kernel modules..."

  local modules=("overlay" "br_netfilter")

  for module in "${modules[@]}"; do
    if ! lsmod | grep -q "^$module"; then
      log_info "Loading module: $module"
      modprobe $module || {
        log_error "Failed to load kernel module: $module"
        return 1
      }
    else
      log_debug "Module already loaded: $module"
    fi
  done

  # Make modules persistent across reboots
  cat > /etc/modules-load.d/k8s.conf <<EOF
# Kubernetes required kernel modules
overlay
br_netfilter
EOF

  log_success "Kernel modules loaded and configured for persistence"
}

# Configure sysctl parameters for Kubernetes
configure_sysctl() {
  log_info "Configuring sysctl parameters for Kubernetes..."

  cat > /etc/sysctl.d/k8s.conf <<EOF
# Kubernetes required sysctl parameters
# Enable IP forwarding
net.ipv4.ip_forward = 1

# Enable bridge netfilter
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Disable IPv4 forwarding (re-enabled above, but explicit)
net.ipv4.conf.all.forwarding = 1

# Recommended for better performance
net.ipv4.tcp_congestion_control = bbr
vm.overcommit_memory = 1
kernel.panic = 10
kernel.panic_on_oops = 1

# For high-load scenarios
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8096
net.core.netdev_max_backlog = 16384
EOF

  # Apply sysctl parameters
  sysctl --system || {
    log_error "Failed to apply sysctl parameters"
    return 1
  }

  log_success "Sysctl parameters configured"
}

# Disable swap (required by Kubernetes)
disable_swap() {
  log_info "Ensuring swap is disabled..."

  # Check if swap is enabled (store result to avoid set -e issues)
  local swap_output
  swap_output=$(swapon --show 2>/dev/null || true)

  if [[ -n "$swap_output" ]]; then
    log_warn "Swap is currently enabled, disabling now..."
    swapoff -a || {
      log_error "Failed to disable swap"
      return 1
    }

    # Remove swap entries from /etc/fstab
    sed -i '/\sswap\s/d' /etc/fstab || {
      log_warn "Could not modify /etc/fstab (may not exist or no swap entries)"
    }

    log_success "Swap disabled successfully"
  else
    log_success "Swap already disabled"
  fi

  # Verify swap is off
  if [[ -n "$(swapon --show 2>/dev/null)" ]]; then
    log_error "Swap is still active after disable attempt"
    return 1
  fi
}

# Configure proxy settings if specified
configure_proxy() {
  if [[ -z "${HTTP_PROXY}${HTTPS_PROXY}" ]]; then
    log_debug "No proxy configuration specified"
    return 0
  fi

  log_info "Configuring proxy settings..."

  # System-wide proxy
  cat > /etc/profile.d/proxy.sh <<EOF
# Proxy configuration for Kubernetes
export HTTP_PROXY="${HTTP_PROXY}"
export HTTPS_PROXY="${HTTPS_PROXY}"
export NO_PROXY="${NO_PROXY}"
export http_proxy="${HTTP_PROXY}"
export https_proxy="${HTTPS_PROXY}"
export no_proxy="${NO_PROXY}"
EOF

  # Apply for current session
  source /etc/profile.d/proxy.sh || {
    log_warn "Failed to source proxy configuration"
  }

  # Configure proxy for containerd
  if [[ "${CONTAINER_RUNTIME}" == "containerd" ]]; then
    mkdir -p /etc/systemd/system/containerd.service.d
    cat > /etc/systemd/system/containerd.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF
  fi

  # Configure proxy for kubelet
  mkdir -p /etc/systemd/system/kubelet.service.d
  cat > /etc/systemd/system/kubelet.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF

  systemctl daemon-reload || {
    log_warn "Failed to reload systemd daemon"
  }

  log_success "Proxy settings configured"
  return 0
}

# -----------------------------------------------------------------------------
# Container Runtime Installation
# -----------------------------------------------------------------------------

# Install and configure containerd
install_containerd() {
  log_info "Installing containerd..."

  # Install containerd
  retry_command 3 5 "apt update"
  apt install -y containerd || {
    log_error "Failed to install containerd"
    return 1
  }

  # Create containerd configuration directory
  mkdir -p /etc/containerd

  # Generate default configuration
  containerd config default > /etc/containerd/config.toml

  # Configure SystemdCgroup if specified
  if [[ "${CGROUP_DRIVER}" == "systemd" ]]; then
    log_info "Configuring containerd to use systemd cgroup driver..."

    # Update config.toml to use SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

    log_success "SystemdCgroup configured for containerd"
  fi

  # Configure registry mirrors if specified
  if [[ -n "${REGISTRY_MIRROR}" ]]; then
    log_info "Configuring registry mirror: ${REGISTRY_MIRROR}"

    # Add registry mirror configuration
    sed -i '/\[plugins."io.containerd.grpc.v1.cri".registry.mirrors\]/a\        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]\n          endpoint = ["'${REGISTRY_MIRROR}'"]' /etc/containerd/config.toml

    log_success "Registry mirror configured"
  fi

  # Restart and enable containerd
  systemctl restart containerd || {
    log_error "Failed to restart containerd"
    return 1
  }
  systemctl enable containerd

  # Verify containerd is running
  if systemctl is-active --quiet containerd; then
    log_success "Containerd installed and running"
  else
    log_error "Containerd is not running"
    return 1
  fi
}

# Install and configure CRI-O
install_crio() {
  log_info "Installing CRI-O..."

  local OS="xUbuntu_$(lsb_release -rs)"
  local CRIO_VERSION="${CRIO_VERSION:-${K8S_VERSION}}"

  # Add CRI-O repository
  log_info "Adding CRI-O repository for version ${CRIO_VERSION}..."

  echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
  echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list

  # Add GPG keys
  mkdir -p /usr/share/keyrings
  curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
  curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

  # Install CRI-O
  retry_command 3 5 "apt update"
  apt install -y cri-o cri-o-runc || {
    log_error "Failed to install CRI-O"
    return 1
  }

  # Configure CRI-O for systemd cgroup
  if [[ "${CGROUP_DRIVER}" == "systemd" ]]; then
    log_info "Configuring CRI-O to use systemd cgroup manager..."

    mkdir -p /etc/crio/crio.conf.d
    cat > /etc/crio/crio.conf.d/02-cgroup-manager.conf <<EOF
[crio.runtime]
cgroup_manager = "systemd"
EOF

    log_success "SystemdCgroup configured for CRI-O"
  fi

  # Configure registry mirrors if specified
  if [[ -n "${REGISTRY_MIRROR}" ]]; then
    log_info "Configuring registry mirror: ${REGISTRY_MIRROR}"

    mkdir -p /etc/crio/crio.conf.d
    cat > /etc/crio/crio.conf.d/01-registry-mirror.conf <<EOF
[[registry]]
prefix = "docker.io"
insecure = false
blocked = false
location = "docker.io"

[[registry.mirror]]
location = "${REGISTRY_MIRROR}"
insecure = false
EOF

    log_success "Registry mirror configured for CRI-O"
  fi

  # Start and enable CRI-O
  systemctl daemon-reload
  systemctl restart crio || {
    log_error "Failed to restart CRI-O"
    return 1
  }
  systemctl enable crio

  # Verify CRI-O is running
  if systemctl is-active --quiet crio; then
    log_success "CRI-O installed and running"
  else
    log_error "CRI-O is not running"
    return 1
  fi
}

# Main container runtime installation dispatcher
install_container_runtime() {
  log_info "==================================================="
  log_info "Installing Container Runtime: ${CONTAINER_RUNTIME}"
  log_info "==================================================="

  # Load kernel modules (required for all runtimes)
  load_kernel_modules || return 1

  # Configure sysctl parameters
  configure_sysctl || return 1

  # Disable swap
  disable_swap || return 1

  # Configure proxy if specified
  configure_proxy || {
    log_error "Failed to configure proxy settings"
    return 1
  }

  # Install the selected runtime
  case "${CONTAINER_RUNTIME}" in
    containerd)
      install_containerd || return 1
      ;;
    cri-o|crio)
      install_crio || return 1
      ;;
    *)
      log_error "Unknown container runtime: ${CONTAINER_RUNTIME}"
      log_error "Supported runtimes: containerd, cri-o"
      return 1
      ;;
  esac

  log_success "Container runtime installation completed"
}

# -----------------------------------------------------------------------------
# Kubernetes Tools Installation
# -----------------------------------------------------------------------------

install_kubernetes_tools() {
  log_info "==================================================="
  log_info "Installing Kubernetes Tools (version ${K8S_VERSION})"
  log_info "==================================================="

  # Install prerequisites
  log_info "Installing prerequisites..."
  retry_command 3 5 "apt update"
  apt install -y apt-transport-https ca-certificates curl gpg || {
    log_error "Failed to install prerequisites"
    return 1
  }

  # Create keyrings directory
  mkdir -p /etc/apt/keyrings

  # Add Kubernetes repository GPG key
  log_info "Adding Kubernetes repository..."

  if [[ -n "${HTTP_PROXY}" ]]; then
    # Use proxy for curl
    curl -x "${HTTP_PROXY}" -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
      gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  else
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
      gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  fi

  if [[ $? -ne 0 ]]; then
    log_error "Failed to add Kubernetes repository key"
    return 1
  fi

  # Add Kubernetes repository
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    tee /etc/apt/sources.list.d/kubernetes.list

  # Update package index
  retry_command 3 5 "apt update"

  # Install Kubernetes tools
  log_info "Installing kubelet, kubeadm, kubectl..."
  apt install -y kubelet kubeadm kubectl || {
    log_error "Failed to install Kubernetes tools"
    return 1
  }

  # Hold Kubernetes packages at current version
  apt-mark hold kubelet kubeadm kubectl

  log_info "Installed versions:"
  kubelet --version
  kubeadm version -o short
  kubectl version --client=true --short=true 2>/dev/null || kubectl version --client=true

  log_success "Kubernetes tools installation completed"
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------

verify_installation() {
  log_info "Verifying installation..."

  local errors=0

  # Check kernel modules
  for module in overlay br_netfilter; do
    if ! lsmod | grep -q "^$module"; then
      log_error "Kernel module not loaded: $module"
      ((errors++))
    fi
  done

  # Check sysctl parameters
  if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
    log_error "IP forwarding not enabled"
    ((errors++))
  fi

  if [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" != "1" ]]; then
    log_error "bridge-nf-call-iptables not enabled"
    ((errors++))
  fi

  # Check container runtime
  case "${CONTAINER_RUNTIME}" in
    containerd)
      if ! systemctl is-active --quiet containerd; then
        log_error "Containerd is not running"
        ((errors++))
      fi
      ;;
    cri-o|crio)
      if ! systemctl is-active --quiet crio; then
        log_error "CRI-O is not running"
        ((errors++))
      fi
      ;;
  esac

  # Check Kubernetes tools
  for tool in kubelet kubeadm kubectl; do
    if ! command -v $tool &>/dev/null; then
      log_error "$tool is not installed"
      ((errors++))
    fi
  done

  if [[ $errors -gt 0 ]]; then
    log_error "Verification failed with $errors error(s)"
    return 1
  fi

  log_success "Installation verification passed"
  return 0
}