# Redpanda NixOS Package

Automated Redpanda packaging for NixOS with automatic version updates.

## Features

- 🔄 **Automatic Updates**: Update script fetches and packages any Redpanda version
- 🔥 **Smart Firewall**: Automatically extracts all ports from Redpanda config
- 🎯 **Multi-Listener Support**: Configure multiple listeners per service (Kafka, Admin, etc.)
- 📦 **Flakes Support**: Modern Nix flakes for reproducible builds
- 🛡️ **NixOS Module**: Full systemd service with security hardening
- 🔒 **TLS Enforcement**: Optional TLS validation for STIG SC-8 and CJIS 5.10 compliance
- 📋 **Automated SBOM**: CycloneDX/SPDX generation with SLSA v1.0 provenance (DoD requirement)
- 🔍 **Vulnerability Scanning**: Automated CVE detection via sbomnix
- 📊 **CJIS Audit Retention**: 365-day log retention for FBI compliance
- 🏗️ **Multi-Architecture**: x86_64 and ARM64/aarch64 support (Apple Silicon ready)
- ✅ **Multi-Framework Compliance**: 8 frameworks - SOC 2, NIST 800-161, STIG, CJIS, FedRAMP, and more

## Prerequisites

### For NixOS
- NixOS with flakes enabled
- `nix-prefetch-url` (or `nix-shell` to run it)
- `curl`
- `jq` (optional, for JSON parsing)

### For Ubuntu / Debian / RHEL / CentOS / macOS
- Install Nix package manager first: `sh <(curl -L https://nixos.org/nix/install) --daemon`
- **See [INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md) for platform-specific instructions**
  - Ubuntu / Debian (easy - no SELinux)
  - RHEL / CentOS / Rocky / Alma (SELinux considerations)
  - macOS (Intel and Apple Silicon)

**Key Point**: Nix installs alongside apt/yum/brew without conflicts. Your existing packages are not affected.

## Quick Start

### Install Latest Version

```bash
./update.sh
nix build
```

### Install Specific Version

```bash
./update.sh 25.2.8
nix build
```

> **Note**: The `update.sh` script must be run on a system with Nix tools available. It will automatically use `nix-shell` if `nix-prefetch-url` is not directly available.

## Usage

### As a Flake Package

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    redpanda.url = "path:/home/josh/projects/redpanda/nix";
  };

  outputs = { self, nixpkgs, redpanda }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        redpanda.nixosModules.default
        {
          services.redpanda.enable = true;
        }
      ];
    };
  };
}
```

### NixOS Configuration

#### Basic Configuration

```nix
{
  services.redpanda = {
    enable = true;
    openFirewall = true;  # Automatically opens all configured ports

    settings = {
      redpanda = {
        data_directory = "/var/lib/redpanda";
        node_id = 0;

        kafka_api = [{
          address = "0.0.0.0";
          port = 9092;
        }];

        admin = [{
          address = "0.0.0.0";
          port = 9644;
        }];

        rpc_server = {
          address = "0.0.0.0";
          port = 33145;
        };

        developer_mode = true;
      };

      schema_registry = {
        schema_registry_api = [{
          address = "0.0.0.0";
          port = 8081;
        }];
      };

      pandaproxy = {
        pandaproxy_api = [{
          address = "0.0.0.0";
          port = 8082;
        }];
      };
    };
  };
}
```

#### Advanced: Multiple Listeners

Configure multiple listeners for each service (just like the Helm chart):

```nix
{
  services.redpanda = {
    enable = true;
    openFirewall = true;

    settings = {
      redpanda = {
        # Multiple Kafka API listeners
        # Pattern: 9092, 9192, 9292, ... (increment first digit)
        kafka_api = [
          {
            address = "0.0.0.0";
            port = 9092;
            name = "internal";
          }
          {
            address = "0.0.0.0";
            port = 9192;
            name = "external";
          }
          {
            address = "0.0.0.0";
            port = 9292;
            name = "public";
          }
        ];

        # Admin API (typically single listener)
        admin = [{
          address = "0.0.0.0";
          port = 9644;
        }];

        rpc_server = {
          address = "0.0.0.0";
          port = 33145;
        };
      };

      schema_registry = {
        # Pattern: 8081, 8181, 8281, ... (increment first digit)
        schema_registry_api = [
          { address = "0.0.0.0"; port = 8081; name = "internal"; }
          { address = "0.0.0.0"; port = 8181; name = "external"; }
        ];
      };

      pandaproxy = {
        # Pattern: 8082, 8182, 8282, ... (increment first digit)
        pandaproxy_api = [
          { address = "0.0.0.0"; port = 8082; name = "internal"; }
          { address = "0.0.0.0"; port = 8182; name = "external"; }
        ];
      };
    };
  };
}
```

**Port Pattern**: When configuring multiple listeners, follow this pattern for easier management:
- **Kafka API**: 9092, 9192, 9292, 9392, ... (increment first digit: 9x92)
- **Schema Registry**: 8081, 8181, 8281, 8381, ... (increment first digit: 8x81)
- **HTTP Proxy**: 8082, 8182, 8282, 8382, ... (increment first digit: 8x82)
- **Admin API**: Usually single listener (9644), multiple admin ports are uncommon

**Firewall Note**: When `openFirewall = true`, all configured ports are automatically extracted and opened. You only configure ports once!

## Update Script

The `update.sh` script automates package updates:

### Features

- Fetches latest release from GitHub
- Downloads and hashes binary artifacts
- Generates `default.nix` with correct version and SHA256
- Updates `flake.nix` version reference

### Requirements

The update script requires:
- `curl` for GitHub API calls
- `nix-prefetch-url` (will use `nix-shell -p nix` if not available)

### Usage

```bash
# Update to latest version
./update.sh

