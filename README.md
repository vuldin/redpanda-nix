# Redpanda NixOS Package

Automated Redpanda packaging for NixOS with automatic version updates, multi-framework compliance, and CI/CD.

[![CI](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![Update Redpanda](../../actions/workflows/update-redpanda.yml/badge.svg)](../../actions/workflows/update-redpanda.yml)

## Features

### Packaging

- **Pre-built packages** from official Redpanda deb packages (5-10 min install)
- **FIPS 140-2 variant** with BoringCrypto for FedRAMP High deployments
- **Version pinning** to tagged stable releases only (e.g., `v26.1.2`)
- **Nix flakes** for reproducible, declarative builds

### NixOS Integration

- **Full NixOS module** with systemd service and security hardening
- **Automatic firewall** port extraction from listener configuration
- **Multi-listener support** for Kafka, Admin, Schema Registry, and HTTP Proxy
- **Cluster topology** with automatic seed server discovery and rack awareness

### Compliance & Security

- **TLS enforcement** with build-time validation (STIG SC-8, CJIS 5.10)
- **Automated SBOM generation** in CycloneDX/SPDX with SLSA v1.0 provenance
- **Vulnerability scanning** via sbomnix with automated CVE detection
- **CJIS audit retention** with 365-day log retention for FBI compliance
- **8-framework compliance** covering SOC 2, NIST 800-161, STIG, CJIS, FedRAMP, and more

### CI/CD

- **Weekly version detection** via GitHub Actions with automated packaging
- **Build verification** and compliance artifact generation on every update
- **Automated pull requests** with changelog, vulnerability summary, and compliance status

## Prerequisites

### For NixOS
- NixOS with flakes enabled
- `curl` for GitHub API (used by update script)
- `jq` for JSON parsing

### For Ubuntu / Debian / RHEL / CentOS / macOS
- Install Nix package manager first: `sh <(curl -L https://nixos.org/nix/install) --daemon`
- See [docs/INSTALLATION_GUIDE.md](./docs/INSTALLATION_GUIDE.md) for platform-specific instructions

## Quick Start

### NixOS

Add the flake as an input and enable the module:

```nix
{
  inputs.redpanda.url = "github:your-org/redpanda-nix";

  outputs = { nixpkgs, redpanda, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        redpanda.nixosModules.default
        { services.redpanda.enable = true; }
      ];
    };
  };
}
```

To use a different variant, set `services.redpanda.package`:

```nix
{ pkgs, inputs, ... }: {
  services.redpanda = {
    enable = true;
    package = inputs.redpanda.packages.${pkgs.system}.redpanda-fips;
  };
}
```

On NixOS, the module handles everything: user creation, systemd service, config generation, and firewall rules. No install script needed.

### Other Linux distros (Ubuntu, Debian, RHEL, Fedora, etc.)

Requires Nix with flakes enabled. See [Prerequisites](#prerequisites) if you don't have Nix yet.

```bash
git clone <repository-url> redpanda-nix
cd redpanda-nix
sudo ./scripts/install.sh
```

This builds Redpanda, creates a `redpanda` system user, installs a default config to `/etc/redpanda/redpanda.yaml`, sets up a systemd service, and starts Redpanda.

To install a different variant:

```bash
sudo ./scripts/install.sh --variant fips
```

To upgrade after pulling new changes:

```bash
sudo ./scripts/install.sh  # rebuilds, re-symlinks, and restarts
```

To uninstall:

```bash
sudo ./scripts/uninstall.sh          # keeps config and data
sudo ./scripts/uninstall.sh --purge  # removes everything
```

### Package Variants

| Variant | Build Time | Description | When to use |
|---------|-----------|-------------|-------------|
| `redpanda` (default) | 5-10 min | Official pre-built binary from Cloudsmith deb | Production and development for most users |
| `fips` | 5-10 min | Base binary + FIPS 140-2 OpenSSL overlay (BoringCrypto) | FedRAMP High, DoD IL4+, CJIS, or any environment requiring FIPS-validated cryptography |

## Configuration

### NixOS

On NixOS, configuration is declarative via Nix attributes (not a YAML file). The module generates the YAML at build time:

```nix
{
  services.redpanda = {
    enable = true;
    openFirewall = true;  # auto-opens all configured ports

    settings = {
      redpanda = {
        kafka_api = [
          { address = "0.0.0.0"; port = 9092; name = "internal"; }
          { address = "0.0.0.0"; port = 9192; name = "external"; }
        ];
        admin = [{ address = "0.0.0.0"; port = 9644; }];
        rpc_server = { address = "0.0.0.0"; port = 33145; };
        developer_mode = true;
      };
      schema_registry.schema_registry_api = [
        { address = "0.0.0.0"; port = 8081; }
      ];
      pandaproxy.pandaproxy_api = [
        { address = "0.0.0.0"; port = 8082; }
      ];
    };
  };
}
```

### Other Linux distros (Ubuntu, Debian, RHEL, etc.)

Edit `/etc/redpanda/redpanda.yaml` directly. The install script creates a default single-node config. Changes take effect after restarting the service:

```bash
sudo systemctl restart redpanda
```

To add multiple listeners, edit the YAML:

```yaml
redpanda:
  kafka_api:
    - address: 0.0.0.0
      port: 9092
      name: internal
    - address: 0.0.0.0
      port: 9192
      name: external
  advertised_kafka_api:
    - address: 127.0.0.1
      port: 9092
      name: internal
    - address: 127.0.0.1
      port: 9192
      name: external
```

Port pattern for multiple listeners:
- Kafka API: 9092, 9192, 9292 (9x92)
- Schema Registry: 8081, 8181, 8281 (8x81)
- HTTP Proxy: 8082, 8182, 8282 (8x82)

## Updating

The `scripts/update.sh` script automates package updates:

```bash
# Update to latest version
./scripts/update.sh

# Update to specific version
./scripts/update.sh 26.1.2
```

The script validates the release tag, downloads the official deb, generates `default.nix` with the correct hash, updates `flake.nix`, and generates compliance artifacts (SBOM, SLSA provenance, vulnerability scan).

## Module Options (NixOS only)

These options apply when using the NixOS module. Non-NixOS users configure Redpanda by editing `/etc/redpanda/redpanda.yaml`.

### Core Options

| Option | Description | Default |
|--------|-------------|---------|
| `services.redpanda.enable` | Enable the Redpanda service | `false` |
| `services.redpanda.package` | The Redpanda package to use | flake default |
| `services.redpanda.dataDir` | Data storage directory | `/var/lib/redpanda` |
| `services.redpanda.user` / `group` | Service user and group | `redpanda` |
| `services.redpanda.settings` | Redpanda config as Nix attrs (maps to `redpanda.yaml`) | `{}` |
| `services.redpanda.openFirewall` | Auto-open ports for all configured listeners | `false` |

### Compliance Options

| Option | Description | Frameworks |
|--------|-------------|------------|
| `services.redpanda.enforceTLS` | Build-time TLS validation for all services | STIG SC-8, CJIS 5.10, FedRAMP |
| `services.redpanda.cjisAuditRetention` | 365-day audit log retention | FBI CJIS 5.4, STIG AU-11 |
| `services.redpanda.auditRetentionDays` | Override retention period (default: 365) | CJIS |

### Cluster Options

| Option | Description |
|--------|-------------|
| `services.redpanda.cluster.nodes` | Multi-node topology with auto seed server generation |

See [examples/](./examples/) for complete configurations including TLS and multi-node clusters.

## Architecture

```
scripts/update.sh -> default.nix -> flake.nix -> NixOS module
       |                 |              |              |
   Fetch + hash     Package def    Build system   systemd service
   from Cloudsmith   (deb extract)  + distribution  + firewall
```

- `default.nix` = How to package Redpanda (auto-generated by `scripts/update.sh`)
- `flake.nix` = How to use/run/deploy Redpanda on NixOS (stable wrapper)

## Port Reference

| Service | Default Port | Multi-Listener Pattern | Config Key |
|---------|-------------|------------------------|------------|
| Kafka API | 9092 | 9092, 9192, 9292... | `redpanda.kafka_api` |
| Schema Registry | 8081 | 8081, 8181, 8281... | `schema_registry.schema_registry_api` |
| HTTP Proxy | 8082 | 8082, 8182, 8282... | `pandaproxy.pandaproxy_api` |
| Admin API | 9644 | Single listener | `redpanda.admin` |
| RPC Server | 33145 | Single listener | `redpanda.rpc_server` |

## Compliance

This package targets 8 compliance frameworks. Percentages reflect implemented, verifiable controls as of 2026-04-09. See [docs/compliance/COMPLIANCE_MATRIX.md](./docs/compliance/COMPLIANCE_MATRIX.md) for detailed gap analysis.

| Framework | Implemented | Key Gap |
|-----------|-------------|---------|
| SOC 2 Type II | ~90% | No automated audit evidence collection |
| FBI CJIS Security Policy v6.0 | ~80% | MFA enforcement is application-dependent |
| NIST SP 800-161 (Supply Chain) | ~70% | SBOM tooling requires running update.sh |
| ISO/IEC 27036 | ~60% | No formal supplier agreements |
| FedRAMP High | ~55% | 3PAO assessment and SSP required |
| DoD SBOM Management (Jan 2024) | ~50% | SBOM artifacts generated on update, not shipped |
| NIST CSF 2.0 (Feb 2024) | ~50% | No incident response plan |
| Anduril NixOS STIG (Dec 2024) | ~45% | No structured audit logging |

Key controls: reproducible builds, SHA256 verification, immutable `/nix/store`, automated SBOM (CycloneDX/SPDX), SLSA v1.0 provenance, systemd hardening, TLS enforcement, 365-day audit retention.

Running `./scripts/update.sh` automatically generates compliance artifacts (SBOM, provenance, vulnerability scan) saved to `compliance/`.

## Documentation

- [docs/](./docs/) - Installation guide, build selection, FIPS deployment
- [examples/](./examples/) - Ready-to-use NixOS configurations (dev, cluster, TLS)
- [.github/workflows/](./.github/workflows/) - CI/CD pipeline details

## Contributing

1. Run `./scripts/update.sh <version>` (or wait for the automated weekly update)
2. Test the build: `nix build`
3. Test the module in a NixOS configuration
4. Submit changes (or review the automated PR)

## License

This packaging is provided as-is. Redpanda itself is licensed under the Redpanda Business Source License.
