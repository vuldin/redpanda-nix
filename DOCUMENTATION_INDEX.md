# Documentation Index - Redpanda NixOS Package

## Quick Links

**Start Here**:
- **[README.md](./README.md)** - Project overview and quick start
- **[INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md)** - Multi-platform installation (Ubuntu, RHEL, macOS)

**For Compliance & Security Teams**:
- **[COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md)** - 7-framework compliance analysis
- **[COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md)** - OS-independent vs OS-dependent compliance

**For Developers**:
- **[CLAUDE.md](./CLAUDE.md)** - Development guide and architecture

---

## Complete Documentation Map

### 1. Getting Started

| Document | Purpose | Audience |
|----------|---------|----------|
| **[README.md](./README.md)** | Project overview, features, quick start | Everyone |
| **[INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md)** | Multi-platform installation guide (Ubuntu, RHEL, macOS) | Ops, DevOps |
| **[CLAUDE.md](./CLAUDE.md)** | Developer instructions, architecture, port config | Developers |

### 2. Compliance & Security

| Document | Purpose | Frameworks Covered |
|----------|---------|-------------------|
| **[COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md)** | Comprehensive 7-framework analysis | SOC 2, NIST 800-161, ISO 27036, NIST CSF 2.0, DoD SBOM, STIG, FedRAMP |
| **[COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md)** | OS-independent compliance explained | All frameworks (architectural view) |
| **[COMPLIANCE_COMPARISON.md](./COMPLIANCE_COMPARISON.md)** | Comparison with similar projects | Analysis of Anduril STIG, sbomnix, Redpanda Cloud |
| **[SOC2_COMPLIANCE.md](./SOC2_COMPLIANCE.md)** | Detailed SOC 2 Type II control mapping | SOC 2 Type II |
| **[FBI_CJIS_COMPLIANCE.md](./FBI_CJIS_COMPLIANCE.md)** | FBI Criminal Justice Information Services | CJIS Security Policy v6.0 (Dec 2024) |
| **[COMPLIANCE_SUMMARY.md](./COMPLIANCE_SUMMARY.md)** | Executive summary of all compliance | All frameworks (summary) |

### 3. Enterprise & Adoption

| Document | Purpose | Audience |
|----------|---------|----------|
| **[NIX_ENTERPRISE_ADOPTION_CASE.md](./NIX_ENTERPRISE_ADOPTION_CASE.md)** | Case for Nix in enterprise and DoD | Executives, CISOs, Compliance Officers |
| **[REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)** | FIPS 140-2 implementation guide | Security Engineers, DoD contractors |
| **[NIX_BAZEL_INTEGRATION.md](./NIX_BAZEL_INTEGRATION.md)** | Building from source with Bazel | Developers, FIPS deployments |

### 4. Project Management

| Document | Purpose |
|----------|---------|
| **[UPDATES_SUMMARY.md](./UPDATES_SUMMARY.md)** | Project update log |
| **[IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)** | Future implementation roadmap |

---

## Documentation by Use Case

### "I want to install Redpanda on Ubuntu/RHEL/macOS"
1. Read [INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md)
2. Follow platform-specific section (Ubuntu §2, RHEL §3, macOS §4)
3. Generate compliance artifacts (§7)

