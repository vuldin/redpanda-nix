# Supplier Security Agreement Template

**Version**: 1.0
**Date**: 2026-04-10
**Compliance**: ISO/IEC 27036, NIST SP 800-161 SR-5

---

## Purpose

This template defines the information security requirements for suppliers whose software or services are included in the Redpanda NixOS package supply chain. It is intended to be adapted and used as part of formal supplier relationship management.

---

## 1. Identified Suppliers

| Supplier | Component | Relationship | Risk Level |
|----------|-----------|-------------|------------|
| Redpanda Data, Inc. | Redpanda binary (deb packages) | Primary vendor | High |
| NixOS Foundation | Nix package manager, nixpkgs | Build infrastructure | High |
| Cloudsmith | Package distribution CDN | Distribution | Medium |
| GitHub | Source hosting, CI/CD | Infrastructure | Medium |
| TII (sbomnix) | SBOM generation tooling | Compliance tooling | Low |
| Sigstore | Artifact signing (cosign) | Integrity verification | Low |

---

## 2. Information Security Requirements

### 2.1 Cryptographic Standards

- All software deliverables must support TLS 1.2 or later
- FIPS 140-2 validated cryptographic modules required for FedRAMP/CJIS deployments
- Software signing with verifiable cryptographic signatures

### 2.2 Vulnerability Management

- Supplier must maintain a vulnerability disclosure process
- Critical vulnerabilities must be patched within 30 days of disclosure
- High vulnerabilities must be patched within 90 days of disclosure
- CVE identifiers must be assigned to all publicly known vulnerabilities

### 2.3 Supply Chain Integrity

- Software releases must be associated with verifiable source code (tagged releases)
- Binary packages must be reproducibly buildable from published source where feasible
- Package distribution must use cryptographic checksums (SHA256 minimum)
- Software Bill of Materials (SBOM) must be available in CycloneDX or SPDX format

### 2.4 Access Control

- Multi-factor authentication required for all systems involved in the build and release pipeline
- Principle of least privilege for all CI/CD and build infrastructure access
- Audit logging of all administrative actions on build/release systems

---

## 3. Incident Notification

| Severity | Notification Window | Method |
|----------|-------------------|--------|
| Critical (active exploitation, supply chain compromise) | 24 hours | Direct email + security advisory |
| High (exploitable CVE with public PoC) | 72 hours | Security advisory |
| Medium (CVE without known exploitation) | 30 days | Release notes |

### Required Information in Notifications

- Description of the incident or vulnerability
- Affected versions and components
- Severity assessment (CVSS score if applicable)
- Recommended mitigation or workaround
- Timeline for a fix

---

## 4. Data Handling and Retention

- Supplier must not collect or retain end-user data from the software package
- Build telemetry, if any, must be opt-in and documented
- Audit logs related to the build and release process must be retained for a minimum of 365 days (CJIS 5.4 requirement for CJI environments)

---

## 5. Audit Rights

- The package maintainer reserves the right to:
  - Verify the integrity of supplied software using cryptographic checksums
  - Scan supplied software for vulnerabilities using automated tools
  - Request evidence of the supplier's security practices
  - Verify reproducibility of builds from published source code

- Verification methods currently in use:
  - SHA256 hash verification (`default.nix`, `fips.nix`)
  - SBOM generation and vulnerability scanning (`scripts/update.sh`)
  - Nix store integrity verification (`nix-store --verify`)
  - FIPS module path verification (flake checks)

---

## 6. Termination and Transition

In the event that a supplier relationship is terminated or a component must be replaced:

- All supplier-provided components must be identifiable via the Nix dependency closure
- Alternative components must meet the same security requirements defined in this agreement
- Transition plan must include verification that no security regressions are introduced
- The supply chain event log must document the transition

---

## 7. Agreement Acceptance

This template should be adapted to the specific supplier relationship and signed by both parties. For the Redpanda NixOS package, supplier compliance is primarily verified through technical controls (SHA256 hashes, SBOM scanning, reproducible builds) rather than contractual agreements.

| Field | Value |
|-------|-------|
| **Package Maintainer** | ________________________________ |
| **Supplier Representative** | ________________________________ |
| **Date** | ________________________________ |
| **Review Cycle** | Annual |
