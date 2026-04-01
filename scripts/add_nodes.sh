#!/bin/bash

# =============================================================================
# Worker Node Addition Script - Production-Ready Multi-Node Management
# =============================================================================
# This script securely adds multiple worker nodes to a Kubernetes cluster
# Features:
# - Secure join token distribution
# - SSH key validation
# - Progress tracking with status reporting
# - Failed node retry logic
# - Post-join health verification
# - Node labeling support
# - Parallel or serial execution
# =============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source configuration
if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
  echo "❌ ERROR: .env file not found in $PROJECT_ROOT"
  exit 1
fi

source "$PROJECT_ROOT/.env"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NODES_FILE="${NODES_FILE:-$SCRIPT_DIR/nodes.txt}"
LOG_DIR="${LOG_DIR:-/var/log/k8s-bootstrap}"
LOG_FILE="$LOG_DIR/add_nodes_$(date +%Y%m%d_%H%M%S).log"
PARALLEL_EXECUTION="${PARALLEL_EXECUTION:-false}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"
SSH_TIMEOUT="${SSH_TIMEOUT:-30}"
POST_JOIN_WAIT="${POST_JOIN_WAIT:-60}"

# Status tracking
declare -A NODE_STATUS
declare -A NODE_ATTEMPTS
TOTAL_NODES=0
SUCCESSFUL_NODES=0
FAILED_NODES=0

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
mkdir -p "$LOG_DIR"

log() {
  local level=$1
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_success() { log "SUCCESS" "✅ $@"; }
log_warn() { log "WARN" "⚠️  $@"; }
log_error() { log "ERROR" "❌ $@"; }

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------

# Validate SSH key
validate_ssh_key() {
  log_info "Validating SSH key: $SSH_KEY"

  if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found: $SSH_KEY"
    return 1
  fi

  # Check key permissions
  local key_perms=$(stat -c %a "$SSH_KEY" 2>/dev/null || stat -f %A "$SSH_KEY" 2>/dev/null)
  if [[ "$key_perms" != "600" && "$key_perms" != "400" ]]; then
    log_warn "SSH key permissions are $key_perms (should be 600 or 400)"
    log_info "Attempting to fix permissions..."
    chmod 600 "$SSH_KEY" || {
      log_error "Failed to set SSH key permissions"
      return 1
    }
  fi

  log_success "SSH key validated"
  return 0
}

# Validate join command
validate_join_command() {
  log_info "Validating join command..."

  if [[ -z "$JOIN_COMMAND" ]]; then
    log_error "JOIN_COMMAND is not set"
    log_error "Please run the installation on the control plane first"
    log_error "Or regenerate the join command with: ./k8s_installation.sh renew-tokens"
    return 1
  fi

  # Check if join command contains required components
  if ! echo "$JOIN_COMMAND" | grep -q "kubeadm join"; then
    log_error "JOIN_COMMAND does not appear to be valid"
    return 1
  fi

  if ! echo "$JOIN_COMMAND" | grep -q "token"; then
    log_error "JOIN_COMMAND does not contain a token"
    return 1
  fi

  log_success "Join command validated"
  return 0
}

# Validate nodes file
validate_nodes_file() {
  log_info "Validating nodes file: $NODES_FILE"

  if [[ ! -f "$NODES_FILE" ]]; then
    log_error "Nodes file not found: $NODES_FILE"
    log_info "Create $NODES_FILE with one IP address per line"
    return 1
  fi

  # Count non-empty, non-comment lines
  TOTAL_NODES=$(grep -v '^#' "$NODES_FILE" | grep -v '^$' | wc -l)

  if [[ $TOTAL_NODES -eq 0 ]]; then
    log_error "No nodes found in $NODES_FILE"
    return 1
  fi

  log_success "Found $TOTAL_NODES node(s) to add"
  return 0
}

# Test SSH connectivity to a node
test_ssh_connectivity() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Testing SSH connectivity..."

  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "echo 'SSH OK'" &>/dev/null

  if [[ $? -eq 0 ]]; then
    log_success "[$node_name] SSH connectivity verified"
    return 0
  else
    log_error "[$node_name] SSH connectivity failed"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Node Operations
# -----------------------------------------------------------------------------

# Copy installation scripts to remote node
copy_scripts_to_node() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Copying installation scripts..."

  # Create temporary directory on remote node
  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "mkdir -p /tmp/k8s-bootstrap" || return 1

  # Copy necessary files
  scp -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$PROJECT_ROOT/.env" \
      "$PROJECT_ROOT/k8s_precheck_installation.sh" \
      "$PROJECT_ROOT/k8s_installation.sh" \
      "$SSH_USER@$node_ip:/tmp/k8s-bootstrap/" || return 1

  # Copy lib directory
  scp -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      -r "$PROJECT_ROOT/lib" \
      "$SSH_USER@$node_ip:/tmp/k8s-bootstrap/" || return 1

  log_success "[$node_name] Scripts copied successfully"
  return 0
}

