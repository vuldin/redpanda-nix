# Claude Code Instructions for Redpanda NixOS Package

## Project Overview

This project provides automated Redpanda packaging for NixOS with a focus on maintainability, automation, and **compliance-relevant security controls**.

### Key Design Principles

1. **Single Source of Truth**: Port configuration lives in `services.redpanda.settings` only - firewall rules are automatically extracted
2. **Multi-Listener Support**: All services (Kafka API, Admin, Schema Registry, HTTP Proxy, RPC) support multiple listeners like the Helm chart
3. **Automatic Updates**: `scripts/update.sh` script can package any Redpanda version automatically with integrated compliance artifacts
4. **Nix-First**: Uses modern flakes and follows NixOS best practices
5. **Security-First**: Built-in TLS enforcement, audit retention, and automated SBOM generation supporting multiple compliance frameworks
6. **Multi-Architecture**: Native x86_64 and ARM64/aarch64 support (Apple Silicon ready)

## Architecture

```
Build Approaches:

1. SOURCE (Default — SLSA Build L3):
   Git Tag → fetchFromGitHub → Bazel Build in Nix Sandbox → NixOS Module
       ↓          ↓                    ↓                        ↓
   Tagged     SHA256           Hermetic compilation        systemd
   release    verified         (13 pre-built deps,         + firewall
   only                        fetch-nixify-build loop)
   (~1 hr on 22 cores, ~4 hr on free-tier CI)

   Adapted from redpanda-data/redpanda#29919 by randomizedcoder.

2. DEB (Fast fallback):
   Redpanda deb → Extract → Nix Package → NixOS Module
        ↓           ↓           ↓              ↓
   Official    Unpack      Package        systemd
   package     binaries    to /nix/store  + firewall
   (5 min)

3. FIPS (FedRAMP High — CMVP certified):
   Redpanda FIPS deb → Extract → Nix Package → NixOS Module
        ↓                ↓            ↓              ↓
   BoringCrypto     Unpack       Package        systemd
   (NIST cert)      binaries     to /nix/store  + firewall
   (5 min)
```

### File Descriptions

- **`source/build.nix`**: Builds Redpanda from source using Bazel in a Nix sandbox (DEFAULT — SLSA Build L3, full SBOM)
- **`source/`**: Supporting files for source build (static lib derivations, bazel-deps, nixify rules, patches)
- **`deb.nix`**: Fast fallback — extracts official Redpanda deb packages (5 min)
- **`fips.nix`**: CMVP-certified FIPS 140-2 build from official FIPS deb packages
- **`rpk.nix`**: Standalone rpk CLI built via Go's buildGoModule
- **`oci.nix`**: Minimal OCI container image via dockerTools (~313 MB)
- **`flake.nix`**: Modern Nix flake providing packages, apps, dev shell, and NixOS module
- **`scripts/patch-module-bazel.py`**: Patches Redpanda's MODULE.bazel for Nix sandbox compatibility
- **`scripts/gen-bazel-deps.py`**: Generates source/bazel-deps.nix from Bazel lockfile
- **`docs/WHICH_BUILD.md`**: Decision tree to help users choose the right build approach
- **`examples/`**: Production-ready configuration examples with compliance warnings
- **`README.md`**: User-facing documentation

**All build approaches are working.** See `docs/WHICH_BUILD.md` for the decision tree.

## Port Configuration System

### How It Works

The NixOS module includes an `extractPorts` function that:

1. Traverses the `services.redpanda.settings` attribute set
2. Extracts ports from all listener configurations:
   - `redpanda.kafka_api` (list or single)
   - `redpanda.admin` (list or single)
   - `redpanda.rpc_server` (single)
   - `schema_registry.schema_registry_api` (list or single)
   - `pandaproxy.pandaproxy_api` (list or single)
3. Handles both object format `{address: "...", port: 1234}` and simple integers
4. Returns unique list of all ports for firewall configuration

### Example Multi-Listener Config

Follow this port pattern for multiple listeners:
- **Kafka API**: 9092, 9192, 9292, ... (9x92)
- **Schema Registry**: 8081, 8181, 8281, ... (8x81)
- **HTTP Proxy**: 8082, 8182, 8282, ... (8x82)
- **Admin API**: Usually single listener (9644)

