# Redpanda NixOS Module Implementation Plan

## Overview

This plan addresses all functionality gaps identified in comparison to fornybar/redpanda.nix while incorporating requirements from Redpanda's Helm chart and Kubernetes operator.

## Requirements Summary

### Core Requirements
1. **Binary-based installation**: Use pre-built binaries from GitHub releases (no source builds)
2. **Stretch cluster support**: Configurable seed servers and RPC advertised listeners
3. **Optional tuning**: Disabled by default, opt-in for iotune and system tuning
4. **Helm chart parity**: Support key configuration options from values.yaml
5. **Operator parity**: Support relevant CRD configuration options
6. **Operational features**: Support common cluster/node operations

---

## Current Status (Updated: 2025-10-08)

### ✅ Completed
- Research phase (Helm chart, K8s operator CRD analysis)
- Implementation plan creation

### 🚧 In Progress
- **Phase 1.1**: Cluster configuration module
  - ✅ Added `nodeName` option (defaults to hostname)
  - ✅ Added `cluster.nodes` option with node definitions
  - ✅ Implemented automatic seed server generation from cluster.nodes
  - ✅ Implemented automatic RPC advertised listener configuration
  - ✅ Implemented automatic Kafka advertised address configuration
  - ✅ Implemented rack awareness support for stretch clusters
  - ✅ Settings merge logic (cluster config + user settings)
  - ⏳ **Next**: Test flake syntax and build

### 📋 Pending
- Phase 1.2: Enhanced listener configuration
- Phase 1.3: Multi-stage systemd services
- Phase 2.1: Admin user management
- Phase 2.2: Redpanda Console module
- Phase 3.1: Optional tuning support
- Phase 3.2: Auto-restart and maintenance mode
- Phase 3.3: Enhanced configuration options
- Phase 4.1: NixOS VM tests
- Phase 4.2: Documentation updates
- Phase 5: Package improvements (optional)

### 🎯 Next Steps
1. Validate flake.nix syntax and fix any errors
2. Create example configuration and test cluster setup
3. Continue with Phase 1.2 (enhanced listener configuration)

---

## Implementation Phases

---

## Phase 1: Core Cluster Configuration (High Priority)

### 1.1 Cluster Configuration Module
**Goal**: Support multi-node cluster deployments with stretch cluster capabilities

**New Options**:
```nix
services.redpanda = {
  # Node identity
  nodeName = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Node name. Defaults to hostname if not specified.";
  };

  # Cluster topology
  cluster = {
    nodes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          seed = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this node is a seed server";
          };

          rpcAddress = mkOption {
            type = types.str;
            description = "RPC address for internal cluster communication";
            example = "192.168.1.10:33145";
          };

          kafkaAddress = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Advertised Kafka API address";
            example = "192.168.1.10:9092";
          };

          rack = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Rack ID for rack awareness (stretch clusters)";
            example = "us-west-2a";
          };
        };
      });
      default = {};
      description = ''
        Cluster node definitions. Each machine should have the same cluster.nodes
        configuration, and will auto-discover which node it is based on nodeName/hostname.
      '';
    };

    autoDiscovery = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically discover node identity from hostname";
    };
  };
};
```

**Implementation Details**:
- Automatically generate `seed_servers` from `cluster.nodes` where `seed = true`
- Auto-populate `advertised_rpc_api` from node's `rpcAddress`
- Auto-populate `advertised_kafka_api` from node's `kafkaAddress`
- Support hostname-based node discovery (like fornybar)
- Support explicit `nodeName` override for complex deployments

**Files to Modify**:
- `flake.nix`: Add cluster configuration logic and seed server generation

---

### 1.2 Enhanced Listener Configuration
**Goal**: Support all listener types with proper advertised addresses for stretch clusters