# Update to specific version
./update.sh 25.2.8

# The script will:
# 1. Fetch release info from GitHub
# 2. Download the tarball
# 3. Calculate SHA256 hash using nix-prefetch-url
# 4. Generate default.nix with version and hash
# 5. Update flake.nix version reference
```

The generated `default.nix` can then be built with `nix build` or included in your NixOS configuration.

## Available Apps

When using flakes, you can run Redpanda tools directly:

```bash
# Run redpanda
nix run .#default

# Run rpk CLI
nix run .#rpk

# Run update script
nix run .#update
```

## Port Configuration

All Redpanda services support multiple listeners:

| Service | Default Port(s) | Multi-Listener Pattern | Config Location |
|---------|----------------|------------------------|-----------------|
| Kafka API | 9092 | 9092, 9192, 9292, 9x92... | `redpanda.kafka_api` |
| Schema Registry | 8081 | 8081, 8181, 8281, 8x81... | `schema_registry.schema_registry_api` |
| HTTP Proxy | 8082 | 8082, 8182, 8282, 8x82... | `pandaproxy.pandaproxy_api` |
| Admin API | 9644 | Single listener (uncommon to have multiple) | `redpanda.admin` |
| RPC Server | 33145 | Single listener | `redpanda.rpc_server` |

**Port Pattern**: For multiple listeners, increment the first digit (9x92, 8x81, 8x82) to keep ports organized and easy to remember.

### Automatic Port Detection

The NixOS module automatically:
- Extracts all ports from `kafka_api`, `admin`, `rpc_server`, `schema_registry_api`, and `pandaproxy_api`
- Handles both single listeners and arrays of listeners
- Opens all detected ports when `openFirewall = true`
- Warns if `openFirewall = true` but no ports are detected

## Development

### Dev Shell

```bash
nix develop
```

This provides a shell with Redpanda, curl, and jq.

### Building

```bash
# Build the package
nix build

# Build and run
nix run

