# Multi-Framework Compliance Matrix

**Last updated**: 2026-04-12

This document maps package-level technical controls to framework requirements. **Organizational controls (audits, policies, personnel, training) are deployer responsibility.** This package provides controls that *support* these frameworks — it does not by itself make an organization compliant.

Frameworks analyzed:
1. **SLSA v1.0** - Supply Chain Levels for Software Artifacts
2. **SOC 2 Type II** - Trust Services Criteria
3. **NIST SP 800-161 Rev. 1** - Cybersecurity Supply Chain Risk Management
4. **ISO/IEC 27036** - Information Security for Supplier Relationships
5. **NIST CSF 2.0** - Cybersecurity Framework 2.0 (Feb 2024)
6. **DoD SBOM Management** - NSA Supply Chain Security Guidance (Jan 2024)
7. **Anduril NixOS STIG** - DoD Security Technical Implementation Guide (Dec 2024)
8. **FedRAMP High** - Federal Risk and Authorization Management Program

### Status Overview

| Framework | Coverage | Key Gap |
|-----------|----------|---------|
| **SLSA v1.0** | Build L3 (self-assessed) | Formal SLSA conformance program not yet completed |
| **SOC 2 Type II** | Strong | Audit evidence collection automated but not continuously running |
| **FBI CJIS v6.0** | Strong | `cjisCompliant` preset available; MFA still deployer-dependent |
| **NIST SP 800-161** | Strong | Full source-to-binary provenance via source build |
| **ISO/IEC 27036** | Moderate | Supplier agreement template available; formal signing required |
| **FedRAMP High** | Partial (organizational gaps) | 3PAO assessment and SSP required (organizational) |
| **DoD SBOM Management** | Strong | Full SBOM and provenance via source build |
| **NIST CSF 2.0** | Moderate | Incident response plan and CVE scanning supported |
| **Anduril NixOS STIG** | Partial (service-level only) | Structured audit logging via `auditLog` option |