**Updated Options**:
```nix
services.redpanda.settings = {
  redpanda = {
    # Kafka API - support both simple and advanced formats
    kafka_api = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          address = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
          authentication_method = mkOption {
            type = types.nullOr (types.enum ["none" "sasl" "mtls_identity"]);
            default = null;
          };
        };
      });
      default = [{ name = "internal"; address = "0.0.0.0"; port = 9092; }];
    };

    # Advertised Kafka API for stretch clusters
    advertised_kafka_api = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          address = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
        };
      });
      default = [];
      description = "Advertised addresses for Kafka API (for stretch/multi-DC)";
    };

    # RPC Server with advertised address
    rpc_server = {
      address = mkOption { type = types.str; default = "0.0.0.0"; };
      port = mkOption { type = types.port; default = 33145; };
    };

    advertised_rpc_api = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          address = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
        };
      });
      default = null;
      description = "Advertised RPC address for stretch clusters";
    };

    # Admin API
    admin = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          address = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
          authentication_method = mkOption {
            type = types.nullOr (types.enum ["none" "sasl" "mtls_identity"]);
            default = null;
          };
        };
      });
      default = [{ name = "internal"; address = "0.0.0.0"; port = 9644; }];
    };
  };

  # Schema Registry
  schema_registry = {
    schema_registry_api = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          address = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
          authentication_method = mkOption {
            type = types.nullOr (types.enum ["none" "http_basic"]);
            default = null;
          };
        };
      });
      default = [{ name = "internal"; address = "0.0.0.0"; port = 8081; }];
    };
  };

  # HTTP Proxy (PandaProxy)
  pandaproxy = {
    pandaproxy_api = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          address = mkOption { type = types.str; };
          port = mkOption { type = types.port; };
          authentication_method = mkOption {
            type = types.nullOr (types.enum ["none" "http_basic"]);
            default = null;
          };
        };
      });
      default = [{ name = "internal"; address = "0.0.0.0"; port = 8082; }];
    };
  };
};
```

**Implementation Details**:
- Maintain backward compatibility with simple port numbers
- Support named listeners (internal/external)
- Auto-populate advertised addresses from `cluster.nodes` if available
- Proper type checking and validation

**Files to Modify**:
- `flake.nix`: Update options and port extraction logic

---

### 1.3 Multi-Stage Systemd Services
**Goal**: Proper initialization sequence with setup, config, and main services

**Service Structure**:
```
redpanda-setup.service (oneshot)
  ↓
redpanda-config.service (oneshot)
  ↓
redpanda.service (simple)
```

**redpanda-setup.service**:
- Create directories (`/var/lib/redpanda`, `/etc/redpanda`)
- Generate initial configuration files
- Discover node identity (if `cluster.autoDiscovery = true`)
- Optionally run `rpk redpanda tune all` (if `tuning.enable = true`)
- Optionally run iotune (if `tuning.iotune.enable = true`)

**redpanda-config.service**:
- Import cluster configuration
- Create admin user (if configured)
- Validate configuration
- Check cluster health

**redpanda.service**:
- Main Redpanda broker process
- Runs `rpk redpanda start --config /etc/redpanda/redpanda.yaml`

**Files to Modify**:
- `flake.nix`: Replace single systemd service with three-stage setup

---

## Phase 2: Security & Management (High Priority)

### 2.1 Admin User Management
**Goal**: Declarative superuser creation and management

**New Options**:
```nix
services.redpanda = {
  admin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to create an admin superuser";
    };

    username = mkOption {
      type = types.str;
      default = "admin";
      description = "Admin username";
    };

    passwordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing admin password";
      example = "/run/secrets/redpanda-admin-password";
    };

    mechanism = mkOption {
      type = types.enum ["SCRAM-SHA-256" "SCRAM-SHA-512"];
      default = "SCRAM-SHA-256";
      description = "SASL mechanism for admin user";
    };
  };
};
```

**Implementation Details**:
- Create admin user in `redpanda-config.service`
- Use `rpk acl user create` with password from file
- Idempotent creation (check if user exists first)

**Files to Create/Modify**:
- `flake.nix`: Add admin options and service configuration

---

