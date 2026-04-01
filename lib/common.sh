# =============================================================================
# COMMON UTILITIES - Logging, Error Handling, and Helper Functions
# =============================================================================

# -----------------------------------------------------------------------------
# Logging Configuration
# -----------------------------------------------------------------------------
LOG_FILE=""
SCRIPT_START_TIME=$(date +%s)

# Initialize logging
init_logging() {
  # Create log directory if it doesn't exist
  LOG_DIR=${LOG_DIR:-/var/log/k8s-bootstrap}
  mkdir -p "$LOG_DIR"

  # Set log file with timestamp
  local timestamp=$(date +%Y%m%d_%H%M%S)
  LOG_FILE="${LOG_DIR}/k8s_install_${NODE_ROLE}_${timestamp}.log"

  # Start logging
  exec 1> >(tee -a "$LOG_FILE")
  exec 2>&1

  log_info "==================================================="
  log_info "Kubernetes Bootstrap Installation Log"
  log_info "Node Role: ${NODE_ROLE}"
  log_info "Cluster Mode: ${CLUSTER_MODE}"
  log_info "Start Time: $(date)"
  log_info "Log File: ${LOG_FILE}"
  log_info "==================================================="
}

# Log rotation (keep only last N days)
rotate_logs() {
  local retention_days=${LOG_RETENTION_DAYS:-30}
  find "$LOG_DIR" -name "k8s_install_*.log" -mtime +$retention_days -delete 2>/dev/null || true
  log_info "Log rotation completed (retention: ${retention_days} days)"
}

