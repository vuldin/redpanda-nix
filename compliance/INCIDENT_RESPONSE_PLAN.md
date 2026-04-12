# Incident Response Plan: Redpanda NixOS Package

**Version**: 1.0
**Date**: 2026-04-10
**Compliance**: NIST CSF 2.0 GV.SC-07, FBI CJIS 5.3, NIST SP 800-161 SR-7

---

## 1. Scope

This plan covers security incidents affecting the Redpanda NixOS package, including:

- **Supply chain compromise**: Upstream package tampering, hash mismatch, unexpected binary changes
- **CVE discovery**: New vulnerabilities in Redpanda or its dependencies
- **Build integrity failure**: Nix store verification failures, reproducibility breaks
- **Configuration exposure**: Accidental exposure of TLS keys, SASL credentials, or other secrets

This plan does **not** cover incidents in deployed Redpanda clusters (those are the deployer's responsibility) or NixOS operating system-level incidents (covered by the NixOS STIG baseline).

---

## 2. Incident Classification

| Severity | Definition | Response Time | Examples |
|----------|-----------|--------------|---------|
| **Critical** | Active exploitation or supply chain compromise | 1 hour | SHA256 mismatch on upstream deb, FIPS module tampered |
| **High** | Exploitable CVE with public PoC | 24 hours | Remote code execution in Redpanda, critical OpenSSL CVE |
| **Medium** | CVE without known exploitation | 72 hours | Denial of service, privilege escalation requiring local access |
| **Low** | Informational or theoretical risk | 1 week | Minor dependency CVE, configuration hardening improvement |

---

## 3. Roles and Responsibilities

| Role | Responsibility |
|------|---------------|
| **Package Maintainer** | Triage, investigate, apply fixes, issue updates |
| **Security Contact** | Coordinate disclosure, notify affected parties |
| **Deployers** | Apply updates, monitor their own clusters |

---

## 4. Detection

Incidents may be detected through:

1. **Automated CVE scanning** (`.github/workflows/vulnerability-scan.yml`) — weekly scan creates GitHub issues for CRITICAL/HIGH CVEs
2. **Build verification failure** — `nix build` fails due to SHA256 hash mismatch (indicates upstream package changed)
3. **Nix store integrity check** — `nix-store --verify --check-contents` detects tampering
4. **Supply chain event log** — anomalies in `compliance/supply-chain-events.jsonl`
5. **External report** — security advisory from Redpanda, NixOS, or a third party
6. **FIPS validation failure** — `openssl.cnf` fails to load FIPS provider

---

## 5. Response Procedures

### 5.1 Supply Chain Compromise

**Detection**: SHA256 hash mismatch during `scripts/update.sh`, unexpected binary content

1. **Contain**: Do NOT merge the update. Halt any automated PR creation.
2. **Verify**: Compare the hash against the official Redpanda release page and Cloudsmith CDN directly.
3. **Investigate**: If the hash genuinely changed, contact Redpanda security (security@redpanda.com) to confirm whether this is expected.
4. **Remediate**: If confirmed compromise, pin to the last known-good version and issue a security advisory.
5. **Log**: Record the event in `compliance/supply-chain-events.jsonl`.

### 5.2 CVE Discovery

**Detection**: Automated vulnerability scan, external advisory

1. **Triage**: Classify severity using the table in Section 2.
2. **Assess**: Determine if the CVE affects the packaged version and whether the NixOS module's hardening mitigates it.
3. **Update**: If a fixed version exists, run `scripts/update.sh <fixed-version>` and create a PR.
4. **Notify**: For CRITICAL/HIGH, create a GitHub issue and notify known deployers.
5. **Verify**: Build and test the updated package. Run `nix flake check`.
6. **Log**: Record in supply chain event log.

### 5.3 Build Integrity Failure

**Detection**: `nix-store --verify` failure, reproducibility check failure

1. **Isolate**: Identify which store paths are affected.
2. **Compare**: Rebuild from the same inputs and compare outputs.
3. **Investigate**: Check if the Nix store was corrupted (disk error) or if inputs changed.
4. **Rebuild**: If corruption, rebuild affected paths. If inputs changed, investigate as a supply chain incident (Section 5.1).
5. **Log**: Record in supply chain event log.

### 5.4 Configuration Exposure

**Detection**: Accidental commit of secrets, log exposure

1. **Revoke**: Immediately rotate any exposed credentials (TLS keys, SASL passwords).
2. **Purge**: Remove secrets from git history using `git filter-branch` or BFG Repo-Cleaner.
3. **Notify**: Inform affected deployers to rotate their credentials.
4. **Prevent**: Verify `.gitignore` excludes sensitive files. Consider adding pre-commit hooks.

---

## 6. Communication

### 6.1 Internal Communication

- All incidents are tracked as GitHub issues with the `security` label
- Supply chain events are logged to `compliance/supply-chain-events.jsonl`

### 6.2 FBI CJIS Notification (CJIS 5.3)

For organizations handling Criminal Justice Information (CJI):

- **72-hour notification**: Security incidents involving CJI must be reported to the FBI CJIS Division within 72 hours
- **Contact**: FBI CJIS Division Information Security Officer (ISO)
- **What to report**: Nature of incident, systems affected, data potentially compromised, remediation steps taken

### 6.3 Public Disclosure

- CRITICAL vulnerabilities: Coordinated disclosure within 90 days
- Supply chain compromises: Immediate public advisory via GitHub Security Advisory

---

## 7. Post-Incident Review

After resolution of any HIGH or CRITICAL incident:

1. **Timeline**: Document the incident timeline (detection to resolution)
2. **Root cause**: Identify the root cause and contributing factors
3. **Effectiveness**: Evaluate how well automated detection worked
4. **Improvements**: Identify changes to prevent recurrence
5. **Update**: Update this plan, detection mechanisms, or hardening as needed
6. **Log**: Final summary in supply chain event log

### Post-Incident Review Template

```
Incident ID: INC-YYYY-NNN
Date Detected: YYYY-MM-DD HH:MM UTC
Date Resolved: YYYY-MM-DD HH:MM UTC
Severity: Critical/High/Medium/Low
Category: Supply Chain / CVE / Build Integrity / Config Exposure

Summary: [One paragraph description]

Timeline:
- [timestamp] Detection
- [timestamp] Triage
- [timestamp] Containment
- [timestamp] Remediation
- [timestamp] Verification
- [timestamp] Closure

Root Cause: [Description]

What Worked:
- [Detection mechanism, response speed, etc.]

What Didn't Work:
- [Gaps, delays, etc.]

Action Items:
- [ ] [Specific improvement]
- [ ] [Specific improvement]
```

---

## 8. Existing Controls

This plan builds on the following automated controls already in the repository:

| Control | Implementation | Compliance |
|---------|---------------|------------|
| SHA256 verification | `deb.nix`, `fips.nix` | NIST 800-161 SR-3 |
| Immutable store | `/nix/store` read-only | NIST 800-161 SR-9 |
| Store integrity verification | `nix-store --verify` | NIST 800-161 SR-10 |
| Version tag validation | `scripts/update.sh` | SOC 2 CC8.1 |
| Supply chain event logging | `compliance/supply-chain-events.jsonl` | NIST 800-161 SR-5 |
| Automated CVE scanning | `.github/workflows/vulnerability-scan.yml` | NIST CSF GV.SC-10 |
| FIPS path verification | `flake.nix` checks | FedRAMP SC-13 |
| TLS enforcement | `enforceTLS` module option | CJIS 5.10, STIG SC-8 |
| Audit evidence collection | `scripts/collect-evidence.sh` | SOC 2 CC7.2 |