### 2.2 Redpanda Console Module
**Goal**: Web UI for Redpanda management

**New Module**: `flake.nix` (add second NixOS module)

**Options**:
```nix
services.redpanda-console = {
  enable = mkEnableOption "Redpanda Console web UI";

  package = mkOption {
    type = types.package;
    description = "Redpanda Console package";
  };

  port = mkOption {
    type = types.port;
    default = 8080;
    description = "HTTP port for Console";
  };

  kafkaBrokers = mkOption {
    type = types.listOf types.str;
    default = ["localhost:9092"];
    description = "Kafka broker addresses";
    example = ["broker1:9092" "broker2:9092"];
  };

  settings = mkOption {
    type = types.attrs;
    default = {};
    description = "Additional console configuration (YAML)";
  };

  openFirewall = mkOption {
    type = types.bool;
    default = false;
    description = "Open firewall port for Console";
  };
};
```

**Implementation Details**:
- Download Redpanda Console binary from GitHub releases
- Generate `console-config.yaml` from options
- Create systemd service
- Auto-configure to connect to local broker if `services.redpanda.enable = true`

**Files to Create**:
- `console.nix`: New package derivation
- Update `flake.nix`: Add console package and module

---

### 2.3 ACL Management Module
**Goal**: Declarative ACL management (optional, lower priority)

**New Module**: Can be added later as separate module or integrated

**Options**:
```nix
services.redpanda-acls = {
  enable = mkEnableOption "Declarative ACL management";

  kafkaConnect = {
    brokers = mkOption {
      type = types.listOf types.str;
      default = ["localhost:9092"];
    };

    sasl = {
      username = mkOption { type = types.str; };
      passwordFile = mkOption { type = types.path; };
      mechanism = mkOption {
        type = types.enum ["SCRAM-SHA-256" "SCRAM-SHA-512"];
        default = "SCRAM-SHA-256";
      };
    };
  };

  users = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        passwordFile = mkOption { type = types.path; };
        acls = mkOption {
          type = types.listOf (types.submodule {
            options = {
              topics = mkOption { type = types.listOf types.str; default = []; };
              groups = mkOption { type = types.listOf types.str; default = []; };
              operations = mkOption {
                type = types.listOf (types.enum ["read" "write" "all"]);
              };
              resourcePatternType = mkOption {
                type = types.enum ["literal" "prefixed"];
                default = "literal";
              };
            };
          });
        };
      };
    });
  };
};
```

**Implementation**: Lower priority, can use Python script approach similar to fornybar

---

## Phase 3: Operational Features (Medium Priority)

### 3.1 Optional Tuning Support
**Goal**: Opt-in system and I/O tuning (disabled by default per requirements)

**New Options**:
```nix
services.redpanda = {
  tuning = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable automatic system tuning via rpk";
    };

    tuneList = mkOption {
      type = types.listOf types.str;
      default = ["all"];
      description = "List of tuners to enable";
      example = ["net" "disk" "cpu"];
    };

    iotune = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Run iotune to generate I/O configuration";
      };

      configPath = mkOption {
        type = types.path;
        default = "/var/lib/redpanda/io-config.yaml";
        description = "Path to generated io-config.yaml";
      };

      duration = mkOption {
        type = types.int;
        default = 600;
        description = "Duration in seconds for iotune run";
      };
    };
  };
};
```

**Implementation Details**:
- Run `rpk redpanda tune ${concatStringsSep " " cfg.tuning.tuneList}` in setup service
- Run iotune in setup service if enabled
- Skip tuning entirely if `tuning.enable = false` (default)

**Files to Modify**:
- `flake.nix`: Add tuning options and setup service logic

---

### 3.2 Auto-Restart and Maintenance Mode
**Goal**: Controlled restart behavior during configuration changes

**New Options**:
```nix
services.redpanda = {
  autoRestart = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Automatically restart Redpanda when configuration changes.
      If false, manual restart required via systemctl.
    '';
  };

  maintenanceMode = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable maintenance mode support";
    };

    drainTimeout = mkOption {
      type = types.int;
      default = 300;
      description = "Timeout for leadership draining (seconds)";
    };
  };
};
```

