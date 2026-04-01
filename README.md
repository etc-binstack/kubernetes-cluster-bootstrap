
# K8s Bootstrap (Production-Ready)

Cloud-agnostic Kubernetes cluster bootstrap using kubeadm.

## Directory

```
k8s-bootstrap/
├── .env
├── k8s_precheck_installation.sh
├── k8s_installation.sh
├── lib/
│   ├── common.sh
│   ├── install.sh
│   ├── network.sh
│   └── kubeadm.sh
└── logs/
```

## Features
- Single-node & multi-node support
- Auto SSH worker join
- Terraform AWS provisioning
- Modular scripts
- .env driven config

## Usage

### 1. Configure
Edit `.env`

### 2. Run Control Plane
```bash
sudo bash k8s_precheck_installation.sh
sudo bash k8s_installation.sh
```

### 3. Add Workers
```bash
bash scripts/add_nodes.sh
```

## Terraform (AWS)
```bash
cd terraform/aws
terraform init
terraform apply
```