**Key improvements** (2026-04-12): Source build from Bazel (`nix build .#redpanda`) achieves SLSA Build L3 (self-assessed) with hermetic Nix sandbox, full source-to-binary provenance, and complete SBOMs. Adapted from [redpanda-data/redpanda#29919](https://github.com/redpanda-data/redpanda/pull/29919) by randomizedcoder. Deb extraction (`nix build .#redpanda-deb`) and FIPS (`nix build .#redpanda-fips`) retained as fallback and CMVP-certified options respectively.

**Previous improvements** (2026-04-10): SBOM distribution to `compliance/current/` and GitHub Releases, automated audit evidence collection, structured audit logging via Redpanda's internal audit topic, continuous CVE scanning workflow, incident response plan, supplier agreement template, and `cjisCompliant` meta-option for one-flag CJIS compliance.

---

## Table of Contents

1. [SLSA v1.0](#1-slsa-v10-build-provenance)
2. [SOC 2 Type II](#2-soc-2-type-ii-compliance)
3. [NIST SP 800-161](#3-nist-sp-800-161-analysis)
4. [ISO/IEC 27036](#4-isoiec-27036-analysis)
5. [NIST CSF 2.0](#5-nist-csf-20-analysis)
6. [DoD SBOM Management](#6-dod-sbom-management)
7. [Anduril NixOS STIG](#7-anduril-nixos-stig)
8. [FedRAMP High](#8-fedramp-high-analysis)
9. [Cross-framework evidence reuse](#9-cross-framework-evidence-reuse)
10. [Remaining gaps](#10-remaining-gaps)
11. [OS independence](#11-os-independence)

---

## 1. SLSA v1.0 Build Provenance

### Status: Build L3 (self-assessed)

**SLSA** (Supply-chain Levels for Software Artifacts) is a framework by Google/OpenSSF that defines levels of supply chain security for software builds. It is increasingly referenced in DoD procurement and federal supply chain guidance.

**Important**: SLSA Build L3 is self-assessed. Formal certification requires the [SLSA conformance program](https://slsa.dev/spec/v1.0/verifying-artifacts). Only the source build (`nix build .#redpanda`) achieves L3. The deb fallback (`nix build .#redpanda-deb`) and FIPS package (`nix build .#redpanda-fips`) are L1 only (provenance exists but build is not hermetic from source).

### Build Track Requirements

| Requirement | L1 | L2 | L3 | Source build | Deb build |
|------------|----|----|----|--------------------|-----------|
| **Provenance exists** | Required | Required | Required | SLSA provenance JSON generated per build | Provenance JSON (packaging only) |
| **Hosted build platform** | -- | Required | Required | GitHub Actions + Nix sandbox | GitHub Actions |
| **Build as code** | -- | Required | Required | `source/build.nix` is the declarative build definition | `deb.nix` |
| **Hermetic builds** | -- | -- | Required | Nix sandbox: no network access, all inputs declared in derivation | Not hermetic (deb from CDN) |
| **Isolated builds** | -- | -- | Required | Nix sandbox: sandboxed filesystem, no host state access | Nix sandbox (packaging only) |
| **Reproducible builds** | -- | -- | Expected | Same source + same `flake.lock` = identical binary | Same deb URL + same hash = identical extraction |

### How It Works

The source build (`source/build.nix`) compiles Redpanda from tagged release source inside a Nix sandbox:

1. **Source**: `fetchFromGitHub` pins a tagged release (`v${version}`) — never `main` or a branch
2. **Dependencies**: 365 archives pre-fetched into a content-addressed repository cache
3. **Compilation**: Bazel runs inside the Nix sandbox with `--spawn_strategy=local` (no nested sandboxing)
4. **Isolation**: No network access during build; all inputs declared in the Nix derivation
5. **Output**: Binary installed to `/nix/store` with runtime library paths patched via `patchelf`

### Provenance Chain

```
Git tag (v26.1.2) → fetchFromGitHub (SHA256 verified)
    → Nix sandbox (hermetic, isolated)
        → Bazel build (13 pre-built deps + 365 cached archives)
            → patchelf (Nix store rpath)
                → /nix/store/...-redpanda-26.1.2/bin/redpanda
```

Every step is deterministic and auditable. The complete dependency graph is queryable via `nix-store -q --tree`.

### Cross-Framework Impact

SLSA Build L3 strengthens claims in other frameworks:

| Framework | Control | Impact |
|-----------|---------|--------|
| NIST SP 800-161 | SR-4 (Provenance) | Full source-to-binary provenance chain |
| DoD SBOM Management | Req 6 (Provenance Tracking) | SLSA L3 attestation satisfies requirement |
| NIST CSF 2.0 | GV.SC-06 (Security practices integrated) | Hermetic builds as security practice |
| SOC 2 | CC9.1 (Supply chain security) | Stronger verification evidence |

### Verification

```bash
# Build from source with full provenance
nix build .#redpanda

# Query the complete dependency graph
nix-store -q --tree ./result

# Verify store integrity
nix-store --verify --check-contents ./result
```

### Limitations

- **Self-assessed**: Not independently verified through the SLSA conformance program
- **Reproducibility**: "Expected" at L3, not "required". Depends on Bazel's determinism within the Nix sandbox. Not yet verified with `nix build --rebuild`
- **Deb/FIPS packages**: Only L1 — provenance exists but the binary comes from Redpanda's build pipeline, not ours

---

## 2. SOC 2 Type II — Supported Controls

### Status: Strong technical control coverage

**Summary**: Nix architecture provides controls supporting SOC 2 Trust Services Criteria through:
- **Reproducible Builds**: Cryptographically verifiable, byte-for-byte identical outputs
- **Immutable Infrastructure**: Read-only package storage prevents tampering
- **Complete Audit Trails**: Git-based change tracking with full provenance
- **Automated Security Controls**: systemd hardening and least-privilege access
- **Atomic Rollbacks**: Instant recovery from failures or security incidents

### Trust Services Criteria Mapping

| Criteria | Control Area | Implementation | Status |
|----------|-------------|----------------|--------|
| **CC6.1** | Logical and Physical Access Controls | Least privilege user, systemd hardening | Implemented |
| **CC6.2** | Authentication and Access | Declarative firewall rules, port management | Implemented |
| **CC6.6** | Logical Access - Removal/Modification | Read-only `/nix/store`, immutable packages | Implemented |
| **CC6.7** | Logical Access - Security Settings | Automated security hardening via systemd | Implemented |
| **CC7.1** | Detection of Security Events | systemd logging, journald integration | Implemented |
| **CC7.2** | Monitoring System Components | Reproducible builds detect tampering | Implemented |
| **CC7.3** | Incident Response | Atomic rollback capability | Implemented |
| **CC8.1** | Change Management - Authorization | Git-based approval workflow | Implemented |
| **CC9.1** | Risk Assessment Program | Cryptographic verification of all packages | Implemented |
| **CC9.2** | Risk Mitigation | Multiple mitigation layers | Implemented |

### Detailed Control Implementation

#### CC6.1 - Logical and Physical Access Controls

**Least Privilege User Model**:
```nix
# flake.nix:362-370
users.users.${cfg.user} = {
  isSystemUser = true;
  group = cfg.group;
  description = "Redpanda daemon user";
  home = cfg.dataDir;
  createHome = true;
};
```

**systemd Security Hardening**:
```nix
serviceConfig = {
  NoNewPrivileges = true;      # Prevents privilege escalation
  PrivateTmp = true;            # Isolated /tmp
  ProtectSystem = "strict";     # Read-only /usr, /boot, /etc
  ProtectHome = true;           # No access to /home
  ReadWritePaths = [ cfg.dataDir ];  # Only dataDir is writable
  LimitNOFILE = 65536;          # Resource limits
};
```

**Verification**:
```bash
# Check systemd hardening
systemctl show redpanda | grep -E "(NoNewPrivileges|ProtectSystem|PrivateTmp)"
```

#### CC6.6 - Logical Access - Removal and Modification

**Immutable Package Storage**:
```bash
# /nix/store is read-only
ls -la /nix/store/
# drwxr-xr-x root root (read-only after build)

# Attempt to modify package (will fail)
echo "malicious" > /nix/store/abc123-redpanda-25.2.8/bin/redpanda
# bash: Read-only file system
```

**Cryptographic Verification**:
```nix
# deb.nix (auto-generated by update.sh)
{
  pname = "redpanda";
  version = "25.2.8";

  src = fetchurl {
    url = "https://github.com/redpanda-data/redpanda/releases/download/v25.2.8/redpanda-25.2.8-amd64.tar.gz";
    sha256 = "1a2b3c4d...";  # Cryptographic hash verified on every build
  };
}
```

#### CC7.2 - System Monitoring - Detection of Anomalies

**Reproducible Build Verification**:
```bash
# Verify package integrity
nix-store --verify --check-contents /nix/store/*-redpanda-*

# Tamper detection
nix-store --verify
# Detects any modifications to /nix/store
```

#### CC7.3 - Response to Security Incidents

**Atomic Rollback**:
```bash
# Instant rollback to previous configuration
nixos-rebuild switch --rollback

# List available generations
nix-env --list-generations --profile /nix/var/nix/profiles/system
```

**Recovery Time Objective (RTO)**: < 2 minutes (atomic switch)
**Recovery Point Objective (RPO)**: Last git commit (typically < 1 day)

#### CC8.1 - Change Management

**Git-Based Change Control**:
```bash
# All changes require git commit
git log --all --format="%h %an %ad %s" -- flake.nix deb.nix

# Automated Update Process
./update.sh 25.2.8
git diff deb.nix
# Shows: version change + new SHA256 hash
```

**Change Approval Workflow**:
1. Developer runs `update.sh <version>`
2. Script generates `deb.nix` with SHA256 hash
3. `nix build` verifies build succeeds
4. Git commit creates audit record
5. Code review (optional, recommended)
6. Merge to main branch
7. Deploy via `nixos-rebuild switch`

#### CC9.1 - Risk Assessment - Supply Chain Security

**Multi-Layer Verification**:
1. **Source Verification**: Official Redpanda releases from GitHub
2. **Cryptographic Verification**: SHA256 hash in `deb.nix`/`source/build.nix`
3. **Reproducible Build**: Same inputs → identical output
4. **Immutable Storage**: Package cannot be modified after build

```bash
# Verify supply chain integrity
./update.sh 25.2.8  # Downloads + verifies SHA256
nix build .#redpanda-deb --print-out-paths  # Verifies hash matches
nix-store --verify --check-contents  # Verifies no tampering
```

### Evidence Collection for Auditors

**Change Management Evidence**:
```bash
# Complete audit trail
git log --all --stat --format=fuller

# Export for audit
git log --all --format="%H|%an|%ae|%ad|%s" > change-audit-trail.csv
```

**Access Control Evidence**:
```bash
# User configuration
nix-instantiate --eval --strict '<nixpkgs/nixos>' -A config.users.users.redpanda

# systemd hardening
systemctl show redpanda > redpanda-systemd-config.txt
```

**Security Monitoring Evidence**:
```bash
# Export logs for audit period
journalctl -u redpanda \
  --since "2025-01-01" \
  --until "2025-12-31" \
  -o json > redpanda-audit-logs-2025.json
```

**Build Reproducibility Evidence**:
```bash
# Verify package integrity
nix-store --verify --check-contents > nix-store-integrity-$(date +%Y%m%d).txt

# Build provenance
nix-store -q --tree /nix/store/*-redpanda-* > redpanda-dependencies.txt
```

### Continuous Monitoring

**Daily Integrity Check** (cron):
```bash
#!/bin/bash
# /etc/cron.daily/nix-store-verify
nix-store --verify --check-contents || alert_security_team
```

**Generate Comprehensive Compliance Report**:
```bash
#!/bin/bash
cat > soc2-compliance-report-$(date +%Y%m%d).txt <<EOF
===================================
SOC 2 COMPLIANCE REPORT
Generated: $(date)
===================================

--- CHANGE MANAGEMENT (CC8.1) ---
$(git log --since="6 months ago" --format="%h|%an|%ad|%s" -- flake.nix deb.nix)

--- ACCESS CONTROLS (CC6.1) ---
$(systemctl show redpanda | grep -E "(NoNewPrivileges|ProtectSystem)")

--- SECURITY MONITORING (CC7.1) ---
$(journalctl -u redpanda --since "7 days ago" --priority=err --no-pager | tail -20)

--- BUILD INTEGRITY (CC9.1) ---
$(nix-store --verify --check-contents 2>&1)

--- INCIDENT RESPONSE (CC7.3) ---
$(nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5)
===================================
EOF
```

### Key Differentiators

**vs. Traditional Package Management** (yum/apt):

| Feature | Traditional | NixOS Redpanda | SOC 2 Impact |
|---------|------------|----------------|--------------|
| **Reproducibility** | No | Byte-for-byte | CC7.2 - Anomaly detection |
| **Rollback** | Manual | Atomic (< 1 min) | CC7.3 - Incident response |
| **Audit Trail** | Partial | Complete (git) | CC8.1 - Change management |
| **Immutability** | No | Read-only store | CC6.6 - Prevent modification |
| **Verification** | GPG only | Cryptographic + reproducible | CC9.1 - Supply chain security |

---

## 3. NIST SP 800-161 — Supported Controls

### Status: Strong alignment

**NIST SP 800-161 Rev. 1**: *Cybersecurity Supply Chain Risk Management Practices for Systems and Organizations*

### Framework Overview

NIST SP 800-161 provides guidance on:
- Identifying, assessing, and mitigating supply chain cybersecurity risks
- Integrating C-SCRM (Cybersecurity Supply Chain Risk Management) into enterprise risk management
- Supplier assessment and monitoring
- Software Bill of Materials (SBOM) generation
- Provenance and transparency requirements

### Strong Alignment Areas

| Requirement | Nix Implementation | Evidence |
|-------------|-------------------|----------|
| **Provenance Tracking** | Full source-to-binary provenance via source build (SLSA Build L3). Git tag → Bazel compilation → Nix store. Deb fallback provides publisher attestation only. | `nix-store -q --tree <derivation>` |
| **Reproducible Builds** | Bit-for-bit identical outputs | `nix-build --check` |
| **Cryptographic Verification** | SHA256 hashes in `deb.nix`, `source/build.nix` | Hash verification on every build |
| **Supply Chain Transparency** | All dependencies explicitly declared | `flake.lock` pins exact versions |
| **Immutability** | Read-only package storage | `/nix/store` filesystem |
| **Audit Trail** | Complete change history | Git commit log |
| **Vulnerability Management** | Automated update process | `update.sh` + `nix-channel --update` |
| **Incident Response** | Atomic rollback to known-good state | `nixos-rebuild switch --rollback` |

### Partial Compliance Areas

| Requirement | Current State | Gap | Remediation |
|-------------|--------------|-----|-------------|
| **SBOM Generation** | Tools exist (nix2sbom, bombon) | Not automated in build | Integrate SBOM generation into `update.sh` |
| **Supplier Risk Assessment** | Implicit (nixpkgs community) | No formal process | Document nixpkgs governance model |
| **Third-Party Verification** | Community code review | Not formally documented | Create supplier assessment doc |
| **C-SCRM Plan** | Technical controls exist | No formal C-SCRM document | Write C-SCRM implementation plan |

### SBOM Capabilities

**Available Tools**:

1. **nix2sbom** - Extracts CycloneDX and SPDX SBOMs from Nix derivations
   - Supports CycloneDX 1.4
   - Supports SPDX 2.3 (experimental)
   - JSON and YAML output
   - Handles patches automatically

2. **bombon** - CLI and Nix library for CycloneDX v1.5 SBOMs
   - Compliant with BSI TR-03183 and US EO 14028
   - Handles vendored dependencies (Rust, Go)
   - Automatic SBOM composition

**Implementation Example**:
```bash
# Generate SBOM for Redpanda package
nix build .#redpanda
nix2sbom $(nix build .#redpanda-deb --print-out-paths) --output redpanda-sbom.json --format cyclonedx

# OR using bombon
nix run github:nikstur/bombon -- $(nix build .#redpanda-deb --print-out-paths)
```

**Output**: Complete dependency tree with:
- Component names and versions
- Licenses
- Cryptographic hashes
- Dependency relationships
- Patch information

### NIST 800-161 Control Family Mapping

| Control Family | Package Support | Notes |
|----------------|----------------|-------|
| **SR-1: Policy & Procedures** | Partial | C-SCRM plan documented; formal organizational policy is deployer responsibility |
| **SR-2: Supply Chain Risk Mgmt Plan** | Partial | Technical controls exist; formal plan is deployer responsibility |
| **SR-3: Supply Chain Controls** | Supported | Reproducible builds, cryptographic verification |
| **SR-4: Provenance** | Supported | Complete dependency tracking via Nix store |
| **SR-5: Acquisition Strategies** | Supported | `fetchurl` with SHA256 verification |
| **SR-6: Supplier Assessments** | Partial | Supplier assessment documented; formal audit is deployer responsibility |
| **SR-7: Supplier Reviews** | Partial | GitHub code review; formal review process is deployer responsibility |
| **SR-8: Notification Agreements** | N/A | Organizational policy, not technical |
| **SR-9: Tamper Resistance** | Supported | Immutable `/nix/store`, hash verification |
| **SR-10: Inspection of Systems** | Supported | `nix-store --verify --check-contents` |
| **SR-11: Component Authenticity** | Supported | SHA256 hashes, reproducible builds |
| **SR-12: Component Disposal** | Supported | `nix-collect-garbage`, secure deletion |

SBOM generation, vulnerability scanning, and supply chain event logging are supported via `scripts/update.sh`. C-SCRM plan and supplier assessment are in this directory. See C-SCRM_PLAN.md and SUPPLIER_ASSESSMENT.md.

---

## 4. ISO/IEC 27036 — Supported Controls

### Status: Moderate alignment

**ISO/IEC 27036-2:2022**: *Cybersecurity — Supplier relationships — Part 2: Requirements*

### Framework Overview

ISO/IEC 27036 provides requirements for:
- Managing information security in supplier relationships
- Lifecycle management (per ISO/IEC/IEEE 15288)
- Applicable to all procurement and supply activities
- Both acquirer and supplier responsibilities

### Lifecycle Stages

| Stage | Nix/NixOS Implementation | Status |
|-------|-------------------------|--------|
| **1. Planning** | Declarative configuration in `flake.nix` | Complete |
| **2. Supplier Selection** | nixpkgs community vetting | Informal |
| **3. Agreement** | Licenses declared in derivations | Documented |
| **4. Delivery** | Automated via `nix-build`, SHA256 verified | Secure |
| **5. Operations** | systemd service management | Complete |
| **6. Monitoring** | `nix-store --verify`, journald logs | Complete |
| **7. Change Management** | Git + `nixos-rebuild` | Complete |
| **8. Termination** | `nix-collect-garbage`, clean removal | Complete |

### ISO 27036 Clause Mapping

#### Clause 6: Fundamental Requirements

| Requirement | Implementation | Status | Evidence |
|-------------|----------------|--------|----------|
| **6.1 General** | Nix package management | | Architecture |
| **6.2 Information Security Policy** | Need organizational policy | | Gap |
| **6.3 Supplier Relationships** | nixpkgs community | | Informal |
| **6.4 Asset Management** | `/nix/store` tracking | | `nix-store -q` |
| **6.7 Operations Management** | systemd + Nix | | flake.nix:372-395 |
| **6.8 Communications Security** | HTTPS for downloads | | `fetchurl` |
| **6.9 Access Control** | systemd hardening | | NoNewPrivileges, ProtectSystem |
| **6.10 Cryptography** | SHA256 verification | | deb.nix/source/build.nix hashes |
| **6.11 System Acquisition** | `update.sh` process | | Automated |
| **6.12 Supplier Service Delivery** | Continuous delivery | | `nix-channel --update` |
| **6.13 Security Incident Management** | Atomic rollback | | `nixos-rebuild switch --rollback` |
| **6.14 Business Continuity** | Multiple generations | | Rollback capability |
| **6.15 Compliance** | This document | | Needs formal audit |

#### Clause 7: High-Level Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **7.1 Information Security in Agreements** | Need supplier agreements template | |
| **7.2 Managing Changes** | Git-based change control | |
| **7.3 Supply Chain Transparency** | SBOM generation | |
| **7.4 Termination or Disposal** | `nix-collect-garbage` | |

Supplier agreement template is in SUPPLIER_AGREEMENT_TEMPLATE.md. Supplier assessment is in SUPPLIER_ASSESSMENT.md.

---

## 5. NIST CSF 2.0 — Supported Controls

### Status: Moderate alignment

**Released**: February 26, 2024
**Major Change**: Added 6th core function "GOVERN" (GV)

### Framework Overview

NIST CSF 2.0 expands the previous 5-function model (Identify, Protect, Detect, Respond, Recover) with a new **GOVERN** function emphasizing organizational cybersecurity risk management strategy.

**Key Innovation**: First major framework to explicitly require **supply chain governance**, not just technical controls.

### GV.SC - Cybersecurity Supply Chain Risk Management

The most relevant category for this package is **GV.SC** (10 subcategories):

| Subcategory | Description | Status | Implementation | Gap |
|------------|-------------|--------|----------------|-----|
| **GV.SC-01** | Supply chain risk mgmt process established | Partial | Git-based change tracking | Need formal SCRM policy document |
| **GV.SC-02** | Suppliers and partners identified | Complete | `flake.lock` tracks all dependencies | None |
| **GV.SC-03** | Contracts include security requirements | N/A | No supplier contracts (open source) | Not applicable |
| **GV.SC-04** | Suppliers assessed prior to acquisition | Partial | nixpkgs governance | Need documented supplier assessment |
| **GV.SC-05** | Supply chain events communicated | Gap | No event logging | **Need supply chain event logging** |
| **GV.SC-06** | Security practices integrated | Complete | Reproducible builds, SBOM, provenance | None |
| **GV.SC-07** | Risk response plans established | Gap | No incident response plan | **Need supply chain incident response** |
| **GV.SC-08** | Security practices shared | Complete | Documentation, git history | None |
| **GV.SC-09** | Assurance processes implemented | Complete | `nix-store --verify`, reproducible builds | None |
| **GV.SC-10** | Supply chain risks monitored | Partial | Manual CVE tracking | **Need automated CVE monitoring** |

### Compliance Score Breakdown

**Current Implementation**:
- Fully Supported: 4/10
- Partially Supported: 3/10
- Not Supported: 2/10
- Not Applicable: 1/10

Supply chain event logging is implemented in `compliance/supply-chain-events.jsonl`. Incident response plan is in INCIDENT_RESPONSE_PLAN.md. CVE scanning runs weekly via `.github/workflows/vulnerability-scan.yml`.

---

## 6. DoD SBOM Management (Jan 2024)

### Status: Strong alignment

**Source**: NSA Cybersecurity Information Sheet
**Document**: "Recommendations for Software Bill of Materials (SBOM) Management"
**Version**: 1.1 (January 2024)
**Scope**: National Security Systems (NSS) and DoD contractors

### Requirements Overview

The NSA published updated SBOM management guidance focusing on:
1. **Format Standards**: CycloneDX or SPDX (JSON/XML)
2. **Provenance Tracking**: SLSA attestation or equivalent
3. **Vulnerability Management**: Automated CVE detection and alerting
4. **SBOM Enrichment**: Augment with license, CVE, and dependency data

### Compliance Matrix

| Requirement | Status | Implementation | Gap |
|------------|--------|----------------|-----|
| **SBOM Format Support** | Complete | CycloneDX via sbomnix/bombon | None |
| **SPDX Support** | Complete | sbomnix supports SPDX | None |
| **JSON/XML Output** | Complete | Both formats supported | None |
| **Hash Capture** | Complete | SHA256 for all components in `/nix/store` | None |
| **SBOM Enrichment** | Partial | sbomnix enrichment available | Not automated |
| **SBOM Aggregation** | Gap | Not implemented | **Need aggregation tooling** |
| **Format Conversion** | Complete | sbomnix converts SPDX ↔ CycloneDX | None |
| **Vulnerability Alerting** | Complete | Weekly CVE scanning via GitHub Actions workflow | None |
| **Provenance Tracking** | Complete | SLSA Build L3 (self-assessed) via hermetic Nix sandbox source build. Full source-to-binary provenance chain. See Section 1. | None (source build only; deb is L1) |
| **Repository Integration** | Partial | Git-based tracking | Need SBOM repository |

### Coverage Breakdown

- Fully Supported: 7/10
- Partially Supported: 2/10
- Not Supported: 1/10

**Note**: Provenance Tracking and Vulnerability Alerting were previously gaps. Provenance is now satisfied by the source build's SLSA L3 provenance chain. Vulnerability alerting is satisfied by the weekly CVE scanning workflow (`.github/workflows/vulnerability-scan.yml`).

### U.S. Army SBOM Mandate (Effective Early 2025)

**Memo**: Assistant Secretary of the Army (August 16, 2024)
**Requirement**: All Army software contracts must include SBOMs in SPDX or CycloneDX format

**Relevance**: This package supports Army SBOM requirements with automated SBOM generation.

SLSA provenance, vulnerability scanning, and SBOM generation are implemented in `scripts/update.sh`. Current-version artifacts are published to `compliance/current/`. Weekly CVE scanning runs via `.github/workflows/vulnerability-scan.yml`.

---

## 7. Anduril NixOS STIG (Dec 2024)

### Status: Partial — service-level controls only (full OS STIG requires NixOS baseline)

**Source**: Defense Information Systems Agency (DISA)
**Release**: Version 1, Release 1 (December 4, 2024)
**Scope**: DoD Security Technical Implementation Guide for NixOS
**Based On**: NIST 800-53 Rev. 5 controls

### STIG Overview

**Total Controls**: 104
- **CAT I (High)**: 11 controls
- **CAT II (Medium)**: 92 controls
- **CAT III (Low)**: 1 control

**Categories**:
1. Access Control (AC)
2. Audit and Accountability (AU)
3. Identification and Authentication (IA)
4. System and Communications Protection (SC)
5. Configuration Management (CM)
6. Remote Access (RA)
7. Session Management (SC)

### Applicability to Redpanda Package

**Important Note**: This is an **application service package**, not a full operating system. Many STIG controls apply to OS-level configurations (kernel parameters, bootloader, system accounts) that are **not applicable** to an application package.

**Applicable Control Categories**:
- **AU (Audit)** - Audit logging (systemd journal)
- **SC (Cryptography)** - TLS/encryption
- **AC (Access Control)** - User/group privileges
- **CM (Configuration Management)** - Declarative config
- **IA (Authentication)** - Handled by Redpanda internally
- **OS-level controls** - Handled by NixOS STIG baseline

### Compliance Matrix (Applicable Controls Only)

| STIG Control | Category | Status | Implementation | Gap |
|-------------|----------|--------|----------------|-----|
| **V-268078** | Firewall enabled | Complete | `openFirewall` option | None |
| **V-268117** | Log directory permissions 0750 | Partial | systemd `LogsDirectory` | Need explicit permission setting |
| **AU-*** | Audit record generation | Partial | systemd journal | Need structured audit logging |
| **SC-8** | Transmission confidentiality | Partial | TLS available | **Need `enforceTLS` option** |
| **SC-13** | Cryptographic protection | Complete | TLS, FIPS mode available | None (if FIPS enabled) |
| **AC-3** | Access enforcement | Complete | Least privilege `redpanda` user | None |
| **AC-6** | Least privilege | Complete | systemd hardening | None |
| **CM-6** | Configuration settings | Complete | Declarative NixOS module | None |

### Coverage

**Applicable Controls**: ~40 out of 104 total (application-level only). Remaining controls require OS-level implementation from a NixOS STIG baseline (see github.com/nealfennimore/nixos-stig-anduril).

`enforceTLS` (SC-8) and `auditLog` (AU-3) are implemented in the NixOS module. For full STIG compliance, combine this package with the NixOS STIG baseline (github.com/nealfennimore/nixos-stig-anduril) for OS-level controls.

---

## 8. FedRAMP High — Supported Controls

### Status: Partial (organizational gaps are blocking)

**FedRAMP High Baseline**: Based on NIST SP 800-53 Rev. 5 (392 controls)

Nix-based FIPS deployment avoids some limitations of container-based FIPS:
- Redpanda provides `redpanda-fips` packages with OpenSSL 3.0.9 (FIPS 140-2 validated)
- Nix provides system-level FIPS enforcement rather than container-level
- Full control over the cryptographic stack
- Reproducible builds with cryptographic verification

### How Nix addresses container-based FIPS limitations

#### Redpanda's Documented Limitations (Container-Based)

From [Redpanda FIPS Documentation](https://docs.redpanda.com/current/manage/security/fips-compliance/):

> **Limitations:**
> - Not fully FIPS-compliant in Kubernetes deployments
> - Redpanda Console is not FIPS-compliant
> - PKCS#12 keys are not supported in FIPS mode

**Root Cause**: Container runtime complexities, Kubernetes networking layers (non-FIPS components), pre-built container images with mixed dependencies, no control over base image cryptographic libraries

#### NixOS Solution: System-Level FIPS Enforcement

How Nix addresses these:

1. **Complete Stack Control**
```nix
# Every component is explicitly declared and FIPS-validated
{ config, pkgs, ... }: {
  # Kernel-level FIPS mode
  boot.kernelParams = [ "fips=1" ];

  # All OpenSSL is FIPS-validated
  nixpkgs.overlays = [(self: super: {
    openssl = super.openssl.override { enableFips = true; };
  })];

  # Redpanda with FIPS
  services.redpanda = {
    package = pkgs.callPackage ./fips.nix { };
    settings.redpanda.fips_mode = "enabled";
  };
}
```

2. **No Hidden Dependencies**
   - Containers: Unknown libraries in base images
   - Nix: Every dependency in `/nix/store` with cryptographic hash

3. **Reproducible FIPS Builds**
   - Same `flake.lock` → identical FIPS system on any machine
   - Auditable: `nix-store -q --tree` shows complete dependency graph

Note: This package covers Redpanda only. Redpanda Console is out of scope.

### Comparison: Container vs. NixOS FIPS Deployment

| Feature | Container deployment | Nix deployment |
|---------|---------------------|----------------|
| FIPS compliance | Partial (Kubernetes limitations) | System-wide FIPS |
| Cryptographic stack | Mixed (container layers) | FIPS-validated |
| Reproducibility | Container drift possible | Byte-for-byte identical |
| Auditability | Limited | Full dependency graph |
| Rollback | Manual redeployment | Atomic (<1 min) |

### Critical Control Families (20 families)

| Family | Name | Nix+FIPS Status | Notes |
|--------|------|-----------------|-------|
| **AC** | Access Control | Supported | systemd hardening + FIPS crypto |
| **AU** | Audit and Accountability | Supported | journald logging, git audit trail |
| **AT** | Awareness and Training | Deployer responsibility | Out of scope for package |
| **CM** | Configuration Management | Supported | Declarative config, git-tracked |
| **CP** | Contingency Planning | Supported | Atomic rollback, multiple generations |
| **IA** | Identification/Authentication | Supported | FIPS 140-2 crypto modules |
| **IR** | Incident Response | Partial | Atomic rollback, audit logs |
| **MA** | Maintenance | Partial | Automated updates, needs formal process |
| **MP** | Media Protection | Deployer responsibility | Out of scope |
| **PS** | Personnel Security | Deployer responsibility | Out of scope |
| **PE** | Physical/Environmental | Deployer responsibility | Out of scope |
| **PL** | Planning | Partial | Need formal security plan |
| **PM** | Program Management | Deployer responsibility | Out of scope |
| **RA** | Risk Assessment | Supported | Reproducible builds, SBOM |
| **CA** | Assessment/Authorization | Not started | Need 3PAO audit |
| **SC** | System/Communications | Supported | FIPS 140-2 available via `redpanda-fips` |
| **SI** | System/Information Integrity | Supported | Hash verification, immutability |
| **SA** | System/Services Acquisition | Supported | `update.sh`, SBOM |
| **SR** | Supply Chain Risk Mgmt | Supported | See NIST 800-161 analysis |
| **PT** | PII Processing/Transparency | Deployer responsibility | Out of scope |

### SC-13: Cryptographic protection

The `redpanda-fips` package uses FIPS-validated OpenSSL 3.0.9. The `fips.nix` build patches `openssl.cnf` to reference the correct Nix store path for `fipsmodule.cnf`, verified by the `fips-openssl-path` flake check.

### Remaining gaps

The gap is entirely organizational:

| Gap | Description |
|-----|-------------|
| 3PAO assessment | Independent security assessment ($150-500K, 6-12 months) |
| System Security Plan | 500-1000 page document covering all 392 controls |
| Continuous monitoring | Monthly security deliverables to FedRAMP PMO |

### Nix strengths for FedRAMP

| Control | Nix implementation | Status |
|---------|--------------|-----------------|
| **CM-2: Baseline Configuration** | `flake.nix` is declarative baseline | Meets requirement fully |
| **CM-3: Configuration Change Control** | Git-based approval workflow | Audit trail for all changes |
| **CM-5: Access Restrictions** | `/nix/store` immutability | Prevents unauthorized modification |
| **CM-6: Configuration Settings** | Automated via NixOS modules | Consistent, repeatable config |
| **SI-7: Software Integrity** | SHA256 + reproducible builds | Tamper detection |
| **CP-9: System Backup** | Multiple generations preserved | Meets backup requirement |
| **CP-10: System Recovery** | Atomic rollback (< 1 min) | Exceeds RTO requirements |
| **SC-13: Cryptographic Protection** | **FIPS 140-2 system-wide** | **Fully satisfied** |

FIPS 140-2 is supported and the technical controls are in place. The remaining gap is entirely organizational: 3PAO assessment ($150-500K, 6-12 months), System Security Plan, and continuous monitoring program.

---

## 9. Cross-framework evidence reuse

Each piece of evidence satisfies controls in multiple frameworks. Run `scripts/collect-evidence.sh` to generate a complete evidence package.

| Evidence type | SOC 2 | NIST 800-161 | ISO 27036 | FedRAMP | SLSA |
|--------------|-------|--------------|-----------|---------|------|
| Git audit trail | CC8.1 | SR-3 | Clause 7.2 | CM-3 | -- |
| SHA256 verification | CC9.1 | SR-11 | Clause 6.10 | SI-7 | -- |
| Reproducible builds | CC7.2 | SR-3, SR-9 | Clause 6.13 | SI-7 | Build L3 |
| Immutable store | CC6.6 | SR-9 | Clause 6.7 | CM-5 | -- |
| SBOM | N/A | Required | Clause 7.3 | SA-4 | -- |
| Source build provenance | CC9.1 | SR-4 | Clause 7.3 | SI-7 | Build L3 |
| Hermetic sandbox | N/A | SR-3 | N/A | SI-7 | Build L3 |
| systemd hardening | CC6.1 | SR-3 | Clause 6.9 | AC-6 | -- |
| journald logs | CC7.1 | Monitoring | Clause 6.13 | AU-3 | -- |
| FIPS crypto | N/A | N/A | N/A | SC-13 | -- |

---

## 10. Remaining gaps

| Gap | Frameworks affected | Severity | Notes |
|-----|-------------------|----------|-------|
| 3PAO assessment | FedRAMP High | Blocking | $150-500K, 6-12 months |
| System Security Plan | FedRAMP High | Blocking | 500-1000 pages |
| Continuous monitoring program | FedRAMP High | Blocking | Monthly reporting to FedRAMP PMO |
| Formal supplier agreements | ISO 27036 | Non-blocking | Template available in SUPPLIER_AGREEMENT_TEMPLATE.md |
| Continuous evidence collection | SOC 2 | Non-blocking | Script exists, needs scheduled execution |

FedRAMP High gaps are organizational, not technical. The FIPS package provides the technical foundation; remaining gaps are 3PAO assessment, SSP documentation, and continuous monitoring.

---

## 11. OS independence

Application-level compliance (SOC 2, NIST 800-161, ISO 27036, DoD SBOM, NIST CSF) is OS-independent because Nix builds in an isolated `/nix/store` regardless of the host OS. OS-level compliance (STIG kernel controls, FedRAMP OS-level AC/AU/SC) requires an OS-specific security baseline.

| Layer | Scope | OS-dependent? |
|-------|-------|--------------|
| Application compliance (SOC 2, SBOM, supply chain) | This package | No |
| Runtime security (systemd hardening, TLS, firewall) | This package | Requires systemd |
| OS security (kernel, bootloader, accounts, SELinux) | OS baseline | Yes |

For full STIG/FedRAMP compliance, combine this package with an OS-specific security baseline (e.g., Anduril NixOS STIG).

---

**Last updated**: 2026-04-12