**Implementation Details**:
- If `autoRestart = false`: Set `RestartIfChanged = false` in systemd
- If `maintenanceMode.enable = true`: Run `rpk cluster maintenance enable` before restart
- Use `ExecStopPost` to disable maintenance mode after stop

**Files to Modify**:
- `flake.nix`: Add restart control and maintenance mode logic

---

### 3.3 Enhanced Configuration from Helm/Operator

**New Options** (based on Helm chart analysis):
```nix
services.redpanda.settings = {
  redpanda = {
    # Rack awareness for stretch clusters
    rack = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Rack ID for rack awareness";
    };

    # Connection limits
    kafka_connection_rate_limit = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Max Kafka connections per second";
    };

    # Storage
    log_segment_size = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Log segment size in bytes";
    };

    # Compaction
    log_compaction_interval_ms = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Log compaction interval";
    };

    # Retention
    delete_retention_ms = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Tombstone retention time";
    };

    # Cloud storage / Tiered storage
    cloud_storage_enabled = mkOption {
      type = types.bool;
      default = false;
      description = "Enable tiered storage";
    };

    cloud_storage_region = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    cloud_storage_bucket = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    cloud_storage_access_key = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    cloud_storage_secret_key_file = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing cloud storage secret key";
    };
  };

  # Audit logging
  audit_enabled = mkOption {
    type = types.bool;
    default = false;
    description = "Enable audit logging";
  };

  # Schema registry settings
  schema_registry = {
    schema_registry_replication_factor = mkOption {
      type = types.nullOr types.int;
      default = null;
    };
  };

  # Pandaproxy settings
  pandaproxy = {
    pandaproxy_api_cors_enabled = mkOption {
      type = types.bool;
      default = false;
    };
  };
};
```

**Files to Modify**:
- `flake.nix`: Add comprehensive configuration options

---

## Phase 4: Testing & Documentation (Medium Priority)

### 4.1 NixOS VM Tests

**Test Cases**:
1. **Single Node Test** (`tests/single-node.nix`):
   - Basic broker startup
   - Topic creation
   - Produce/consume messages
   - Admin API access

2. **Multi-Node Cluster Test** (`tests/cluster.nix`):
   - 3-node cluster formation
   - Seed server discovery
   - Cross-node replication
   - Node failure recovery

3. **Stretch Cluster Test** (`tests/stretch-cluster.nix`):
   - Multi-rack awareness
   - Advertised listeners
   - Cross-datacenter simulation

4. **Console Test** (`tests/console.nix`):
   - Console deployment
   - Broker connection
   - UI accessibility

**Test Structure**:
```nix
# tests/single-node.nix
import <nixpkgs/nixos/tests/make-test-python.nix> {
  name = "redpanda-single-node";

  nodes = {
    broker = { ... }: {
      imports = [ ../flake.nix ];
      services.redpanda = {
        enable = true;
        openFirewall = true;
      };
    };
  };

  testScript = ''
    broker.start()
    broker.wait_for_unit("redpanda.service")
    broker.wait_for_open_port(9092)

    # Test topic creation
    broker.succeed("${pkgs.redpanda}/bin/rpk topic create test")

    # Test produce
    broker.succeed("echo 'hello' | ${pkgs.redpanda}/bin/rpk topic produce test")

    # Test consume
    broker.succeed("${pkgs.redpanda}/bin/rpk topic consume test -n 1")
  '';
}
```

**Files to Create**:
- `tests/single-node.nix`
- `tests/cluster.nix`
- `tests/stretch-cluster.nix`
- `tests/console.nix`

---

### 4.2 Documentation Updates

**README.md Updates**:
- Cluster deployment examples
- Stretch cluster configuration guide
- Rack awareness setup
- Admin user management
- Console setup
- Tuning options

