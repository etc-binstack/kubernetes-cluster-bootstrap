# =============================================================================
# NETWORK PLUGIN INSTALLATION - CNI Configuration
# =============================================================================

# Install Calico CNI
install_calico() {
  log_info "Installing Calico CNI..."

  local calico_version="${CNI_VERSION:-v3.27.0}"

  # Download Calico manifest
  local manifest_url="https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/calico.yaml"

  log_info "Downloading Calico manifest (${calico_version})..."
  kubectl apply -f "$manifest_url" || {
    log_error "Failed to install Calico"
    return 1
  }

  # Wait a moment for resources to be created
  log_info "Waiting for Calico resources to be created..."
  sleep 5

  # Wait for Calico pods to be ready
  log_info "Waiting for Calico pods to be ready..."
  local max_wait=60
  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    local pod_count=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l)
    if [[ $pod_count -gt 0 ]]; then
      log_info "Found $pod_count Calico pod(s), waiting for them to be ready..."
      kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=240s 2>/dev/null || {
        log_warn "Calico pods took longer than expected to be ready"
      }
      break
    fi
    sleep 5
    ((elapsed+=5))
  done

  log_success "Calico CNI installed successfully"
}

# Install Flannel CNI
install_flannel() {
  log_info "Installing Flannel CNI..."

  local flannel_version="${CNI_VERSION:-master}"

  # Download Flannel manifest
  local manifest_url="https://raw.githubusercontent.com/flannel-io/flannel/${flannel_version}/Documentation/kube-flannel.yml"

  log_info "Downloading Flannel manifest (${flannel_version})..."
  kubectl apply -f "$manifest_url" || {
    log_error "Failed to install Flannel"
    return 1
  }

  # Wait for Flannel pods to be ready
  log_info "Waiting for Flannel pods to be ready..."
  kubectl wait --for=condition=Ready pods -l app=flannel -n kube-flannel --timeout=300s || {
    log_warn "Flannel pods took longer than expected to be ready"
  }

  log_success "Flannel CNI installed successfully"
}

# Install Cilium CNI
install_cilium() {
  log_info "Installing Cilium CNI..."

  local cilium_version="${CNI_VERSION:-v1.15.0}"

  # Check if Cilium CLI is available
  if command -v cilium &>/dev/null; then
    log_info "Using Cilium CLI for installation..."
    cilium install --version="${cilium_version}" || {
      log_error "Failed to install Cilium via CLI"
      return 1
    }
  else
    # Use manifest installation
    log_info "Installing Cilium via manifest (${cilium_version})..."
    local manifest_url="https://raw.githubusercontent.com/cilium/cilium/${cilium_version}/install/kubernetes/quick-install.yaml"

    kubectl apply -f "$manifest_url" || {
      log_error "Failed to install Cilium"
      return 1
    }
  fi

  # Wait for Cilium pods to be ready
  log_info "Waiting for Cilium pods to be ready..."
  kubectl wait --for=condition=Ready pods -l k8s-app=cilium -n kube-system --timeout=300s || {
    log_warn "Cilium pods took longer than expected to be ready"
  }

  log_success "Cilium CNI installed successfully"
}

# Install Weave Net CNI
install_weave() {
  log_info "Installing Weave Net CNI..."

  local weave_version="${CNI_VERSION:-v2.8.1}"

  # Download and apply Weave manifest
  log_info "Downloading Weave Net manifest (${weave_version})..."
  kubectl apply -f "https://github.com/weaveworks/weave/releases/download/${weave_version}/weave-daemonset-k8s.yaml" || {
    log_error "Failed to install Weave Net"
    return 1
  }

  # Wait for Weave pods to be ready
  log_info "Waiting for Weave Net pods to be ready..."
  kubectl wait --for=condition=Ready pods -l name=weave-net -n kube-system --timeout=300s || {
    log_warn "Weave Net pods took longer than expected to be ready"
  }

  log_success "Weave Net CNI installed successfully"
}

