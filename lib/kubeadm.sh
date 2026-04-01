# =============================================================================
# KUBEADM CLUSTER OPERATIONS
# =============================================================================

# Initialize control plane
init_control_plane() {
  log_info "Initializing control plane..."

  # Generate kubeadm config
  local config_file=$(generate_kubeadm_config)

  # Generate audit and encryption configs if enabled
  generate_audit_policy
  generate_encryption_config

  # Initialize cluster with config file
  log_info "Running kubeadm init with config file..."

  if [[ "${HA_MODE}" == "true" ]]; then
    log_info "HA mode enabled - uploading certificates..."
    kubeadm init --config="$config_file" --upload-certs 2>&1 | tee /tmp/kubeadm-init.log
  else
    kubeadm init --config="$config_file" 2>&1 | tee /tmp/kubeadm-init.log
  fi

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_error "kubeadm init failed"
    return 1
  fi

  log_success "Control plane initialized successfully"
}

# Setup kubectl for current user
setup_kubectl() {
  log_info "Setting up kubectl access..."

  mkdir -p $HOME/.kube
  cp /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  # Also setup for root if running as sudo
  if [[ -n "$SUDO_USER" ]]; then
    local user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    mkdir -p "$user_home/.kube"
    cp /etc/kubernetes/admin.conf "$user_home/.kube/config"
    chown -R "$SUDO_USER":"$SUDO_USER" "$user_home/.kube"
    log_info "kubectl configured for user: $SUDO_USER"
  fi

  log_success "kubectl access configured"
}

# Allow workloads on control plane (single-node mode)
allow_master_schedule() {
  if [[ "${CLUSTER_MODE}" == "single" ]]; then
    log_info "Single-node mode: removing control-plane taint..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
    log_success "Control plane can now schedule workloads"
  else
    log_info "Multi-node mode: control plane taint preserved"
  fi
}

# Apply node labels if configured
apply_node_labels() {
  if [[ -z "${NODE_LABELS}" ]]; then
    return 0
  fi

  log_info "Applying node labels..."

  local node_name=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

  IFS=',' read -ra LABELS <<< "$NODE_LABELS"
  for label in "${LABELS[@]}"; do
    kubectl label node "$node_name" "$label" --overwrite
    log_info "Applied label: $label"
  done

  log_success "Node labels applied"
}

# Apply node taints if configured
apply_node_taints() {
  if [[ -z "${NODE_TAINTS}" || "${CLUSTER_MODE}" == "single" ]]; then
    return 0
  fi

  log_info "Applying node taints..."

  local node_name=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

  IFS=',' read -ra TAINTS <<< "$NODE_TAINTS"
  for taint in "${TAINTS[@]}"; do
    kubectl taint node "$node_name" "$taint" --overwrite || true
    log_info "Applied taint: $taint"
  done

  log_success "Node taints applied"
}

# Generate join command with expiration handling
generate_join_command() {
  log_info "Generating join command for worker nodes..."

  # Default token TTL is 24h, make it configurable
  local token_ttl="${JOIN_TOKEN_TTL:-24h}"

  # Generate join command
  local join_cmd=$(kubeadm token create --print-join-command --ttl="$token_ttl")

  if [[ -z "$join_cmd" ]]; then
    log_error "Failed to generate join command"
    return 1
  fi

  # Save to file
  echo "#!/bin/bash" > join.sh
  echo "# Generated: $(date)" >> join.sh
  echo "# Expires: $token_ttl from generation time" >> join.sh
  echo "# To regenerate: kubeadm token create --print-join-command" >> join.sh
  echo "" >> join.sh
  echo "$join_cmd" >> join.sh
  chmod 600 join.sh  # Secure the file

  log_success "Join command saved to: join.sh (expires in $token_ttl)"
  log_info "Join command: $join_cmd"

  # If HA mode, also extract certificate key
  if [[ "${HA_MODE}" == "true" ]]; then
    generate_ha_join_command
  fi
}

# Generate HA control plane join command
generate_ha_join_command() {
  log_info "Generating HA control plane join information..."

  # Extract certificate key from init log
  local cert_key=$(grep -oP 'certificate-key \K[^\s]+' /tmp/kubeadm-init.log | head -1)

  if [[ -z "$cert_key" ]]; then
    log_warn "Certificate key not found. Generating new one..."
    cert_key=$(kubeadm init phase upload-certs --upload-certs 2>&1 | grep -oP 'Using certificate key:\s*\K.*')
  fi

  # Generate control plane join command
  local cp_join_cmd=$(kubeadm token create --print-join-command --ttl="${JOIN_TOKEN_TTL:-24h}")
  cp_join_cmd="${cp_join_cmd} --control-plane --certificate-key ${cert_key}"

  # Save to separate file
  echo "#!/bin/bash" > join-control-plane.sh
  echo "# Control Plane Join Command" >> join-control-plane.sh
  echo "# Generated: $(date)" >> join-control-plane.sh
  echo "# Expires: ${JOIN_TOKEN_TTL:-24h} from generation time" >> join-control-plane.sh
  echo "" >> join-control-plane.sh
  echo "$cp_join_cmd" >> join-control-plane.sh
  chmod 600 join-control-plane.sh

  log_success "Control plane join command saved to: join-control-plane.sh"
  log_info "Certificate key: $cert_key"
}

