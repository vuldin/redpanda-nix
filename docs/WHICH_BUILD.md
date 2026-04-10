# Which Redpanda Build Should I Use?

This project provides three Redpanda packages. Use this guide to choose the right one.

## Quick Decision Tree

```
Do you need FIPS 140-2 compliance?
├─ YES → Are you deploying to production?
│  ├─ YES → Use redpanda-fips (pre-built FIPS packages)
│  └─ NO  → Use redpanda-bazel (build FIPS from source for testing)
│
└─ NO → Are you a Redpanda employee developing features?
   ├─ YES → Use redpanda-bazel (source builds for development)
   └─ NO  → Use redpanda (default - fast pre-built packages)
```

## The Three Packages

### 1. `redpanda` (Default) - **Recommended for 99% of users**

**Use this if:**
- ✅ You're an external user
- ✅ You want fast installation (5-10 min download)
- ✅ You need SOC 2, NIST 800-161, DoD SBOM, CJIS, or STIG compliance
- ✅ You don't need FIPS 140-2

**Installation:**
```bash
nix build
# or
nix build .#redpanda
```

**What you get:**
- Official pre-built binaries from Redpanda
- Standard OpenSSL cryptography
- Full compliance (except FIPS 140-2)
- Best performance

**Compliance satisfied:**
- ✅ SOC 2 Type II
- ✅ NIST SP 800-161 (C-SCRM)
- ✅ DoD SBOM Management
- ✅ FBI CJIS v6.0 (except FIPS crypto)
- ✅ Anduril NixOS STIG
- ✅ ISO/IEC 27036
- ✅ NIST CSF 2.0

---

### 2. `redpanda-fips` - **For FedRAMP High deployments**

**Use this if:**
- ✅ You need FedRAMP High compliance
- ✅ You need FIPS 140-2 validated cryptography
- ✅ You're deploying to DoD IL4/IL5 environments
- ✅ You have regulatory requirements for FIPS

**Installation:**
```bash
nix build .#redpanda-fips
```

**What you get:**
- Official pre-built FIPS binaries from Redpanda
- BoringCrypto (FIPS 140-2 validated)
- All standard features
- 10-30% slower (FIPS validation overhead)

**Additional compliance:**
- ✅ All compliance from `redpanda` package, PLUS:
- ✅ FedRAMP High (FIPS 140-2)
- ✅ DoD IL4/IL5 (FIPS cryptography)
- ✅ NIST SP 800-53 SC-13 (cryptographic protection)
- ✅ FBI CJIS 5.10 (FIPS-validated encryption)

**Configuration:**
```nix
services.redpanda = {
  enable = true;
  settings.redpanda = {
    enable_fips = true;  # Enable FIPS mode
  };
};
```

**Documentation:**
- https://docs.redpanda.com/current/manage/security/fips-compliance/

---

### 3. `redpanda-bazel` - **For Redpanda employees & developers**

**Use this if:**
- ✅ You're a Redpanda employee
- ✅ You're developing Redpanda features
- ✅ You need to apply custom patches
- ✅ You're testing unreleased versions
- ✅ You're in an air-gapped environment
- ✅ You need custom FIPS builds (testing)

**Installation:**
```bash
nix build .#redpanda-bazel
```

**What you get:**
- Built from source using Bazel
- Full control over build flags
- Latest source code
- Development flexibility
- 30-60 min build time (first build)

**When you DON'T need this:**
- ❌ External users (use `redpanda` instead)
- ❌ Production FIPS deployments (use `redpanda-fips` instead)
- ❌ Just want to try Redpanda (use `redpanda` instead)

**Development workflow:**
```bash
# Enter dev shell with Bazel
nix develop

# Build from source
bazel build //src/v/redpanda:redpanda --config=release

# Or use Nix wrapper
nix build .#redpanda-bazel
```

---

## Comparison Matrix

| Feature | `redpanda` | `redpanda-fips` | `redpanda-bazel` |
|---------|------------|-----------------|------------------|
| **Install time** | 5-10 min | 5-10 min | 30-60 min |
| **Source** | Official deb | Official FIPS deb | Git source |
| **Cryptography** | OpenSSL | BoringCrypto | Configurable |
| **Performance** | Fast | 10-30% slower | Fast |
| **FIPS 140-2** | ❌ | ✅ | ⚠️ Custom |
| **SOC 2 / NIST 800-161** | ✅ | ✅ | ✅ |
| **FedRAMP High** | ❌ | ✅ | ⚠️ Custom |
| **Development** | ❌ | ❌ | ✅ |
| **Custom patches** | ❌ | ❌ | ✅ |
| **Recommended for** | External users | FedRAMP/DoD | Redpanda devs |

---

## Common Questions

### Q: Why not just use FIPS for everything?

**A:** FIPS validation adds 10-30% performance overhead. Only 1-2% of deployments need FIPS 140-2, so most users shouldn't pay the penalty.

### Q: Is `redpanda` less secure than `redpanda-fips`?

**A:** No. Both use strong cryptography. FIPS is about **validation and certification**, not additional security. Standard OpenSSL is secure and faster.

### Q: Can I switch between packages later?

**A:** Yes. All packages install the same binaries to the same paths. Data directories are compatible.

### Q: Which package for SOC 2 compliance?

**A:** Use `redpanda` (default). SOC 2 does not require FIPS 140-2.

### Q: Which package for HIPAA compliance?

**A:** Use `redpanda` (default). HIPAA does not require FIPS 140-2.

### Q: Which package for ISO 27001?

**A:** Use `redpanda` (default). ISO 27001 does not require FIPS 140-2.

### Q: Which package for PCI DSS?

**A:** Use `redpanda` (default). PCI DSS requires strong encryption but not FIPS 140-2.

### Q: When do I actually need FIPS?

**A:** Only when:
- Deploying to FedRAMP High environments
- Deploying to DoD IL4+ (classified networks)
- Contractually required (some government contracts)
- State/local government mandates (rare)

---

## Still Not Sure?

**Default answer: Use `redpanda`** (the default package)

If you're unsure, start with the default `redpanda` package. It covers 99% of compliance requirements and is the fastest option.

You can always switch to `redpanda-fips` later if you discover you need FIPS 140-2.

**Contact:**
- Redpanda Support: support@redpanda.com
- Documentation: https://docs.redpanda.com/
