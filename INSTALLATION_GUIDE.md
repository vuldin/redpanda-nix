# Installing Redpanda Nix Package: Multi-Platform Guide

## Executive Summary

This guide provides comprehensive installation instructions for the Redpanda Nix package across multiple platforms: **Ubuntu, Debian, RHEL, CentOS, Rocky Linux, Alma Linux, and macOS**.

**Key Insight**: Nix installs completely alongside your existing package manager (apt/yum/dnf/brew) without conflicts. Your system packages remain untouched.

**Supported Platforms**:
- ✅ Ubuntu 18.04+ / Debian 9+
- ✅ RHEL 7/8/9 / CentOS / Rocky / Alma
- ✅ macOS 10.15+ (Catalina and newer)
- ✅ NixOS (native support)

---

## Table of Contents

1. [Quick Start (Any Platform)](#1-quick-start-any-platform)
2. [Ubuntu / Debian Installation](#2-ubuntu--debian-installation)
3. [RHEL / CentOS / Rocky / Alma Installation](#3-rhel--centos--rocky--alma-installation)
4. [macOS Installation](#4-macos-installation)
5. [Building the Redpanda Package](#5-building-the-redpanda-package)
6. [Creating System Services](#6-creating-system-services)
7. [Compliance Artifacts Generation](#7-compliance-artifacts-generation)
8. [Troubleshooting](#8-troubleshooting)
9. [Updating and Maintenance](#9-updating-and-maintenance)
10. [Uninstallation](#10-uninstallation)

---

## 1. Quick Start (Any Platform)

### TL;DR - 3 Commands to Install

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

---

## 2. Ubuntu / Debian Installation

### 2.1 Prerequisites

**Supported Versions**:
- Ubuntu: 18.04 LTS, 20.04 LTS, 22.04 LTS, 24.04 LTS
- Debian: 9 (Stretch), 10 (Buster), 11 (Bullseye), 12 (Bookworm)

**Minimum Requirements**:
- 2GB RAM (4GB+ recommended)
- 10-50GB free disk space
- `sudo` access
- Internet connection

### 2.2 Pre-Installation Check

```bash
# Check OS version
lsb_release -a

# Check available disk space (need 10GB+ free)
df -h /

# Verify sudo access
sudo echo "Access confirmed"

# Install dependencies (usually pre-installed)
sudo apt update
sudo apt install -y curl xz-utils
```

### 2.3 Install Nix Package Manager

**Option A: Standard Nix Installer (Recommended)**

```bash
# Multi-user installation (daemon-based)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Reload shell environment
source /etc/profile.d/nix.sh

# Verify installation
nix --version
```

**Option B: Determinate Systems Installer (Enterprise, SOC2-certified)**

```bash
# Determinate Nix with better UX and enterprise support
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# Reload shell
source /etc/profile.d/nix.sh

# Verify
nix --version
```

**What Gets Installed**:
- `/nix` directory (isolated from system)
- `nix-daemon.service` systemd service
- 32 build users (`nixbld1-nixbld32`)
- Shell integration in `/etc/profile.d/nix.sh`
- **NO changes to apt or system packages**

**Troubleshooting**:
```bash
# If "nix: command not found"
exec $SHELL

# Or manually source
source /etc/profile.d/nix.sh

# Check daemon status
systemctl status nix-daemon.service
```

### 2.4 Enable Flakes

```bash
# Create Nix config directory
mkdir -p ~/.config/nix

# Enable modern Nix features
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF
```

### 2.5 Ubuntu-Specific: Firewall Configuration

```bash
# If using UFW (Ubuntu Firewall)
sudo ufw status

# Open Redpanda ports (if needed)
sudo ufw allow 9092/tcp   # Kafka API
sudo ufw allow 9644/tcp   # Admin API
sudo ufw allow 8081/tcp   # Schema Registry
sudo ufw allow 8082/tcp   # HTTP Proxy
sudo ufw allow 33145/tcp  # RPC (for clusters)

# Reload
sudo ufw reload
```

---

## 3. RHEL / CentOS / Rocky / Alma Installation

### 3.1 Prerequisites

**Supported Versions**:
- RHEL: 7.x, 8.x, 9.x
- CentOS: 7, 8, Stream
- Rocky Linux: 8.x, 9.x
- AlmaLinux: 8.x, 9.x

**Minimum Requirements**:
- 2GB RAM (4GB+ recommended)
- 10-50GB free disk space
- `sudo` access
- Internet connection

### 3.2 Pre-Installation Check

```bash
# Check OS version
cat /etc/redhat-release

# Check available disk space
df -h /

# Install dependencies
sudo yum install -y xz curl

# RHEL 8/9: Ensure systemd is available
systemctl --version
```

### 3.3 SELinux Considerations

**Important**: RHEL/CentOS have SELinux enabled by default. Choose one approach:

#### Option A: Multi-User Install (Requires SELinux Disabled/Permissive)

**Recommended for**: Production servers, shared environments

```bash
# Check SELinux status
getenforce

# Temporarily disable (for installation)
sudo setenforce 0

# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Reload shell
source /etc/profile.d/nix.sh

# Verify
nix --version
systemctl status nix-daemon

# (Optional) Re-enable SELinux after installation
# Note: May cause issues with Nix builds
sudo setenforce 1
```

**Permanent SELinux Disable** (if required):
```bash
# Edit /etc/selinux/config
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Reboot required for permanent change
sudo reboot
```

#### Option B: Single-User Install (SELinux Compatible)

**Recommended for**: Developer workstations, strict SELinux policies

```bash
# No need to modify SELinux
sh <(curl -L https://nixos.org/nix/install) --no-daemon

# Reload shell
source ~/.nix-profile/etc/profile.d/nix.sh

# Verify
nix --version
```

**Trade-offs**:
- ✅ SELinux stays enabled (security compliance)
- ✅ No system users or daemon
- ❌ Builds run as your user (higher resource usage)
- ❌ Can't share `/nix/store` with other users

#### Option C: Determinate Systems Installer (Recommended for Enterprise)

```bash
# Handles SELinux automatically (best UX)
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# Reload shell
source /etc/profile.d/nix.sh
```

### 3.4 Enable Flakes

```bash
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF
```

### 3.5 RHEL-Specific: Firewall Configuration

```bash
# If using firewalld
sudo firewall-cmd --state

# Open Redpanda ports permanently
sudo firewall-cmd --permanent --add-port=9092/tcp   # Kafka API
sudo firewall-cmd --permanent --add-port=9644/tcp   # Admin API
sudo firewall-cmd --permanent --add-port=8081/tcp   # Schema Registry
sudo firewall-cmd --permanent --add-port=8082/tcp   # HTTP Proxy
sudo firewall-cmd --permanent --add-port=33145/tcp  # RPC

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

---

## 4. macOS Installation

### 4.1 Prerequisites

**Supported Versions**:
- macOS 10.15 (Catalina) and newer
- macOS 11 (Big Sur), 12 (Monterey), 13 (Ventura), 14 (Sonoma), 15 (Sequoia)

**Minimum Requirements**:
- 2GB RAM (4GB+ recommended)
- 10-50GB free disk space
- Admin account access
- Internet connection

**Architecture Support**:
- ✅ Intel (x86_64)
- ✅ Apple Silicon (M1/M2/M3 - arm64)

### 4.2 Pre-Installation Check

```bash
# Check macOS version
sw_vers

# Check available disk space (need 10GB+ free)
df -h /

# Check architecture
uname -m
# x86_64 = Intel
# arm64 = Apple Silicon
```

### 4.3 Install Nix Package Manager

**Option A: Standard Nix Installer**

```bash
# Multi-user installation (recommended)
sh <(curl -L https://nixos.org/nix/install)

# Reload shell
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Add to your shell profile for persistence
echo 'source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' >> ~/.zshrc

# Verify installation
nix --version
```

**Option B: Determinate Systems Installer (Recommended for Apple Silicon)**

```bash
# Better support for macOS, especially M1/M2/M3
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# Reload shell
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Verify
nix --version
```

**What Gets Installed**:
- `/nix` directory (on separate APFS volume in Catalina+)
- `org.nixos.nix-daemon` LaunchDaemon
- Build users (`nixbld1-nixbld32`)
- Shell integration for bash/zsh

**macOS Catalina+ Specific**:
- Nix creates a dedicated APFS volume at `/nix` (read-only root workaround)
- Synthetic.conf entry: `/etc/synthetic.conf` contains `nix`
- Requires reboot for volume creation on first install

### 4.4 Apple Silicon Specific Notes

**Rosetta Not Required**: Nix has native Apple Silicon support.

**Binary Cache**: Most packages available as native ARM64 binaries from cache.nixos.org.

**Building from Source**: If no ARM64 binary available, Nix builds natively on M1/M2/M3.

```bash
# Check if you're using native ARM64 Nix
file $(which nix)
# Should output: Mach-O 64-bit executable arm64
```

### 4.5 Enable Flakes

```bash
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF
```

### 4.6 macOS Firewall Configuration

```bash
# If macOS Firewall is enabled (System Settings > Network > Firewall)
# Redpanda will need to accept incoming connections

# Allow Redpanda through firewall (when service starts, macOS will prompt)
# Or add manually:
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/redpanda
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/local/bin/redpanda
```

### 4.7 macOS-Specific: Homebrew Compatibility

**Important**: Nix and Homebrew coexist without issues.

```bash
# You can use both simultaneously
brew --version  # Homebrew still works
nix --version   # Nix also works

# They install to different locations:
# - Homebrew: /usr/local (Intel) or /opt/homebrew (Apple Silicon)
# - Nix: /nix/store

# No conflicts!
```

---

## 5. Building the Redpanda Package

**Same process on all platforms** (Ubuntu, RHEL, macOS):

### 5.1 Clone Repository

```bash
# Clone the repository
git clone <repository-url> redpanda-nix
cd redpanda-nix

# Or download tarball (if no git)
curl -L <repository-tarball-url> | tar xz
cd redpanda-nix
```

### 5.2 Build Redpanda Package

```bash
# Build latest version
nix build

# Build outputs a symlink: result -> /nix/store/...-redpanda-VERSION
ls -lh result/

# Check what was built
tree result/ -L 2

# Test Redpanda CLI
nix run .#rpk -- --help

# Test full Redpanda binary
nix run .#redpanda -- --help
```

### 5.3 Update to Specific Version (Optional)

```bash
# Update to specific Redpanda version
./update.sh 25.2.8

# Rebuild
nix build

# Check version
./result/bin/redpanda --version
```

### 5.4 Verify Build Reproducibility

```bash
# Build twice and compare hashes
nix-build default.nix
hash1=$(nix-hash --type sha256 result)

rm result
nix-build default.nix
hash2=$(nix-hash --type sha256 result)

# Should be identical (reproducible build)
[ "$hash1" = "$hash2" ] && echo "✅ Build is reproducible" || echo "❌ Build differs"
```

---

## 6. Creating System Services

Since this is a Nix package on non-NixOS systems, you need to create native system services.

### 6.1 Linux Systems (Ubuntu, Debian, RHEL, CentOS)

#### Step 1: Create Redpanda User

```bash
# Create dedicated user for Redpanda
sudo useradd --system --home-dir /var/lib/redpanda \
  --create-home --shell /usr/sbin/nologin redpanda
```

#### Step 2: Install Binaries

```bash
# Create symlinks in /usr/local/bin
sudo ln -sf $(readlink -f result)/bin/redpanda /usr/local/bin/redpanda
sudo ln -sf $(readlink -f result)/bin/rpk /usr/local/bin/rpk

# Verify
which redpanda rpk
redpanda --version
```

#### Step 3: Create Configuration

```bash
# Create config directory
sudo mkdir -p /etc/redpanda

# Create basic configuration
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

# Set permissions
sudo chown -R redpanda:redpanda /etc/redpanda /var/lib/redpanda
sudo chmod 0750 /var/lib/redpanda
```

#### Step 4: Create systemd Service

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

#### Step 5: Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Start Redpanda
sudo systemctl start redpanda

# Check status
sudo systemctl status redpanda

# Enable on boot
sudo systemctl enable redpanda

# View logs
sudo journalctl -u redpanda -f
```

#### Step 6: Verify Installation

```bash
# Check cluster info
rpk cluster info

# Create test topic
rpk topic create test-topic

# Produce message
echo "Hello from Nix Redpanda!" | rpk topic produce test-topic

# Consume message
rpk topic consume test-topic --num 1
```

---

### 6.2 macOS Systems

**Note**: Redpanda is primarily designed for Linux. For macOS development:

#### Option A: Run Redpanda Directly (Development)

```bash
# Install binaries
sudo ln -sf $(readlink -f result)/bin/redpanda /usr/local/bin/redpanda
sudo ln -sf $(readlink -f result)/bin/rpk /usr/local/bin/rpk

# Create data directory
mkdir -p ~/redpanda-data

# Create config
mkdir -p ~/.config/redpanda
cat > ~/.config/redpanda/redpanda.yaml <<EOF
redpanda:
  data_directory: $HOME/redpanda-data
  node_id: 0
  rpc_server:
    address: 127.0.0.1
    port: 33145
  kafka_api:
    - address: 127.0.0.1
      port: 9092
  admin:
    - address: 127.0.0.1
      port: 9644
  developer_mode: true
EOF

# Run Redpanda manually
redpanda --redpanda-cfg ~/.config/redpanda/redpanda.yaml
```

#### Option B: LaunchDaemon (Background Service)

```bash
# Create LaunchDaemon plist
sudo tee /Library/LaunchDaemons/com.redpanda.service.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.redpanda.service</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/redpanda</string>
        <string>--redpanda-cfg</string>
        <string>/usr/local/etc/redpanda/redpanda.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/usr/local/var/log/redpanda.log</string>
    <key>StandardErrorPath</key>
    <string>/usr/local/var/log/redpanda.error.log</string>
</dict>
</plist>
EOF

# Create config directory
sudo mkdir -p /usr/local/etc/redpanda /usr/local/var/log

# Copy config
sudo cp ~/.config/redpanda/redpanda.yaml /usr/local/etc/redpanda/

# Load service
sudo launchctl load /Library/LaunchDaemons/com.redpanda.service.plist

# Check logs
tail -f /usr/local/var/log/redpanda.log
```

#### Option C: Use Docker Instead (Recommended for macOS)

```bash
# Redpanda officially recommends Docker for macOS
docker run -d --name=redpanda \
  -p 9092:9092 -p 9644:9644 \
  vectorized/redpanda:latest \
  redpanda start --smp 1 --memory 1G --overprovisioned
```

---

## 7. Compliance Artifacts Generation

**Same commands work on all platforms** (Ubuntu, RHEL, macOS):

### 7.1 Generate SBOM (Software Bill of Materials)

```bash
# Using bombon (CycloneDX format)
nix run github:nikstur/bombon -- $(nix-build default.nix) > redpanda-sbom.json

# Using sbomnix (recommended for DoD compliance)
nix run github:tiiuae/sbomnix -- $(nix-build default.nix) \
  --sbom cyclonedx --output redpanda-sbom.json

# Generate SPDX format
nix run github:tiiuae/sbomnix -- $(nix-build default.nix) \
  --sbom spdx --output redpanda-sbom.spdx.json
```

### 7.2 Generate SLSA Provenance (DoD Requirement)

```bash
nix run github:tiiuae/sbomnix -- $(nix-build default.nix) \
  --provenance slsa --output redpanda-provenance.json
```

### 7.3 Vulnerability Scanning

```bash
# First generate SBOM
nix run github:tiiuae/sbomnix -- $(nix-build default.nix) \
  --sbom cyclonedx --output sbom.json

# Run vulnerability scan
vulnxscan $(nix-build default.nix) --sbom sbom.json --output vulnerabilities.csv

# View vulnerabilities
cat vulnerabilities.csv
```

### 7.4 Verify Package Integrity

```bash
# Cryptographic verification
nix-store --verify --check-contents $(nix-build default.nix)

# Show dependency tree
nix-store -q --tree $(nix-build default.nix)

# Show all runtime dependencies
nix-store -q --requisites $(nix-build default.nix)
```

### 7.5 Create Compliance Audit Package

```bash
# Generate complete compliance evidence
mkdir -p compliance-evidence

# Package hash
echo "SHA256: $(nix-hash --type sha256 $(nix-build default.nix))" > compliance-evidence/hash.txt

# Git commit info
git log -1 > compliance-evidence/git-commit.txt

# SBOM
nix run github:tiiuae/sbomnix -- $(nix-build default.nix) \
  --sbom cyclonedx --output compliance-evidence/sbom.json

# SLSA provenance
nix run github:tiiuae/sbomnix -- $(nix-build default.nix) \
  --provenance slsa --output compliance-evidence/provenance.json

# Dependency tree
nix-store -q --tree $(nix-build default.nix) > compliance-evidence/dependencies.txt

# Create tarball
tar czf compliance-evidence-$(date +%Y%m%d).tar.gz compliance-evidence/

echo "✅ Compliance package created: compliance-evidence-$(date +%Y%m%d).tar.gz"
```

---

## 8. Troubleshooting

### 8.1 Common Issues - All Platforms

#### "nix: command not found"

```bash
# Linux
source /etc/profile.d/nix.sh

# macOS
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

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
systemctl status nix-daemon       # Linux
launchctl list | grep nix-daemon  # macOS

# Restart daemon
sudo systemctl restart nix-daemon  # Linux
sudo launchctl kickstart -k system/org.nixos.nix-daemon  # macOS
```

### 8.2 Ubuntu/Debian Specific

#### systemd service won't start

```bash
# Check logs
sudo journalctl -u redpanda -n 50

# Check binary exists
which redpanda

# Check permissions
ls -l /var/lib/redpanda
sudo chown -R redpanda:redpanda /var/lib/redpanda
```

### 8.3 RHEL/CentOS Specific

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
# Check firewall status
sudo firewall-cmd --list-all

# Verify ports are listening
sudo ss -tlnp | grep redpanda

# Check if firewall is blocking
sudo firewall-cmd --add-port=9092/tcp --permanent
sudo firewall-cmd --reload
```

### 8.4 macOS Specific

#### "/nix volume not found" after reboot

```bash
# macOS Catalina+ specific: check synthetic.conf
cat /etc/synthetic.conf

# Should contain:
# nix

# If missing, reinstall Nix
sh <(curl -L https://nixos.org/nix/install)
```

#### Apple Silicon binary not found

```bash
# Check if using native ARM64
file $(which nix)

# Force native build (don't use Rosetta)
nix build --system aarch64-darwin
```

#### Permission issues with /nix

```bash
# Check ownership
ls -ld /nix

# Should be owned by root:nixbld
# If not, reinstall Nix
```

---

## 9. Updating and Maintenance

### 9.1 Update Redpanda Version

```bash
cd redpanda-nix

# Update to latest version
./update.sh

# Or specific version
./update.sh 25.3.1

# Rebuild
nix build

# Update symlinks (Linux)
sudo ln -sf $(readlink -f result)/bin/redpanda /usr/local/bin/redpanda
sudo ln -sf $(readlink -f result)/bin/rpk /usr/local/bin/rpk

# Restart service
sudo systemctl restart redpanda  # Linux
sudo launchctl kickstart -k system/com.redpanda.service  # macOS
```

### 9.2 Update Nix Itself

```bash
# Update Nix package manager
nix upgrade-nix

# Verify new version
nix --version
```

### 9.3 Garbage Collection

```bash
# Clean up old Nix store paths
nix-collect-garbage

# Aggressive cleanup (delete old generations)
nix-collect-garbage -d

# Check disk usage before/after
du -sh /nix/store
```

### 9.4 Update Nix Channels (if using channels)

```bash
# Update channel
nix-channel --update

# List channels
nix-channel --list
```

---

## 10. Uninstallation

### 10.1 Remove Redpanda Service

#### Linux (Ubuntu, RHEL, etc.)

```bash
# Stop and disable service
sudo systemctl stop redpanda
sudo systemctl disable redpanda

# Remove systemd unit
sudo rm /etc/systemd/system/redpanda.service
sudo systemctl daemon-reload

# Remove binaries and data
sudo rm /usr/local/bin/redpanda /usr/local/bin/rpk
sudo rm -rf /var/lib/redpanda /etc/redpanda

# Remove user
sudo userdel redpanda
```

#### macOS

```bash
# Unload LaunchDaemon
sudo launchctl unload /Library/LaunchDaemons/com.redpanda.service.plist

# Remove files
sudo rm /Library/LaunchDaemons/com.redpanda.service.plist
sudo rm /usr/local/bin/redpanda /usr/local/bin/rpk
sudo rm -rf /usr/local/etc/redpanda /usr/local/var/log/redpanda*
```

### 10.2 Uninstall Nix (Optional)

**Warning**: This removes ALL Nix packages, not just Redpanda.

#### Linux (Ubuntu, Debian, RHEL, CentOS)

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

#### macOS

```bash
# If using Determinate Systems installer
sudo /nix/nix-installer uninstall

# If using standard Nix installer
sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo rm /Library/LaunchDaemons/org.nixos.nix-daemon.plist

# Remove Nix volume (Catalina+)
sudo diskutil apfs deleteVolume /nix

# Remove synthetic.conf entry
sudo sed -i '' '/^nix$/d' /etc/synthetic.conf

# Remove Nix files
sudo rm -rf /nix ~/.nix-* /etc/nix

# Remove build users
for i in {1..32}; do sudo dscl . -delete /Users/_nixbld$i; done
```

---

## 11. Platform Comparison

| Feature | Ubuntu/Debian | RHEL/CentOS | macOS |
|---------|--------------|-------------|-------|
| **Installation Difficulty** | Easy | Medium (SELinux) | Easy |
| **systemd Support** | ✅ Native | ✅ Native | ❌ Use LaunchDaemon |
| **Binary Cache** | ✅ x86_64 | ✅ x86_64 | ✅ x86_64 + ARM64 |
| **SELinux Issues** | ❌ None | ⚠️ Require disable/workaround | ❌ N/A |
| **Production Ready** | ✅ Yes | ✅ Yes | ⚠️ Development only |
| **Compliance Features** | ✅ Full | ✅ Full | ✅ Full (SBOM, provenance) |
| **Recommended For** | Production | Enterprise | Development/Testing |

---

## 12. Quick Reference

### Essential Commands

```bash
# Install Nix (any platform)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes
mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Build Redpanda
nix build

# Update version
./update.sh 25.2.8

# Generate SBOM
nix run github:tiiuae/sbomnix -- $(nix-build) --sbom cyclonedx

# Clean up old builds
nix-collect-garbage -d

# Verify installation
nix --version
rpk --version
```

### Platform-Specific Reload Commands

```bash
# Linux: Reload Nix environment
source /etc/profile.d/nix.sh

# macOS: Reload Nix environment
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Linux: Restart Redpanda service
sudo systemctl restart redpanda

# macOS: Restart Redpanda service
sudo launchctl kickstart -k system/com.redpanda.service
```

---

## 13. Next Steps

After installation, see:

- **[COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md)** - Understand OS-independent compliance
- **[COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md)** - 7-framework compliance analysis
- **[REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)** - FIPS 140-2 compliance
- **[NIX_ENTERPRISE_ADOPTION_CASE.md](./NIX_ENTERPRISE_ADOPTION_CASE.md)** - Enterprise adoption case

---

**Document Version**: 1.0
**Last Updated**: 2025-10-10
**Tested On**: Ubuntu 22.04/24.04, RHEL 9, macOS 14 (Sonoma)