# Create secure join script on remote node
create_join_script() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Creating secure join script..."

  # Create join script remotely (avoids exposing JOIN_COMMAND in process list)
  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "cat > /tmp/k8s-bootstrap/join.sh" <<EOF
#!/bin/bash
cd /tmp/k8s-bootstrap
export JOIN_COMMAND='$JOIN_COMMAND'
export NODE_ROLE=worker
sudo -E bash k8s_installation.sh
EOF

  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "chmod 600 /tmp/k8s-bootstrap/join.sh" || return 1

  log_success "[$node_name] Join script created with secure permissions"
  return 0
}

# Run precheck on remote node
run_precheck() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Running pre-installation checks..."

  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "cd /tmp/k8s-bootstrap && sudo bash k8s_precheck_installation.sh" 2>&1 | tee -a "$LOG_FILE"

  if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    log_success "[$node_name] Pre-checks passed"
    return 0
  else
    log_error "[$node_name] Pre-checks failed"
    return 1
  fi
}

# Join node to cluster
join_node() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Joining node to cluster..."

  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "bash /tmp/k8s-bootstrap/join.sh" 2>&1 | tee -a "$LOG_FILE"

  if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    log_success "[$node_name] Node joined successfully"
    return 0
  else
    log_error "[$node_name] Node join failed"
    return 1
  fi
}

# Apply node labels
apply_node_labels() {
  local node_ip=$1
  local node_name=${2:-$node_ip}
  local labels=${3:-$NODE_LABELS}

  if [[ -z "$labels" ]]; then
    log_info "[$node_name] No labels to apply"
    return 0
  fi

  log_info "[$node_name] Applying node labels: $labels"

  # Get the actual node name from Kubernetes
  local k8s_node_name=$(kubectl get nodes -o wide | grep "$node_ip" | awk '{print $1}')

  if [[ -z "$k8s_node_name" ]]; then
    log_warn "[$node_name] Could not find Kubernetes node name, skipping labels"
    return 1
  fi

  # Apply each label
  IFS=',' read -ra LABEL_ARRAY <<< "$labels"
  for label in "${LABEL_ARRAY[@]}"; do
    kubectl label node "$k8s_node_name" "$label" --overwrite || {
      log_warn "[$node_name] Failed to apply label: $label"
    }
  done

  log_success "[$node_name] Labels applied"
  return 0
}

# Verify node health
verify_node_health() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Verifying node health..."

  # Wait for node to appear in cluster
  log_info "[$node_name] Waiting $POST_JOIN_WAIT seconds for node to stabilize..."
  sleep $POST_JOIN_WAIT

  # Get the actual node name from Kubernetes
  local k8s_node_name=$(kubectl get nodes -o wide | grep "$node_ip" | awk '{print $1}')

  if [[ -z "$k8s_node_name" ]]; then
    log_error "[$node_name] Node not found in cluster"
    return 1
  fi

  # Check node status
  local node_status=$(kubectl get node "$k8s_node_name" --no-headers | awk '{print $2}')

  if [[ "$node_status" == "Ready" ]]; then
    log_success "[$node_name] Node is Ready"

    # Check system pods on the node
    local pods_not_running=$(kubectl get pods -A -o wide --field-selector spec.nodeName="$k8s_node_name" | grep -v "Running\|Completed" | grep -v "NAMESPACE" | wc -l)

    if [[ $pods_not_running -eq 0 ]]; then
      log_success "[$node_name] All pods are running"
    else
      log_warn "[$node_name] $pods_not_running pod(s) not yet running"
    fi

    return 0
  else
    log_warn "[$node_name] Node status: $node_status (not Ready yet)"
    return 1
  fi
}

# Cleanup remote files
cleanup_remote_node() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  log_info "[$node_name] Cleaning up temporary files..."

  ssh -i "$SSH_KEY" \
      -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      "$SSH_USER@$node_ip" "rm -rf /tmp/k8s-bootstrap" || {
    log_warn "[$node_name] Failed to cleanup remote files"
  }
}

# -----------------------------------------------------------------------------
# Main Node Addition Workflow
# -----------------------------------------------------------------------------