# Apply custom CNI configuration (if specified)
apply_custom_cni_config() {
  local plugin=$1

  case "$plugin" in
    calico)
      # Custom Calico configuration
      if [[ -n "${CALICO_IPV4POOL_CIDR}" ]]; then
        log_info "Configuring custom Calico IPv4 pool..."
        kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_CIDR="${CALICO_IPV4POOL_CIDR}"
      fi

      # Enable IP-in-IP encapsulation if specified
      if [[ "${CALICO_IP_IN_IP}" == "true" ]]; then
        log_info "Enabling Calico IP-in-IP encapsulation..."
        kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_IPIP="Always"
      fi

      # Enable VXLAN if specified
      if [[ "${CALICO_VXLAN}" == "true" ]]; then
        log_info "Enabling Calico VXLAN encapsulation..."
        kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_VXLAN="Always"
      fi
      ;;

    flannel)
      # Custom Flannel backend
      if [[ -n "${FLANNEL_BACKEND}" ]]; then
        log_info "Flannel backend: ${FLANNEL_BACKEND}"
        # Flannel backend is configured via ConfigMap before installation
      fi
      ;;

    cilium)
      # Cilium custom options are typically set during installation
      log_info "Cilium installed with default configuration"
      ;;

    weave)
      # Weave Net supports encryption
      if [[ "${WEAVE_ENCRYPTION}" == "true" && -n "${WEAVE_PASSWORD}" ]]; then
        log_info "Configuring Weave Net encryption..."
        kubectl create secret -n kube-system generic weave-passwd --from-literal=weave-passwd="${WEAVE_PASSWORD}" || true
      fi
      ;;
  esac
}

# Verify CNI installation
verify_cni_installation() {
  log_info "Verifying CNI installation..."

  local plugin=$1
  local errors=0

  # Check if CNI pods are running
  local pod_selector=""
  local namespace="kube-system"

  case "$plugin" in
    calico)
      pod_selector="k8s-app=calico-node"
      ;;
    flannel)
      pod_selector="app=flannel"
      namespace="kube-flannel"
      ;;
    cilium)
      pod_selector="k8s-app=cilium"
      ;;
    weave)
      pod_selector="name=weave-net"
      ;;
  esac

  if [[ -n "$pod_selector" ]]; then
    local running_pods=$(kubectl get pods -n "$namespace" -l "$pod_selector" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local total_pods=$(kubectl get pods -n "$namespace" -l "$pod_selector" --no-headers 2>/dev/null | wc -l)

    if [[ $total_pods -eq 0 ]]; then
      log_error "No $plugin pods found in namespace $namespace"
      ((errors++))
    elif [[ $running_pods -eq 0 ]]; then
      log_warn "No $plugin pods are running yet (found $total_pods pod(s) in other states)"
      log_info "Pods may still be starting - this is normal immediately after installation"
      kubectl get pods -n "$namespace" -l "$pod_selector" 2>/dev/null || true
    else
      log_success "$plugin pods running: $running_pods/$total_pods"
    fi
  fi

  # Check node network status
  local not_ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l)

  if [[ $not_ready_nodes -gt 0 ]]; then
    log_warn "$not_ready_nodes node(s) not ready yet (CNI may still be initializing)"
  else
    log_success "All nodes are Ready"
  fi

  # Check CoreDNS status
  local coredns_running=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

  if [[ $coredns_running -eq 0 ]]; then
    log_warn "CoreDNS pods are not running yet"
  else
    log_success "CoreDNS is running"
  fi

  if [[ $errors -gt 0 ]]; then
    log_error "CNI verification failed with $errors critical error(s)"
    log_warn "The CNI plugin may need more time to fully initialize"
    log_info "You can check status later with: kubectl get pods -n $namespace"
    return 1
  fi

  log_success "CNI installation verification passed"
  return 0
}

# Main CNI installation dispatcher
install_network_plugin() {
  log_info "==================================================="
  log_info "Installing Network Plugin: ${NETWORK_PLUGIN}"
  log_info "Pod Network CIDR: ${POD_NETWORK_CIDR}"
  log_info "==================================================="

  # Validate network plugin selection
  if [[ -z "${NETWORK_PLUGIN}" ]]; then
    log_error "NETWORK_PLUGIN is not set"
    return 1
  fi

  # Install the selected CNI plugin
  case "${NETWORK_PLUGIN}" in
    calico)
      install_calico || return 1
      apply_custom_cni_config "calico"
      ;;
    flannel)
      install_flannel || return 1
      apply_custom_cni_config "flannel"
      ;;
    cilium)
      install_cilium || return 1
      apply_custom_cni_config "cilium"
      ;;
    weave)
      install_weave || return 1
      apply_custom_cni_config "weave"
      ;;
    none)
      log_warn "No network plugin will be installed (NETWORK_PLUGIN=none)"
      log_info "You must manually install a CNI plugin for the cluster to function"
      return 0
      ;;
    *)
      log_error "Unknown network plugin: ${NETWORK_PLUGIN}"
      log_error "Supported plugins: calico, flannel, cilium, weave, none"
      return 1
      ;;
  esac

  # Wait a moment for CNI to initialize
  log_info "Waiting for CNI to initialize..."
  sleep 10

  # Verify installation
  verify_cni_installation "${NETWORK_PLUGIN}"

  log_success "Network plugin installation completed"
}