**New Documentation**:
- `docs/CLUSTER_SETUP.md`: Multi-node cluster guide
- `docs/STRETCH_CLUSTERS.md`: Stretch cluster guide
- `docs/SECURITY.md`: Authentication and ACL guide
- `docs/TUNING.md`: Performance tuning guide

**Example Configurations**:
- `examples/single-node.nix`
- `examples/three-node-cluster.nix`
- `examples/stretch-cluster.nix`
- `examples/with-console.nix`
- `examples/with-authentication.nix`

**Files to Create/Update**:
- `README.md`
- `docs/*.md`
- `examples/*.nix`

---

## Phase 5: Package Improvements (Lower Priority)

### 5.1 Redpanda Console Package

**New Package**: `console.nix`

```nix
{ lib, stdenv, fetchurl, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname = "redpanda-console";
  version = "latest";  # Will be updated by update.sh

  src = fetchurl {
    url = "https://github.com/redpanda-data/console/releases/download/v${version}/console-${version}-linux-amd64.tar.gz";
    sha256 = "...";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    mkdir -p $out/bin
    cp console $out/bin/redpanda-console
  '';
}
```

**Update Script Enhancement**:
- Extend `update.sh` to also fetch Console releases
- Generate both `default.nix` (Redpanda) and `console.nix` (Console)

**Files to Create/Modify**:
- `console.nix`
- `update.sh`

---

### 5.2 Binary Cache Setup

**Goal**: Provide pre-built binaries via Cachix

**Setup**:
1. Create Cachix account and cache
2. Add GitHub Actions workflow for building packages
3. Automatically push builds to Cachix
4. Document cache usage in README

**Files to Create**:
- `.github/workflows/build.yml`
- Update `README.md` with cache instructions

---

### 5.3 Pre-commit Hooks

**Goal**: Code quality and formatting

**Setup**:
```nix
# flake.nix
{
  inputs = {
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = { self, nixpkgs, pre-commit-hooks, ... }: {
    checks = {
      pre-commit-check = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          nixpkgs-fmt.enable = true;
          statix.enable = true;
        };
      };
    };
  };
}
```

**Files to Modify**:
- `flake.nix`

---

## Implementation Priority Order

### Sprint 1 (Core Functionality) - IN PROGRESS
1. 🚧 Phase 1.1: Cluster configuration module (cluster.nodes, seed servers) - **IN PROGRESS**
2. ⏳ Phase 1.2: Enhanced listener configuration (advertised addresses) - PENDING
3. ⏳ Phase 1.3: Multi-stage systemd services - PENDING

### Sprint 2 (Management & Security) - NOT STARTED
4. ⏳ Phase 2.1: Admin user management - PENDING
5. ⏳ Phase 2.2: Redpanda Console module - PENDING
6. ⏳ Phase 3.1: Optional tuning support - PENDING
7. ⏳ Phase 3.2: Auto-restart and maintenance mode - PENDING

### Sprint 3 (Configuration & Testing) - NOT STARTED
8. ⏳ Phase 3.3: Enhanced configuration options (rack awareness, tiered storage, etc.) - PENDING
9. ⏳ Phase 4.1: NixOS VM tests (single-node, cluster) - PENDING
10. ⏳ Phase 4.2: Documentation updates - PENDING

### Sprint 4 (Polish) - NOT STARTED
11. ⚠️ Phase 2.3: ACL management module (optional) - DEFERRED
12. ⚠️ Phase 5.1: Console package - DEFERRED
13. ⚠️ Phase 5.2: Binary cache - DEFERRED
14. ⚠️ Phase 5.3: Pre-commit hooks - DEFERRED

---

## Configuration Examples

### Example 1: Single Node (Simple)
```nix
services.redpanda = {
  enable = true;
  openFirewall = true;

  settings = {
    redpanda = {
      developer_mode = true;
    };
  };
};
```