# Check token expiration and regenerate if needed
check_and_renew_token() {
  log_info "Checking join token status..."

  # List tokens
  local tokens=$(kubeadm token list 2>/dev/null)

  if [[ -z "$tokens" || ! "$tokens" =~ "system:bootstrappers:kubeadm:default-node-token" ]]; then
    log_warn "No valid tokens found or token expired"
    log_info "Regenerating join command..."
    generate_join_command
    return 0
  fi

  log_info "Valid token exists"

  # Check expiration time
  local expiration=$(echo "$tokens" | awk 'NR==2 {print $3}')
  log_info "Token expiration: $expiration"
}

# Join worker node to cluster
join_worker() {
  log_info "Joining worker node to cluster..."

  if [[ -z "$JOIN_COMMAND" ]]; then
    log_error "JOIN_COMMAND missing in .env"
    log_error "Please obtain the join command from the control plane"
    return 1
  fi

  # Generate join config file for better control
  local config_file=$(generate_join_config)

  if [[ -n "$config_file" ]]; then
    log_info "Using join configuration file..."
    kubeadm join --config="$config_file"
  else
    log_warn "Using direct join command (config generation failed)..."
    eval $JOIN_COMMAND
  fi

  if [[ $? -eq 0 ]]; then
    log_success "Worker node joined successfully"
  else
    log_error "Failed to join worker node"
    return 1
  fi
}

# Post-installation validation
post_install_validation() {
  log_info "Running post-installation validation..."

  local errors=0

  # Check if kubectl is working
  if ! kubectl version --short &>/dev/null; then
    log_error "kubectl is not working properly"
    ((errors++))
  else
    log_success "kubectl is operational"
  fi

  # Check node status
  log_info "Checking node status..."
  local node_status=$(kubectl get nodes --no-headers 2>/dev/null)

  if [[ -z "$node_status" ]]; then
    log_error "No nodes found in cluster"
    ((errors++))
  else
    echo "$node_status" | while read line; do
      local node_name=$(echo $line | awk '{print $1}')
      local node_ready=$(echo $line | awk '{print $2}')

      if [[ "$node_ready" == "Ready" ]]; then
        log_success "Node $node_name is Ready"
      else
        log_warn "Node $node_name is $node_ready (may take a few minutes)"
      fi
    done
  fi

  # Check system pods
  log_info "Checking system pods..."
  local pending_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)

  if [[ $pending_pods -gt 0 ]]; then
    log_warn "$pending_pods system pods are not running yet"
    kubectl get pods -n kube-system
  else
    log_success "All system pods are running"
  fi

  # Check CNI installation
  log_info "Checking CNI plugin..."
  local cni_pods=$(kubectl get pods -n kube-system -l k8s-app --no-headers 2>/dev/null | wc -l)

  if [[ $cni_pods -gt 0 ]]; then
    log_success "CNI plugin pods detected"
  else
    log_warn "No CNI pods found - network plugin may not be installed"
  fi

  # Check API server health
  if [[ "${NODE_ROLE}" == "control-plane" ]]; then
    log_info "Checking API server health..."

    if curl -k https://localhost:6443/healthz &>/dev/null; then
      log_success "API server is healthy"
    else
      log_error "API server health check failed"
      ((errors++))
    fi

    # Check etcd health (if local etcd)
    if [[ "${EXTERNAL_ETCD_ENABLED}" != "true" ]]; then
      log_info "Checking etcd health..."

      if kubectl get --raw /healthz/etcd &>/dev/null; then
        log_success "etcd is healthy"
      else
        log_warn "etcd health check failed or not accessible"
      fi
    fi
  fi

  # Check for critical component status
  log_info "Checking component status..."
  if kubectl get componentstatuses &>/dev/null 2>&1; then
    kubectl get componentstatuses 2>/dev/null | grep -v "Warning" || true
  fi

  if [[ $errors -gt 0 ]]; then
    log_error "Post-installation validation completed with $errors error(s)"
    return 1
  fi

  log_success "Post-installation validation passed!"
  return 0
}