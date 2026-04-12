# Installing Redpanda Nix Package

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Install Nix on Non-NixOS Linux](#2-install-nix-on-non-nixos-linux)
3. [Building the Redpanda Package](#3-building-the-redpanda-package)
4. [Creating System Services](#4-creating-system-services)
5. [Compliance Artifacts](#5-compliance-artifacts)
6. [Troubleshooting](#6-troubleshooting)
7. [Updating and Maintenance](#7-updating-and-maintenance)
8. [Uninstallation](#8-uninstallation)

---

## 1. Quick Start

```bash
# 1. Install Nix (automatically detects your OS)
sh <(curl -L https://nixos.org/nix/install) --daemon

# 2. Enable flakes
mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# 3. Build Redpanda
git clone <repository-url> redpanda-nix && cd redpanda-nix && nix build
```

**Time to Install**: 5-10 minutes
**Disk Space Required**: 10-50GB for `/nix/store`

> **macOS**: The Redpanda server is Linux-only. For the rpk CLI only: `nix build .#redpanda-rpk`

---

## 2. Install Nix on Non-NixOS Linux

Nix installs completely alongside your existing package manager (apt/yum/dnf) without conflicts. Your system packages remain untouched.

**Supported Distributions**:
- Ubuntu 18.04+ / Debian 9+
- RHEL 7/8/9 / CentOS / Rocky / Alma
- NixOS (native support, skip this section)

**Minimum Requirements**:
- 2GB RAM (4GB+ recommended)
- 10-50GB free disk space
- `sudo` access
- Internet connection

### 2.1 Pre-Installation

```bash
# Check available disk space (need 10GB+ free)
df -h /

# Install dependencies
# Ubuntu/Debian:
sudo apt update && sudo apt install -y curl xz-utils

# RHEL/CentOS/Rocky/Alma:
sudo yum install -y xz curl
```

### 2.2 Install Nix Package Manager

**Option A: Standard Nix Installer (Recommended)**

```bash
# Multi-user installation (daemon-based)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Reload shell environment
source /etc/profile.d/nix.sh

# Verify installation
nix --version
```

**Option B: Determinate Systems Installer (Enterprise)**

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

source /etc/profile.d/nix.sh
nix --version
```

**What Gets Installed**:
- `/nix` directory (isolated from system)
- `nix-daemon.service` systemd service
- 32 build users (`nixbld1-nixbld32`)
- Shell integration in `/etc/profile.d/nix.sh`
- **NO changes to apt/yum or system packages**

**Troubleshooting**:
```bash
# If "nix: command not found"
exec $SHELL
# Or manually source
source /etc/profile.d/nix.sh

# Check daemon status
systemctl status nix-daemon.service
```

### 2.3 Enable Flakes

```bash
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF
```

### 2.4 RHEL/CentOS: SELinux Considerations

**Important**: RHEL-family distributions have SELinux enabled by default.

#### Multi-User Install (Requires SELinux Disabled/Permissive)

Recommended for production servers and shared environments.

```bash
# Check SELinux status
getenforce

# Temporarily disable (for installation)
sudo setenforce 0

# Install Nix (see 2.2 above), then optionally re-enable
sudo setenforce 1
```

**Permanent SELinux Disable** (if required):
```bash
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sudo reboot
```

#### Single-User Install (SELinux Compatible)

Recommended for developer workstations or strict SELinux policies.

```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
source ~/.nix-profile/etc/profile.d/nix.sh
nix --version
```

Trade-offs: SELinux stays enabled, no system users or daemon needed, but builds run as your user and `/nix/store` cannot be shared.

#### Determinate Systems Installer (Handles SELinux Automatically)

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
```

### 2.5 Firewall Configuration

#### Ubuntu/Debian (UFW)

```bash
sudo ufw allow 9092/tcp   # Kafka API
sudo ufw allow 9644/tcp   # Admin API
sudo ufw allow 8081/tcp   # Schema Registry
sudo ufw allow 8082/tcp   # HTTP Proxy
sudo ufw allow 33145/tcp  # RPC (for clusters)
sudo ufw reload
```

#### RHEL/CentOS/Rocky/Alma (firewalld)

```bash
sudo firewall-cmd --permanent --add-port=9092/tcp   # Kafka API
sudo firewall-cmd --permanent --add-port=9644/tcp   # Admin API
sudo firewall-cmd --permanent --add-port=8081/tcp   # Schema Registry
sudo firewall-cmd --permanent --add-port=8082/tcp   # HTTP Proxy
sudo firewall-cmd --permanent --add-port=33145/tcp  # RPC
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
```

---

## 3. Building the Redpanda Package

### 3.1 Clone Repository

```bash
git clone <repository-url> redpanda-nix
cd redpanda-nix
```

### 3.2 Build Redpanda Package

```bash
# Build latest version
nix build

# Build outputs a symlink: result -> /nix/store/...-redpanda-VERSION
ls -lh result/

# Test rpk CLI
nix run .#rpk -- --help

# Test full Redpanda binary
nix run .#redpanda -- --help
```

### 3.3 Update to Specific Version (Optional)

```bash
./scripts/update.sh 25.2.8
nix build
./result/bin/redpanda --version
```

---

## 4. Creating System Services

Since this is a Nix package on non-NixOS systems, you need to create native systemd services.

### Step 1: Create Redpanda User

```bash
sudo useradd --system --home-dir /var/lib/redpanda \
  --create-home --shell /usr/sbin/nologin redpanda
```

### Step 2: Install Binaries

```bash
sudo ln -sf $(readlink -f result)/bin/redpanda /usr/local/bin/redpanda
sudo ln -sf $(readlink -f result)/bin/rpk /usr/local/bin/rpk

which redpanda rpk
redpanda --version
```

### Step 3: Create Configuration

```bash
sudo mkdir -p /etc/redpanda

sudo tee /etc/redpanda/redpanda.yaml <<EOF
redpanda:
  data_directory: /var/lib/redpanda/data
  node_id: 0
  rpc_server:
    address: 0.0.0.0
    port: 33145
  kafka_api:
    - address: 0.0.0.0
      port: 9092
  admin:
    - address: 0.0.0.0
      port: 9644
  developer_mode: true

pandaproxy:
  pandaproxy_api:
    - address: 0.0.0.0
      port: 8082

schema_registry:
  schema_registry_api:
    - address: 0.0.0.0
      port: 8081
EOF

sudo chown -R redpanda:redpanda /etc/redpanda /var/lib/redpanda
sudo chmod 0750 /var/lib/redpanda
```

### Step 4: Create systemd Service

```bash
sudo tee /etc/systemd/system/redpanda.service <<EOF
[Unit]
Description=Redpanda (Nix Package)
Documentation=https://docs.redpanda.com/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=redpanda
Group=redpanda
ExecStart=/usr/local/bin/redpanda \\
  --redpanda-cfg /etc/redpanda/redpanda.yaml \\
  --default-log-level=info

# Security hardening (from NixOS module)
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
ReadWritePaths=/var/lib/redpanda /var/log/redpanda

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Restart policy
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
```

### Step 5: Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl start redpanda
sudo systemctl status redpanda
sudo systemctl enable redpanda
sudo journalctl -u redpanda -f
```

### Step 6: Verify Installation

```bash
rpk cluster info
rpk topic create test-topic
echo "Hello from Nix Redpanda!" | rpk topic produce test-topic
rpk topic consume test-topic --num 1
```

### Verify Build Reproducibility (Optional)

```bash
nix build .#redpanda-deb --print-out-paths
hash1=$(nix-hash --type sha256 result)
rm result
nix build .#redpanda-deb --print-out-paths
hash2=$(nix-hash --type sha256 result)
[ "$hash1" = "$hash2" ] && echo "Build is reproducible" || echo "Build differs"
```

---

## 5. Compliance Artifacts

Run `./scripts/update.sh` to generate compliance artifacts (SBOM, provenance, vulnerability scan). See [compliance/COMPLIANCE_MATRIX.md](../compliance/COMPLIANCE_MATRIX.md) for framework details.

You can also verify package integrity at any time:

```bash
# Cryptographic verification
nix-store --verify --check-contents $(nix build .#redpanda-deb --print-out-paths)

# Show dependency tree
nix-store -q --tree $(nix build .#redpanda-deb --print-out-paths)

# Show all runtime dependencies
nix-store -q --requisites $(nix build .#redpanda-deb --print-out-paths)
```

---

## 6. Troubleshooting

### 6.1 Common Issues (All Distributions)

#### "nix: command not found"

```bash
source /etc/profile.d/nix.sh
# Or restart shell
exec $SHELL
```

#### "experimental features not enabled"

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

#### Permission denied errors

```bash
# Check nix-daemon is running
systemctl status nix-daemon

# Restart daemon
sudo systemctl restart nix-daemon
```

### 6.2 Ubuntu/Debian Specific

#### systemd service won't start

```bash
sudo journalctl -u redpanda -n 50
which redpanda
ls -l /var/lib/redpanda
sudo chown -R redpanda:redpanda /var/lib/redpanda
```

### 6.3 RHEL/CentOS Specific

#### SELinux denials

```bash
# Check for SELinux denials
sudo ausearch -m avc -ts recent

# Temporarily disable SELinux
sudo setenforce 0

# Or use single-user Nix install
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

#### Firewall blocking connections

```bash
sudo firewall-cmd --list-all
sudo ss -tlnp | grep redpanda
sudo firewall-cmd --add-port=9092/tcp --permanent
sudo firewall-cmd --reload
```

---

## 7. Updating and Maintenance

### 7.1 Update Redpanda Version

```bash
cd redpanda-nix

# Update to latest or specific version
./scripts/update.sh 25.3.1

# Rebuild
nix build

# Update symlinks
sudo ln -sf $(readlink -f result)/bin/redpanda /usr/local/bin/redpanda
sudo ln -sf $(readlink -f result)/bin/rpk /usr/local/bin/rpk

# Restart service
sudo systemctl restart redpanda
```

### 7.2 Update Nix Itself

```bash
nix upgrade-nix
nix --version
```

### 7.3 Garbage Collection

```bash
# Clean up old Nix store paths
nix-collect-garbage

# Aggressive cleanup (delete old generations)
nix-collect-garbage -d

# Check disk usage
du -sh /nix/store
```

---

## 8. Uninstallation

### 8.1 Remove Redpanda Service

```bash
sudo systemctl stop redpanda
sudo systemctl disable redpanda
sudo rm /etc/systemd/system/redpanda.service
sudo systemctl daemon-reload

sudo rm /usr/local/bin/redpanda /usr/local/bin/rpk
sudo rm -rf /var/lib/redpanda /etc/redpanda
sudo userdel redpanda
```

### 8.2 Uninstall Nix (Optional)

**Warning**: This removes ALL Nix packages, not just Redpanda.

```bash
# If using Determinate Systems installer
sudo /nix/nix-installer uninstall

# If using standard Nix installer
sudo systemctl stop nix-daemon
sudo systemctl disable nix-daemon
sudo rm -rf /nix /etc/nix ~/.nix-* /etc/profile.d/nix.sh

# Remove build users
for i in {1..32}; do sudo userdel nixbld$i; done
sudo groupdel nixbld
```

---

## Next Steps

After installation, see:

- **[REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)** - FIPS 140-2 compliance
- **[WHICH_BUILD.md](./WHICH_BUILD.md)** - Choose the right build approach
- **[compliance/COMPLIANCE_MATRIX.md](../compliance/COMPLIANCE_MATRIX.md)** - Multi-framework compliance analysis

---

**Last Updated**: 2026-04-12