```nix
services.redpanda.settings = {
  redpanda = {
    # Multiple Kafka API listeners - pattern: 9x92
    kafka_api = [
      { address = "0.0.0.0"; port = 9092; name = "internal"; }
      { address = "0.0.0.0"; port = 9192; name = "external"; }
      { address = "0.0.0.0"; port = 9292; name = "public"; }
    ];

    # Admin API - typically single listener
    admin = [
      { address = "0.0.0.0"; port = 9644; }
    ];
  };

  schema_registry = {
    # Multiple Schema Registry listeners - pattern: 8x81
    schema_registry_api = [
      { address = "0.0.0.0"; port = 8081; name = "internal"; }
      { address = "0.0.0.0"; port = 8181; name = "external"; }
    ];
  };

  pandaproxy = {
    # Multiple HTTP Proxy listeners - pattern: 8x82
    pandaproxy_api = [
      { address = "0.0.0.0"; port = 8082; name = "internal"; }
      { address = "0.0.0.0"; port = 8182; name = "external"; }
    ];
  };
};
```

All ports (9092, 9192, 9292, 9644, 8081, 8181, 8082, 8182) are automatically extracted and opened when `openFirewall = true`.

## Build Process

### How Source Builds Work (Default)

Adapted from [redpanda-data/redpanda#29919](https://github.com/redpanda-data/redpanda/pull/29919) by [randomizedcoder](https://github.com/randomizedcoder).

1. **Fetch Source**: `fetchFromGitHub` downloads tagged release source (SHA256 verified)
2. **Patch Source**: `patch-module-bazel.py` removes dev extensions, adds Nix toolchain support
3. **Pre-build Dependencies**: 13 C/C++ libraries built from nixpkgs (c-ares, krb5, openssl, etc.)
4. **Repository Cache**: 258 archives pre-fetched into a content-addressed linkFarm
5. **Fetch-Nixify-Build Loop**: Run `bazel fetch` → patchelf downloaded ELF binaries → retry (up to 3 passes)
6. **Compile**: `bazel build //src/v/redpanda:redpanda` with `--spawn_strategy=local`
7. **Install**: Copy binary, patchelf runtime library paths (krb5, openssl)

Key: Nix sandbox provides hermeticity (no network during build). All inputs declared in the derivation.

### How Deb/FIPS Builds Work (Fallback)

1. **Fetch Deb Package**: Download official Redpanda deb from Cloudsmith CDN
2. **Extract**: Use `dpkg-deb` to extract binaries from the deb
3. **Patch**: Use `patchelf` to set the ELF interpreter to the bundled `ld.so`
4. **Wrap**: Create a bash wrapper script that sets `LD_LIBRARY_PATH` to bundled libs
5. **Install**: Copy binaries, libraries, and systemd service files to Nix store

### Version Pinning Strategy

- **ONLY package tagged releases**: Use git tags like `v26.1.2`, NOT `main` or `dev` branches
- **Verify tag exists**: `scripts/update.sh` validates stable release tags before packaging
- **Immutable builds**: Same version + same hash = reproducible output

## Development Workflow

### Building

```bash
# Build from source (default — SLSA L3, ~1 hr)
nix build .#redpanda

# Build from deb (fast fallback, ~5 min)
nix build .#redpanda-deb

# Build rpk CLI only (~2 min)
nix build .#redpanda-rpk

# Update to a specific version
./scripts/update.sh 26.1.2

# Validate flake
nix flake check

# Test NixOS module in VM:
nixos-rebuild build-vm -I nixos-config=./test-config.nix
```

### Adding New Features

When modifying the NixOS module:
1. Update `flake.nix` nixosModules.default section
2. Update README.md with new options
3. Add example configuration
4. Test in a NixOS VM or configuration

## Common Tasks

### Update to New Redpanda Version

```bash
# 1. Run the update script (validates tag, updates deb/fips/rpk hashes)
./scripts/update.sh 26.1.2

# 2. Regenerate source build deps (requires network — run outside sandbox)
python3 scripts/gen-bazel-deps.py \
  --lockfile <v26.1.2 MODULE.bazel.lock> \
  --bcr $(nix-build --no-out-link -E 'with import <nixpkgs> {}; callPackage ./source/bcr.nix {}') \
  --module-bazel <v26.1.2 MODULE.bazel> \
  > source/bazel-deps.nix

# 3. Build and test
nix build .#redpanda-deb && ./result/bin/redpanda --version
nix build .#redpanda-rpk && ./result/bin/rpk version

# 4. Commit changes
git add deb.nix fips.nix rpk.nix flake.nix source/bazel-deps.nix source/MODULE.bazel.lock.nix compliance/
git commit -m "update to Redpanda v26.1.2"
```

### Add Support for New Listener Type

If Redpanda adds a new service with listeners:

1. Add extraction logic in `flake.nix`:
```nix
newServicePorts =
  if settings ? new_service && settings.new_service ? new_service_api then
    map extractPort (if builtins.isList settings.new_service.new_service_api
                     then settings.new_service.new_service_api
                     else [ settings.new_service.new_service_api ])
  else [];
```

2. Add to `allPorts` concatenation:
```nix
allPorts = kafkaPorts ++ adminPorts ++ rpcPorts ++ ... ++ newServicePorts;
```

3. Update README.md port table

### Debugging Port Extraction

To see what ports are detected from a configuration:

```nix
# In a test config:
config.networking.firewall.allowedTCPPorts
# This will show the extracted ports
```

## New NixOS Module Options (2025-10-10)

### TLS Enforcement (`services.redpanda.enforceTLS`)

**Purpose**: Build-time validation that TLS is properly configured for all Redpanda services

**Compliance**: STIG SC-8, CJIS 5.10, FedRAMP High, SOC 2 CC6.7

**Usage**:
```nix
services.redpanda = {
  enforceTLS = true;  # Validates TLS at build time
  settings.redpanda = {
    kafka_api_tls = [{
      enabled = true;
      key_file = "/etc/redpanda/certs/tls.key";
      cert_file = "/etc/redpanda/certs/tls.crt";
    }];
    # ... configure TLS for all services
  };
};
```

**Behavior**:
- Checks all services: Kafka API, Admin API, RPC Server, Schema Registry, HTTP Proxy
- Fails at build time if any service is missing TLS configuration
- Provides helpful error messages with documentation links
- Shows confirmation warnings when TLS is properly configured

### CJIS Audit Retention (`services.redpanda.cjisAuditRetention`)

**Purpose**: Configure FBI CJIS-compliant 365-day audit log retention

**Compliance**: CJIS 5.4, STIG AU-11

**Usage**:
```nix
services.redpanda = {
  cjisAuditRetention = true;  # 365-day retention
  auditRetentionDays = 365;   # Optional: override (e.g., 730 for 2 years)
};
```

**Behavior**:
- Automatically configures systemd-journald for persistent storage
- Sets MaxRetentionSec, Storage, Compress, SystemMaxUse
- Creates oneshot service displaying compliance status at boot
- Logs viewable with `journalctl -u redpanda --since=-7days`

### Production Configuration Examples

**Use `examples/3-node-cluster-tls.nix` for production** - it includes:
- TLS enforcement (`enforceTLS = true`)
- CJIS audit retention (`cjisAuditRetention = true`)
- Multi-node cluster with rack awareness
- Complete TLS certificate setup instructions

**Non-TLS configs are clearly marked DEV/TESTING ONLY** with compliance warnings.

## Important Notes

- **Official Deb Packages**: Default and FIPS builds extract official deb packages from Cloudsmith CDN
- **Patchelf + Wrapper**: Binaries use Redpanda's bundled `ld.so` and libraries via patchelf and a bash wrapper script
- **Version Tags**: Always use tagged releases (e.g., `v26.1.2`), never `main` or development branches
- **Build Time**: Deb extraction takes 5-10 minutes
- **Security**: Module includes systemd hardening (NoNewPrivileges, ProtectSystem, etc.)
- **Architecture**: x86_64-linux supported for deb packages

## Compliance

This package provides technical controls that support multiple compliance frameworks. Organizational controls (audits, training, policies) are deployer responsibility. See [COMPLIANCE_MATRIX.md](./compliance/COMPLIANCE_MATRIX.md) for the authoritative control mapping.

### Compliance Documentation

- **[COMPLIANCE_MATRIX.md](./compliance/COMPLIANCE_MATRIX.md)** — Master control mapping across all frameworks
- **[C-SCRM_PLAN.md](./compliance/C-SCRM_PLAN.md)** — NIST SP 800-161 supply chain risk management
- **[FBI_CJIS_COMPLIANCE.md](./compliance/FBI_CJIS_COMPLIANCE.md)** — FBI CJIS Security Policy analysis and implementation roadmap
- **[INCIDENT_RESPONSE_PLAN.md](./compliance/INCIDENT_RESPONSE_PLAN.md)** — Incident response procedures
- **[SUPPLIER_ASSESSMENT.md](./compliance/SUPPLIER_ASSESSMENT.md)** — Supplier security assessment
- **[SUPPLIER_AGREEMENT_TEMPLATE.md](./compliance/SUPPLIER_AGREEMENT_TEMPLATE.md)** — ISO 27036 supplier agreement template

### Key Technical Controls

- **Reproducible builds**: Same inputs produce identical outputs (SHA256 verified)
- **Immutable infrastructure**: `/nix/store` is read-only, packages cannot be modified post-build
- **SLSA Build L3** (self-assessed): Source build via hermetic Nix sandbox
- **FIPS 140-2**: Available via `redpanda-fips` package (CMVP-certified BoringCrypto)
- **SBOM generation**: CycloneDX/SPDX via sbomnix, integrated in `scripts/update.sh`
- **systemd hardening**: `NoNewPrivileges=true`, `ProtectSystem=strict`, `PrivateTmp=true`
- **Audit trail**: Git history provides complete change log; 365-day journal retention option

### SBOM Generation

```bash
# Using sbomnix (recommended for DoD/NIST — supports CycloneDX, SPDX, SLSA provenance, CVE scanning)
sbomnix $(nix build .#redpanda --print-out-paths) --cdx redpanda-sbom.cdx.json
provenance $(nix build .#redpanda --print-out-paths) --out redpanda-provenance.json
vulnxscan $(nix build .#redpanda-deb --print-out-paths) --out vulns.csv

# Alternative: bombon (CycloneDX only)
nix run github:nikstur/bombon -- $(nix build .#redpanda-deb --print-out-paths)
```

Note: SBOM artifacts are generated when `scripts/update.sh` runs but are gitignored. They are not shipped with the package.

### FedRAMP Gaps

Remaining FedRAMP gaps are organizational (3PAO assessment, System Security Plan, continuous monitoring). The `redpanda-fips` package provides the technical foundation. See COMPLIANCE_MATRIX.md Section 8 for details.

### FIPS on NixOS

Nix-based FIPS deployment provides system-level FIPS enforcement rather than container-level. See [REDPANDA_FIPS_NIXOS.md](./docs/REDPANDA_FIPS_NIXOS.md) for implementation guide.

## CI/CD Automation

This project includes comprehensive GitHub Actions workflows for automated quality assurance and version updates.

### Workflow: `update-redpanda.yml`

**Purpose**: Automatically detect and package new Redpanda releases

**Schedule**: Weekly on Monday at 9 AM UTC (configurable)

**Process**:
1. Query GitHub API for latest Redpanda release
2. Compare with current version in `deb.nix`
3. If update available:
   - Run `scripts/update.sh` to generate package (validates tag, fetches deb, generates compliance artifacts)
   - Generate compliance artifacts (SBOM, provenance, CVE scan)
   - Build package to verify correctness
   - Create branch `update-redpanda-{version}`
   - Commit changes with detailed message
   - Open PR with compliance artifact summary
   - Add PR comment with verification commands

**Manual Trigger**: GitHub UI → Actions → Update Redpanda Package → Run workflow (optional version input)

**Compliance Integration**:
- Satisfies NIST SP 800-161 SR-3 (automated supply chain controls)
- Satisfies DoD SBOM requirements (automated generation)
- Satisfies NIST CSF 2.0 GV.SC-10 (automated vulnerability monitoring)

### Workflow: `ci.yml`

**Purpose**: Continuous integration for all commits and PRs

**Triggers**: Push to main/master, PRs against main/master

**Jobs**:
1. **check-formatting**: Validates Nix flake structure
2. **build-x86_64**: Builds package, verifies binaries
3. **build-examples**: Validates example configurations
4. **check-compliance**: Verifies SBOM/provenance artifacts exist (PRs only)
5. **documentation-check**: Ensures docs exist and dev examples have warnings
6. **compliance-status**: Displays compliance scores in PR summary
7. **summary**: Aggregates all results

**Critical Checks**:
- Dev examples MUST have `WARNING: NOT COMPLIANT FOR PRODUCTION`
- TLS example MUST be marked `PRODUCTION`
- All required documentation files must exist

**Testing Locally**:
```bash
# Check flake validity
nix flake check --show-trace

# Build package
nix build --show-trace

# Validate examples (syntax only)
for f in examples/*.nix; do nix-instantiate --parse "$f"; done
```

### Modifying Workflows

**Change update schedule**:
```yaml
# .github/workflows/update-redpanda.yml
schedule:
  - cron: '0 9 * * 1'  # Weekly
  # Change to: '0 9 * * *' for daily
```

**Add notifications** (Slack, Discord, etc.):
Add a final step to `update-redpanda.yml`:
```yaml
- name: Notify
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
```

**See**: `.github/workflows/README.md` for complete documentation

## Completed Features

- [x] Bazel-from-source build as default (SLSA Build L3, self-assessed)
- [x] Deb extraction fallback (fast, 5 min)
- [x] FIPS 140-2 package support (redpanda-fips, CMVP certified)
- [x] Standalone rpk CLI (buildGoModule)
- [x] OCI container images (dockerTools)
- [x] Version tag validation in update.sh
- [x] TLS enforcement validation (enforceTLS option)
- [x] Automated SBOM generation (CycloneDX + SPDX)
- [x] SLSA Build L3 provenance (hermetic Nix sandbox)
- [x] Automated vulnerability scanning (CVE detection)
- [x] CJIS audit retention (365-day configurable)
- [x] Cluster configuration examples with compliance warnings
- [x] CI/CD for automatic version updates (GitHub Actions)

## Future Enhancements

- [ ] PGO support for source builds — apply Redpanda's `.profdata` via `--fdo_optimize` if published as release artifacts (see `docs/WHICH_BUILD.md` PGO FAQ)
- [ ] TLS certificate generation/management helpers
- [ ] Formal SLSA conformance program certification (third-party verification)
- [ ] Self-hosted GitHub Actions runner for faster source builds

## Resources

### External Resources
- [Redpanda Helm Chart](https://github.com/redpanda-data/redpanda-operator/tree/main/charts/redpanda/chart) - Reference for listener configuration
- [NixOS Manual](https://nixos.org/manual/nixos/stable/) - Module system documentation
- [Nix Flakes](https://nixos.wiki/wiki/Flakes) - Flake format and usage

### Internal Documentation
- [COMPLIANCE_MATRIX.md](./compliance/COMPLIANCE_MATRIX.md) - Master compliance control mapping
- [C-SCRM_PLAN.md](./compliance/C-SCRM_PLAN.md) - NIST SP 800-161 implementation
- [SUPPLIER_ASSESSMENT.md](./compliance/SUPPLIER_ASSESSMENT.md) - Supplier security assessment
- [FBI_CJIS_COMPLIANCE.md](./compliance/FBI_CJIS_COMPLIANCE.md) - CJIS Security Policy analysis
- [REDPANDA_FIPS_NIXOS.md](./docs/REDPANDA_FIPS_NIXOS.md) - FIPS 140-2 implementation guide
- [INCIDENT_RESPONSE_PLAN.md](./compliance/INCIDENT_RESPONSE_PLAN.md) - Incident response procedures