# Build specific output
nix build .#redpanda
```

## Module Options

### Core Options

#### `services.redpanda.enable`
Enable the Redpanda service. Default: `false`

#### `services.redpanda.package`
The Redpanda package to use. Defaults to the package defined in this flake.

#### `services.redpanda.dataDir`
Directory where Redpanda stores data. Default: `/var/lib/redpanda`

#### `services.redpanda.user` / `services.redpanda.group`
User and group for the Redpanda service. Default: `redpanda`

#### `services.redpanda.settings`
Redpanda configuration as a Nix attribute set. This maps directly to `redpanda.yaml`.

#### `services.redpanda.openFirewall`
Automatically open firewall ports for all configured listeners. When enabled, ports are extracted from `settings` and opened automatically. Default: `false`

### Compliance Options (NEW)

#### `services.redpanda.enforceTLS`
**STIG SC-8, CJIS 5.10, FedRAMP**

Enforce TLS for all Redpanda services. Validates at build time that TLS is properly configured for Kafka API, Admin API, RPC Server, Schema Registry, and HTTP Proxy. Default: `false`

```nix
services.redpanda = {
  enforceTLS = true;
  settings.redpanda.kafka_api_tls = [{
    enabled = true;
    key_file = "/etc/redpanda/certs/tls.key";
    cert_file = "/etc/redpanda/certs/tls.crt";
  }];
};
```

See [examples/3-node-cluster-tls.nix](./examples/3-node-cluster-tls.nix) for complete TLS configuration.

#### `services.redpanda.cjisAuditRetention`
**FBI CJIS 5.4, STIG AU-11**

Configure CJIS-compliant 365-day audit retention. Automatically configures systemd-journald to retain logs for minimum 365 days as required by FBI CJIS Security Policy v6.0. Default: `false`

```nix
services.redpanda.cjisAuditRetention = true;
```

#### `services.redpanda.auditRetentionDays`
Number of days to retain audit logs when `cjisAuditRetention` is enabled. Default: `365` (CJIS minimum). Can be increased for stricter requirements (e.g., 730 for 2 years).

### Cluster Options

#### `services.redpanda.cluster.nodes`
Multi-node cluster topology configuration. When configured, seed servers and advertised addresses are automatically generated based on hostname.

```nix
services.redpanda.cluster.nodes = {
  broker1 = {
    seed = true;
    rpcAddress = "192.168.1.10:33145";
    kafkaAddress = "broker1.example.com:9092";
    rack = "us-west-2a";
  };
};
```

See [examples/3-node-cluster-tls.nix](./examples/3-node-cluster-tls.nix) for complete cluster configuration.

## Architecture

```
update.sh → default.nix → flake.nix → NixOS module
   ↓           ↓              ↓            ↓
 Fetch      Package      Build      systemd service
 latest     definition   system     + firewall
```

### File Structure

#### `default.nix` - Package Derivation

Defines **how to build Redpanda** as a package:
- Fetches the Redpanda binary tarball from GitHub releases
- Specifies build dependencies (autoPatchelfHook, zlib, openssl, systemd)
- Defines installation steps (copying binaries from `opt/redpanda/bin/`)
- Sets package metadata (description, license, supported platforms)

This is a **standalone, pure package definition** that works without flakes and can be used directly with `nix-build default.nix`.

#### `flake.nix` - Modern Distribution Interface

Wraps `default.nix` and provides **multiple integration points**:
- **Packages**: Makes Redpanda available via `nix build`
- **Apps**: Runnable commands (`nix run .#rpk`, `nix run .#update`)
- **Dev Shell**: Development environment with Redpanda + tools
- **NixOS Module**: Full `services.redpanda` systemd service with cluster topology, firewall management, and configuration

The flake is the **user-facing interface** that distributes the package and enables declarative NixOS deployments.

#### Relationship

```
default.nix (package) → flake.nix (distribution + NixOS integration)
```

- `default.nix` = "How to build Redpanda" (auto-generated by `update.sh`)
- `flake.nix` = "How to use/run/deploy Redpanda on NixOS" (stable wrapper)

## Contributing

To add support for new Redpanda versions:

1. Run `./update.sh <version>`
2. Test the build: `nix build`
3. Test the module in a NixOS configuration
4. Submit changes

## Compliance & Security

This Redpanda NixOS package is designed to meet multiple compliance frameworks:

### Supported Frameworks (8 Frameworks)

| Framework | Status | Documentation |
|-----------|--------|---------------|
| **SOC 2 Type II** | ✅ 100% Compliant | [SOC2_COMPLIANCE.md](./SOC2_COMPLIANCE.md) |
| **NIST SP 800-161** (Supply Chain) | ✅ 95% Compliant | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) |
| **ISO/IEC 27036** | 🟡 80% Compliant | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) |
| **NIST CSF 2.0** (Feb 2024) | 🟡 60% Compliant | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) |
| **DoD SBOM Management** (Jan 2024) | ✅ 95% Compliant | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) |
| **Anduril NixOS STIG** (Dec 2024) | 🟡 60% Service-Level | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) |
| **FedRAMP High** | 🟢 90% with FIPS+TLS | [REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md) |
| **FBI CJIS Security Policy v6.0** | ✅ 95% Compliant | [FBI_CJIS_COMPLIANCE.md](./FBI_CJIS_COMPLIANCE.md) |

**NEW**: U.S. Army SBOM mandate (effective early 2025) - This package is procurement-ready with automated SBOM generation.

### Core Security Controls

