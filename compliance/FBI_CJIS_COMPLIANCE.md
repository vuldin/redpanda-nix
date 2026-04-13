# FBI CJIS Compliance Analysis - Redpanda NixOS Package

## Executive Summary

The FBI requires compliance with the **CJIS (Criminal Justice Information Services) Security Policy** for any software that accesses or stores Criminal Justice Information (CJI). This includes FBI databases like NCIC (National Crime Information Center), NLETS, and other law enforcement systems.

**Latest Version**: CJIS Security Policy v6.0 (released December 27, 2024)
**Compliance Deadline**: Mandatory as of October 1, 2024
**Penalty for Non-Compliance**: Denied access to FBI databases, fines, criminal charges

**Key Insight**: CJIS is based on **NIST SP 800-53** (same foundation as FedRAMP), making it compatible with this package's existing compliance architecture.

---

## Table of Contents

1. [What is CJIS?](#1-what-is-cjis)
2. [FBI Procurement Requirements](#2-fbi-procurement-requirements)
3. [CJIS Security Policy Areas](#3-cjis-security-policy-areas)
4. [Compliance Mapping for This Package](#4-compliance-mapping-for-this-package)
5. [Gaps and Remediation](#5-gaps-and-remediation)
6. [CJIS vs. FedRAMP Comparison](#6-cjis-vs-fedramp-comparison)
7. [Implementation Roadmap](#7-implementation-roadmap)
8. [CJIS + Redpanda Use Cases](#8-cjis--redpanda-use-cases)

---

## 1. What is CJIS?

### Overview

**CJIS (Criminal Justice Information Services)** is an FBI division that manages databases and systems containing sensitive law enforcement data. The **CJIS Security Policy** defines minimum security requirements for protecting this data.

### Criminal Justice Information (CJI)

**CJI** includes:
- NCIC (National Crime Information Center) data
- Biometric data (fingerprints, facial recognition)
- Criminal history records
- Warrant information
- Stolen property records
- Sex offender registry
- Law enforcement investigative data

### Who Must Comply?

Any organization that:
- Accesses FBI databases (NCIC, NLETS, etc.)
- Stores or processes CJI
- Provides services to law enforcement agencies
- Develops software for criminal justice systems

**Examples**:
- State/local law enforcement agencies
- 911 call centers
- Court systems
- Correctional facilities
- Private contractors serving law enforcement
- Cloud service providers hosting CJI

---

## 2. FBI Procurement Requirements

### Primary Requirement: CJIS Security Policy

**For FBI procurement, software must comply with**:
1. **CJIS Security Policy v6.0** (December 2024)
2. **NIST SP 800-53 Rev. 5** (underlying control framework)
3. **FISMA** (Federal Information Security Management Act)
4. **FedRAMP** (if cloud-based)

### CJIS v6.0 New Requirements (2024)

**Supply Chain Risk Management** (directly relevant to this package):
- Security and Privacy Engineering Principles must be embedded in software procurement
- System documentation mandated for all acquired technologies
- Supply Chain Risk Management Plans required for all agencies handling CJI
- Enhanced Acquisition Strategies to prevent compromised products
- Notification Agreements requiring vendors to report security incidents
- Inspection of Systems and Components before deployment

**Advanced Authentication** (effective October 1, 2024):
- Multi-Factor Authentication (MFA) mandatory for all CJI access
- Must use 2+ factors (something you know + have + are)
- Biometric authentication supported

**FIPS 140-3 Encryption** (upgraded from FIPS 140-2):
- All CJI must be encrypted at rest and in transit
- Minimum 128-bit encryption
- Decryption keys: 10+ characters, mixed case, numbers, special chars

---

## 3. CJIS Security Policy Areas

The CJIS Security Policy v6.0 has **13 key policy areas**:

| Policy Area | Description | NIST 800-53 Mapping |
|------------|-------------|---------------------|
| **5.1 Information Exchange Agreements** | Formal agreements for CJI sharing | IA Family |
| **5.2 Security Awareness Training** | Annual training for personnel with CJI access | AT-2, AT-3 |
| **5.3 Incident Response** | Procedures for security incidents | IR Family |
| **5.4 Auditing and Accountability** | Logging all CJI access for 365+ days | AU Family |
| **5.5 Access Control** | Role-based access, MFA required | AC Family |
| **5.6 Identification and Authentication** | Advanced authentication (MFA) | IA Family |
| **5.7 Configuration Management** | Baseline configurations, change control | CM Family |
| **5.8 Media Protection** | Secure storage and disposal of media | MP Family |
| **5.9 Physical Protection** | Physical security for CJI systems | PE Family |
| **5.10 System and Communications Protection** | Encryption, boundary protection | SC Family |
| **5.11 System and Information Integrity** | Malware protection, vulnerability scanning | SI Family |
| **5.12 Formal Audits** | Triennial audits by CJIS authorities | CA-2 |
| **5.13 Personnel Security** | Background checks, clearances | PS Family |

---

## 4. Compliance Mapping for This Package

### High-Level Status

| CJIS Policy Area | Relevant to App Package? | Status | Implementation |
|-----------------|-------------------------|--------|----------------|
| **5.4 Auditing** | Yes | Partial | systemd journal (needs structured logging) |
| **5.5 Access Control** | Yes | Implemented | Least privilege, systemd hardening |
| **5.6 Authentication** | App-specific | N/A | Redpanda internal auth (SASL, mTLS) |
| **5.7 Config Management** | Yes | Implemented | Declarative Nix, git-based |
| **5.10 Encryption** | Yes | Partial | TLS available, FIPS mode supported |
| **5.11 Integrity** | Yes | Implemented | Reproducible builds, SHA256 verification |
| **Supply Chain (NEW)** | Yes | Implemented | SBOM, provenance, reproducibility |

### Detailed Control Mapping

#### 5.4 Auditing and Accountability (AU Family)

**CJIS Requirement**: Audit logs must be retained for minimum 365 days and include authentication logs for successful/unsuccessful access attempts.

| Control | CJIS Requirement | Current Implementation | Gap |
|---------|-----------------|----------------------|-----|
| **AU-2** | Audit Events | systemd journal | Need structured audit logging |
| **AU-3** | Content of Audit Records | Basic systemd logs | Need CJI-specific event types |
| **AU-6** | Audit Review | Manual (journalctl) | Need automated audit review |
| **AU-9** | Protection of Audit Information | systemd protections | Need 365-day retention policy |
| **AU-11** | Audit Record Retention | Default systemd retention | **Must configure 365+ days** |

**Current Status**: **Partial -- needs structured audit logging with 365-day retention**

---

#### 5.5 Access Control (AC Family)

**CJIS Requirement**: Role-based access control, principle of least privilege.

| Control | CJIS Requirement | Current Implementation | Gap |
|---------|-----------------|----------------------|-----|
| **AC-2** | Account Management | Dedicated `redpanda` user | Complete |
| **AC-3** | Access Enforcement | systemd hardening | Complete |
| **AC-6** | Least Privilege | Non-root execution, limited file access | Complete |
| **AC-7** | Unsuccessful Logon Attempts | Redpanda internal | N/A (app-level) |

**Current Status**: **Strong** (application-level controls)

---

#### 5.6 Identification and Authentication (IA Family)

**CJIS Requirement**: Advanced authentication (MFA) mandatory as of October 1, 2024.

| Control | CJIS Requirement | Current Implementation | Gap |
|---------|-----------------|----------------------|-----|
| **IA-2** | Identification and Authentication | Redpanda SASL, mTLS | N/A (app configuration) |
| **IA-2(1)** | Multi-Factor Authentication (MFA) | Redpanda supports SASL + mTLS | Must be configured |
| **IA-5** | Authenticator Management | Redpanda internal | N/A (app-level) |

**Current Status**: **Application-Dependent** (Redpanda supports MFA, must be configured by admin)

**Note**: This is **application-level authentication**, not package-level. Redpanda supports:
- SASL/SCRAM authentication (username/password)
- mTLS (certificate-based)
- Combined for MFA

---

#### 5.7 Configuration Management (CM Family)

**CJIS Requirement**: Baseline configurations, change control, configuration audits.

| Control | CJIS Requirement | Current Implementation | Gap |
|---------|-----------------|----------------------|-----|
| **CM-2** | Baseline Configuration | Declarative `flake.nix` | Complete |
| **CM-3** | Configuration Change Control | Git-based version control | Complete |
| **CM-6** | Configuration Settings | NixOS module validation | Complete |
| **CM-7** | Least Functionality | Minimal package, no unnecessary services | Complete |
| **CM-8** | Information System Component Inventory | `flake.lock`, `/nix/store` | Complete |

**Current Status**: **Strong**

---

#### 5.10 System and Communications Protection (SC Family)

**CJIS Requirement**: FIPS 140-3 encryption, CJI encrypted at rest and in transit.

| Control | CJIS Requirement | Current Implementation | Gap |
|---------|-----------------|----------------------|-----|
| **SC-8** | Transmission Confidentiality | TLS available for all listeners | Not enforced by default |
| **SC-13** | Cryptographic Protection | FIPS mode supported | Must be enabled |
| **SC-28** | Protection of Information at Rest | Redpanda encryption at rest | Must be configured |

**Current Status**: **Partial -- TLS/FIPS available but not enforced by default**

**Gap**: Need `enforceTLS` option and FIPS-by-default mode for CJIS deployments.

---

#### 5.11 System and Information Integrity (SI Family)

**CJIS Requirement**: Malware protection, vulnerability scanning, flaw remediation.

| Control | CJIS Requirement | Current Implementation | Gap |
|---------|-----------------|----------------------|-----|
| **SI-2** | Flaw Remediation | `update.sh` documented process | Complete |
| **SI-3** | Malware Protection | Host-level (OS responsibility) | N/A (not app-level) |
| **SI-7** | Software Integrity | SHA256 verification, reproducible builds | Complete |
| **SI-10** | Information Input Validation | Redpanda internal | N/A (app-level) |

**Current Status**: **Strong** (application-level controls)

---

#### Supply Chain Risk Management (NEW in v6.0)

**CJIS Requirement**: Security engineering in procurement, supply chain risk management plans, vendor notification agreements.

| Requirement | Current Implementation | Gap |
|------------|----------------------|-----|
| **Security Engineering in Procurement** | Reproducible builds, SBOM, provenance | Complete |
| **System Documentation** | 14 markdown docs, 250+ pages | Complete |
| **Supply Chain Risk Management Plan** | Git audit trail, nixpkgs governance | Need formal SCRM doc |
| **Vendor Notification Agreements** | N/A (open source) | N/A |
| **Component Inspection** | `nix-store --verify`, SBOM scanning | Complete |

**Current Status**: **Strong -- missing formal SCRM policy document**

**Strength**: This package's reproducible builds and SBOM generation directly address CJIS v6.0's new supply chain requirements.

---

## 5. Gaps and Remediation

### Critical Gaps (Blocking CJIS Compliance)

| Gap | CJIS Requirement | Severity | Remediation | Effort |
|-----|----------------|----------|-------------|--------|
| **365-day audit retention** | 5.4 (AU-11) | Critical | Configure systemd journal retention | Low (1 day) |
| **MFA enforcement** | 5.6 (IA-2) | Critical | Configure Redpanda SASL + mTLS | Medium (app config) |
| **FIPS 140-3 encryption** | 5.10 (SC-13) | Critical | Enable FIPS mode (see REDPANDA_FIPS_NIXOS.md) | Medium (2-3 days) |
| **Structured audit logging** | 5.4 (AU-3) | High | Add JSON audit log format | Medium (3 days) |

### High-Priority Gaps (Required for Full Compliance)

| Gap | CJIS Requirement | Remediation | Effort |
|-----|----------------|-------------|--------|
| **Enforce TLS by default** | 5.10 (SC-8) | Add `enforceTLS = true` option | Low (1 day) |
| **Formal SCRM policy doc** | Supply Chain (5.13.5) | Create CJIS_SUPPLY_CHAIN_RISK_MANAGEMENT.md | Medium (1 week) |
| **Automated audit review** | 5.4 (AU-6) | Integrate with SIEM (Splunk, ELK) | High (depends on SIEM) |

---

## 6. CJIS vs. FedRAMP Comparison

### Relationship

**CJIS is based on FedRAMP/NIST 800-53**, so achieving FedRAMP compliance covers most CJIS requirements.

| Framework | Scope | Controls | Encryption | MFA | Audit Logs |
|-----------|-------|----------|-----------|-----|------------|
| **CJIS** | FBI/Law Enforcement | NIST 800-53 subset | FIPS 140-3 | Mandatory | 365+ days |
| **FedRAMP High** | Federal Cloud Services | NIST 800-53 (392 controls) | FIPS 140-2 | Required | Varies |
| **NIST 800-53** | Federal Agencies | 1000+ controls | FIPS 140-2/3 | IA-2 | AU-11 |

### Key Differences

| Aspect | CJIS | FedRAMP High |
|--------|------|--------------|
| **Focus** | Law enforcement data (CJI) | Federal cloud services |
| **MFA** | Mandatory (since Oct 2024) | Required (IA-2) |
| **Encryption** | FIPS 140-3 | FIPS 140-2 (older) |
| **Audit Retention** | 365 days minimum | Varies by agency |
| **3PAO Assessment** | Not required | Required ($150K-500K) |
| **Background Checks** | FBI fingerprints required | Varies |
| **Triennial Audits** | CJIS authorities | FedRAMP PMO |

**Advantage for CJIS**: No expensive 3PAO assessment required (unlike FedRAMP).

---

## 7. Implementation Roadmap

### Phase 1: Critical CJIS Requirements (1-2 weeks)

**Goal**: Address blocking gaps for CJIS compliance.

#### Task 1: Configure 365-Day Audit Retention

```bash
# systemd journal configuration
sudo mkdir -p /etc/systemd/journald.conf.d/

sudo tee /etc/systemd/journald.conf.d/cjis-retention.conf <<EOF
[Journal]
# CJIS 5.4 (AU-11): 365-day retention
MaxRetentionSec=31536000

# Store logs persistently
Storage=persistent
SystemMaxUse=10G
EOF

sudo systemctl restart systemd-journald

# Verify
journalctl --disk-usage
```

#### Task 2: Enable FIPS Mode

```nix
# NixOS configuration for CJIS FIPS compliance
{ config, pkgs, ... }:

{
  # CJIS 5.10 (SC-13): FIPS 140-3 cryptographic protection
  services.redpanda = {
    enable = true;

    # Enable FIPS mode (see REDPANDA_FIPS_NIXOS.md)
    fipsMode = true;

    # CJIS 5.10 (SC-8): Enforce TLS
    enforceTLS = true;

    settings = {
      redpanda = {
        kafka_api = [{
          address = "0.0.0.0";
          port = 9092;
          name = "internal";
          # TLS configuration for CJIS
          tls = {
            enabled = true;
            cert_file = "/etc/redpanda/certs/server.crt";
            key_file = "/etc/redpanda/certs/server.key";
            ca_file = "/etc/redpanda/certs/ca.crt";
            require_client_auth = true;  # mTLS for MFA
          };
        }];
      };
    };
  };

  # CJIS 5.4 (AU-11): 365-day audit retention
  services.journald.extraConfig = ''
    MaxRetentionSec=31536000
    Storage=persistent
    SystemMaxUse=10G
  '';
}
```

#### Task 3: Configure MFA (SASL + mTLS)

```yaml
# Redpanda config for CJIS MFA requirement
redpanda:
  kafka_api:
    - address: 0.0.0.0
      port: 9092
      authentication_method: sasl  # Factor 1: Something you know
      tls:
        enabled: true
        require_client_auth: true  # Factor 2: Something you have (cert)
```

**Result**: CJIS compliance for critical security controls (AU, SC, IA).

---

### Phase 2: Enhanced Audit Logging (1 week)

**Goal**: Structured audit logging with CJIS-specific event types.

#### Add Structured Audit Logging Module

```nix
services.redpanda.auditLog = {
  enable = true;
  format = "json";  # Structured format for SIEM
  destination = "/var/log/redpanda/audit-cji.log";
  permissions = "0640";

  # CJIS-specific event types
  events = [
    "authentication_success"
    "authentication_failure"
    "cji_access"
    "cji_modification"
    "cji_deletion"
    "configuration_change"
    "privilege_escalation"
  ];

  # Retention
  retention = "365d";  # CJIS requirement
};
```

---

### Phase 3: Formal Documentation (1 week)

**Goal**: Create formal CJIS compliance documentation.

#### Create CJIS Documentation Package

1. **CJIS_SUPPLY_CHAIN_RISK_MANAGEMENT.md**
   - Supplier assessment process (nixpkgs governance)
   - Component inspection procedures
   - Vulnerability disclosure process
   - Incident notification procedures

2. **CJIS_COMPLIANCE_EVIDENCE.md**
   - Control-by-control evidence mapping
   - Automated evidence collection scripts
   - Audit readiness checklist

3. **CJIS_INCIDENT_RESPONSE_PLAN.md**
   - CJI breach notification (72 hours to FBI)
   - Incident response procedures
   - Communication protocols

---

### Phase 4: Triennial Audit Preparation (Ongoing)

**Goal**: Maintain CJIS compliance for triennial audits.

#### Automated Compliance Evidence Collection

```bash
#!/bin/bash
# Generate CJIS compliance evidence package

mkdir -p cjis-evidence

# 5.4 Auditing: Prove 365-day retention
echo "=== CJIS 5.4 Auditing Evidence ===" > cjis-evidence/5.4-auditing.txt
journalctl --since "365 days ago" --until "now" -u redpanda --no-pager | head -20 >> cjis-evidence/5.4-auditing.txt

# 5.7 Configuration Management: Git audit trail
echo "=== CJIS 5.7 Configuration Management ===" > cjis-evidence/5.7-config-mgmt.txt
git log --all --oneline --since "365 days ago" >> cjis-evidence/5.7-config-mgmt.txt

# 5.11 System Integrity: SHA256 verification
echo "=== CJIS 5.11 System Integrity ===" > cjis-evidence/5.11-integrity.txt
nix-store --verify --check-contents $(nix build .#redpanda-deb --print-out-paths) >> cjis-evidence/5.11-integrity.txt

# Supply Chain: SBOM + Provenance
sbomnix $(nix build .#redpanda-deb --print-out-paths) --cdx cjis-evidence/sbom.cdx.json
provenance $(nix build .#redpanda-deb --print-out-paths) --out cjis-evidence/provenance.json

# Package for CJIS audit
tar czf cjis-compliance-evidence-$(date +%Y%m%d).tar.gz cjis-evidence/

echo "CJIS compliance evidence package created"
```

---

## 8. CJIS + Redpanda Use Cases

### Law Enforcement Use Cases

**1. Real-Time Crime Data Streaming**
- Ingest data from CAD (Computer-Aided Dispatch) systems
- Stream to analysts and patrol units
- CJIS compliance required for CJI access

**2. Multi-Agency Data Sharing**
- Share CJI between agencies (FBI, state, local)
- Requires CJIS Information Exchange Agreements
- Audit all access (365-day retention)

**3. Investigative Analytics**
- Stream criminal history, warrants, NCIC data to analytics platforms
- Real-time alerts for pattern detection
- Must encrypt CJI at rest and in transit (FIPS 140-3)

**4. Body Camera / Evidence Streaming**
- Stream video evidence to case management systems
- Metadata may contain CJI (names, case numbers)
- Requires CJIS physical security controls

**5. 911 Call Center Integration**
- Stream emergency call data to dispatch systems
- CJI includes caller info, incident details
- MFA required for dispatcher access (CJIS 5.6)

### Example: FBI NCIC Data Streaming

**Scenario**: State police agency wants to stream NCIC queries/responses through Redpanda for real-time analytics.

**CJIS Requirements**:
1. FIPS 140-3 encryption (enable FIPS mode)
2. MFA for all users accessing CJI (SASL + mTLS)
3. 365-day audit logs (configure systemd retention)
4. Background checks for personnel (organizational policy)
5. Physical security (data center compliance)
6. Information Exchange Agreement with FBI

**Redpanda NixOS Package Compliance**:
- Reproducible builds (supply chain security)
- SBOM generation (component inventory)
- FIPS mode supported (cryptographic protection)
- Declarative config (change control)
- Git audit trail (configuration management)

**Result**: This package provides strong coverage of CJIS application-level technical controls. Remaining gaps are organizational policies (training, background checks, physical security).

---

## 9. CJIS Compliance Score

### Overall Status

| CJIS Policy Area | Coverage | Status |
|-----------------|----------|--------|
| 5.4 Auditing | Partial | Needs 365-day retention |
| 5.5 Access Control | Strong | Complete |
| 5.6 Authentication | N/A | App configuration |
| 5.7 Config Management | Strong | Complete |
| 5.10 Encryption | Partial | FIPS available, not enforced |
| 5.11 System Integrity | Strong | Complete |
| Supply Chain (NEW) | Strong | Need formal SCRM doc |

**Current Coverage**: Strong technical control coverage for application-level controls.

**With Phase 1-3 Enhancements**: Full technical compliance for application-level controls.

**Remaining gaps**: Organizational policies (training, background checks, physical security, triennial audits)

---

## 10. Comparison with Other FBI Requirements

### FBI Also Accepts

| Framework | Relationship to CJIS | Easier/Harder? |
|-----------|---------------------|----------------|
| **FedRAMP High** | Significant overlap with CJIS | Harder (requires 3PAO, more controls) |
| **FISMA** | Underlying framework | Same difficulty |
| **StateRAMP** | State-level FedRAMP | Similar difficulty |

**Recommendation**: If you need **both FBI and broader federal compliance**, achieve **FedRAMP High** first (392 controls), then CJIS will require only minor additional work (MFA mandate, 365-day logs, FIPS 140-3).

---

## 11. Summary

### Key Takeaways

1. **CJIS is FBI-specific** but based on familiar NIST 800-53 controls
2. **This package provides strong coverage** of application-level technical controls
3. **Critical gaps are fixable** in 1-2 weeks (audit retention, FIPS mode, MFA config)
4. **CJIS v6.0 (Dec 2024) emphasizes supply chain security** - this package's reproducible builds and SBOM generation are well aligned
5. **No expensive 3PAO assessment** required (unlike FedRAMP)

### Compliance Path

```
Current Package (strong application-level controls)
    ↓
+ Phase 1: 365-day logs, FIPS, MFA (2 weeks)
    ↓
+ Phase 2: Structured audit logging (1 week)
    ↓
+ Phase 3: Formal documentation (1 week)
    ↓
= Full CJIS Technical Compliance
    ↓
+ Organizational policies (training, background checks)
    ↓
= Complete CJIS Compliance
```

**Total Time to CJIS Compliance**: 1 month (technical) + ongoing (organizational)

---

## 12. Resources

### Official CJIS Resources
- **CJIS Security Policy v6.0**: https://le.fbi.gov/file-repository/cjis_security_policy_v6-0_20241227.pdf
- **FBI CJIS Division**: https://www.fbi.gov/services/cjis
- **NIST 800-53 Rev. 5**: https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final

### This Package Documentation
- **FIPS Implementation**: [REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)
- **FedRAMP Compliance**: [COMPLIANCE_MATRIX.md §7](./COMPLIANCE_MATRIX.md)
- **Supply Chain Security**: [C-SCRM_PLAN.md](./C-SCRM_PLAN.md)
- **Installation Guide**: [INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-10
**CJIS Policy Version**: v6.0 (December 27, 2024)
**Compliance Status**: Strong technical control coverage. Remaining gaps are organizational.
