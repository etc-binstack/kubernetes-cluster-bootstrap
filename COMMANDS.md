# Kubernetes Bootstrap - Commands & Step-by-Step Guide

**Complete command reference and installation guide for K8s Bootstrap Production**

---

## Table of Contents

1. [Pre-requisites (Manual Setup)](#1-pre-requisites-manual-setup)
2. [Configure Environment File](#2-configure-environment-file)
3. [Create Worker Nodes File](#3-create-worker-nodes-file)
4. [Test SSH Connectivity](#4-test-ssh-connectivity)
5. [Step-by-Step Installation](#5-step-by-step-installation)
6. [Failure Recovery & Cleanup](#6-failure-recovery--cleanup)
7. [Common Commands Reference](#7-common-commands-reference)
8. [Troubleshooting](#8-troubleshooting)

---

📄 File Structure:
```
COMMANDS.md
├── Table of Contents (with anchors)
├── 1. Pre-requisites (SSH Key Setup)
├── 2. Configure .env File
├── 3. Create nodes.txt File
├── 4. Test SSH Connectivity
├── 5. Step-by-Step Installation
│   ├── Single-Node Installation
│   ├── Multi-Node Installation
│   └── HA Installation
├── 6. Failure Recovery & Cleanup
├── 7. Common Commands Reference
├── 8. Troubleshooting
└── Quick Reference Card
```

---

## 1. Pre-requisites (Manual Setup)

### SSH Key Setup

#### **Option A: Use Existing SSH Key**

```bash
# Check if SSH key exists
ls -la ~/.ssh/id_rsa

# If exists, verify permissions
chmod 600 ~/.ssh/id_rsa

# Update .env file
SSH_KEY=~/.ssh/id_rsa
```

#### **Option B: Generate New SSH Key**

```bash
# Generate SSH key pair (no passphrase for automation)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s_nodes -N ""

# Set proper permissions
chmod 600 ~/.ssh/k8s_nodes
chmod 644 ~/.ssh/k8s_nodes.pub

# Update .env file
SSH_KEY=~/.ssh/k8s_nodes
```

#### **Option C: AWS PEM Key**

```bash
# Download PEM key from AWS Console
# Save to: ~/k8s-cluster.pem

# Set proper permissions (required for AWS keys)
chmod 400 ~/k8s-cluster.pem

# Update .env file
SSH_KEY=~/k8s-cluster.pem
SSH_USER=ubuntu  # or ec2-user for Amazon Linux
```

### Distribute SSH Key to Worker Nodes

**Method 1: Using ssh-copy-id (Recommended)**

```bash
# Copy public key to each worker node
ssh-copy-id -i ~/.ssh/id_rsa ubuntu@10.0.1.10
ssh-copy-id -i ~/.ssh/id_rsa ubuntu@10.0.1.11
ssh-copy-id -i ~/.ssh/id_rsa ubuntu@10.0.1.12

# Verify access (should not prompt for password)
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10 "echo 'SSH OK'"
```

**Method 2: Manual Key Distribution**

```bash
# Copy public key content
cat ~/.ssh/id_rsa.pub

# SSH to each worker and add key
ssh ubuntu@10.0.1.10
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "paste-your-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

**Method 3: AWS EC2 (Key Pre-configured)**

```bash
# AWS EC2 instances come with SSH key pre-configured during launch
# Just download the PEM key from AWS Console
# No manual key distribution needed

# Test connectivity
ssh -i ~/k8s-cluster.pem ubuntu@<instance-ip> "echo 'SSH OK'"
```

---

## 2. Configure Environment File

### Step 1: Copy Example File

```bash
# Navigate to project directory
cd k8s-bootstrap-prod

# Copy .env.example to .env
cp .env.example .env
```

### Step 2: Edit Configuration

```bash
# Open .env in your favorite editor
nano .env
# or
vim .env
# or
code .env  # VS Code
```

### Step 3: Basic Configuration

**For Single-Node Cluster (Development/Testing):**

```bash
# Cluster Configuration
CLUSTER_MODE=single              # single node deployment
NODE_ROLE=control-plane          # this is the control plane

# Node Configuration
CONTROL_PLANE_HOSTNAME=k8s-master
NUMBER_OF_NODES=1

# Network Configuration
POD_NETWORK_CIDR=192.168.0.0/16
SERVICE_CIDR=10.96.0.0/12
NETWORK_PLUGIN=calico            # calico | flannel | cilium | weave

# Container Runtime
CONTAINER_RUNTIME=containerd     # containerd | cri-o
K8S_VERSION=1.29

# SSH Configuration (not needed for single-node)
SSH_USER=ubuntu
SSH_KEY=~/.ssh/id_rsa
SSH_PORT=22
```

**For Multi-Node Cluster (Production):**

```bash
# Cluster Configuration
CLUSTER_MODE=multi               # multi-node deployment
NODE_ROLE=control-plane          # control plane node

# Node Configuration
CONTROL_PLANE_HOSTNAME=k8s-control-plane-01
NUMBER_OF_NODES=4                # 1 control plane + 3 workers
ATTACHED_NODES=0                 # increment as you add workers

# Network Configuration
POD_NETWORK_CIDR=192.168.0.0/16
SERVICE_CIDR=10.96.0.0/12
NETWORK_PLUGIN=calico

# Container Runtime
CONTAINER_RUNTIME=containerd
K8S_VERSION=1.29

# SSH Configuration (REQUIRED for multi-node)
SSH_USER=ubuntu
SSH_KEY=~/.ssh/id_rsa            # or ~/k8s-cluster.pem for AWS
SSH_PORT=22

# Worker Node Addition Configuration
NODES_FILE=scripts/nodes.txt
PARALLEL_EXECUTION=false         # true for faster parallel join
MAX_RETRIES=3
RETRY_DELAY=10
SSH_TIMEOUT=30
POST_JOIN_WAIT=60
```

**For HA Cluster (High Availability):**

```bash
# Cluster Configuration
CLUSTER_MODE=ha                  # high availability mode
NODE_ROLE=control-plane          # first control plane node

# HA Control Plane Settings
HA_MODE=true
CONTROL_PLANE_COUNT=3            # 3, 5, or 7 recommended
CONTROL_PLANE_IPS="10.0.1.10,10.0.1.11,10.0.1.12"

# Load Balancer Configuration (REQUIRED for HA)
LOAD_BALANCER_ENABLED=true
LOAD_BALANCER_DNS="k8s-api.example.com"  # or use IP
LOAD_BALANCER_IP="10.0.1.100"
LOAD_BALANCER_PORT=6443

# Auto-configured control plane endpoint
CONTROL_PLANE_ENDPOINT="${LOAD_BALANCER_IP}:${LOAD_BALANCER_PORT}"

# Network Configuration
POD_NETWORK_CIDR=192.168.0.0/16
SERVICE_CIDR=10.96.0.0/12
NETWORK_PLUGIN=calico

# Container Runtime
CONTAINER_RUNTIME=containerd
K8S_VERSION=1.29

# Certificate Configuration
CERT_VALIDITY_DAYS=365
CERT_EXTRA_SANS="k8s-api.example.com,10.0.1.100"

# SSH Configuration
SSH_USER=ubuntu
SSH_KEY=~/.ssh/id_rsa
SSH_PORT=22
```

### Step 4: Advanced Configuration (Optional)

**Proxy Environment:**

```bash
# Proxy Configuration
HTTP_PROXY="http://proxy.example.com:8080"
HTTPS_PROXY="http://proxy.example.com:8080"
NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16,.cluster.local"
```

**CNI Customization:**

```bash
# Calico Configuration
CNI_VERSION="v3.27.0"            # pin specific version
CALICO_IPV4POOL_CIDR="192.168.0.0/16"
CALICO_IP_IN_IP=false            # or true for IP-in-IP encapsulation
CALICO_VXLAN=true                # or false to disable VXLAN

# Flannel Configuration
FLANNEL_BACKEND="vxlan"          # vxlan | host-gw | udp | wireguard

# Weave Net Configuration
WEAVE_ENCRYPTION=true            # enable encryption
WEAVE_PASSWORD="your-secure-password"
```

**Security Configuration:**

```bash
# Encryption at Rest
ENCRYPTION_AT_REST=true

# Audit Logging
AUDIT_LOG_ENABLED=true
AUDIT_LOG_PATH=/var/log/kubernetes/audit.log
AUDIT_LOG_MAX_AGE=30
AUDIT_LOG_MAX_BACKUP=10
AUDIT_LOG_MAX_SIZE=100

# Certificate Management
CERT_VALIDITY_DAYS=365
CERT_RENEW_BEFORE_DAYS=30
CERT_AUTO_RENEW=false
```

**Logging Configuration:**

```bash
# Logging
LOG_LEVEL=info                   # debug | info | warn | error
LOG_DIR=/var/log/k8s-bootstrap
LOG_RETENTION_DAYS=30
```

### Step 5: Verify Configuration

```bash
# Check .env file
cat .env | grep -v '^#' | grep -v '^$'

# Validate required variables
grep -E '^(CLUSTER_MODE|NODE_ROLE|NETWORK_PLUGIN|CONTAINER_RUNTIME)=' .env
```

---

## 3. Create Worker Nodes File

### Step 1: Copy Example File

```bash
# Copy example file
cp scripts/nodes.txt.example scripts/nodes.txt
```

### Step 2: Edit nodes.txt

```bash
# Open in editor
nano scripts/nodes.txt
# or
vim scripts/nodes.txt
```

### Step 3: Add Worker Node IPs

**Format:**
```
IP_ADDRESS [OPTIONAL_NAME]
```

**Example 1: Simple (IP only)**

```txt
# Worker nodes for production cluster
10.0.1.10
10.0.1.11
10.0.1.12
```

**Example 2: With Names**

```txt
# Worker nodes with custom names
10.0.1.10 worker-node-01
10.0.1.11 worker-node-02
10.0.1.12 worker-node-03
10.0.1.13 worker-node-04
```

**Example 3: With Comments**

```txt
# =============================================================================
# Production Kubernetes Worker Nodes
# =============================================================================
# Zone: us-east-1a
10.0.1.10 worker-zone-a-01
10.0.1.11 worker-zone-a-02

# Zone: us-east-1b
10.0.2.10 worker-zone-b-01
10.0.2.11 worker-zone-b-02

# Zone: us-east-1c
10.0.3.10 worker-zone-c-01
10.0.3.11 worker-zone-c-02
```

### Step 4: Verify nodes.txt

```bash
# Check file content
cat scripts/nodes.txt

# Count worker nodes (excluding comments and empty lines)
grep -v '^#' scripts/nodes.txt | grep -v '^$' | wc -l

# Preview what will be processed
grep -v '^#' scripts/nodes.txt | grep -v '^$'
```

---

## 4. Test SSH Connectivity

### Test SSH Access to Control Plane (if remote)

```bash
# Test SSH connectivity to control plane
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.5 "echo 'Control Plane SSH OK'"

# Test with timeout
ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 ubuntu@10.0.1.5 "echo 'SSH OK'"
```

### Test SSH Access to All Worker Nodes

```bash
# Test single worker
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10 "echo 'Worker SSH OK'"

# Test all workers from nodes.txt
while read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^#.*$ ]] && continue
  [[ -z "$line" ]] && continue

  # Extract IP (first column)
  ip=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')

  echo "Testing SSH: $ip ${name:+($name)}"
  ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 ubuntu@$ip "echo '  ✅ SSH OK'" || echo "  ❌ SSH FAILED"
done < scripts/nodes.txt
```

### Test Root Access (Required for Installation)

```bash
# Test sudo access on worker nodes
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10 "sudo echo 'Root access OK'"

# Test on all workers
while read -r line; do
  [[ "$line" =~ ^#.*$ ]] && continue
  [[ -z "$line" ]] && continue
  ip=$(echo "$line" | awk '{print $1}')
  echo "Testing root access: $ip"
  ssh -i ~/.ssh/id_rsa ubuntu@$ip "sudo echo '  ✅ Root access OK'" || echo "  ❌ Root access FAILED"
done < scripts/nodes.txt
```

### Automated SSH Test Script

```bash
# Create a test script
cat > test_ssh.sh <<'EOF'
#!/bin/bash
source .env

echo "Testing SSH connectivity to all worker nodes..."
echo ""

while read -r line; do
  [[ "$line" =~ ^#.*$ ]] && continue
  [[ -z "$line" ]] && continue

  ip=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')

  printf "%-20s %-15s " "${name:-$ip}" "$ip"

  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
     "$SSH_USER@$ip" "sudo echo 'OK' > /dev/null 2>&1"; then
    echo "✅ SSH OK"
  else
    echo "❌ SSH FAILED"
  fi
done < "$NODES_FILE"
EOF

chmod +x test_ssh.sh
./test_ssh.sh
```

---

## 5. Step-by-Step Installation

### Single-Node Installation

#### **Step 1: Run Pre-flight Checks**

```bash
# Run precheck script
sudo bash k8s_precheck_installation.sh

# Expected output:
# ✅ Root privilege check passed
# ✅ OS check passed (Ubuntu)
# ✅ CPU check passed (2 cores)
# ✅ RAM check passed (4096MB)
# ✅ Disk space check passed (50GB available)
# ✅ Kernel version check passed (5.15.0)
# ✅ Kernel modules check passed (br_netfilter, overlay)
# ✅ Swap check passed (disabled)
# ✅ Port availability check passed
# ✅ DNS resolution check passed
# ✅ Internet connectivity check passed
# ✅ Time synchronization service is active
# ✅ All prechecks passed successfully
```

#### **Step 2: Install Kubernetes Cluster**

```bash
# Run installation
sudo bash k8s_installation.sh

# Or explicitly specify install command
sudo bash k8s_installation.sh install

# Installation takes 5-10 minutes
# Logs are saved to: /var/log/k8s-bootstrap/
```

#### **Step 3: Verify Installation**

```bash
# Check cluster status
kubectl get nodes

# Expected output:
# NAME             STATUS   ROLES           AGE   VERSION
# k8s-master       Ready    control-plane   2m    v1.29.0

# Check system pods
kubectl get pods -n kube-system

# Check cluster info
kubectl cluster-info

# Check component status
kubectl get componentstatuses
```

#### **Step 4: Test Cluster**

```bash
# Deploy test pod
kubectl run nginx --image=nginx --port=80

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/nginx --timeout=60s

# Check pod status
kubectl get pods

# Expose service
kubectl expose pod nginx --type=NodePort --port=80

# Get service details
kubectl get svc nginx

# Test (get NodePort)
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://localhost:$NODE_PORT

# Cleanup test resources
kubectl delete pod nginx
kubectl delete svc nginx
```

---

### Multi-Node Installation

#### **Control Plane Installation (Step 1-3)**

**On Control Plane Node:**

```bash
# Step 1: Update .env
nano .env
# Set: CLUSTER_MODE=multi
# Set: NODE_ROLE=control-plane

# Step 2: Run precheck
sudo bash k8s_precheck_installation.sh

# Step 3: Install control plane
sudo bash k8s_installation.sh

# Step 4: Verify control plane
kubectl get nodes
kubectl get pods -n kube-system

# Step 5: Verify join command was generated
ls -la join.sh
cat join.sh

# Step 6: Copy JOIN_COMMAND to .env (or note it down)
grep "kubeadm join" join.sh
```

#### **Worker Nodes Addition (Step 4-6)**

**Option A: Automated SSH Join (Recommended)**

```bash
# On control plane node:

# Step 1: Verify nodes.txt is configured
cat scripts/nodes.txt

# Step 2: Verify SSH connectivity
# (Use test script from section 4)
./test_ssh.sh

# Step 3: Copy JOIN_COMMAND to .env
# Extract join command from join.sh
JOIN_CMD=$(grep "kubeadm join" join.sh)

# Add to .env file
echo "JOIN_COMMAND=\"$JOIN_CMD\"" >> .env

# Step 4: Run automated worker addition
sudo bash scripts/add_nodes.sh

# Monitor progress in real-time
tail -f /var/log/k8s-bootstrap/add_nodes_*.log
```

**Option B: Manual Worker Join**

```bash
# On each worker node:

# Step 1: Copy installation files to worker
scp -i ~/.ssh/id_rsa -r .env lib/ k8s_* ubuntu@10.0.1.10:~/k8s-bootstrap/

# Step 2: SSH to worker
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10

# Step 3: Update .env on worker
cd ~/k8s-bootstrap
nano .env
# Set: NODE_ROLE=worker
# Add: JOIN_COMMAND="kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"

# Step 4: Run precheck
sudo bash k8s_precheck_installation.sh

# Step 5: Install worker
sudo bash k8s_installation.sh

# Step 6: Exit worker node
exit

# Step 7: Verify on control plane
kubectl get nodes
```

#### **Verify Multi-Node Cluster**

```bash
# On control plane:

# Check all nodes are Ready
kubectl get nodes -o wide

# Expected output:
# NAME                STATUS   ROLES           AGE   VERSION   INTERNAL-IP
# k8s-control-plane   Ready    control-plane   10m   v1.29.0   10.0.1.5
# worker-node-01      Ready    <none>          5m    v1.29.0   10.0.1.10
# worker-node-02      Ready    <none>          5m    v1.29.0   10.0.1.11
# worker-node-03      Ready    <none>          5m    v1.29.0   10.0.1.12

# Check pods distribution
kubectl get pods -A -o wide

# Check node details
kubectl describe nodes

# Test pod scheduling on workers
kubectl run test-pod --image=nginx --replicas=3
kubectl get pods -o wide  # Should be distributed across workers
kubectl delete deployment test-pod
```

---

### HA (High Availability) Installation

#### **Prerequisites**

```bash
# You need:
# - 3, 5, or 7 control plane nodes (odd numbers)
# - 1 load balancer (HAProxy, NGINX, or cloud LB)
# - Static IPs for all control plane nodes
# - Load balancer DNS name or VIP
```

#### **Step 1: Setup Load Balancer**

**HAProxy Configuration Example:**

```bash
# Install HAProxy on dedicated node
sudo apt-get update
sudo apt-get install -y haproxy

# Configure HAProxy
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend k8s_api
    bind *:6443
    default_backend k8s_control_plane

backend k8s_control_plane
    balance roundrobin
    option tcp-check
    server control-plane-01 10.0.1.10:6443 check
    server control-plane-02 10.0.1.11:6443 check
    server control-plane-03 10.0.1.12:6443 check
EOF

# Restart HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# Verify HAProxy
sudo systemctl status haproxy
```

#### **Step 2: First Control Plane Node**

```bash
# On first control plane (10.0.1.10):

# Update .env
CLUSTER_MODE=ha
NODE_ROLE=control-plane
HA_MODE=true
CONTROL_PLANE_COUNT=3
CONTROL_PLANE_IPS="10.0.1.10,10.0.1.11,10.0.1.12"
LOAD_BALANCER_ENABLED=true
LOAD_BALANCER_DNS="k8s-api.example.com"
LOAD_BALANCER_IP="10.0.1.100"
LOAD_BALANCER_PORT=6443

# Run precheck
sudo bash k8s_precheck_installation.sh

# Install first control plane
sudo bash k8s_installation.sh

# Verify and save certificate key
cat join-control-plane.sh
# Note: This contains certificate key for additional control planes
```

#### **Step 3: Additional Control Plane Nodes**

```bash
# On second control plane (10.0.1.11):

# Copy join-control-plane.sh from first control plane
scp -i ~/.ssh/id_rsa ubuntu@10.0.1.10:~/join-control-plane.sh ~/

# Copy .env and scripts
scp -i ~/.ssh/id_rsa ubuntu@10.0.1.10:~/k8s-bootstrap/.env ~/k8s-bootstrap/
scp -i ~/.ssh/id_rsa -r ubuntu@10.0.1.10:~/k8s-bootstrap/lib ~/k8s-bootstrap/

# Run precheck
sudo bash k8s_precheck_installation.sh

# Join as control plane
sudo bash join-control-plane.sh

# Verify on first control plane
kubectl get nodes
# Should show 2 control plane nodes

# Repeat for third control plane (10.0.1.12)
```

#### **Step 4: Add Worker Nodes**

```bash
# Same as multi-node installation
# Use scripts/add_nodes.sh for automated addition
sudo bash scripts/add_nodes.sh
```

#### **Step 5: Verify HA Cluster**

```bash
# Check all control plane nodes
kubectl get nodes | grep control-plane

# Expected output: 3 control plane nodes in Ready state

# Check etcd cluster health
kubectl exec -n kube-system etcd-<control-plane-name> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Test API server through load balancer
curl -k https://k8s-api.example.com:6443/healthz

# Test failover: Stop one control plane
ssh ubuntu@10.0.1.10 "sudo systemctl stop kubelet"
kubectl get nodes  # Should still work through LB
ssh ubuntu@10.0.1.10 "sudo systemctl start kubelet"
```

---

## 6. Failure Recovery & Cleanup

### Check Installation Logs

```bash
# View latest installation log
sudo tail -f /var/log/k8s-bootstrap/k8s_install_control-plane_*.log

# List all logs
ls -lht /var/log/k8s-bootstrap/

# View specific log
sudo cat /var/log/k8s-bootstrap/k8s_install_control-plane_20260401_120000.log

# Search for errors
sudo grep -i error /var/log/k8s-bootstrap/*.log
sudo grep -i failed /var/log/k8s-bootstrap/*.log
```

### Option A: Automatic Rollback (Configured by Default)

```bash
# Check .env configuration
grep ROLLBACK_ON_ERROR .env

# Should be:
ROLLBACK_ON_ERROR=true

# If installation fails, automatic rollback will:
# 1. Run kubeadm reset
# 2. Stop services (kubelet, containerd/cri-o)
# 3. Clean up directories (partial cleanup)

# After automatic rollback, fix the issue and retry:
sudo bash k8s_installation.sh
```

### Option B: Manual Cleanup (Recommended After Failed Install)

```bash
# Run cleanup command
sudo bash k8s_installation.sh cleanup

# What it does:
# - Drains nodes (if joined to cluster)
# - Runs kubeadm reset -f
# - Stops kubelet service
# - Stops container runtime (containerd/cri-o)
# - Optionally removes config directories

# After cleanup, retry installation:
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

### Option C: Complete System Reset (Nuclear Option)

```bash
# WARNING: This removes everything including packages

# Step 1: Reset kubeadm
sudo kubeadm reset -f

# Step 2: Unhold packages
sudo apt-mark unhold kubelet kubeadm kubectl

# Step 3: Remove packages
sudo apt-get purge -y kubelet kubeadm kubectl containerd

# For CRI-O:
sudo apt-get purge -y cri-o cri-o-runc

# Step 4: Clean up directories
sudo rm -rf /etc/kubernetes
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/kubelet
sudo rm -rf /var/lib/containerd
sudo rm -rf /var/lib/crio
sudo rm -rf /etc/cni
sudo rm -rf /opt/cni
sudo rm -rf ~/.kube

# Step 5: Clean up iptables rules
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# Step 6: Remove kernel modules
sudo rmmod br_netfilter overlay || true

# Step 7: Reboot (recommended)
sudo reboot

# After reboot, start fresh:
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

### Fix Common Issues

#### Issue 1: Port Already in Use

```bash
# Check what's using port 6443
sudo ss -tuln | grep 6443

# Kill process using the port
sudo lsof -ti:6443 | xargs sudo kill -9

# Or identify and stop service
sudo netstat -tulpn | grep 6443
```

#### Issue 2: Swap Still Enabled

```bash
# Disable swap
sudo swapoff -a

# Make it persistent
sudo sed -i '/swap/d' /etc/fstab

# Verify
swapon --show  # Should be empty
```

#### Issue 3: Container Runtime Not Running

```bash
# For containerd
sudo systemctl status containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# For CRI-O
sudo systemctl status crio
sudo systemctl restart crio
sudo systemctl enable crio

# Check runtime socket
sudo ls -la /var/run/containerd/containerd.sock
sudo ls -la /var/run/crio/crio.sock
```

#### Issue 4: CNI Plugin Failed

```bash
# Check CNI pods
kubectl get pods -n kube-system | grep -E 'calico|flannel|cilium|weave'

# Check CNI logs
kubectl logs -n kube-system -l k8s-app=calico-node

# Re-apply CNI plugin
kubectl delete -f <cni-manifest-url>
kubectl apply -f <cni-manifest-url>
```

#### Issue 5: Node Not Ready

```bash
# Check node status
kubectl describe node <node-name>

# Check kubelet logs
sudo journalctl -u kubelet -f

# Restart kubelet
sudo systemctl restart kubelet

# Check container runtime
sudo systemctl status containerd
```

### Remove Worker Node from Cluster

```bash
# On control plane:

# Drain node (gracefully evict pods)
kubectl drain worker-node-01 --ignore-daemonsets --delete-emptydir-data

# Remove node from cluster
kubectl delete node worker-node-01

# On worker node:
# Run cleanup
sudo bash k8s_installation.sh cleanup
```

### Renew Join Tokens

```bash
# Join tokens expire after 24 hours by default

# On control plane, renew tokens:
sudo bash k8s_installation.sh renew-tokens

# This generates new join.sh file with fresh token

# View new join command
cat join.sh

# Update .env with new JOIN_COMMAND
grep "kubeadm join" join.sh
```

---

## 7. Common Commands Reference

### Cluster Management

```bash
# View cluster info
kubectl cluster-info
kubectl cluster-info dump  # Detailed info

# View nodes
kubectl get nodes
kubectl get nodes -o wide
kubectl describe node <node-name>

# View all resources
kubectl get all -A

# View cluster version
kubectl version
kubeadm version
```

### Node Management

```bash
# Label node
kubectl label node <node-name> environment=production
kubectl label node <node-name> zone=us-east-1a

# Remove label
kubectl label node <node-name> environment-

# Taint node (prevent scheduling)
kubectl taint node <node-name> key=value:NoSchedule

# Remove taint
kubectl taint node <node-name> key=value:NoSchedule-

# Cordon node (mark unschedulable)
kubectl cordon <node-name>

# Uncordon node
kubectl uncordon <node-name>

# Drain node (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

### Pod Management

```bash
# View pods
kubectl get pods
kubectl get pods -A  # All namespaces
kubectl get pods -n kube-system
kubectl get pods -o wide

# Describe pod
kubectl describe pod <pod-name>

# View pod logs
kubectl logs <pod-name>
kubectl logs <pod-name> -f  # Follow logs
kubectl logs <pod-name> --previous  # Previous container logs

# Execute command in pod
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec <pod-name> -- ls /

# Delete pod
kubectl delete pod <pod-name>
```

### Deployment Management

```bash
# Create deployment
kubectl create deployment nginx --image=nginx --replicas=3

# View deployments
kubectl get deployments
kubectl describe deployment nginx

# Scale deployment
kubectl scale deployment nginx --replicas=5

# Update image
kubectl set image deployment/nginx nginx=nginx:1.21

# Rollback deployment
kubectl rollout undo deployment/nginx

# View rollout status
kubectl rollout status deployment/nginx

# Delete deployment
kubectl delete deployment nginx
```

### Service Management

```bash
# Expose deployment
kubectl expose deployment nginx --port=80 --type=NodePort

# View services
kubectl get svc
kubectl describe svc nginx

# Get service endpoint
kubectl get endpoints nginx

# Delete service
kubectl delete svc nginx
```

### System Pod Management

```bash
# View system pods
kubectl get pods -n kube-system

# View kube-apiserver
kubectl get pods -n kube-system | grep apiserver
kubectl logs -n kube-system kube-apiserver-<node-name>

# View etcd
kubectl get pods -n kube-system | grep etcd
kubectl logs -n kube-system etcd-<node-name>

# View controller-manager
kubectl get pods -n kube-system | grep controller-manager

# View scheduler
kubectl get pods -n kube-system | grep scheduler

# View CNI pods
kubectl get pods -n kube-system | grep -E 'calico|flannel|cilium|weave'
```

### Certificate Management

```bash
# View certificate expiration
sudo kubeadm certs check-expiration

# Renew all certificates
sudo kubeadm certs renew all

# Renew specific certificate
sudo kubeadm certs renew apiserver

# After renewal, restart control plane components
sudo systemctl restart kubelet
```

### Token Management

```bash
# List tokens
sudo kubeadm token list

# Create new token
sudo kubeadm token create

# Create token with TTL
sudo kubeadm token create --ttl 2h

# Create token with join command
sudo kubeadm token create --print-join-command

# Delete token
sudo kubeadm token delete <token>
```

### Etcd Management

```bash
# Check etcd health
kubectl exec -n kube-system etcd-<control-plane-name> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# List etcd members (HA cluster)
kubectl exec -n kube-system etcd-<control-plane-name> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Backup etcd
sudo ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

### Logs and Debugging

```bash
# View kubelet logs
sudo journalctl -u kubelet -f
sudo journalctl -u kubelet --since "10 minutes ago"

# View containerd logs
sudo journalctl -u containerd -f

# View CRI-O logs
sudo journalctl -u crio -f

# View system logs
sudo journalctl -xe

# View installation logs
sudo tail -f /var/log/k8s-bootstrap/*.log

# Check kubeconfig
echo $KUBECONFIG
cat ~/.kube/config

# Debug API server
kubectl get --raw /healthz
kubectl get --raw /readyz
kubectl get --raw /livez
```

---

## 8. Troubleshooting

### Diagnostic Commands

```bash
# Full cluster diagnosis
kubectl get nodes
kubectl get pods -A
kubectl get componentstatuses
kubectl cluster-info dump

# Check system pod logs
kubectl logs -n kube-system -l component=kube-apiserver
kubectl logs -n kube-system -l component=kube-controller-manager
kubectl logs -n kube-system -l component=kube-scheduler
kubectl logs -n kube-system -l component=etcd

# Check CNI logs
kubectl logs -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l app=flannel
kubectl logs -n kube-system -l k8s-app=cilium
kubectl logs -n kube-system -l name=weave-net

# Check events
kubectl get events -A --sort-by='.lastTimestamp'
```

### Quick Health Checks

```bash
# Create health check script
cat > health_check.sh <<'EOF'
#!/bin/bash

echo "=== Kubernetes Cluster Health Check ==="
echo ""

echo "1. Cluster Info:"
kubectl cluster-info
echo ""

echo "2. Node Status:"
kubectl get nodes
echo ""

echo "3. System Pods:"
kubectl get pods -n kube-system
echo ""

echo "4. Component Status:"
kubectl get cs
echo ""

echo "5. API Server Health:"
kubectl get --raw /healthz
echo ""

echo "6. Storage Classes:"
kubectl get sc
echo ""

echo "7. Recent Events:"
kubectl get events -A --sort-by='.lastTimestamp' | tail -10
echo ""

echo "=== Health Check Complete ==="
EOF

chmod +x health_check.sh
./health_check.sh
```

### Getting Help

```bash
# Installation issues:
# Check logs in /var/log/k8s-bootstrap/

# Join issues:
# Verify JOIN_COMMAND is correct
# Check worker node can reach control plane IP:6443
# Verify certificates are valid

# Pod scheduling issues:
# Check node resources: kubectl describe node <name>
# Check taints: kubectl describe node <name> | grep Taints
# Check pod events: kubectl describe pod <name>

# Network issues:
# Check CNI pods: kubectl get pods -n kube-system
# Check pod network: kubectl exec <pod> -- ip addr
# Test pod-to-pod: kubectl exec <pod1> -- ping <pod2-ip>

# For more help:
# GitHub: https://github.com/kubernetes/kubernetes/issues
# Kubernetes Slack: https://slack.k8s.io/
# Documentation: https://kubernetes.io/docs/
```

---

## Quick Reference Card

```bash
# Pre-flight
sudo bash k8s_precheck_installation.sh

# Install (control plane)
sudo bash k8s_installation.sh

# Install (worker - automated)
sudo bash scripts/add_nodes.sh

# Cleanup
sudo bash k8s_installation.sh cleanup

# Renew tokens
sudo bash k8s_installation.sh renew-tokens

# View nodes
kubectl get nodes

# View pods
kubectl get pods -A

# View logs
sudo tail -f /var/log/k8s-bootstrap/*.log

# Health check
kubectl get cs && kubectl cluster-info
```

---

**End of Commands & Step-by-Step Guide**
