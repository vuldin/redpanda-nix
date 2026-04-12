# Installing Redpanda Nix Package

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Installing Nix](#2-installing-nix)
3. [Firewall Configuration](#3-firewall-configuration)
4. [Verification](#4-verification)
5. [Compliance Artifacts](#5-compliance-artifacts)
6. [Updating and Maintenance](#6-updating-and-maintenance)
7. [Uninstallation](#7-uninstallation)
8. [Troubleshooting](#8-troubleshooting)
9. [Reference: What install.sh Does](#9-reference-what-installsh-does)

---

## 1. Quick Start

Prerequisites: a Linux system with systemd and [Nix installed with flakes enabled](#2-installing-nix).

> **macOS**: The Redpanda server is Linux-only. For the rpk CLI only: `nix build .#redpanda-rpk`

```bash
git clone <repository-url> redpanda-nix
cd redpanda-nix
sudo ./scripts/install.sh
```

This single command builds Redpanda, creates a system user, writes a default config, installs a systemd service, and starts Redpanda. See [Section 9](#9-reference-what-installsh-does) for exactly what it does.

To install the FIPS variant:

```bash
sudo ./scripts/install.sh --variant fips
```

To upgrade after pulling new changes:

```bash
sudo ./scripts/install.sh  # rebuilds, re-symlinks, and restarts
```

**Time to install**: 5-10 minutes (deb variant), 1-4 hours (source variant)
**Disk space**: 10-50 GB for `/nix/store`

---

## 2. Installing Nix

If you already have Nix with flakes enabled, skip to [Quick Start](#1-quick-start).

Nix installs alongside your existing package manager (apt/yum/dnf) without conflicts. Your system packages remain untouched.

**Supported distributions**: Ubuntu 18.04+, Debian 9+, RHEL 7/8/9, CentOS, Rocky, Alma, NixOS (native — skip this section)

**Minimum requirements**: 2 GB RAM (4 GB+ recommended), 10-50 GB free disk, sudo access, internet

### 2.1 Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y curl xz-utils

# RHEL/CentOS/Rocky/Alma
sudo yum install -y xz curl
```

### 2.2 Install Nix Package Manager

**Option A: Standard Nix Installer (Recommended)**

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
source /etc/profile.d/nix.sh
nix --version
```

**Option B: Determinate Systems Installer (Enterprise)**

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
source /etc/profile.d/nix.sh
nix --version
```

**What gets installed**: `/nix` directory (isolated from system), `nix-daemon.service`, 32 build users (`nixbld1`-`nixbld32`), shell integration in `/etc/profile.d/nix.sh`. No changes to apt/yum or system packages.

### 2.3 Enable Flakes

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### 2.4 RHEL/CentOS: SELinux Considerations

RHEL-family distributions have SELinux enabled by default.

**Multi-user install** (recommended for servers):

```bash
# Temporarily set permissive for installation
sudo setenforce 0
# Install Nix (see 2.2 above), then re-enable
sudo setenforce 1
```

To permanently set permissive (if required):

```bash
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sudo reboot
```

**Single-user install** (SELinux compatible, for developer workstations):

```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
source ~/.nix-profile/etc/profile.d/nix.sh
```

Trade-offs: SELinux stays enforcing, no daemon or system users needed, but builds run as your user and `/nix/store` cannot be shared.

**Determinate Systems Installer** handles SELinux automatically:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
```

---

## 3. Firewall Configuration

The install script does not modify firewall rules. If your firewall is active, open the Redpanda ports:

### Ubuntu/Debian (UFW)

```bash
sudo ufw allow 9092/tcp   # Kafka API
sudo ufw allow 9644/tcp   # Admin API
sudo ufw allow 8081/tcp   # Schema Registry
sudo ufw allow 8082/tcp   # HTTP Proxy
sudo ufw allow 33145/tcp  # RPC (for clusters)
sudo ufw reload
```

### RHEL/CentOS/Rocky/Alma (firewalld)

```bash
sudo firewall-cmd --permanent --add-port=9092/tcp
sudo firewall-cmd --permanent --add-port=9644/tcp
sudo firewall-cmd --permanent --add-port=8081/tcp
sudo firewall-cmd --permanent --add-port=8082/tcp
sudo firewall-cmd --permanent --add-port=33145/tcp
sudo firewall-cmd --reload
```

> **NixOS note**: On NixOS, set `services.redpanda.openFirewall = true` instead — the module auto-opens all configured listener ports.

---

## 4. Verification

After `install.sh` completes:

```bash
# Check service status
systemctl status redpanda

# Test with rpk
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

## 6. Updating and Maintenance

### Update Redpanda Version

```bash
cd redpanda-nix

# Update to latest or specific version
./scripts/update.sh 26.1.2

# Rebuild and reinstall
sudo ./scripts/install.sh
```

### Update Nix Itself

```bash
nix upgrade-nix
nix --version
```

### Garbage Collection

```bash
# Clean up old store paths
nix-collect-garbage

# Aggressive cleanup (delete old generations)
nix-collect-garbage -d

# Check disk usage
du -sh /nix/store
```

---

## 7. Uninstallation

### Remove Redpanda

```bash
sudo ./scripts/uninstall.sh          # keeps config and data
sudo ./scripts/uninstall.sh --purge  # removes everything
```

---

## 8. Troubleshooting

### "nix: command not found"

```bash
source /etc/profile.d/nix.sh
# Or restart shell
exec $SHELL
```

### "experimental features not enabled"

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### Permission denied errors

```bash
# Check nix-daemon is running
systemctl status nix-daemon
sudo systemctl restart nix-daemon
```

### systemd service won't start

```bash
sudo journalctl -u redpanda -n 50
which redpanda
ls -l /var/lib/redpanda
sudo chown -R redpanda:redpanda /var/lib/redpanda
```

### SELinux denials (RHEL/CentOS)

```bash
sudo ausearch -m avc -ts recent
# Temporarily disable
sudo setenforce 0
# Or use single-user Nix install (see Section 2.4)
```

### Firewall blocking connections

```bash
sudo ss -tlnp | grep -E '9092|9644|8081|8082|33145'
# See Section 3 for firewall rules
```

---

## 9. Reference: What install.sh Does

The `scripts/install.sh` script automates the following steps. This section is for reference — you do not need to run these manually.

1. **Builds the package** — runs `nix build` for the selected variant (or uses an existing `result` symlink)
2. **Creates system user** — adds a `redpanda` user and group (`useradd --system`)
3. **Creates directories** — `/var/lib/redpanda/data` and `/etc/redpanda` with correct ownership
4. **Symlinks binary** — links the Nix store binary to `/usr/local/bin/redpanda`
5. **Writes default config** — creates `/etc/redpanda/redpanda.yaml` if it doesn't exist (single-node, developer mode). Existing configs are preserved on upgrade.
6. **Installs systemd service** — writes `/etc/systemd/system/redpanda.service` with security hardening (`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, etc.)
7. **Starts/restarts service** — enables and starts Redpanda, or restarts if already running

The script is idempotent — safe to re-run after rebuilds to upgrade in place.

The `scripts/uninstall.sh` script reverses these steps: stops the service, removes the systemd unit and binary symlink. With `--purge`, it also removes config, data, and the system user.

---

## Next Steps

- **[WHICH_BUILD.md](./WHICH_BUILD.md)** — Choose the right build approach
- **[REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)** — FIPS 140-2 deployment
- **[compliance/COMPLIANCE_MATRIX.md](../compliance/COMPLIANCE_MATRIX.md)** — Compliance control mapping
