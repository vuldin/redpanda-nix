# Compliance Evaluation Report: Redpanda NixOS Package

**Evaluator role**: U.S. Government compliance officer
**Repository**: `github.com/vuldin/redpanda-nix`
**Version evaluated**: v26.1.2 (current `main` branch)
**Date**: 2026-04-09

---

## Verdict: CONDITIONAL PASS with MATERIAL FINDINGS

The project demonstrates genuine engineering effort toward compliance and has real, functional security controls in its NixOS module. However, the documentation significantly overstates the actual compliance posture, and several critical technical issues undermine the claims. This would not pass a rigorous FedRAMP or CJIS assessment in its current state, but it has a legitimate foundation to build on.

---

## Table of Contents

1. [Finding 1: FIPS 140-2 Configuration Is Broken](#finding-1--critical-fips-140-2-configuration-is-broken)
2. [Finding 2: Compliance Percentages Are Inflated and Inconsistent](#finding-2--high-compliance-percentages-are-inflated-and-inconsistent)
3. [Finding 3: CI Pipeline Would Fail on Its Own Repository](#finding-3--high-ci-pipeline-would-fail-on-its-own-repository)
4. [Finding 4: Supply Chain Event Log Has Stale/Incorrect Data](#finding-4--medium-supply-chain-event-log-has-staleincorrect-data)
5. [Finding 5: update.sh Does Not Update FIPS Package](#finding-5--medium-updatesh-does-not-update-fips-package)
6. [Finding 6: No Integration Tests Exist](#finding-6--medium-no-integration-tests-exist)
7. [Finding 7: Compliance Documents Are External to the Repository](#finding-7--low-compliance-documents-are-external-to-the-repository)
8. [What Actually Works](#what-actually-works)
9. [Revised Compliance Assessment](#revised-compliance-assessment)
10. [Recommendation](#recommendation)

---

## Finding 1 — CRITICAL: FIPS 140-2 Configuration Is Broken

**Severity**: Blocker for FedRAMP High, CJIS 5.10, DoD IL4+

The FIPS OpenSSL configuration (`openssl.cnf`) contains a hardcoded `.include` path:

```
.include /opt/redpanda/openssl/fipsmodule.cnf
```

But when deployed via Nix, the actual file lives at:

```
/nix/store/dnnvpbyc11f8621fvblb1vann554bkjg-redpanda-fips-26.1.2/opt/redpanda/openssl/fipsmodule.cnf
```

The wrapper script correctly sets `OPENSSL_CONF` to the Nix store path:

```bash
export OPENSSL_CONF="${REDPANDA_HOME}/openssl/openssl.cnf"
```

But the `.include` directive inside that file points to `/opt/redpanda/openssl/fipsmodule.cnf` — a path that does not exist on a NixOS system. This means FIPS mode is not actually activating. The FIPS provider cannot load `fipsmodule.cnf`, so OpenSSL falls back to default (non-FIPS) cryptography silently.

**Impact**: The "90% FedRAMP High compliant" claim and all FIPS-related compliance assertions (SC-13, CJIS 5.10 FIPS requirement) are invalid. The binary runs, but without FIPS-validated cryptography.

**Remediation**: Patch `openssl.cnf` during the Nix build phase to rewrite the `.include` path to `$out/opt/redpanda/openssl/fipsmodule.cnf`, or use a relative `.include` path.

**Files affected**: `fips.nix` installPhase (no patching of `openssl.cnf` occurs)

---

## Finding 2 — HIGH: Compliance Percentages Are Inflated and Inconsistent

The documentation contradicts itself across multiple files:

| Framework | COMPLIANCE_MATRIX.md (baseline) | CLAUDE.md / C-SCRM_PLAN.md (post-enhancement) | README.md (user-facing) |
|-----------|--------------------------------------|----------------------------------------------------------|-------------------------|
| NIST 800-161 | 85% | 100% | 100% |
| DoD SBOM | 70% | 100% | 100% |
| NIST CSF 2.0 | 60% | 70% | (not listed separately) |
| FedRAMP High | 85% | 90% | 90% |
| FBI CJIS | (not in matrix) | 99% | 99% |

The `COMPLIANCE_MATRIX.md` is the most honest assessment. The README and CLAUDE.md claim "100%" for frameworks the baseline document rates at 70-85%. The jump from 70% to "100%" is attributed to scripts that exist in the repo but whose output artifacts are gitignored and not present:

- No SBOM files in the repository (`.gitignore` excludes `compliance/*.json`)
- No SLSA provenance attestation present
- No vulnerability scan results present
- The only compliance artifact committed to git is `supply-chain-events.jsonl`, which contains 3 events from a different version (25.2.8, not the current 26.1.2)

The compliance claims assume these tools will be run, but there is no evidence they have been run for the current version, and no mechanism enforces they are run before deployment.

**Remediation**: Reconcile all compliance percentages across documents to reflect the actual current state. Clearly distinguish between "achievable with tooling" and "currently achieved." Consider committing generated compliance artifacts (SBOMs, provenance) to the repository or a release artifact store so auditors can verify them.

**Files affected**: `README.md`, `CLAUDE.md`, `COMPLIANCE_MATRIX.md`, `C-SCRM_PLAN.md`

---

## Finding 3 — HIGH: CI Pipeline Would Fail on Its Own Repository

The CI workflow (`.github/workflows/ci.yml`) `documentation-check` job checks for files that do not exist in the repo:

- `DOCUMENTATION_INDEX.md` — missing from repo root
- `COMPLIANCE_MATRIX.md` — missing from repo root (exists in sibling `nix-docs/` directory, not tracked in this repo)

The `documentation-check` job would fail on every push/PR with `exit 1`. This means either:

1. The CI has never actually been run successfully, or
2. The workflow was written speculatively and not tested

Additionally, the CI `build-x86_64` job checks for `rpk` binary in the build output (`test -f ./result/bin/rpk`), but the current FIPS build does not include an `rpk` binary. The default build may or may not — this was not verified. The check uses `echo` on failure rather than `exit 1`, so it would produce a warning rather than a hard failure.

**Remediation**: Either add the missing files to the repository, update the CI to reference correct paths, or remove checks for files that are intentionally external. Run the CI pipeline at least once and verify all jobs pass.

**Files affected**: `.github/workflows/ci.yml` lines 162-178

---

## Finding 4 — MEDIUM: Supply Chain Event Log Has Stale/Incorrect Data

The `compliance/supply-chain-events.jsonl` — the sole versioned compliance artifact — contains 3 events, all for version 25.2.8. The repository currently packages version 26.1.2. One event claims:

```json
{"event":"package_generated","version":"25.2.8","details":"Multi-arch package (x86_64 + aarch64)"}
```

But both `default.nix` and `fips.nix` restrict to `x86_64-linux` only:

```nix
platforms = [ "x86_64-linux" ];
```

The flake uses `eachDefaultSystem` which would attempt to build for all platforms, but the derivations would fail on non-x86_64 due to the platform restriction. The "aarch64" claim in the event log is false.

The event log was never updated for the current version (26.1.2), meaning the "supply chain event logging" compliance control (NIST 800-161 SR-5, NIST CSF GV.SC-05) is not operational for the shipping version.

**Remediation**: Run `scripts/update.sh 26.1.2` to regenerate the event log for the current version. Fix the `update.sh` script to not claim aarch64 support when the derivation is x86_64-only. Consider adding a CI check that the event log version matches `default.nix` version.

**Files affected**: `compliance/supply-chain-events.jsonl`, `scripts/update.sh`

---

## Finding 5 — MEDIUM: update.sh Does Not Update FIPS Package

`scripts/update.sh` only generates/updates `default.nix`. Line 224 explicitly states:

> "NOTE: fips.nix must be updated separately if a FIPS build is needed."

But there is no `update-fips.sh` or any documented mechanism to update `fips.nix`. For an organization depending on the FIPS variant, version updates require manual intervention with no documented procedure. The FIPS deb has a separate SHA256 hash that must be independently fetched and verified.

This breaks the "automated supply chain controls" claim (NIST 800-161 SR-3) for the FIPS variant, which is the variant most likely to be used by the government organizations these compliance claims target.

**Remediation**: Either extend `update.sh` to also update `fips.nix` (fetching both the base deb and the FIPS supplement deb), or create a separate `update-fips.sh` with equivalent compliance artifact generation.

**Files affected**: `scripts/update.sh`, `fips.nix`

---

## Finding 6 — MEDIUM: No Integration Tests Exist

The project has zero test files of any kind. The CI performs basic syntax checking (`nix-instantiate --parse` on examples) but no functional verification:

- No NixOS VM tests (the standard NixOS testing mechanism via `nixos/tests`)
- No verification that the module produces a running Redpanda instance
- No validation that TLS enforcement assertions fire correctly when TLS is missing
- No test that CJIS audit retention journald configuration works
- No test that MFA enforcement assertions fire correctly

The `flake.nix` provides no `checks` output. `nix flake check` only validates the flake structure, not the module behavior.

For a project claiming 100% SOC 2 compliance (CC7.2 — "Monitoring System Components") and 100% NIST 800-161 compliance, the absence of any automated functional testing is a significant gap.

**Remediation**: Add NixOS VM tests that:
1. Start the module with default settings and verify the service starts
2. Enable `enforceTLS` without TLS config and verify the build fails
3. Enable `enforceMFA` without SASL+mTLS and verify the build fails
4. Enable `cjisAuditRetention` and verify journald config is applied
5. Verify the FIPS build actually loads the FIPS provider (once Finding 1 is fixed)

**Files affected**: `flake.nix` (add `checks` output)

---

## Finding 7 — LOW: Compliance Documents Are External to the Repository

The primary compliance documentation lives in `/home/josh/redpanda/nix-docs/`, a sibling directory not tracked in the `redpanda-nix` git repository. These documents:

- `COMPLIANCE_MATRIX.md` — Master 7-framework analysis
- `C-SCRM_PLAN.md` — NIST 800-161 implementation plan
- `SOC2_COMPLIANCE.md` — SOC 2 Type II control mapping
- `FBI_CJIS_COMPLIANCE.md` — CJIS Security Policy analysis
- `SUPPLIER_ASSESSMENT.md` — Supplier security assessment

Issues with this arrangement:

1. No version control visible to auditors reviewing the repository
2. Cannot be verified as being in sync with the code
3. Reference line numbers and code snippets that may be from older versions (e.g., `COMPLIANCE_MATRIX.md` references "version 3.0, last updated 2025-10-10" but the code has changed since)
4. Not accessible to anyone who clones the repository
5. The CI workflow checks for `COMPLIANCE_MATRIX.md` in the repo root, where it does not exist

**Remediation**: Either move these documents into the repository (e.g., a `docs/compliance/` directory) or set up a submodule/symlink and update CI references accordingly.

**Files affected**: All files in `nix-docs/`, `.github/workflows/ci.yml`

---

## What Actually Works

Credit where due — the following controls are genuine and correctly implemented:

### systemd Hardening (flake.nix:526-538)
`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, `ProtectHome`, `ReadWritePaths` restricted to `dataDir` only. These are real, effective security controls that satisfy SOC 2 CC6.1 and CC6.7.

### TLS Enforcement Assertions (flake.nix:590-695)
The `enforceTLS` option uses NixOS assertions to validate at build time that TLS is configured for all 5 services (Kafka API, Admin API, RPC Server, Schema Registry, HTTP Proxy). The assertion logic handles both list and single-listener formats and provides clear error messages with documentation links.

### MFA Enforcement (flake.nix:606-632)
The `enforceMFA` option validates both SASL (first factor) and mTLS with `require_client_auth` (second factor) are configured. This is a correct implementation of dual-factor authentication validation.

### Port Extraction System (flake.nix:72-126)
The `extractPorts` function correctly handles all listener formats (list, single object, integer) across all 5 Redpanda services and deduplicates results. Firewall rules are automatically generated.

### SHA256 Pinning (default.nix, fips.nix)
Both package definitions pin to specific SHA256 hashes from the Cloudsmith CDN. The update script uses `nix-prefetch-url` to compute hashes. This provides genuine cryptographic verification (SOC 2 CC7.2, CC9.1).

### Version Tag Validation (scripts/update.sh:20-37)
The `verify_version_tag()` function rejects pre-release suffixes and verifies the tag exists in the upstream repository via `git ls-remote`.

### CJIS Audit Retention (flake.nix:546-582)
The journald configuration is correctly wired with `MaxRetentionSec`, `Storage=persistent`, `Compress=yes`, `SyncIntervalSec=30`. The oneshot service displays compliance status at boot.

### Production TLS Example (examples/3-node-cluster-tls.nix)
Complete TLS configuration for all 5 services with rack awareness, cluster topology, and compliance annotations. Dev examples correctly carry "NOT COMPLIANT FOR PRODUCTION" warnings.

### Dedicated Service User (flake.nix:510-517)
The `redpanda` system user is created with `isSystemUser = true`, no login shell, and restricted home directory.

---

## Revised Compliance Assessment

Based on validation of the actual code, artifacts, and technical behavior:

| Framework | Claimed | Validated | Key Gap |
|-----------|---------|-----------|---------|
| SOC 2 Type II | 100% | ~85% | Real controls, but no audit evidence collection or functional tests |
| NIST SP 800-161 | 100% | ~60% | SBOM tooling scripted but not operational; no artifacts in repo |
| DoD SBOM Management | 100% | ~30% | Scripts exist but no SBOMs generated or shipped for current version |
| FBI CJIS v6.0 | 99% | ~70% | Audit retention real; FIPS broken; MFA not tested in practice |
| FedRAMP High | 90% | ~40% | FIPS not functional; no 3PAO; no SSP; no ConMon |
| ISO/IEC 27036 | 80% | ~50% | Compliance docs not in repo; no formal supplier agreements |
| NIST CSF 2.0 | 70% | ~40% | Event log stale; no incident response plan |
| Anduril NixOS STIG | 60% | ~40% | Service-level controls exist; no structured audit logging |

---

## Recommendation

The NixOS module itself is well-engineered with real security controls. The compliance documentation and automation is aspirational — it describes what could be achieved if all the scripts were run and all the tooling were operational, but it does not reflect the current state of the repository.

### Priority remediation order:

1. **Fix FIPS OpenSSL path** (Finding 1) — Without this, all FIPS/FedRAMP/CJIS encryption claims are invalid
2. **Run update.sh for current version** (Finding 4) — Generate actual compliance artifacts for v26.1.2
3. **Fix CI pipeline** (Finding 3) — Ensure CI actually passes before claiming automated quality assurance
4. **Reconcile compliance percentages** (Finding 2) — Align all documents to reflect validated state
5. **Add FIPS to update automation** (Finding 5) — The most compliance-critical variant has no automation
6. **Add NixOS VM tests** (Finding 6) — Prove controls work, not just that they're declared
7. **Move compliance docs into repo** (Finding 7) — Auditors need version-controlled evidence