### Example 2: Three-Node Cluster
```nix
services.redpanda = {
  enable = true;
  openFirewall = true;

  cluster = {
    nodes = {
      broker1 = {
        seed = true;
        rpcAddress = "10.0.1.10:33145";
        kafkaAddress = "10.0.1.10:9092";
      };
      broker2 = {
        seed = true;
        rpcAddress = "10.0.1.11:33145";
        kafkaAddress = "10.0.1.11:9092";
      };
      broker3 = {
        seed = true;
        rpcAddress = "10.0.1.12:33145";
        kafkaAddress = "10.0.1.12:9092";
      };
    };
  };

  settings = {
    redpanda = {
      developer_mode = false;
    };
  };
};
```

### Example 3: Stretch Cluster (Multi-DC)
```nix
services.redpanda = {
  enable = true;
  openFirewall = true;

  cluster = {
    nodes = {
      dc1-broker1 = {
        seed = true;
        rpcAddress = "10.1.0.10:33145";
        kafkaAddress = "broker1.dc1.example.com:9092";
        rack = "dc1-az1";
      };
      dc1-broker2 = {
        seed = true;
        rpcAddress = "10.1.0.11:33145";
        kafkaAddress = "broker2.dc1.example.com:9092";
        rack = "dc1-az2";
      };
      dc2-broker1 = {
        seed = true;
        rpcAddress = "10.2.0.10:33145";
        kafkaAddress = "broker1.dc2.example.com:9092";
        rack = "dc2-az1";
      };
    };
  };

  settings = {
    redpanda = {
      developer_mode = false;
      # Advertised addresses auto-populated from cluster.nodes
    };
  };
};
```

### Example 4: With Admin User & Console
```nix
services.redpanda = {
  enable = true;
  openFirewall = true;

  admin = {
    enable = true;
    username = "admin";
    passwordFile = "/run/secrets/redpanda-admin-password";
  };

  settings = {
    redpanda = {
      kafka_api = [{
        name = "internal";
        address = "0.0.0.0";
        port = 9092;
        authentication_method = "sasl";
      }];
    };
  };
};

services.redpanda-console = {
  enable = true;
  openFirewall = true;
  kafkaBrokers = ["localhost:9092"];
};
```

---

## Backward Compatibility

All existing configurations must continue to work:

✅ Simple port-based configuration
✅ Flat `settings` attribute
✅ Existing firewall port extraction
✅ Default single-node setup

New cluster features are opt-in and don't break existing deployments.

---

## Success Criteria

**Phase 1 (Core Cluster Features)**
- [x] Cluster node configuration structure (cluster.nodes)
- [x] Automatic seed server generation
- [x] Configurable RPC advertised listeners
- [x] Configurable Kafka advertised addresses
- [x] Rack awareness for stretch clusters
- [ ] Syntax validation and flake build success
- [ ] Multi-stage systemd services (setup, config, main)
- [ ] Test deployment with example configurations

**Phase 2 (Security & Management)**
- [ ] Admin user creation working
- [ ] Console module working
- [ ] Optional tuning (disabled by default)
- [ ] Auto-restart control

**Phase 3 (Testing & Documentation)**
- [ ] NixOS VM tests passing (single-node)
- [ ] NixOS VM tests passing (cluster)
- [ ] Documentation complete with examples
- [ ] Example configurations for all use cases

**Overall Requirements**
- [ ] Stretch cluster deployment working across 3+ nodes
- [ ] Backward compatibility maintained
- [ ] No regressions in existing functionality

---

## Timeline Estimate

- **Sprint 1**: 2-3 days (core cluster functionality)
- **Sprint 2**: 2-3 days (security and management)
- **Sprint 3**: 2-3 days (testing and docs)
- **Sprint 4**: 1-2 days (optional polish)

**Total**: 7-11 days for full implementation

---

## Notes

- Focus on binary installations only (no source builds in this iteration)
- Stretch cluster support is primary goal
- Configuration should feel natural for Kubernetes/Helm users
- Maintain simplicity for single-node use cases
- All new options should have sensible defaults
