# Redpanda NixOS Configuration Examples

This directory contains example configurations for different deployment scenarios.

## 🔒 Production (Compliance-Ready)

### [3-node-cluster-tls.nix](./3-node-cluster-tls.nix) ✅ RECOMMENDED
**Use this for production deployments**

- ✅ TLS encryption for all services
- ✅ STIG SC-8 compliant (transmission confidentiality)
- ✅ CJIS 5.10 compliant (encryption)
- ✅ FedRAMP High compliant (with FIPS mode)
- ✅ SOC 2 CC6.7 compliant (encryption controls)
- ✅ 365-day audit retention (CJIS 5.4)
- ✅ 3-node cluster with rack awareness
- ✅ Automatic seed server discovery

**Compliance Frameworks Satisfied:**
- DoD STIG (Anduril NixOS STIG)
- FBI CJIS Security Policy v6.0
- FedRAMP High (with FIPS configuration)
- SOC 2 Type II
- NIST SP 800-161 (supply chain security)
- ISO/IEC 27036

---

## 🧪 Development/Testing (Non-Compliant)

### [single-node-dev.nix](./single-node-dev.nix) ⚠️ DEV ONLY
**Simple standalone setup for local development**

- ❌ NO TLS encryption
- ❌ NOT compliant with STIG/CJIS/FedRAMP/SOC 2
- ✅ Good for learning Redpanda
- ✅ Quick local testing

**Use for:**
- Local development on your laptop
- Learning Redpanda basics
- Quick demos

### [3-node-cluster-dev.nix](./3-node-cluster-dev.nix) ⚠️ DEV ONLY
**3-node cluster without TLS**

- ❌ NO TLS encryption
- ❌ NOT compliant with STIG/CJIS/FedRAMP/SOC 2
- ✅ Good for testing cluster features
- ✅ Internal networks with VPN/IPsec

**Use for:**
- Development clusters
- Testing multi-node behavior
- Networks with existing encryption layer

---

## Quick Start

### Production Deployment (TLS)

1. **Generate TLS certificates:**
   ```bash
   sudo mkdir -p /etc/redpanda/certs
   sudo openssl req -x509 -newkey rsa:4096 -nodes \
     -keyout /etc/redpanda/certs/tls.key \
     -out /etc/redpanda/certs/tls.crt \
     -days 365 -subj "/CN=broker1.example.com"
   sudo cp /etc/redpanda/certs/tls.crt /etc/redpanda/certs/ca.crt
   ```

2. **Copy configuration to all nodes:**
   ```bash
   sudo cp examples/3-node-cluster-tls.nix /etc/nixos/redpanda.nix
   ```

3. **Set hostname on each node:**
   ```bash
   # On node 1:
   sudo hostnamectl set-hostname broker1

   # On node 2:
   sudo hostnamectl set-hostname broker2

   # On node 3:
   sudo hostnamectl set-hostname broker3
   ```

4. **Import in configuration.nix:**
   ```nix
   imports = [ ./redpanda.nix ];
   ```

5. **Deploy:**
   ```bash
   sudo nixos-rebuild switch
   ```

### Development (Local Single Node)

```bash
sudo cp examples/single-node-dev.nix /etc/nixos/redpanda.nix
# Add to configuration.nix imports
sudo nixos-rebuild switch
```

---

## Compliance Decision Matrix

| Requirement | single-node-dev | 3-node-cluster-dev | 3-node-cluster-tls |
|------------|----------------|-------------------|-------------------|
| **STIG SC-8** (Transmission Confidentiality) | ❌ | ❌ | ✅ |
| **CJIS 5.10** (Encryption) | ❌ | ❌ | ✅ |
| **FedRAMP High** (Data in Transit) | ❌ | ❌ | ✅ |
| **SOC 2 CC6.7** (Encryption Controls) | ❌ | ❌ | ✅ |
| **CJIS 5.4** (365-day Audit Retention) | ❌ | ❌ | ✅ |
| **DoD SBOM** (Supply Chain) | ✅ | ✅ | ✅ |
| **NIST 800-161** (Provenance) | ✅ | ✅ | ✅ |

**Legend:**
- ✅ = Compliant
- ❌ = Not compliant

---

## Additional Configuration

### Enable FIPS Mode (CJIS Requirement)

For FBI CJIS compliance, enable FIPS 140-3 encryption:

See [REDPANDA_FIPS_NIXOS.md](../REDPANDA_FIPS_NIXOS.md) for complete FIPS configuration.

### Multi-Listener Configuration

All examples support multiple listeners per service:

```nix
kafka_api = [
  { address = "0.0.0.0"; port = 9092; name = "internal"; }
  { address = "0.0.0.0"; port = 9192; name = "external"; }
  { address = "0.0.0.0"; port = 9292; name = "public"; }
];
```

Pattern: 9x92, 8x81, 8x82 (increment first digit)

---

## Questions?

- **General docs**: [../README.md](../README.md)
- **Installation**: [../INSTALLATION_GUIDE.md](../INSTALLATION_GUIDE.md)
- **Compliance**: [../COMPLIANCE_MATRIX.md](../COMPLIANCE_MATRIX.md)
- **FBI CJIS**: [../FBI_CJIS_COMPLIANCE.md](../FBI_CJIS_COMPLIANCE.md)
- **All docs**: [../DOCUMENTATION_INDEX.md](../DOCUMENTATION_INDEX.md)