### "I need to prove SOC 2 compliance"
1. Read [COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md) - understand what's OS-independent
2. Read [SOC2_COMPLIANCE.md](./SOC2_COMPLIANCE.md) - detailed control mapping
3. Generate SBOM: [INSTALLATION_GUIDE.md §7.1](./INSTALLATION_GUIDE.md#71-generate-sbom-software-bill-of-materials)

### "I need DoD STIG / FedRAMP compliance"
1. Read [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) - see §6 (STIG) and §7 (FedRAMP)
2. Read [COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md) - understand OS-level requirements
3. For FIPS: Read [REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)
4. Apply OS-specific STIG baseline (Ubuntu STIG or RHEL STIG)

### "I'm building a business case for Nix adoption"
1. Read [NIX_ENTERPRISE_ADOPTION_CASE.md](./NIX_ENTERPRISE_ADOPTION_CASE.md) - executive summary
2. Read [COMPLIANCE_COMPARISON.md](./COMPLIANCE_COMPARISON.md) - competitive analysis
3. Present ROI: ~$90K/year savings (from NIX_ENTERPRISE_ADOPTION_CASE.md §10)

### "I want to contribute to this project"
1. Read [CLAUDE.md](./CLAUDE.md) - development guide
2. Read [README.md](./README.md) - contributing section
3. Review [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) - future roadmap

### "I need to meet DoD SBOM Management requirements"
1. Read [COMPLIANCE_MATRIX.md §5](./COMPLIANCE_MATRIX.md) - DoD SBOM requirements
2. Install sbomnix: [INSTALLATION_GUIDE.md §7.2](./INSTALLATION_GUIDE.md#72-generate-slsa-provenance-dod-requirement)
3. Generate SLSA provenance and vulnerability scans

### "I'm deploying Redpanda for FBI/Law Enforcement (CJIS compliance)"
1. Read [FBI_CJIS_COMPLIANCE.md](./FBI_CJIS_COMPLIANCE.md) - CJIS Security Policy v6.0 analysis
2. Review critical gaps (§5): 365-day audit retention, FIPS 140-3, MFA
3. Follow implementation roadmap (§7): Phase 1-3 for 95% compliance
4. Enable FIPS mode: [REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md)
5. Configure MFA (SASL + mTLS) and TLS enforcement

---

## Compliance Framework Coverage

| Framework | Primary Document | Status |
|-----------|-----------------|--------|
| **SOC 2 Type II** | [SOC2_COMPLIANCE.md](./SOC2_COMPLIANCE.md) | ✅ 100% Compliant |
| **NIST SP 800-161** | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) | 🟡 85% Compliant |
| **ISO/IEC 27036** | [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md) | 🟡 80% Compliant |
| **NIST CSF 2.0** | [COMPLIANCE_MATRIX.md §4](./COMPLIANCE_MATRIX.md) | 🟡 60% Compliant |
| **DoD SBOM Management** | [COMPLIANCE_MATRIX.md §5](./COMPLIANCE_MATRIX.md) | 🟡 70% Compliant |
| **Anduril NixOS STIG** | [COMPLIANCE_MATRIX.md §6](./COMPLIANCE_MATRIX.md) | 🟢 40% Service-Level |
| **FedRAMP High** | [REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md) | 🟢 85% with FIPS |
| **FBI CJIS** (NEW Dec 2024) | [FBI_CJIS_COMPLIANCE.md](./FBI_CJIS_COMPLIANCE.md) | 🟡 80% Compliant |

**Legend**:
- ✅ Fully Compliant (100%)
- 🟡 Substantially Compliant (60-90%)
- 🟢 Partially Compliant / Achievable (40-85%)

---

## Document Statistics

**Total Documents**: 15 markdown files

**By Category**:
- Core Documentation: 4 files (README, INSTALLATION, CLAUDE, DOCUMENTATION_INDEX)
- Compliance: 6 files (COMPLIANCE_MATRIX, ARCHITECTURE, COMPARISON, SOC2, FBI_CJIS, SUMMARY)
- Enterprise: 3 files (ENTERPRISE_ADOPTION, FIPS, BAZEL)
- Project Management: 2 files (UPDATES, IMPLEMENTATION_PLAN)

**Total Pages**: ~280 pages of documentation
**Compliance Frameworks**: 8 frameworks analyzed (SOC 2, NIST 800-161, ISO 27036, NIST CSF 2.0, DoD SBOM, STIG, FedRAMP, FBI CJIS)
**Platforms Supported**: Ubuntu, Debian, RHEL, CentOS, Rocky, Alma, macOS, NixOS

---

## Recent Updates (2025-10-10)

### New Documents Created
1. **[INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md)** - Unified multi-platform installation guide
   - Combines Ubuntu, RHEL, and macOS installation
   - Includes systemd and LaunchDaemon setup
   - Compliance artifact generation

2. **[COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md)** - OS-independent compliance explained
   - Layered compliance model
   - OS-independent vs OS-dependent analysis
   - Platform comparison matrix

3. **[COMPLIANCE_COMPARISON.md](./COMPLIANCE_COMPARISON.md)** - Comparison with similar projects
   - Analysis of Anduril STIG, sbomnix, Redpanda Cloud
   - Gap analysis and enhancement roadmap
   - 3-phase implementation plan

### Updated Documents
1. **[COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md)** - Expanded from 4 to 7 frameworks
   - Added NIST CSF 2.0 (Feb 2024)
   - Added DoD SBOM Management (Jan 2024)
   - Added Anduril NixOS STIG (Dec 2024)

2. **[CLAUDE.md](./CLAUDE.md)** - Added new compliance requirements
   - sbomnix tool recommendations
   - SLSA provenance generation
   - Enhanced SBOM section

3. **[NIX_ENTERPRISE_ADOPTION_CASE.md](./NIX_ENTERPRISE_ADOPTION_CASE.md)** - Enhanced with competitive intelligence
   - Added comparison with similar projects
   - Updated ROI calculations (~$90K/year)
   - Added Army SBOM mandate section

4. **[README.md](./README.md)** - Updated prerequisites and compliance section
   - Added macOS to supported platforms
   - Updated to 7 frameworks
   - Enhanced documentation links

---

## Quick Command Reference

### Installation
```bash
# Install Nix (any platform)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes
mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Build Redpanda
nix build
```

### Compliance
```bash
# Generate SBOM (CycloneDX)
nix run github:tiiuae/sbomnix -- $(nix-build) --sbom cyclonedx

# Generate SLSA provenance
nix run github:tiiuae/sbomnix -- $(nix-build) --provenance slsa

# Scan for vulnerabilities
vulnxscan $(nix-build) --sbom sbom.json --output vulns.csv

# Verify integrity
nix-store --verify --check-contents $(nix-build)
```

---

## Support & Resources

- **GitHub Issues**: <repository-url>/issues
- **Documentation**: This repository
- **Nix Documentation**: https://nixos.org/manual/nix/stable/
- **Redpanda Documentation**: https://docs.redpanda.com/
- **Compliance Questions**: See [COMPLIANCE_MATRIX.md](./COMPLIANCE_MATRIX.md)

---

**Last Updated**: 2025-10-10
**Documentation Version**: 3.0
**Maintained By**: Project maintainers