add_worker_node() {
  local node_ip=$1
  local node_name=${2:-$node_ip}
  local attempt=${3:-1}

  log_info "=========================================="
  log_info "Processing node: $node_name ($node_ip)"
  log_info "Attempt: $attempt/$MAX_RETRIES"
  log_info "=========================================="

  NODE_ATTEMPTS[$node_ip]=$attempt

  # Test SSH connectivity
  if ! test_ssh_connectivity "$node_ip" "$node_name"; then
    NODE_STATUS[$node_ip]="ssh_failed"
    return 1
  fi

  # Copy scripts
  if ! copy_scripts_to_node "$node_ip" "$node_name"; then
    NODE_STATUS[$node_ip]="copy_failed"
    return 1
  fi

  # Create secure join script
  if ! create_join_script "$node_ip" "$node_name"; then
    NODE_STATUS[$node_ip]="script_failed"
    return 1
  fi

  # Run prechecks
  if ! run_precheck "$node_ip" "$node_name"; then
    NODE_STATUS[$node_ip]="precheck_failed"
    return 1
  fi

  # Join node to cluster
  if ! join_node "$node_ip" "$node_name"; then
    NODE_STATUS[$node_ip]="join_failed"
    return 1
  fi

  # Apply labels if configured
  if [[ -n "$NODE_LABELS" ]]; then
    apply_node_labels "$node_ip" "$node_name" "$NODE_LABELS"
  fi

  # Verify node health
  if ! verify_node_health "$node_ip" "$node_name"; then
    log_warn "[$node_name] Health check had warnings, but node joined"
  fi

  # Cleanup
  cleanup_remote_node "$node_ip" "$node_name"

  NODE_STATUS[$node_ip]="success"
  ((SUCCESSFUL_NODES++))

  log_success "=========================================="
  log_success "Node $node_name added successfully!"
  log_success "=========================================="

  return 0
}

# Retry failed node
retry_failed_node() {
  local node_ip=$1
  local node_name=${2:-$node_ip}

  local current_attempt=${NODE_ATTEMPTS[$node_ip]:-0}

  if [[ $current_attempt -ge $MAX_RETRIES ]]; then
    log_error "[$node_name] Max retries ($MAX_RETRIES) reached"
    NODE_STATUS[$node_ip]="max_retries"
    ((FAILED_NODES++))
    return 1
  fi

  local next_attempt=$((current_attempt + 1))

  log_warn "[$node_name] Retrying in $RETRY_DELAY seconds..."
  sleep $RETRY_DELAY

  add_worker_node "$node_ip" "$node_name" "$next_attempt"
}

# -----------------------------------------------------------------------------
# Parallel Execution Support
# -----------------------------------------------------------------------------

add_nodes_parallel() {
  log_info "Running in PARALLEL mode..."

  local pids=()

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    local node_ip=$(echo "$line" | awk '{print $1}')
    local node_name=$(echo "$line" | awk '{print $2}')
    [[ -z "$node_name" ]] && node_name=$node_ip

    # Run in background
    (
      if ! add_worker_node "$node_ip" "$node_name"; then
        retry_failed_node "$node_ip" "$node_name"
      fi
    ) &

    pids+=($!)

  done < "$NODES_FILE"

  # Wait for all background jobs
  log_info "Waiting for all nodes to complete..."

  for pid in "${pids[@]}"; do
    wait $pid || true
  done
}

# Serial execution
add_nodes_serial() {
  log_info "Running in SERIAL mode..."

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    local node_ip=$(echo "$line" | awk '{print $1}')
    local node_name=$(echo "$line" | awk '{print $2}')
    [[ -z "$node_name" ]] && node_name=$node_ip

    if ! add_worker_node "$node_ip" "$node_name"; then
      retry_failed_node "$node_ip" "$node_name"
    fi

  done < "$NODES_FILE"
}

# -----------------------------------------------------------------------------
# Summary Report
# -----------------------------------------------------------------------------

print_summary() {
  log_info ""
  log_info "=========================================="
  log_info "Worker Node Addition Summary"
  log_info "=========================================="
  log_info "Total nodes: $TOTAL_NODES"
  log_success "Successful: $SUCCESSFUL_NODES"
  log_error "Failed: $FAILED_NODES"
  log_info ""

  if [[ $FAILED_NODES -gt 0 ]]; then
    log_info "Failed nodes:"
    for node_ip in "${!NODE_STATUS[@]}"; do
      if [[ "${NODE_STATUS[$node_ip]}" != "success" ]]; then
        log_error "  - $node_ip: ${NODE_STATUS[$node_ip]}"
      fi
    done
    log_info ""
  fi

  log_info "Cluster status:"
  kubectl get nodes -o wide || log_warn "Failed to get cluster nodes"

  log_info ""
  log_info "Log file: $LOG_FILE"
  log_info "=========================================="

  if [[ $FAILED_NODES -eq 0 ]]; then
    log_success "All nodes added successfully!"
    return 0
  else
    log_error "Some nodes failed to join"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

main() {
  log_info "=========================================="
  log_info "Kubernetes Worker Node Addition Script"
  log_info "=========================================="
  log_info "Start time: $(date)"
  log_info ""

  # Validations
  validate_ssh_key || exit 1
  validate_join_command || exit 1
  validate_nodes_file || exit 1

  log_info ""

  # Add nodes
  if [[ "$PARALLEL_EXECUTION" == "true" ]]; then
    add_nodes_parallel
  else
    add_nodes_serial
  fi

  # Print summary
  print_summary

  exit $?
}

# Run main function
main "$@"