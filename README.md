# Redpanda NixOS Package

Automated Redpanda packaging for NixOS with automatic version updates.

## Features

- 🔄 **Automatic Updates**: Update script fetches and packages any Redpanda version
- 🔥 **Smart Firewall**: Automatically extracts all ports from Redpanda config
- 🎯 **Multi-Listener Support**: Configure multiple listeners per service (Kafka, Admin, etc.)
- 📦 **Flakes Support**: Modern Nix flakes for reproducible builds
- 🛡️ **NixOS Module**: Full systemd service with security hardening

## Prerequisites

This tooling requires NixOS or a system with Nix installed and the following commands available:
- `nix-prefetch-url` (or `nix-shell` to run it)
- `curl`
- `jq` (optional, for JSON parsing)

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
        kafka_api = [
          {
            address = "0.0.0.0";
            port = 9092;
            name = "internal";
          }
          {
            address = "0.0.0.0";
            port = 9093;
            name = "external";
          }
        ];

        # Multiple Admin API listeners
        admin = [
          {
            address = "127.0.0.1";
            port = 9644;
            name = "internal";
          }
          {
            address = "0.0.0.0";
            port = 9645;
            name = "external";
          }
        ];

        rpc_server = {
          address = "0.0.0.0";
          port = 33145;
        };
      };

      schema_registry = {
        schema_registry_api = [
          { address = "0.0.0.0"; port = 8081; }
          { address = "0.0.0.0"; port = 8084; }
        ];
      };

      pandaproxy = {
        pandaproxy_api = [
          { address = "0.0.0.0"; port = 8082; }
          { address = "0.0.0.0"; port = 8083; }
        ];
      };
    };
  };
}
```

**Firewall Note**: When `openFirewall = true`, all ports (9092, 9093, 9644, 9645, 33145, 8081, 8084, 8082, 8083) are automatically extracted from your configuration and opened. You only configure ports once!

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

| Service | Default Port(s) | Config Location |
|---------|----------------|-----------------|
| Kafka API | 9092, 9093 | `redpanda.kafka_api` |
| Admin API | 9644, 9645 | `redpanda.admin` |
| RPC Server | 33145 | `redpanda.rpc_server` |
| Schema Registry | 8081, 8084 | `schema_registry.schema_registry_api` |
| HTTP Proxy | 8082, 8083 | `pandaproxy.pandaproxy_api` |

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

### `services.redpanda.enable`
Enable the Redpanda service.

### `services.redpanda.package`
The Redpanda package to use. Defaults to the package defined in this flake.

### `services.redpanda.dataDir`
Directory where Redpanda stores data. Default: `/var/lib/redpanda`

### `services.redpanda.user` / `services.redpanda.group`
User and group for the Redpanda service. Default: `redpanda`

### `services.redpanda.settings`
Redpanda configuration as a Nix attribute set. This maps directly to `redpanda.yaml`.

### `services.redpanda.openFirewall`
Automatically open firewall ports for all configured listeners. When enabled, ports are extracted from `settings` and opened automatically.

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

## License

This packaging is provided as-is. Redpanda itself is licensed under the Redpanda Business Source License.
