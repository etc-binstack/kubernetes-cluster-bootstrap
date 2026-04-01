# Frequently Asked Questions (FAQ)

**Common questions and clarifications for K8s Bootstrap Production**

---

## Table of Contents

1. [General Questions](#1-general-questions)
2. [Pre-flight & Installation](#2-pre-flight--installation)
3. [Configuration & Environment](#3-configuration--environment)
4. [Cluster Modes & HA](#4-cluster-modes--ha)
5. [SSH & Worker Node Management](#5-ssh--worker-node-management)
6. [Network & CNI](#6-network--cni)
7. [Failure & Recovery](#7-failure--recovery)
8. [Security & Best Practices](#8-security--best-practices)


---

📝 File Structure:
```
docs/FAQ.md
├── Table of Contents (8 sections)
├── 1. General Questions (5 FAQs)
├── 2. Pre-flight & Installation (4 FAQs)
├── 3. Configuration & Environment (4 FAQs)
├── 4. Cluster Modes & HA (5 FAQs) 🔥 Most detailed
├── 5. SSH & Worker Node Management (4 FAQs)
├── 6. Network & CNI (3 FAQs)
├── 7. Failure & Recovery (4 FAQs)
├── 8. Security & Best Practices (4 FAQs)
├── Quick Reference (Decision Matrix)
├── Common Misconceptions (8 myths)
└── Getting More Help (Links)
```

---

## 1. General Questions

### Q1.1: What does this project do?

**A:** This is a production-ready Kubernetes cluster bootstrap system using `kubeadm`. It automates:
- Pre-flight system validation
- Container runtime installation (containerd/CRI-O)
- Kubernetes tools installation
- Cluster initialization (single-node, multi-node, HA)
- CNI plugin installation
- Worker node joining via SSH
- Post-installation validation

**Supports:** Single-node, multi-node, HA deployments on on-prem or cloud VMs.

---

### Q1.2: What are the system requirements?

**Minimum requirements:**

| Component | Control Plane | Worker Node |
|-----------|---------------|-------------|
| **CPU** | 2 cores | 1 core |
| **RAM** | 2 GB | 1 GB |
| **Disk** | 20 GB | 20 GB |
| **OS** | Ubuntu | Ubuntu |
| **Kernel** | 4.0+ | 4.0+ |

**Additional requirements:**
- Root/sudo access
- Internet connectivity (for package downloads)
- Swap disabled
- Required ports available (6443, 10250, etc.)
- DNS resolution working
- Time synchronization enabled

---

### Q1.3: Which Kubernetes version is supported?

**A:** Currently supports **Kubernetes 1.29** (configurable via `K8S_VERSION=1.29` in `.env`).

**To use different version:**
```bash
# Edit .env
K8S_VERSION=1.30  # or 1.28, 1.27, etc.
```

**Note:** Ensure your CNI plugin version is compatible with the K8s version.

---

### Q1.4: What container runtimes are supported?

**A:** Two container runtimes:

1. **containerd** (default, recommended)
   - Lightweight, production-ready
   - Default for most Kubernetes distributions
   - Configured with SystemdCgroup driver

2. **CRI-O** (alternative)
   - OCI-compliant runtime
   - Kubernetes-specific design
   - Also configured with SystemdCgroup driver

```bash
# Configuration in .env:
CONTAINER_RUNTIME=containerd  # or cri-o
```

**Note:** Docker is NOT supported (Docker Engine deprecated in Kubernetes 1.20+).

---

### Q1.5: What CNI plugins are supported?

**A:** Four CNI (Container Network Interface) plugins:

| Plugin | Default Version | Best For | Features |
|--------|----------------|----------|----------|
| **Calico** | v3.27.0 | Production | NetworkPolicy, BGP routing, IP-in-IP, VXLAN |
| **Flannel** | Latest | Simplicity | Simple overlay, multiple backends |
| **Cilium** | v1.15.0 | Advanced | eBPF-based, observability, security |
| **Weave Net** | v2.8.1 | Mesh | Automatic mesh, encryption support |

```bash
# Configuration in .env:
NETWORK_PLUGIN=calico  # calico | flannel | cilium | weave
```

---

## 2. Pre-flight & Installation

### Q2.1: Do I need to check Docker installation in precheck?

**A:** ❌ **NO** - Docker is NOT needed.

**Explanation:**
- Kubernetes uses **containerd** or **CRI-O** (not Docker)
- Docker Engine was deprecated in Kubernetes 1.20
- These container runtimes are installed during `k8s_installation.sh` (NOT during precheck)
- Precheck only validates system prerequisites (CPU, RAM, kernel, ports, etc.)

**What precheck does:**
- ✅ Validates system resources
- ✅ Checks kernel version and modules
- ✅ Verifies ports availability
- ✅ Tests DNS resolution
- ❌ Does NOT check for Docker
- ❌ Does NOT install anything

---

### Q2.2: Does precheck script change the hostname?

**A:** ❌ **NO** - Precheck is **validation only** (with one exception).

**What precheck does:**
- ✅ Validates system requirements (CPU, RAM, disk, kernel)
- ✅ Checks network prerequisites (DNS, internet, time sync)
- ✅ Verifies port availability
- ⚠️ **Exception:** Loads kernel modules (br_netfilter, overlay) if not already loaded
- ❌ Does NOT change hostname
- ❌ Does NOT install packages
- ❌ Does NOT modify system configuration (except kernel modules)

**When hostname is changed:**
Hostname is changed during **main installation** (`k8s_installation.sh`) by the `set_hostname()` function in `lib/common.sh`.

---

### Q2.3: Does restart required after set_hostname()?

**A:** ❌ **NO** - Restart is NOT required.

**Explanation:**
- Hostname change takes effect immediately via `hostnamectl set-hostname`
- `/etc/hosts` update is immediate
- Kubernetes installation continues without reboot
- All services recognize the new hostname immediately

**When restart IS needed:**
- After kernel upgrades
- After major system updates
- NOT needed for hostname changes

---

### Q2.4: What's the installation order?

**A:** Installation follows this order:

```
1. Run precheck (k8s_precheck_installation.sh)
   ↓
2. Validate configuration (.env validation)
   ↓
3. Set hostname
   ↓
4. Install container runtime (containerd/CRI-O)
   ↓
5. Install Kubernetes tools (kubelet, kubeadm, kubectl)
   ↓
6. Initialize cluster (kubeadm init) OR join cluster (kubeadm join)
   ↓
7. Install CNI plugin (Calico/Flannel/Cilium/Weave)
   ↓
8. Configure kubectl access
   ↓
9. Apply node labels and taints
   ↓
10. Post-installation validation
    ↓
11. Generate join command (control plane only)
```

**Time estimates:**
- Single-node: 5-10 minutes
- Multi-node (per worker): 3-5 minutes
- HA cluster: 15-20 minutes (including load balancer setup)

---

## 3. Configuration & Environment

### Q3.1: What is the .env file used for?

**A:** The `.env` file is the **central configuration** for all installation settings.

**Contains 70+ configuration options:**
- Cluster mode (single/multi/ha)
- Node role (control-plane/worker)
- Network settings (CIDRs, CNI plugin)
- Container runtime selection
- HA configuration (load balancer, control plane IPs)
- Security settings (encryption, audit logging)
- SSH configuration (for worker nodes)
- Certificate management
- Logging configuration

**Key principle:** All installation behavior is driven by `.env` (no hardcoded values in scripts).

---

### Q3.2: Do I need to create .env manually?

**A:** Copy from example file:

```bash
# Step 1: Copy example
cp .env.example .env

# Step 2: Edit for your environment
nano .env

# Step 3: Verify configuration
cat .env | grep -v '^#' | grep -v '^$'
```

**The `.env.example` file includes:**
- Inline documentation for every option
- Default values
- 5 deployment scenario examples
- Best practices comments

---

### Q3.3: Are NUMBER_OF_NODES and ATTACHED_NODES used by scripts?

**A:** ❌ **NO** - These variables are **completely ignored** by all scripts.

**Proof:**
```bash
# These variables exist in .env:
NUMBER_OF_NODES=1
ATTACHED_NODES=0

# But NO script reads them:
grep -r "NUMBER_OF_NODES" *.sh   # No results
grep -r "ATTACHED_NODES" *.sh    # No results
```

**Purpose:** Documentation/tracking only (for your own reference).

**Example proving they're ignored:**
```bash
# Scenario 1: .env says 10 nodes
NUMBER_OF_NODES=10

# But scripts/nodes.txt is empty
# Result: Only 1 node (control plane) is created
# The script ignores NUMBER_OF_NODES

# Scenario 2: .env says 1 node
NUMBER_OF_NODES=1

# But scripts/nodes.txt has 5 IPs
# Result: 6 nodes created (1 control plane + 5 workers)
# The script ignores NUMBER_OF_NODES
```

**What ACTUALLY controls node count:**
- Control plane count: Always 1 (or 3/5/7 for HA)
- Worker count: **Only** the number of lines in `scripts/nodes.txt`

**Recommendation:** These variables can be removed or used for documentation:
```bash
# For your own tracking (optional):
NUMBER_OF_NODES=4     # Planning: 1 control plane + 3 workers
ATTACHED_NODES=3      # Tracking: 3 workers added so far
```

---

### Q3.4: Can I change configuration after installation?

**A:** ⚠️ **Some changes are safe, others require cluster reinstall.**

**Safe to change (without reinstall):**
- ✅ Node labels (`NODE_LABELS`)
- ✅ Log settings (`LOG_LEVEL`, `LOG_RETENTION_DAYS`)
- ✅ SSH configuration (`SSH_USER`, `SSH_KEY`)
- ✅ Worker node retry settings (`MAX_RETRIES`, `RETRY_DELAY`)

**Requires reinstall:**
- ❌ Cluster mode (`CLUSTER_MODE`)
- ❌ Network CIDRs (`POD_NETWORK_CIDR`, `SERVICE_CIDR`)
- ❌ CNI plugin (`NETWORK_PLUGIN`)
- ❌ Container runtime (`CONTAINER_RUNTIME`)
- ❌ Kubernetes version (`K8S_VERSION`)
- ❌ HA settings (`HA_MODE`, `CONTROL_PLANE_IPS`)

**To change settings that require reinstall:**
```bash
# 1. Cleanup existing cluster
sudo bash k8s_installation.sh cleanup

# 2. Update .env
nano .env

# 3. Reinstall
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

---

## 4. Cluster Modes & HA

### Q4.1: What's the difference between single, multi, and ha modes?

**A:** Three deployment modes with different availability characteristics:

| Mode | Control Planes | Workers | Use Case | Downtime Risk | Production Ready? |
|------|---------------|---------|----------|---------------|-------------------|
| **single** | 1 | 0 | Development, Testing | ❌ High (single point of failure) | ❌ Not recommended |
| **multi** | 1 | 1+ | Small production, Cost-sensitive | ⚠️ Medium (control plane is SPOF) | ⚠️ For non-critical workloads |
| **ha** | 3/5/7 | 0+ | Production, Mission-critical | ✅ Low (survives control plane failures) | ✅ Recommended |

**Key differences:**

**Single mode:**
```bash
CLUSTER_MODE=single
# - Control plane runs workloads (taint removed)
# - No HA, no redundancy
# - Cheapest option (1 server)
# - If node dies → entire cluster down
```

**Multi mode:**
```bash
CLUSTER_MODE=multi
# - Control plane does NOT run workloads (taint preserved)
# - Workers run application pods
# - If control plane dies → entire cluster down (can't schedule new pods)
# - If worker dies → pods rescheduled to other workers
```

**HA mode:**
```bash
CLUSTER_MODE=ha
# - 3+ control planes (odd number for etcd quorum)
# - Load balancer distributes API requests
# - If 1 control plane dies → cluster continues on others
# - Can survive N-1 control plane failures (where N=total control planes)
# - Example: 3 control planes → survives 1 failure, needs 2 alive
```

---

### Q4.2: For CLUSTER_MODE=multi, what additional changes needed in .env?

**A:** Only **ONE change** needed:

```bash
# Change this:
CLUSTER_MODE=single

# To this:
CLUSTER_MODE=multi

# That's it! Everything else stays the same.
```

**What happens automatically:**
- ✅ Control plane taint is **preserved** (prevents workload pods on control plane)
- ✅ Worker nodes will be added via `scripts/add_nodes.sh`
- ✅ No other configuration changes needed

**What does NOT change:**
- Network configuration ✓ Same
- CNI plugin ✓ Same
- Container runtime ✓ Same
- SSH configuration ✓ Same
- Everything else ✓ Same

**Full example (.env for multi-node):**
```bash
# Minimal changes for multi-node:
CLUSTER_MODE=multi                    # Only this changed
NODE_ROLE=control-plane               # Same
CONTROL_PLANE_HOSTNAME=k8s-master     # Same
POD_NETWORK_CIDR=192.168.0.0/16       # Same
NETWORK_PLUGIN=calico                 # Same
CONTAINER_RUNTIME=containerd          # Same
SSH_USER=ubuntu                       # Same
SSH_KEY=~/.ssh/id_rsa                 # Same
NODES_FILE=scripts/nodes.txt          # Same (add worker IPs here)
```

---

### Q4.3: If CLUSTER_MODE=ha but HA_MODE=false, what happens?

**A:** ⚠️ **CONFLICT** - Installation will likely **fail or behave incorrectly**.

**Explanation:**
- `CLUSTER_MODE=ha` tells scripts: "Expect HA setup with multiple control planes"
- `HA_MODE=false` tells scripts: "Don't use HA features (single control plane)"
- **These are contradictory!**

**What the code does:**

```bash
# In lib/kubeadm_config.sh:
if [[ "${HA_MODE}" == "true" ]]; then
  # Configures load balancer endpoint
  # Enables certificate upload for additional control planes
  # Configures stacked etcd for multiple control planes
fi

# In k8s_installation.sh:
if [[ "${HA_MODE}" == "true" ]]; then
  kubeadm init --upload-certs  # HA initialization
else
  kubeadm init                 # Single control plane
fi
```

**Result of mismatch:**
- Load balancer endpoint won't be configured
- Additional control planes can't join (no certificate key)
- etcd won't be configured for HA
- Cluster behaves as single control plane (not HA)

**Correct configurations:**

| CLUSTER_MODE | HA_MODE | Result | Valid? |
|--------------|---------|--------|--------|
| `single` | `false` | Single node cluster | ✅ Correct |
| `multi` | `false` | 1 control plane + workers | ✅ Correct |
| `ha` | `true` | HA cluster with 3+ control planes | ✅ Correct |
| `ha` | `false` | **Conflicting settings** | ❌ WRONG |
| `single` | `true` | **Conflicting settings** | ❌ WRONG |
| `multi` | `true` | **Conflicting settings** | ❌ WRONG |

**Fix the conflict:**
```bash
# If you want HA:
CLUSTER_MODE=ha
HA_MODE=true          # Must be true
CONTROL_PLANE_COUNT=3
CONTROL_PLANE_IPS="10.0.1.10,10.0.1.11,10.0.1.12"
LOAD_BALANCER_IP="10.0.1.100"

# If you want multi-node (non-HA):
CLUSTER_MODE=multi
HA_MODE=false         # Must be false
```

**Rule of thumb:** `CLUSTER_MODE` and `HA_MODE` must match logically:
- `ha` → `HA_MODE=true`
- `single` or `multi` → `HA_MODE=false`

---

### Q4.4: For HA mode, do I need to define NUMBER_OF_NODES? Are control planes counted as nodes?

**A:** ❌ **NO** - `NUMBER_OF_NODES` is NOT mandatory and NOT used by scripts.

**Part 1: Is NUMBER_OF_NODES required?**

**Answer:** No, it's documentation only.

```bash
# This variable is ignored by all scripts:
NUMBER_OF_NODES=4     # NOT used by installation scripts

# What ACTUALLY matters for HA:
CLUSTER_MODE=ha                  # Required
HA_MODE=true                     # Required
CONTROL_PLANE_COUNT=3            # Required
CONTROL_PLANE_IPS="10.0.1.10,10.0.1.11,10.0.1.12"  # Required
LOAD_BALANCER_IP="10.0.1.100"    # Required

# Worker count determined by:
scripts/nodes.txt                # ONLY this file matters
```

**Part 2: Are control planes counted as nodes?**

**Answer:** ✅ **YES** - Control planes ARE nodes in Kubernetes.

```bash
# After HA installation:
kubectl get nodes

# Output shows control planes as nodes:
NAME                  ROLE            STATUS   AGE
control-plane-01      control-plane   Ready    10m   # This IS a node
control-plane-02      control-plane   Ready    8m    # This IS a node
control-plane-03      control-plane   Ready    6m    # This IS a node
worker-01             <none>          Ready    5m    # This IS a node
worker-02             <none>          Ready    5m    # This IS a node
```

**Total nodes in cluster = Control planes + Workers**

**Best practice:** ⚠️ **Control planes should NOT run workload pods**

```bash
# Control planes have taints by default:
kubectl describe node control-plane-01 | grep Taints

# Output:
Taints: node-role.kubernetes.io/control-plane:NoSchedule

# This prevents application pods from scheduling on control planes
# Only system pods (etcd, apiserver, controller-manager, scheduler) run there
```

**Example calculation:**

```bash
# HA cluster configuration:
CONTROL_PLANE_COUNT=3              # 3 control planes

# scripts/nodes.txt:
10.0.1.20 worker-01
10.0.1.21 worker-02
10.0.1.22 worker-03
10.0.1.23 worker-04
10.0.1.24 worker-05

# Total nodes in cluster:
# - 3 control plane nodes (with taints, no application workloads)
# - 5 worker nodes (for application workloads)
# - Total: 8 nodes

# Optional documentation variable (not used by scripts):
NUMBER_OF_NODES=8     # 3 control planes + 5 workers (for your tracking)
```

**Summary:**
- `NUMBER_OF_NODES` variable: ❌ Not required, not used
- Control planes as nodes: ✅ Yes, they are nodes (but tainted)
- Workload pods on control planes: ❌ Not recommended (prevented by taint)
- Total cluster size: Control planes + Workers from `nodes.txt`

---

### Q4.5: Can I convert a multi-node cluster to HA later?

**A:** ❌ **NO** - You must reinstall from scratch.

**Why not?**
- etcd configuration is different (single vs clustered)
- Certificates have different SANs (single IP vs load balancer IP)
- API server endpoint changes (direct IP vs load balancer)
- kubeadm doesn't support in-place conversion

**To migrate multi → HA:**
1. Backup workloads (export YAML manifests)
2. Backup persistent data (if any)
3. Cleanup existing cluster: `sudo bash k8s_installation.sh cleanup`
4. Update `.env` to HA configuration
5. Setup load balancer
6. Install new HA cluster
7. Restore workloads and data

**Recommendation:** Plan for HA from the beginning if you need it later.

---

## 5. SSH & Worker Node Management

### Q5.1: Do I need to configure SSH/PEM keys before auto SSH worker join?

**A:** ✅ **YES** - SSH configuration is **100% manual** before running auto join.

**What you MUST do manually:**

**Step 1: Have an SSH key**
```bash
# Option A: Use existing key
ls ~/.ssh/id_rsa

# Option B: Generate new key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s_nodes -N ""

# Option C: Use AWS PEM key (already have it)
chmod 400 ~/mykey.pem
```

**Step 2: Distribute key to ALL worker nodes**
```bash
# Copy public key to each worker
ssh-copy-id -i ~/.ssh/id_rsa ubuntu@10.0.1.10
ssh-copy-id -i ~/.ssh/id_rsa ubuntu@10.0.1.11
ssh-copy-id -i ~/.ssh/id_rsa ubuntu@10.0.1.12

# Or for AWS (key already configured during instance launch)
# No manual distribution needed
```

**Step 3: Configure .env**
```bash
SSH_USER=ubuntu              # Remote user
SSH_KEY=~/.ssh/id_rsa        # Path to private key
SSH_PORT=22                  # SSH port
```

**Step 4: Create nodes.txt**
```bash
# scripts/nodes.txt:
10.0.1.10 worker-01
10.0.1.11 worker-02
10.0.1.12 worker-03
```

**Step 5: Test SSH access**
```bash
# Verify you can SSH without password
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10 "echo 'SSH OK'"
```

**After these manual steps, the script automates:**
- ✅ Validates SSH key permissions
- ✅ Tests SSH connectivity to each node
- ✅ Copies installation scripts to worker nodes
- ✅ Creates join script remotely (secure token distribution)
- ✅ Runs precheck on worker nodes
- ✅ Executes join command
- ✅ Applies node labels
- ✅ Verifies node health
- ✅ Retries on failure

**Summary:**
- SSH key setup: ⚠️ Manual
- SSH key distribution: ⚠️ Manual
- Everything else: ✅ Automated

---

### Q5.2: Do we need a static IP (private) if deploying on AWS EC2?

**A:** ✅ **YES** - Static private IP is **strongly recommended**.

**Why static IPs are important:**

1. **Kubernetes certificates are bound to IP addresses**
   - Control plane certificates include IP SANs
   - If IP changes, certificates become invalid
   - Cluster authentication will break

2. **Node identity relies on stable IPs**
   - Nodes register with their IP
   - Changing IP requires re-joining cluster
   - `/etc/hosts` entries would break

3. **etcd cluster uses IPs**
   - In HA mode, etcd members identify by IP
   - IP changes break etcd quorum
   - Cluster becomes non-functional

**Good news for AWS:**

✅ **AWS EC2 private IPs are already static by default!**

```bash
# AWS EC2 behavior:
# - Private IP assigned at launch
# - Private IP persists across stop/start
# - Private IP only changes if you TERMINATE the instance
# - Rebooting or stopping does NOT change private IP
```

**AWS best practices:**

**Option 1: Use default private IP (recommended)**
```bash
# EC2 private IPs are stable
# No additional configuration needed
# Just note the private IP and use it
```

**Option 2: Allocate Elastic Network Interface (ENI)**
```bash
# For extra stability, pre-allocate ENI with fixed private IP
# Attach ENI to instance
# Even more guaranteed static IP
```

**Option 3: Use Elastic IP (for public access)**
```bash
# Allocate Elastic IP (public)
# Maps to private IP
# Useful if you need external access to API server
# Not required for cluster-internal communication
```

**What to avoid:**
- ❌ Don't rely on public IPs for cluster communication
- ❌ Don't use dynamic private IPs (not applicable to AWS EC2 anyway)
- ❌ Don't terminate and recreate instances (IP will change)

**For other clouds:**
- **Azure:** Private IPs are static by default (similar to AWS)
- **GCP:** Private IPs are static by default (similar to AWS)
- **On-prem:** Configure static IPs in `/etc/netplan/` or network settings

---

### Q5.3: What happens if a worker node fails to join?

**A:** The script has **automatic retry logic** with configurable attempts.

**Retry behavior:**
```bash
# Configuration in .env:
MAX_RETRIES=3          # Retry up to 3 times per node
RETRY_DELAY=10         # Wait 10 seconds between retries
```

**What happens on failure:**

1. **First attempt fails** → Retry after 10s
2. **Second attempt fails** → Retry after 10s
3. **Third attempt fails** → Mark node as "max_retries" and continue

**Status tracking:**
```bash
# Script tracks each node's status:
NODE_STATUS[10.0.1.10]="success"
NODE_STATUS[10.0.1.11]="join_failed"
NODE_STATUS[10.0.1.12]="max_retries"

# At the end, you get a summary:
# Total nodes: 3
# Successful: 1
# Failed: 2
#
# Failed nodes:
# - 10.0.1.11 (join_failed)
# - 10.0.1.12 (max_retries)
```

**Failure status codes:**
- `ssh_failed` - Can't SSH to node
- `copy_failed` - Can't copy scripts to node
- `precheck_failed` - Precheck validation failed
- `join_failed` - kubeadm join command failed
- `max_retries` - Exceeded maximum retry attempts

**To retry failed nodes manually:**
```bash
# 1. Check the log to see why it failed
cat /var/log/k8s-bootstrap/add_nodes_*.log

# 2. Fix the issue (SSH keys, firewall, resources, etc.)

# 3. Create a new nodes.txt with only failed nodes
cat > scripts/nodes_retry.txt <<EOF
10.0.1.11
10.0.1.12
EOF

# 4. Update .env to use retry file
NODES_FILE=scripts/nodes_retry.txt

# 5. Run add_nodes.sh again
sudo bash scripts/add_nodes.sh
```

---

### Q5.4: Can I add worker nodes in parallel?

**A:** ✅ **YES** - Enable parallel execution in `.env`:

```bash
# Enable parallel execution:
PARALLEL_EXECUTION=true

# Then run:
sudo bash scripts/add_nodes.sh
```

**Comparison:**

| Mode | Speed | Resource Usage | Troubleshooting | Recommended For |
|------|-------|----------------|-----------------|-----------------|
| **Serial** (default) | Slower | Low | Easier | Small clusters, first-time setup |
| **Parallel** | Faster | Higher | Harder | Large clusters, experienced users |

**Serial mode (PARALLEL_EXECUTION=false):**
```bash
# Adds nodes one at a time:
Adding worker-01... ✅ (3 minutes)
Adding worker-02... ✅ (3 minutes)
Adding worker-03... ✅ (3 minutes)
# Total time: 9 minutes
```

**Parallel mode (PARALLEL_EXECUTION=true):**
```bash
# Adds all nodes simultaneously:
Adding worker-01... ✅
Adding worker-02... ✅  (all in parallel)
Adding worker-03... ✅
# Total time: ~3 minutes (all finish around same time)
```

**Trade-offs:**

**Parallel mode advantages:**
- ✅ Much faster for large clusters (3x-5x speedup)
- ✅ Efficient resource utilization

**Parallel mode disadvantages:**
- ⚠️ Harder to debug (logs interleaved)
- ⚠️ Higher load on control plane
- ⚠️ All nodes hit control plane API simultaneously

**Recommendation:**
- First-time setup or < 5 nodes: Use serial mode
- Adding many nodes (10+): Use parallel mode
- Production clusters with monitoring: Use parallel mode

---

## 6. Network & CNI

### Q6.1: Can I change CNI plugin after installation?

**A:** ⚠️ **Possible but risky** - Not recommended for production.

**Why it's risky:**
- All pods must be recreated with new network
- Existing pod IPs will change
- Network policies may break
- Services may have brief downtime
- etcd and control plane components need to be carefully handled

**If you must change CNI:**

```bash
# 1. Backup cluster state
kubectl get all -A -o yaml > cluster_backup.yaml

# 2. Delete old CNI
kubectl delete -f <old-cni-manifest>

# 3. Wait for old CNI pods to terminate
kubectl get pods -n kube-system

# 4. Update .env
NETWORK_PLUGIN=new-cni

# 5. Install new CNI
# Re-run network installation portion
source .env
source lib/network.sh
install_network_plugin

# 6. Verify all nodes become Ready
kubectl get nodes

# 7. Verify all pods get new IPs
kubectl get pods -A -o wide
```

**Better approach:** Reinstall cluster with desired CNI from the start.

---

### Q6.2: What network CIDR should I use?

**A:** Default values work for most cases, but avoid conflicts.

**Default configuration:**
```bash
POD_NETWORK_CIDR=192.168.0.0/16    # Pod IP range
SERVICE_CIDR=10.96.0.0/12          # Service IP range
```

**Check for conflicts:**

```bash
# Check existing network routes
ip route

# Check if these ranges are in use:
# - 192.168.0.0/16 (pods)
# - 10.96.0.0/12 (services)

# If conflict exists, choose different ranges:
POD_NETWORK_CIDR=10.244.0.0/16     # Alternative for pods
SERVICE_CIDR=10.96.0.0/12          # Usually safe for services
```

**Common scenarios:**

**Cloud environments (AWS/Azure/GCP):**
```bash
# Cloud VPCs typically use 10.0.0.0/8 or 172.16.0.0/12
# So 192.168.0.0/16 for pods is safe
POD_NETWORK_CIDR=192.168.0.0/16    # Safe, no conflict
```

**On-prem with 192.168.x.x network:**
```bash
# If your on-prem network uses 192.168.0.0/16
# Choose different pod CIDR
POD_NETWORK_CIDR=10.244.0.0/16     # No conflict with on-prem
```

**CIDR requirements:**
- Pod CIDR: Minimum /24 (254 IPs), recommended /16 (65,534 IPs)
- Service CIDR: Minimum /24, recommended /16
- Pod and Service CIDRs must NOT overlap
- Must NOT conflict with node network CIDR
- Must NOT conflict with existing infrastructure networks

---

### Q6.3: Which CNI plugin should I choose?

**A:** Depends on your requirements:

**Quick decision matrix:**

| Need | Recommended CNI | Why |
|------|----------------|-----|
| **Simple production** | Calico | Battle-tested, full features, good performance |
| **Easiest setup** | Flannel | Simple, works out of box, minimal config |
| **Advanced observability** | Cilium | eBPF-based, best monitoring, modern |
| **Encryption** | Weave Net | Built-in encryption, mesh networking |
| **Best performance** | Calico (VXLAN off) | Direct routing when possible |
| **NetworkPolicy** | Calico or Cilium | Full NetworkPolicy support |

**Detailed comparison:**

**Calico** (Recommended for most)
```bash
NETWORK_PLUGIN=calico
CNI_VERSION=v3.27.0
CALICO_VXLAN=true              # Enable for cross-subnet
```
- ✅ Production-ready, widely used
- ✅ Full NetworkPolicy support
- ✅ BGP routing option (advanced)
- ✅ Good performance
- ⚠️ More complex than Flannel

**Flannel** (Easiest)
```bash
NETWORK_PLUGIN=flannel
FLANNEL_BACKEND=vxlan          # or host-gw for better performance
```
- ✅ Simplest setup
- ✅ Reliable, stable
- ✅ Good for beginners
- ❌ No NetworkPolicy support
- ❌ Basic features only

**Cilium** (Advanced)
```bash
NETWORK_PLUGIN=cilium
CNI_VERSION=v1.15.0
```
- ✅ eBPF-based (modern, efficient)
- ✅ Best observability (Hubble UI)
- ✅ Advanced security features
- ✅ Full NetworkPolicy support
- ⚠️ Requires newer kernel (4.9+)
- ⚠️ Steeper learning curve

**Weave Net** (Encryption)
```bash
NETWORK_PLUGIN=weave
WEAVE_ENCRYPTION=true
WEAVE_PASSWORD="your-secure-password"
```
- ✅ Built-in encryption
- ✅ Automatic mesh networking
- ✅ Easy setup
- ⚠️ Lower performance than others
- ⚠️ Less commonly used

**Recommendation:**
- **First cluster / Learning:** Flannel
- **Production / Enterprise:** Calico
- **Advanced users / Observability:** Cilium
- **Security-focused / Encryption:** Weave Net

---

## 7. Failure & Recovery

### Q7.1: What steps are needed if installation fails?

**A:** Three recovery options depending on severity:

**Option A: Automatic Rollback (Default)**

```bash
# Already configured in .env:
ROLLBACK_ON_ERROR=true

# What happens automatically on failure:
# 1. Runs kubeadm reset
# 2. Stops services (kubelet, containerd/cri-o)
# 3. Partial cleanup of directories

# Then fix the issue and retry:
sudo bash k8s_installation.sh
```

**Option B: Manual Cleanup (Recommended)**

```bash
# Run cleanup command:
sudo bash k8s_installation.sh cleanup

# What it does:
# - Drains nodes (if joined)
# - Runs kubeadm reset -f
# - Stops all Kubernetes services
# - Cleans up config directories

# Then reinstall:
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

**Option C: Complete System Reset (Nuclear Option)**

```bash
# WARNING: Removes everything including packages

# Full reset:
sudo kubeadm reset -f
sudo apt-mark unhold kubelet kubeadm kubectl
sudo apt-get purge -y kubelet kubeadm kubectl containerd cri-o
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -X
sudo reboot

# After reboot, start fresh:
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

**Decision tree:**

```
Installation failed?
├─ First failure / Minor issue
│  └─ Option A: Let automatic rollback handle it, retry
├─ Repeated failures / Config issues
│  └─ Option B: Manual cleanup, fix config, reinstall
└─ Completely broken / Start over
   └─ Option C: Nuclear reset, reinstall everything
```

---

### Q7.2: Where are the installation logs?

**A:** Logs are stored in `/var/log/k8s-bootstrap/`:

```bash
# View latest log
sudo tail -f /var/log/k8s-bootstrap/k8s_install_control-plane_*.log

# List all logs
ls -lht /var/log/k8s-bootstrap/

# Search for errors
sudo grep -i error /var/log/k8s-bootstrap/*.log
sudo grep -i failed /var/log/k8s-bootstrap/*.log

# View specific log
sudo cat /var/log/k8s-bootstrap/k8s_install_control-plane_20260401_120000.log

# Worker addition logs
sudo cat /var/log/k8s-bootstrap/add_nodes_*.log
```

**Log files include:**
- Installation logs: `k8s_install_{role}_{timestamp}.log`
- Worker addition logs: `add_nodes_{timestamp}.log`
- Timestamped entries with log levels (INFO, WARN, ERROR)
- Complete installation output

**Log retention:**
```bash
# Configure in .env:
LOG_RETENTION_DAYS=30    # Logs older than 30 days are deleted
```

---

### Q7.3: How do I check if the cluster is healthy?

**A:** Use the health check commands:

**Quick health check:**
```bash
# Check nodes
kubectl get nodes

# All nodes should show STATUS: Ready

# Check system pods
kubectl get pods -n kube-system

# All pods should show STATUS: Running

# Check cluster info
kubectl cluster-info
```

**Detailed health check:**
```bash
# Check component status
kubectl get componentstatuses

# Check API server health
kubectl get --raw /healthz

# Check etcd health (control plane)
kubectl exec -n kube-system etcd-<node-name> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

**Automated health check script:**

See [COMMANDS.md - Section 8: Troubleshooting](COMMANDS.md#8-troubleshooting) for complete health check script.

---

### Q7.4: How do I renew join tokens?

**A:** Join tokens expire after 24 hours by default.

**To renew tokens:**

```bash
# On control plane node:
sudo bash k8s_installation.sh renew-tokens

# This generates new join.sh file with fresh token

# View new join command:
cat join.sh

# Update .env with new JOIN_COMMAND:
JOIN_COMMAND="<new-command-from-join.sh>"
```

**Manual token renewal:**
```bash
# List current tokens:
sudo kubeadm token list

# Create new token with join command:
sudo kubeadm token create --print-join-command

# Create token with custom TTL:
sudo kubeadm token create --ttl 48h --print-join-command

# Delete old token:
sudo kubeadm token delete <token>
```

**Best practice:**
- Generate fresh token before adding new workers
- Don't reuse tokens older than 24 hours
- For production, use shorter TTLs (1-2 hours)

---

## 8. Security & Best Practices

### Q8.1: Is it safe to store tokens in .env file?

**A:** ⚠️ **Not ideal** - But mitigated by file permissions.

**Current security measures:**
```bash
# .env file should have restricted permissions:
chmod 600 .env           # Only owner can read/write
chown root:root .env     # Owned by root

# Join script has restricted permissions:
chmod 600 join.sh        # Only owner can read/write

# JOIN_COMMAND is created remotely (not passed via CLI)
# This prevents token exposure in process list
```

**Better alternatives for production:**

**Option 1: Use external secrets manager**
```bash
# AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id k8s-join-token

# HashiCorp Vault
vault kv get secret/k8s/join-token

# Then inject into script at runtime
```

**Option 2: Generate just-in-time tokens**
```bash
# Generate fresh token right before use
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command --ttl 1h)

# Use immediately
bash scripts/add_nodes.sh
```

**Option 3: Use bootstrap tokens with RBAC**
```bash
# Create bootstrap token with limited permissions
# Instead of long-lived tokens in .env
```

**Current implementation:**
- ✅ Token not exposed in process list (created remotely)
- ✅ Files have restrictive permissions (600)
- ✅ Token has expiration (24h default)
- ⚠️ Token stored in plaintext .env file
- ⚠️ Anyone with root access can read token

**Recommendation for production:**
- Use short-lived tokens (1-2 hours)
- Regenerate tokens frequently
- Consider external secrets manager for highly sensitive environments
- Audit `.env` file access regularly

---

### Q8.2: Should I run workloads on control plane nodes?

**A:** ❌ **NO** - Not recommended for production.

**Why not?**

1. **Resource contention**
   - Application pods compete with control plane components
   - etcd is I/O sensitive, workloads can impact performance
   - API server needs consistent CPU/memory

2. **Security isolation**
   - Control plane should be isolated from user workloads
   - Compromised application pod could affect cluster management

3. **Stability**
   - Control plane should be dedicated to cluster management
   - Workload crashes shouldn't impact cluster operations

4. **Kubernetes defaults prevent this:**
   ```bash
   # Control plane has taint by default:
   node-role.kubernetes.io/control-plane:NoSchedule

   # This prevents regular pods from scheduling there
   ```

**When is it acceptable?**

**Single-node clusters (dev/test only):**
```bash
CLUSTER_MODE=single
# Taint is automatically removed
# Control plane runs workloads (no other option)
```

**Multi-node or HA (never):**
```bash
CLUSTER_MODE=multi  # or ha
# Control plane taint is preserved
# Workloads run only on worker nodes
```

**Best practice:**
- Development: Single-node with workloads on control plane is OK
- Production: Always use dedicated worker nodes
- HA Production: 3 control planes + N workers (minimum N=3)

---

### Q8.3: How do I secure my Kubernetes cluster?

**A:** Multiple layers of security (implemented and recommended):

**Already implemented in this project:**

1. **Encryption at rest**
   ```bash
   ENCRYPTION_AT_REST=true    # Encrypts secrets in etcd
   ```

2. **Audit logging**
   ```bash
   AUDIT_LOG_ENABLED=true     # Logs all API server requests
   ```

3. **Certificate management**
   ```bash
   CERT_VALIDITY_DAYS=365     # Certificate expiration
   CERT_EXTRA_SANS="..."      # Additional certificate SANs
   ```

4. **Secure join token handling**
   - Tokens not exposed in process list
   - Files with restrictive permissions (600)
   - Token expiration (24h default)

5. **SystemdCgroup for container runtime**
   - Better resource isolation
   - Prevents container breakouts

**Recommended additional security:**

6. **Network Policies** (not yet implemented)
   ```bash
   # Restrict pod-to-pod communication
   # Use Calico or Cilium for NetworkPolicy support
   ```

7. **RBAC** (not yet implemented)
   ```bash
   # Role-Based Access Control
   # Limit user permissions
   # Follow principle of least privilege
   ```

8. **Pod Security Standards** (not yet implemented)
   ```bash
   # Restrict pod capabilities
   # Prevent privileged containers
   # Enforce security contexts
   ```

9. **Firewall rules** (manual setup)
   ```bash
   # Control plane: Only allow 6443, 2379-2380, 10250-10252
   # Workers: Only allow 10250, 30000-32767
   # Block all other ingress
   ```

10. **Regular updates**
    ```bash
    # Keep Kubernetes version updated
    # Patch security vulnerabilities
    # Update container runtime
    ```

**CIS Kubernetes Benchmark compliance** (future implementation):
- Run `kube-bench` to check compliance
- Follow CIS security recommendations

**See also:** [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)

---

### Q8.4: What are the minimum production requirements?

**A:** Minimum production-ready configuration:

**Cluster architecture:**
```bash
# HA control plane (minimum for production)
CLUSTER_MODE=ha
HA_MODE=true
CONTROL_PLANE_COUNT=3           # Survives 1 failure

# Load balancer (required for HA)
LOAD_BALANCER_ENABLED=true
LOAD_BALANCER_IP="<your-lb-ip>"

# Worker nodes (minimum 3 for redundancy)
# In scripts/nodes.txt:
# 10.0.1.20 worker-01
# 10.0.1.21 worker-02
# 10.0.1.22 worker-03
```

**Security features:**
```bash
# Enable encryption at rest
ENCRYPTION_AT_REST=true

# Enable audit logging
AUDIT_LOG_ENABLED=true
AUDIT_LOG_PATH=/var/log/kubernetes/audit.log

# Certificate management
CERT_VALIDITY_DAYS=365
CERT_AUTO_RENEW=true
```

**Network:**
```bash
# Production-grade CNI
NETWORK_PLUGIN=calico           # or cilium

# CNI customization for Calico
CALICO_VXLAN=true              # For cross-subnet
```

**Monitoring & logging:**
```bash
# Configure log retention
LOG_RETENTION_DAYS=30

# Future: Add Prometheus/Grafana
# (not yet implemented in this project)
```

**Backup:**
```bash
# etcd backup (configuration ready, automation pending)
ETCD_BACKUP_ENABLED=true
ETCD_BACKUP_DIR=/var/lib/etcd-backup
ETCD_BACKUP_RETENTION_DAYS=7
```

**Resource requirements:**

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Control plane** | 2 CPU, 2 GB RAM | 4 CPU, 8 GB RAM |
| **Worker node** | 2 CPU, 4 GB RAM | 4 CPU, 16 GB RAM |
| **Disk** | 50 GB | 100 GB+ |

**Production readiness checklist:**
- [x] HA control plane (3+ nodes)
- [x] Load balancer configured
- [x] Multiple worker nodes (3+)
- [x] Encryption at rest enabled
- [x] Audit logging enabled
- [x] Certificate management configured
- [x] Production-grade CNI (Calico/Cilium)
- [ ] etcd backup automation (pending)
- [ ] Monitoring (Prometheus/Grafana) (pending)
- [ ] NetworkPolicies configured (manual)
- [ ] RBAC configured (manual)
- [ ] Firewall rules configured (manual)

**Current project status:** 80% production-ready

**See:** [PROCESS.md](../PROCESS.md) for detailed production readiness analysis.

---

## Quick Reference

### Decision Matrix

| If you want... | Use this configuration |
|----------------|------------------------|
| **Dev/test cluster** | `CLUSTER_MODE=single` |
| **Small production** | `CLUSTER_MODE=multi` + 3 workers |
| **Production HA** | `CLUSTER_MODE=ha` + `HA_MODE=true` + 3 control planes + 3+ workers |
| **Simple networking** | `NETWORK_PLUGIN=flannel` |
| **Production networking** | `NETWORK_PLUGIN=calico` |
| **Advanced features** | `NETWORK_PLUGIN=cilium` |
| **Encrypted network** | `NETWORK_PLUGIN=weave` + `WEAVE_ENCRYPTION=true` |
| **AWS deployment** | Use default private IPs (already static) |
| **Manual worker join** | Copy scripts, run on each worker |
| **Automated worker join** | Configure SSH, run `scripts/add_nodes.sh` |

---

## Common Misconceptions

| Myth | Reality |
|------|---------|
| "Docker is required for Kubernetes" | ❌ Wrong - Use containerd or CRI-O |
| "NUMBER_OF_NODES controls cluster size" | ❌ Wrong - Only `scripts/nodes.txt` matters |
| "Precheck changes system configuration" | ⚠️ Mostly false - Only loads kernel modules |
| "CLUSTER_MODE=multi is HA" | ❌ Wrong - `multi` has single control plane (not HA) |
| "Control planes don't count as nodes" | ❌ Wrong - Control planes ARE nodes (but tainted) |
| "SSH keys are configured automatically" | ❌ Wrong - SSH setup is 100% manual |
| "AWS IPs change on reboot" | ❌ Wrong - AWS private IPs are static |
| "Hostname change requires reboot" | ❌ Wrong - Takes effect immediately |

---

## Getting More Help

**Documentation:**
- [COMMANDS.md](../COMMANDS.md) - Complete command reference and step-by-step guide
- [README.md](../README.md) - Project overview and quick start
- [PROCESS.md](../PROCESS.md) - Implementation status and architecture analysis

**Official Kubernetes docs:**
- https://kubernetes.io/docs/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

**Support:**
- GitHub Issues: Report bugs or request features
- Kubernetes Slack: https://slack.k8s.io/

---

**End of FAQ**
