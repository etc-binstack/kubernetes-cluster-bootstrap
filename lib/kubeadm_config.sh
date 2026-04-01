# =============================================================================
# KUBEADM CONFIG FILE GENERATION
# =============================================================================

# Generate kubeadm config file for control plane init
generate_kubeadm_config() {
  log_info "Generating kubeadm configuration file..." >&2

  local config_file="/tmp/kubeadm-config.yaml"

  # Determine control plane endpoint
  local cp_endpoint=""
  if [[ "${HA_MODE}" == "true" && -n "${CONTROL_PLANE_ENDPOINT}" ]]; then
    cp_endpoint="${CONTROL_PLANE_ENDPOINT}"
  fi

  # Determine API server advertise address
  local advertise_addr="${API_SERVER_ADVERTISE_ADDRESS}"
  if [[ -z "${advertise_addr}" ]]; then
    advertise_addr=$(hostname -I | awk '{print $1}')
    log_info "Auto-detected advertise address: ${advertise_addr}" >&2
  fi

  # Build cert SANs list
  local cert_sans=""
  if [[ -n "${CERT_EXTRA_SANS}" ]]; then
    IFS=',' read -ra SANS <<< "$CERT_EXTRA_SANS"
    for san in "${SANS[@]}"; do
      cert_sans="${cert_sans}  - \"${san}\"\n"
    done
  fi

  # Build feature gates
  local feature_gates=""
  if [[ -n "${FEATURE_GATES}" ]]; then
    IFS=',' read -ra GATES <<< "$FEATURE_GATES"
    for gate in "${GATES[@]}"; do
      IFS='=' read -ra PARTS <<< "$gate"
      feature_gates="${feature_gates}    ${PARTS[0]}: ${PARTS[1]}\n"
    done
  fi

  # Build etcd configuration
  local etcd_config=""
  if [[ "${EXTERNAL_ETCD_ENABLED}" == "true" ]]; then
    etcd_config="  external:
    endpoints:"

    IFS=',' read -ra ENDPOINTS <<< "$EXTERNAL_ETCD_ENDPOINTS"
    for endpoint in "${ENDPOINTS[@]}"; do
      etcd_config="${etcd_config}
    - ${endpoint}"
    done

    if [[ -n "${EXTERNAL_ETCD_CA_FILE}" ]]; then
      etcd_config="${etcd_config}
    caFile: ${EXTERNAL_ETCD_CA_FILE}
    certFile: ${EXTERNAL_ETCD_CERT_FILE}
    keyFile: ${EXTERNAL_ETCD_KEY_FILE}"
    fi
  else
    etcd_config="  local:
    dataDir: /var/lib/etcd"
  fi

  # Generate the config file
  cat > "$config_file" <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${advertise_addr}
  bindPort: ${API_SERVER_BIND_PORT:-6443}
nodeRegistration:
  criSocket: unix:///var/run/${CONTAINER_RUNTIME}/${CONTAINER_RUNTIME}.sock
  imagePullPolicy: IfNotPresent
  name: $(hostname)
$(if [[ -n "${NODE_LABELS}" ]]; then
  echo "  kubeletExtraArgs:"
  IFS=',' read -ra LABELS <<< "$NODE_LABELS"
  for label in "${LABELS[@]}"; do
    IFS='=' read -ra PARTS <<< "$label"
    echo "    node-labels: \"${PARTS[0]}=${PARTS[1]}\""
  done
fi)
$(if [[ -n "${NODE_TAINTS}" ]]; then
  echo "  taints:"
  IFS=',' read -ra TAINTS <<< "$NODE_TAINTS"
  for taint in "${TAINTS[@]}"; do
    IFS='=' read -ra PARTS <<< "$taint"
    IFS=':' read -ra KEY_EFFECT <<< "${PARTS[0]}"
    echo "  - effect: ${PARTS[1]}"
    echo "    key: ${KEY_EFFECT[0]}"
    if [[ ${#PARTS[@]} -gt 1 ]]; then
      echo "    value: \"${PARTS[1]}\""
    fi
  done
fi)
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}.0
$(if [[ -n "${cp_endpoint}" ]]; then
  echo "controlPlaneEndpoint: \"${cp_endpoint}\""
fi)
networking:
  podSubnet: ${POD_NETWORK_CIDR}
  serviceSubnet: ${SERVICE_CIDR:-10.96.0.0/12}
  dnsDomain: ${CLUSTER_DNS_DOMAIN:-cluster.local}
apiServer:
  certSANs:
  - $(hostname)
  - ${advertise_addr}
$(if [[ -n "${cert_sans}" ]]; then echo -e "${cert_sans}"; fi)
  extraArgs:
    advertise-address: ${advertise_addr}
    bind-address: ${API_SERVER_BIND_ADDRESS:-0.0.0.0}
$(if [[ "${AUDIT_LOG_ENABLED}" == "true" ]]; then
  echo "    audit-log-path: ${AUDIT_LOG_PATH}"
  echo "    audit-log-maxage: \"${AUDIT_LOG_MAX_AGE}\""
  echo "    audit-log-maxbackup: \"${AUDIT_LOG_MAX_BACKUP}\""
  echo "    audit-log-maxsize: \"${AUDIT_LOG_MAX_SIZE}\""
  echo "    audit-policy-file: /etc/kubernetes/audit-policy.yaml"
fi)
$(if [[ "${ENCRYPTION_AT_REST}" == "true" ]]; then
  echo "    encryption-provider-config: /etc/kubernetes/encryption-config.yaml"
fi)
$(if [[ -n "${KUBEADM_EXTRA_ARGS}" ]]; then
  IFS=' ' read -ra ARGS <<< "$KUBEADM_EXTRA_ARGS"
  for arg in "${ARGS[@]}"; do
    IFS='=' read -ra PARTS <<< "$arg"
    echo "    ${PARTS[0]#--}: \"${PARTS[1]}\""
  done
fi)
$(if [[ "${AUDIT_LOG_ENABLED}" == "true" ]]; then
  echo "  extraVolumes:
  - name: audit-log
    hostPath: $(dirname ${AUDIT_LOG_PATH})
    mountPath: $(dirname ${AUDIT_LOG_PATH})
    readOnly: false
    pathType: DirectoryOrCreate
  - name: audit-policy
    hostPath: /etc/kubernetes/audit-policy.yaml
    mountPath: /etc/kubernetes/audit-policy.yaml
    readOnly: true
    pathType: File"
fi)
$(if [[ "${ENCRYPTION_AT_REST}" == "true" ]]; then
  echo "  - name: encryption-config
    hostPath: /etc/kubernetes/encryption-config.yaml
    mountPath: /etc/kubernetes/encryption-config.yaml
    readOnly: true
    pathType: File"
fi)
controllerManager:
  extraArgs:
    bind-address: 0.0.0.0
$(if [[ -n "${feature_gates}" ]]; then
  echo "    feature-gates: |"
  echo -e "${feature_gates}"
fi)
scheduler:
  extraArgs:
    bind-address: 0.0.0.0
etcd:
${etcd_config}
certificatesDir: /etc/kubernetes/pki
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: ${CGROUP_DRIVER:-systemd}
clusterDNS:
- ${CLUSTER_DNS_IP:-10.96.0.10}
clusterDomain: ${CLUSTER_DNS_DOMAIN:-cluster.local}
$(if [[ -n "${KUBELET_EXTRA_ARGS}" ]]; then
  echo "${KUBELET_EXTRA_ARGS}"
fi)
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: iptables
EOF

  log_success "Kubeadm config generated: ${config_file}" >&2
  log_debug "Config file contents:" >&2
  [[ "${LOG_LEVEL}" == "debug" ]] && cat "$config_file" >&2

  echo "$config_file"
}

# Generate kubeadm join config for workers
generate_join_config() {
  log_info "Generating kubeadm join configuration..." >&2

  local config_file="/tmp/kubeadm-join-config.yaml"
  local node_name=$(hostname)

  # Extract token and ca-cert-hash from JOIN_COMMAND
  local token=$(echo "$JOIN_COMMAND" | grep -oP 'token \K[^\s]+')
  local discovery_hash=$(echo "$JOIN_COMMAND" | grep -oP 'discovery-token-ca-cert-hash \K[^\s]+')
  local api_endpoint=$(echo "$JOIN_COMMAND" | grep -oP 'join \K[^\s]+')

  if [[ -z "$token" || -z "$discovery_hash" || -z "$api_endpoint" ]]; then
    log_error "Failed to parse JOIN_COMMAND" >&2
    return 1
  fi

  cat > "$config_file" <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: ${api_endpoint}
    token: ${token}
    caCertHashes:
    - ${discovery_hash}
    unsafeSkipCAVerification: false
  timeout: 5m0s
nodeRegistration:
  criSocket: unix:///var/run/${CONTAINER_RUNTIME}/${CONTAINER_RUNTIME}.sock
  imagePullPolicy: IfNotPresent
  name: ${node_name}
$(if [[ -n "${NODE_LABELS}" ]]; then
  echo "  kubeletExtraArgs:"
  IFS=',' read -ra LABELS <<< "$NODE_LABELS"
  for label in "${LABELS[@]}"; do
    IFS='=' read -ra PARTS <<< "$label"
    echo "    node-labels: \"${PARTS[0]}=${PARTS[1]}\""
  done
fi)
$(if [[ -n "${NODE_TAINTS}" ]]; then
  echo "  taints:"
  IFS=',' read -ra TAINTS <<< "$NODE_TAINTS"
  for taint in "${TAINTS[@]}"; do
    IFS='=' read -ra PARTS <<< "$taint"
    echo "  - effect: ${PARTS[1]}"
    echo "    key: ${PARTS[0]}"
  done
fi)
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: ${CGROUP_DRIVER:-systemd}
EOF

  log_success "Join config generated: ${config_file}" >&2
  echo "$config_file"
}

# Generate audit policy file
generate_audit_policy() {
  if [[ "${AUDIT_LOG_ENABLED}" != "true" ]]; then
    return 0
  fi

  log_info "Generating audit policy..."

  mkdir -p /etc/kubernetes
  cat > /etc/kubernetes/audit-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all requests at Metadata level
  - level: Metadata
    omitStages:
      - RequestReceived
EOF

  log_success "Audit policy created: /etc/kubernetes/audit-policy.yaml"
}

# Generate encryption config
generate_encryption_config() {
  if [[ "${ENCRYPTION_AT_REST}" != "true" ]]; then
    return 0
  fi

  log_info "Generating encryption configuration..."

  # Generate encryption key if not provided
  local enc_key="${ENCRYPTION_KEY}"
  if [[ -z "${enc_key}" ]]; then
    enc_key=$(head -c 32 /dev/urandom | base64)
    log_info "Generated new encryption key"
  fi

  mkdir -p /etc/kubernetes
  cat > /etc/kubernetes/encryption-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${enc_key}
      - identity: {}
EOF

  chmod 600 /etc/kubernetes/encryption-config.yaml
  log_success "Encryption config created: /etc/kubernetes/encryption-config.yaml"
}