# Logging functions
log_debug() {
  if [[ "${LOG_LEVEL}" == "debug" ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $*"
  fi
  return 0
}

log_info() {
  if [[ "${LOG_LEVEL}" =~ ^(debug|info)$ ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
  fi
  return 0
}

log_warn() {
  if [[ "${LOG_LEVEL}" =~ ^(debug|info|warn)$ ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
  fi
  return 0
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
  return 0
}

log_success() {
  if [[ "${LOG_LEVEL}" =~ ^(debug|info)$ ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] ✅ $*"
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Error Handling
# -----------------------------------------------------------------------------
# Trap for cleanup on error
trap 'error_handler $? $LINENO' ERR

error_handler() {
  local exit_code=$1
  local line_number=$2
  log_error "Installation failed at line ${line_number} with exit code ${exit_code}"
  log_error "Check log file: ${LOG_FILE}"

  # Call cleanup if installation fails
  if [[ "${ROLLBACK_ON_ERROR:-true}" == "true" ]]; then
    log_warn "Initiating rollback procedure..."
    cleanup_on_failure
  fi

  exit $exit_code
}

# Cleanup on failure
cleanup_on_failure() {
  log_info "Starting cleanup procedure..."

  # Reset kubeadm if it was initialized
  if systemctl is-active --quiet kubelet 2>/dev/null; then
    log_info "Resetting kubeadm..."
    kubeadm reset -f || log_warn "kubeadm reset failed"
  fi

  # Stop and disable services
  for service in kubelet containerd crio; do
    if systemctl is-active --quiet $service 2>/dev/null; then
      log_info "Stopping $service..."
      systemctl stop $service || log_warn "Failed to stop $service"
    fi
  done

  # Remove kubernetes directories (optional, based on config)
  if [[ "${CLEANUP_FULL:-false}" == "true" ]]; then
    log_warn "Full cleanup enabled - removing Kubernetes directories..."
    rm -rf /etc/kubernetes
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/etcd
    rm -rf $HOME/.kube
  fi

  log_info "Cleanup completed"
}

# Manual cleanup function (can be called explicitly)
cleanup_cluster() {
  log_info "Manual cluster cleanup initiated..."

  # Drain node if part of cluster
  if command -v kubectl &>/dev/null && kubectl get nodes &>/dev/null; then
    local node_name=$(hostname)
    log_info "Draining node: ${node_name}"
    kubectl drain $node_name --ignore-daemonsets --delete-emptydir-data --force || log_warn "Node drain failed"
    kubectl delete node $node_name || log_warn "Node deletion failed"
  fi

  cleanup_on_failure

  log_success "Cluster cleanup completed successfully"
}

# -----------------------------------------------------------------------------
# Hostname Management
# -----------------------------------------------------------------------------
set_hostname() {
  log_info "Setting hostname..."

  if [[ "$NODE_ROLE" == "control-plane" ]]; then
    hostnamectl set-hostname $CONTROL_PLANE_HOSTNAME
    log_success "Hostname set to: $CONTROL_PLANE_HOSTNAME"
  else
    hostnamectl set-hostname $WORKER_HOSTNAME
    log_success "Hostname set to: $WORKER_HOSTNAME"
  fi

  # Update /etc/hosts
  local node_ip=$(hostname -I | awk '{print $1}')
  local hostname=$(hostname)

  if ! grep -q "$hostname" /etc/hosts; then
    echo "$node_ip $hostname" >> /etc/hosts
    log_info "Updated /etc/hosts with $node_ip $hostname"
  fi
}

# -----------------------------------------------------------------------------
# Configuration Validation
# -----------------------------------------------------------------------------
validate_config() {
  log_info "Validating configuration..."

  local errors=0

  # Validate required variables
  if [[ -z "${NODE_ROLE}" ]]; then
    log_error "NODE_ROLE is not set"
    ((errors++))
  fi

  if [[ -z "${CLUSTER_MODE}" ]]; then
    log_error "CLUSTER_MODE is not set"
    ((errors++))
  fi

  if [[ -z "${K8S_VERSION}" ]]; then
    log_error "K8S_VERSION is not set"
    ((errors++))
  fi

  # Validate HA configuration
  if [[ "${HA_MODE}" == "true" ]]; then
    if [[ -z "${CONTROL_PLANE_ENDPOINT}" ]]; then
      log_error "HA_MODE is enabled but CONTROL_PLANE_ENDPOINT is not set"
      ((errors++))
    fi

    if [[ "${LOAD_BALANCER_ENABLED}" == "false" ]]; then
      log_warn "HA_MODE is enabled but LOAD_BALANCER_ENABLED is false"
    fi
  fi

  # Validate network CIDRs
  if [[ -n "${POD_NETWORK_CIDR}" && -n "${SERVICE_CIDR}" ]]; then
    # Basic CIDR validation (just format check)
    if ! [[ "${POD_NETWORK_CIDR}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
      log_error "Invalid POD_NETWORK_CIDR format: ${POD_NETWORK_CIDR}"
      ((errors++))
    fi

    if ! [[ "${SERVICE_CIDR}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
      log_error "Invalid SERVICE_CIDR format: ${SERVICE_CIDR}"
      ((errors++))
    fi
  fi

  if [[ $errors -gt 0 ]]; then
    log_error "Configuration validation failed with $errors error(s)"
    return 1
  fi

  log_success "Configuration validation passed"
  return 0
}

# -----------------------------------------------------------------------------
# Retry Mechanism
# -----------------------------------------------------------------------------
retry_command() {
  local max_attempts=${1:-3}
  local delay=${2:-5}
  shift 2
  local command="$@"
  local attempt=1

  while [[ $attempt -le $max_attempts ]]; do
    log_info "Executing: $command (attempt $attempt/$max_attempts)"

    if eval "$command"; then
      log_success "Command succeeded on attempt $attempt"
      return 0
    else
      log_warn "Command failed on attempt $attempt"

      if [[ $attempt -lt $max_attempts ]]; then
        log_info "Retrying in ${delay} seconds..."
        sleep $delay
      fi
    fi

    ((attempt++))
  done

  log_error "Command failed after $max_attempts attempts: $command"
  return 1
}

# -----------------------------------------------------------------------------
# Installation Summary
# -----------------------------------------------------------------------------
print_installation_summary() {
  local end_time=$(date +%s)
  local duration=$((end_time - SCRIPT_START_TIME))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  log_info "==================================================="
  log_info "Installation Summary"
  log_info "==================================================="
  log_info "Node Role: ${NODE_ROLE}"
  log_info "Cluster Mode: ${CLUSTER_MODE}"
  log_info "Kubernetes Version: ${K8S_VERSION}"
  log_info "Network Plugin: ${NETWORK_PLUGIN}"
  log_info "Container Runtime: ${CONTAINER_RUNTIME}"
  log_info "Duration: ${minutes}m ${seconds}s"
  log_info "End Time: $(date)"
  log_info "Log File: ${LOG_FILE}"
  log_info "==================================================="

  if [[ "${NODE_ROLE}" == "control-plane" ]]; then
    log_info ""
    log_info "Next Steps:"
    log_info "1. Verify cluster status: kubectl get nodes"
    log_info "2. Check system pods: kubectl get pods -A"

    if [[ -f "join.sh" ]]; then
      log_info "3. Join worker nodes using: ./join.sh"
    fi

    if [[ "${HA_MODE}" == "true" ]]; then
      log_info "4. Join additional control planes with the certificate key"
    fi
  fi

  log_success "Installation completed successfully!"
}