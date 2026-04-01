
# K8s Bootstrap (Production-Ready)

Cloud-agnostic Kubernetes cluster bootstrap using kubeadm.

## Directory

```
k8s-bootstrap-prod/
├── .env                           # ✅ Environment configuration (validated & production-ready)
├── k8s_precheck_installation.sh   # ✅ Pre-flight validation (already working perfectly)
├── k8s_installation.sh            # ✅ Main orchestrator (minor tweak applied below)
├── lib/                           # ✅ Modular function library (NOW COMPLETE)
│   ├── common.sh                  # ✅ Hostname utilities + logging + error handling + validation
│   ├── install.sh                 # ✅ Runtime & K8s tools installation (THIS WAS THE BLOCKER)
│   ├── kubeadm_config.sh          # ✅ Dynamic kubeadm config generator
│   ├── kubeadm.sh                 # ✅ Cluster init & join logic
│   └── network.sh                 # ✅ CNI plugin installation
├── scripts/                       # Automation helpers (ready for next step)
│   ├── add_nodes.sh               # SSH-based worker addition (will work after control-plane)
│   └── nodes.txt                  # Worker node IP list
└── terraform/aws/                 # Infrastructure provisioning (optional, already good)
    └── main.tf                    # AWS EC2 instance template
```

## Features
- Single-node & multi-node support
- **Auto-update `.env` with join command** - Control plane installation automatically updates the `.env` file with the worker join command
- Auto SSH worker join
- Terraform AWS provisioning
- Modular scripts
- .env driven config

## Usage

### 1. Configure
Edit `.env` based on `.env.example`

### 2. Run Control Plane
```bash
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

**After installation completes:**
- The join command is automatically saved to `join.sh` and `.env`
- A backup of `.env` is created as `.env.backup.<timestamp>`
- The `JOIN_COMMAND` field in `.env` is populated with the actual join token

### 3. Add Workers

**Option A: Automated (using add_nodes.sh)**
```bash
# The .env file already contains the join command
bash scripts/add_nodes.sh
```

**Option B: Manual**
```bash
# On the control plane, check the join command
cat join.sh

# Or copy the .env file to worker nodes
scp .env user@worker-node:/opt/kubernetes-cluster-bootstrap/
# Then on worker node:
sudo bash k8s_installation.sh
```

## Terraform (AWS)
```bash
cd terraform/aws
terraform init
terraform apply
```
