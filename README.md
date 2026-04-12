# Redpanda Nix Package

Nix-based Redpanda packaging for Linux with automatic version updates, compliance-relevant security controls, and CI/CD. Works on any Linux distribution with Nix installed, with additional NixOS module integration for declarative deployments.

> **Note**: This is an unofficial, community-maintained package intended for demonstration and evaluation purposes. It is not maintained or supported by Redpanda Data, Inc. Before deploying to production, consult your Redpanda support team to determine whether this packaging approach is supportable for your environment.

[![CI](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![Update Redpanda](../../actions/workflows/update-redpanda.yml/badge.svg)](../../actions/workflows/update-redpanda.yml)

## Features

### Packaging

- **Source builds from Bazel** — SLSA Build L3 (self-assessed), full source-to-binary provenance, complete SBOMs
- **Deb package fallback** from official Redpanda deb packages (5 min install)
- **FIPS 140-2 variant** with CMVP-certified BoringCrypto for FedRAMP High deployments
- **Standalone rpk CLI** via Go's `buildGoModule`
- **OCI container images** via `dockerTools.streamLayeredImage` (~313 MB minimal)
- **Version pinning** to tagged stable releases only (e.g., `v26.1.2`)

### NixOS Module Integration

- **Full NixOS module** with systemd service and security hardening
- **Automatic firewall** port extraction from listener configuration
- **Multi-listener support** for Kafka, Admin, Schema Registry, and HTTP Proxy
- **Cluster topology** with automatic seed server discovery and rack awareness

### Compliance & Security

- **TLS enforcement** with build-time validation (STIG SC-8, CJIS 5.10)
- **SLSA Build L3** (self-assessed) with hermetic Nix sandbox source builds
- **Automated SBOM generation** in CycloneDX/SPDX with SLSA provenance
- **Vulnerability scanning** via sbomnix with automated CVE detection
- **CJIS audit retention** with 365-day log retention for FBI compliance
- **Security controls** supporting SOC 2, CJIS, NIST, and other frameworks — see [compliance/](./compliance/)

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
| `redpanda` (default) | 1-4 hours | Bazel source build, SLSA Build L3, full SBOM | Supply chain compliance, DoD procurement, provenance audits |
| `redpanda-deb` | 5-10 min | Official pre-built binary from Cloudsmith deb (PGO + LTO optimized) | Production and development for most users |
| `redpanda-fips` | 5-10 min | Official FIPS deb with CMVP-certified BoringCrypto (PGO + LTO optimized) | FedRAMP High, DoD IL4+, CJIS, or any environment requiring FIPS-validated cryptography |
| `redpanda-rpk` | 2 min | Standalone rpk CLI via Go's `buildGoModule` | CLI management without the server |

> **Performance note:** The source build (`redpanda`) does not include [PGO](https://www.redpanda.com/blog/supercharging-streaming-profile-guided-optimization), which Redpanda's official binaries use for ~47% lower tail latencies. For production performance, use `redpanda-deb`. See [docs/WHICH_BUILD.md](./docs/WHICH_BUILD.md) for a detailed comparison.

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

The script validates the release tag, downloads the official deb, generates `deb.nix` with the correct hash, updates `flake.nix`, and generates compliance artifacts (SBOM, SLSA provenance, vulnerability scan).

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
scripts/update.sh -> deb.nix + source/build.nix -> flake.nix -> Nix package + NixOS module
       |                 |              |              |
   Fetch + hash     Package def    Build system   Package for any Linux
   from Cloudsmith   (deb extract)  + distribution  + NixOS service/firewall
```

- `deb.nix` = Deb package extraction (fast fallback) (auto-generated by `scripts/update.sh`)
- `flake.nix` = Nix flake providing the package (any Linux) and NixOS module (NixOS only)

## Port Reference

| Service | Default Port | Multi-Listener Pattern | Config Key |
|---------|-------------|------------------------|------------|
| Kafka API | 9092 | 9092, 9192, 9292... | `redpanda.kafka_api` |
| Schema Registry | 8081 | 8081, 8181, 8281... | `schema_registry.schema_registry_api` |
| HTTP Proxy | 8082 | 8082, 8182, 8282... | `pandaproxy.pandaproxy_api` |
| Admin API | 9644 | Single listener | `redpanda.admin` |
| RPC Server | 33145 | Single listener | `redpanda.rpc_server` |

## Compliance

This package provides technical controls that support multiple compliance frameworks. Organizational controls (audits, training, policies) are deployer responsibility. See [compliance/COMPLIANCE_MATRIX.md](./compliance/COMPLIANCE_MATRIX.md) for detailed control mapping.

| Framework | Coverage | Key Gap |
|-----------|----------|---------|
| SLSA v1.0 | Build L3 (self-assessed) | Formal conformance program not yet completed |
| SOC 2 Type II | Strong | Continuous evidence collection is deployer responsibility |
| FBI CJIS v6.0 | Strong | MFA and personnel controls are deployer-dependent |
| NIST SP 800-161 | Strong | Full source-to-binary provenance via source build |
| FedRAMP High | Partial | 3PAO assessment and SSP required (organizational) |
| DoD SBOM Management | Strong | SBOM generation supported via `scripts/update.sh` |

Key controls: reproducible builds, SHA256 verification, immutable `/nix/store`, automated SBOM (CycloneDX/SPDX), SLSA v1.0 provenance, systemd hardening, TLS enforcement, 365-day audit retention.

Running `./scripts/update.sh` generates compliance artifacts (SBOM, provenance, vulnerability scan) saved to `compliance/`.

## Documentation

- [docs/](./docs/) - Installation guide, build selection, FIPS deployment
- [examples/](./examples/) - NixOS module configurations (dev, cluster, TLS)
- [.github/workflows/](./.github/workflows/) - CI/CD pipeline details

## Contributing

1. Run `./scripts/update.sh <version>` (or wait for the automated weekly update)
2. Test the build: `nix build`
3. Test: `nix flake check`, and optionally test the NixOS module in a configuration
4. Submit changes (or review the automated PR)

## Acknowledgments

The source build approach (`source/build.nix`) is adapted from [redpanda-data/redpanda#29919](https://github.com/redpanda-data/redpanda/pull/29919) by [randomizedcoder](https://github.com/randomizedcoder). That PR introduced the Bazel-in-Nix build architecture including the fetch-nixify-build loop, pre-built C/C++ dependency strategy, and declarative nixify rules that this project builds upon.

## License

This packaging is provided as-is. Redpanda itself is licensed under the Redpanda Business Source License.
