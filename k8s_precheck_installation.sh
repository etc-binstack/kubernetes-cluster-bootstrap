
#!/bin/bash
set -e
source .env

echo "[Precheck]"

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root"
  exit 1
fi

# OS check
if ! grep -qi ubuntu /etc/os-release; then
  echo "❌ Only Ubuntu supported"
  exit 1
fi

# CPU check (minimum 2 cores for control-plane, 1 for worker)
CPU_COUNT=$(nproc)
if [[ "$NODE_ROLE" == "control-plane" ]]; then
  if [[ $CPU_COUNT -lt 2 ]]; then
    echo "❌ Control plane requires at least 2 CPU cores (found: $CPU_COUNT)"
    exit 1
  fi
else
  if [[ $CPU_COUNT -lt 1 ]]; then
    echo "❌ Worker node requires at least 1 CPU core (found: $CPU_COUNT)"
    exit 1
  fi
fi
echo "✅ CPU check passed ($CPU_COUNT cores)"

# RAM check (minimum 2GB for control-plane, 1GB for worker)
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [[ "$NODE_ROLE" == "control-plane" ]]; then
  if [[ $RAM_MB -lt 2048 ]]; then
    echo "❌ Control plane requires at least 2GB RAM (found: ${RAM_MB}MB)"
    exit 1
  fi
else
  if [[ $RAM_MB -lt 1024 ]]; then
    echo "❌ Worker node requires at least 1GB RAM (found: ${RAM_MB}MB)"
    exit 1
  fi
fi
echo "✅ RAM check passed (${RAM_MB}MB)"

# Disk space check (minimum 20GB for root partition)
DISK_AVAIL_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ $DISK_AVAIL_GB -lt 20 ]]; then
  echo "❌ Root partition requires at least 20GB available space (found: ${DISK_AVAIL_GB}GB)"
  exit 1
fi
echo "✅ Disk space check passed (${DISK_AVAIL_GB}GB available)"

# Kernel version check (minimum 4.0 for overlay fs, 5.0+ recommended)
KERNEL_VERSION=$(uname -r | cut -d. -f1)
if [[ $KERNEL_VERSION -lt 4 ]]; then
  echo "❌ Kernel version 4.0+ required (found: $(uname -r))"
  exit 1
fi
echo "✅ Kernel version check passed ($(uname -r))"

# Required kernel modules check
REQUIRED_MODULES=(br_netfilter overlay)
for module in "${REQUIRED_MODULES[@]}"; do
  if ! lsmod | grep -q "^$module"; then
    echo "⚠️  Loading kernel module: $module"
    modprobe $module || {
      echo "❌ Failed to load kernel module: $module"
      exit 1
    }
  fi
done
# Make modules persistent
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
echo "✅ Kernel modules check passed (br_netfilter, overlay)"

# SELinux/AppArmor check
if command -v getenforce &>/dev/null; then
  SELINUX_STATUS=$(getenforce)
  if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
    echo "⚠️  SELinux is enforcing. This may cause issues. Consider setting to permissive."
  fi
  echo "✅ SELinux status: $SELINUX_STATUS"
elif systemctl is-active --quiet apparmor; then
  echo "✅ AppArmor is active (Ubuntu default)"
else
  echo "✅ No mandatory access control detected"
fi

# Firewall check
if systemctl is-active --quiet ufw; then
  echo "⚠️  UFW firewall is active"
  if [[ "$NODE_ROLE" == "control-plane" ]]; then
    echo "   Checking required ports for control plane..."
    REQUIRED_FW_PORTS=(6443 2379 2380 10250 10251 10252)
    for port in "${REQUIRED_FW_PORTS[@]}"; do
      if ! ufw status | grep -q "$port"; then
        echo "   ℹ️  Port $port may need to be opened"
      fi
    done
  else
    echo "   Checking required ports for worker..."
    REQUIRED_FW_PORTS=(10250 30000:32767)
    for port in "${REQUIRED_FW_PORTS[@]}"; do
      if ! ufw status | grep -q "$port"; then
        echo "   ℹ️  Port $port may need to be opened"
      fi
    done
  fi
  echo "✅ Firewall check completed (review warnings above)"
else
  echo "✅ No active firewall detected"
fi

# Swap check
if swapon --show | grep -q '^'; then
  echo "❌ Swap is enabled. Disable it first with: swapoff -a && sed -i '/swap/d' /etc/fstab"
  exit 1
fi
echo "✅ Swap check passed (disabled)"

# Required ports check
if [[ "$NODE_ROLE" == "control-plane" ]]; then
  REQUIRED_PORTS=(6443 2379 2380 10250 10251 10252)
else
  REQUIRED_PORTS=(10250)
fi
for port in "${REQUIRED_PORTS[@]}"; do
  if ss -tuln | grep -q ":$port "; then
    echo "❌ Port $port already in use"
    exit 1
  fi
done
echo "✅ Port availability check passed"

# DNS resolution check
DNS_TEST_HOSTS=(google.com kubernetes.io pkgs.k8s.io)
for host in "${DNS_TEST_HOSTS[@]}"; do
  if ! nslookup $host &>/dev/null && ! host $host &>/dev/null; then
    echo "❌ DNS resolution failed for $host"
    exit 1
  fi
done
echo "✅ DNS resolution check passed"

# Internet check
if ! ping -c 1 google.com &>/dev/null; then
  echo "❌ No internet access"
  exit 1
fi
echo "✅ Internet connectivity check passed"

# Time synchronization check
if systemctl is-active --quiet systemd-timesyncd || systemctl is-active --quiet chronyd || systemctl is-active --quiet ntpd; then
  echo "✅ Time synchronization service is active"
  # Check time sync status
  if command -v timedatectl &>/dev/null; then
    if timedatectl status | grep -q "System clock synchronized: yes"; then
      echo "✅ System clock is synchronized"
    else
      echo "⚠️  System clock not yet synchronized (may sync soon)"
    fi
  fi
else
  echo "⚠️  No time synchronization service detected (systemd-timesyncd/chrony/ntp)"
  echo "   This may cause certificate validation issues"
fi

echo ""
echo "✅ All prechecks passed successfully"