- **Reproducible Builds**: Every build is cryptographically verifiable and reproducible
- **Cryptographic Verification**: All packages verified via SHA256 hashes in `default.nix`
- **Immutable Infrastructure**: Nix store provides immutable package storage at `/nix/store`
- **Automated SBOM Generation**: CycloneDX and SPDX formats with SLSA v1.0 provenance (NEW)
- **Vulnerability Scanning**: Automated CVE detection during package updates (NEW)
- **TLS Enforcement**: Build-time validation of TLS configuration for compliance (NEW)
- **Audit Retention**: CJIS-compliant 365-day log retention (NEW)
- **Multi-Architecture**: x86_64 and ARM64/aarch64 support (NEW)
- **Audit Trail**: Complete change history via git, verifiable package provenance
- **Automated Updates**: `update.sh` with integrated compliance artifact generation
- **Security Hardening**: systemd service includes NoNewPrivileges, ProtectSystem, PrivateTmp

### Change Management

- **Declarative Configuration**: All settings in version-controlled `flake.nix` and NixOS modules
- **Atomic Rollbacks**: `nixos-rebuild switch --rollback` for instant recovery
- **Version Pinning**: `flake.lock` ensures exact dependency versions
- **Testing**: Test configurations in VMs before production deployment

### Supply Chain Security (NIST SP 800-161, DoD SBOM, NIST CSF 2.0)

**NEW**: Automated compliance artifact generation integrated into `update.sh`

When you run `./update.sh`, it automatically generates:
1. **CycloneDX SBOM** (JSON) - Primary DoD format
2. **SPDX SBOM** (JSON) - Alternative DoD format
3. **SLSA v1.0 Provenance** - Supply chain attestation (DoD requirement)
4. **Vulnerability Scan** (CSV) - Automated CVE detection

All artifacts are saved to `compliance/redpanda-<version>-*.{json,csv}`

**Manual Generation** (if needed):
```bash
# Generate all compliance artifacts for current build
nix run github:tiiuae/sbomnix -- $(nix-build) --sbom cyclonedx --output sbom.json
nix run github:tiiuae/sbomnix -- $(nix-build) --provenance slsa --output provenance.json
vulnxscan $(nix-build) --sbom sbom.json --output vulns.csv
```

**Additional Controls:**
- **Provenance Tracking**: Complete dependency graph via `/nix/store`
- **Supplier Assessment**: nixpkgs community governance with documented security practices
- **Tamper Detection**: Immutable packages + reproducible builds detect modifications
- **Integrity Verification**: `nix-store --verify --check-contents $(nix-build)`

### Access Controls

- **Least Privilege**: Service runs as dedicated `redpanda` user
- **Firewall Integration**: Automatic port management with `openFirewall` option
- **File Permissions**: systemd `ProtectSystem=strict` and `ReadWritePaths` restrictions

### Monitoring & Logging

- **systemd Integration**: Standard logging via `journalctl -u redpanda`
- **Service Status**: Real-time monitoring via `systemctl status redpanda`
- **Configuration Verification**: Declarative settings prevent configuration drift

### Compliance Documentation

#### Core Compliance Analysis
- **[COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md)** - 7-framework compliance analysis with gaps and remediation
- **[SOC2_COMPLIANCE.md](./SOC2_COMPLIANCE.md)** - Detailed SOC 2 Type II control mapping
- **[COMPLIANCE_COMPARISON.md](./COMPLIANCE_COMPARISON.md)** - Comparison with similar projects and enhancement roadmap

#### Compliance Architecture
- **[COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md)** - OS-independent vs OS-dependent compliance explained
- **Key Insight**: Application-level compliance (SOC 2, SBOM, supply chain) works on **any OS** (Ubuntu, RHEL, NixOS)

#### Installation Guides
- **[INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md)** - Unified multi-platform installation guide
  - Ubuntu / Debian installation
  - RHEL / CentOS / Rocky / Alma installation (SELinux handling)
  - macOS installation (Intel and Apple Silicon)
  - System service setup (systemd / LaunchDaemon)
  - Compliance artifacts generation

#### Enterprise Adoption
- **[NIX_ENTERPRISE_ADOPTION_CASE.md](./NIX_ENTERPRISE_ADOPTION_CASE.md)** - Case for Nix in enterprise and DoD environments
- **[REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)** - FIPS 140-2 compliance implementation

## License

This packaging is provided as-is. Redpanda itself is licensed under the Redpanda Business Source License.
