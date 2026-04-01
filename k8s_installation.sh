
#!/bin/bash

# =============================================================================
# Kubernetes Bootstrap Installation - Main Orchestrator
# =============================================================================

set -e

# Source configuration
if [[ ! -f ".env" ]]; then
  echo "❌ ERROR: .env file not found"
  echo "Please create .env file from .env.example"
  exit 1
fi

source .env

# Load reusable function libraries
source lib/common.sh
source lib/install.sh
source lib/kubeadm_config.sh
source lib/kubeadm.sh
source lib/network.sh

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
  # Initialize logging
  init_logging
  rotate_logs

  log_info "==================================================="
  log_info "Starting Kubernetes Bootstrap Installation"
  log_info "==================================================="

  # Validate configuration
  validate_config || {
    log_error "Configuration validation failed. Exiting."
    exit 1
  }

  # Set hostname
  set_hostname

  # Install container runtime
  install_container_runtime

  # Install Kubernetes tools
  install_kubernetes_tools

  # Branch based on node role
  if [[ "$NODE_ROLE" == "control-plane" ]]; then
    install_control_plane
  else
    install_worker
  fi

  # Post-installation validation
  if [[ "${SKIP_VALIDATION:-false}" != "true" ]]; then
    log_info ""
    log_info "Running post-installation validation..."
    sleep 10  # Give cluster a moment to stabilize

    if post_install_validation; then
      log_success "Post-installation validation passed!"
    else
      log_warn "Post-installation validation found issues (non-fatal)"
      log_warn "The cluster may need a few more minutes to fully initialize"
    fi
  fi

  # Print installation summary
  log_info ""
  print_installation_summary
}

# =============================================================================
# Control Plane Installation
# =============================================================================

install_control_plane() {
  log_info "==================================================="
  log_info "Installing Control Plane"
  log_info "==================================================="

  # Initialize control plane with kubeadm
  init_control_plane

  # Setup kubectl access
  setup_kubectl

  # Install CNI network plugin
  install_network_plugin

  # Handle single-node vs multi-node
  allow_master_schedule

  # Apply node labels and taints
  apply_node_labels
  apply_node_taints

  # Generate join commands for workers and additional control planes
  generate_join_command

  log_success "Control plane installation completed!"
}

# =============================================================================
# Worker Node Installation
# =============================================================================

install_worker() {
  log_info "==================================================="
  log_info "Installing Worker Node"
  log_info "==================================================="

  # Join the cluster
  join_worker

  log_success "Worker node installation completed!"
}

# =============================================================================
# Cleanup Handler (for manual cleanup)
# =============================================================================

cleanup() {
  log_info "Cleanup requested..."
  cleanup_cluster
}

# =============================================================================
# Token Renewal Handler (for maintenance)
# =============================================================================

renew_tokens() {
  log_info "Token renewal requested..."

  if [[ "$NODE_ROLE" != "control-plane" ]]; then
    log_error "Token renewal can only be run on control plane nodes"
    exit 1
  fi

  source lib/kubeadm.sh
  check_and_renew_token
}

# =============================================================================
# Entry Point
# =============================================================================

# Parse command line arguments
case "${1:-install}" in
  install)
    main
    ;;
  cleanup)
    cleanup
    ;;
  renew-tokens)
    renew_tokens
    ;;
  --help|-h)
    echo "Usage: $0 [install|cleanup|renew-tokens]"
    echo ""
    echo "Commands:"
    echo "  install       - Install Kubernetes cluster (default)"
    echo "  cleanup       - Cleanup/remove Kubernetes installation"
    echo "  renew-tokens  - Renew join tokens (control plane only)"
    echo ""
    echo "Environment:"
    echo "  Configuration is read from .env file"
    echo ""
    exit 0
    ;;
  *)
    log_error "Unknown command: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
esac