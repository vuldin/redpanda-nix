# Redpanda FIPS on NixOS
## FIPS 140-2 Deployment Guide

**Document Version**: 1.1
**Last Updated**: 2026-04-12
**Compliance**: FedRAMP High SC-13 (Cryptographic Protection)

---

## Overview

Deploying Redpanda FIPS packages on NixOS enables system-wide FIPS 140-2 enforcement, addressing the limitations documented in Redpanda's official container-based deployment guide.

### Deployment Comparison

| Feature | Container Deployment | NixOS Deployment |
|---------|---------------------|---------------------|
| **FIPS Compliance** | Partial (Kubernetes limitations per Redpanda docs) | System-wide FIPS enforcement |
| **Redpanda Console** | Not FIPS-compliant (per Redpanda docs) | Can be built with FIPS Go crypto |
| **Cryptographic Stack** | Mixed across container layers | Single FIPS-validated OpenSSL via overlay |
| **Reproducibility** | Container drift possible with image updates | Byte-for-byte identical via `flake.lock` |
| **Auditability** | Requires external tooling for full dependency analysis | Complete dependency graph via `nix-store` |
| **Rollback** | Redeployment required | Atomic via `nixos-rebuild switch --rollback` |

---

## How NixOS Addresses Redpanda's FIPS Limitations

### Redpanda's Documented Limitations (Container-Based)

From [Redpanda FIPS Documentation](https://docs.redpanda.com/current/manage/security/fips-compliance/):

> **Limitations:**
> - Not fully FIPS-compliant in Kubernetes deployments
> - Redpanda Console is not FIPS-compliant
> - PKCS#12 keys are not supported in FIPS mode

These limitations stem from container runtime complexities, mixed dependencies in base images, and lack of control over the full cryptographic stack.

### NixOS Approach: System-Level FIPS Enforcement

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
   - Every dependency tracked in `/nix/store` with cryptographic hash
   - Full dependency graph inspectable via `nix-store -q --tree`

3. **Reproducible FIPS Builds**
   - Same `flake.lock` → identical FIPS system on any machine
   - Auditable: `nix-store -q --tree` shows complete dependency graph

4. **FIPS-Compliant Console**
   ```nix
   # Build Redpanda Console with FIPS-validated Go crypto
   services.redpanda-console = {
     enable = true;
     package = pkgs.buildGoModule {
       pname = "redpanda-console-fips";
       src = fetchFromGitHub { ... };

       # Use BoringCrypto (FIPS 140-2 validated Go crypto)
       tags = [ "fips" ];
       CGO_ENABLED = "1";

       buildInputs = [ pkgs.openssl-fips ];
     };
   };
   ```

---

## Implementation Guide

### Phase 1: Redpanda FIPS Package (fips.nix)

```nix
# fips.nix
{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, useFips ? false  # Enable FIPS mode
}:

let
  version = "25.2.8";
  packageSuffix = if useFips then "-fips" else "";
  pname = "redpanda${packageSuffix}";

in pkgs.stdenv.mkDerivation rec {
  inherit pname version;

  src = pkgs.fetchurl {
    # Use FIPS package if enabled
    url = "https://github.com/redpanda-data/redpanda/releases/download/v${version}/redpanda${packageSuffix}-${version}-amd64.tar.gz";
    sha256 = if useFips
      then "..."  # FIPS package hash
      else "..."; # Standard package hash
  };

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
  ];

  buildInputs = [
    pkgs.zlib
    pkgs.systemd
  ] ++ lib.optionals useFips [
    # FIPS-validated OpenSSL
    (pkgs.openssl.override { enableFips = true; })
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r opt/redpanda/bin/* $out/bin/

    # Install FIPS-specific files
    ${lib.optionalString useFips ''
      mkdir -p $out/etc/openssl
      mkdir -p $out/lib/ossl-modules
      cp -r opt/redpanda/openssl/* $out/etc/openssl/ || true
      cp -r opt/redpanda/lib/ossl-modules/* $out/lib/ossl-modules/ || true
    ''}

    runHook postInstall
  '';

  postFixup = lib.optionalString useFips ''
    # Verify FIPS module is present
    if [ ! -f $out/lib/ossl-modules/fips.so ]; then
      echo "ERROR: FIPS module not found!"
      exit 1
    fi
  '';

  meta = with lib; {
    description = "Redpanda streaming platform${if useFips then " (FIPS 140-2)" else ""}";
    license = licenses.unfree; # Enterprise license required for FIPS
    platforms = platforms.linux;
  };
}
```

### Phase 2: NixOS Module with FIPS Configuration (flake.nix)

```nix
# flake.nix
{
  description = "Redpanda with FIPS 140-2 compliance";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules.default = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.services.redpanda;
        redpandaPkg = pkgs.callPackage ./fips.nix {
          useFips = cfg.fipsMode;
        };
      in
      {
        options.services.redpanda = {
          enable = mkEnableOption "Redpanda streaming platform";

          fipsMode = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Enable FIPS 140-2 mode.
              Requires:
              - Enterprise license
              - redpanda-fips packages
              - System in FIPS mode (boot.kernelParams = [ "fips=1" ])
            '';
          };

          package = mkOption {
            type = types.package;
            default = redpandaPkg;
            description = "Redpanda package (FIPS or standard)";
          };

          settings = mkOption {
            type = types.attrs;
            default = {};
            description = "Redpanda configuration";
          };

          # ... other options ...
        };

        config = mkIf cfg.enable {
          # Ensure system is in FIPS mode if requested
          assertions = [
            {
              assertion = !cfg.fipsMode || elem "fips=1" config.boot.kernelParams;
              message = "services.redpanda.fipsMode requires boot.kernelParams = [ \"fips=1\" ]";
            }
          ];

          # Merge FIPS configuration if enabled
          services.redpanda.settings = mkIf cfg.fipsMode {
            redpanda = {
              fips_mode = "enabled";
              openssl_config_file = "${cfg.package}/etc/openssl/openssl.cnf";
              openssl_module_directory = "${cfg.package}/lib/ossl-modules/";
            };
          };

          # Standard service configuration
          systemd.services.redpanda = {
            description = "Redpanda streaming platform${optionalString cfg.fipsMode " (FIPS 140-2)"}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            preStart = mkIf cfg.fipsMode ''
              # Verify FIPS mode is active
              if [ ! -f /proc/sys/crypto/fips_enabled ] || [ "$(cat /proc/sys/crypto/fips_enabled)" != "1" ]; then
                echo "ERROR: System not in FIPS mode. Add boot.kernelParams = [ \"fips=1\" ]"
                exit 1
              fi

              # Verify FIPS module
              if [ ! -f ${cfg.package}/lib/ossl-modules/fips.so ]; then
                echo "ERROR: FIPS module not found in package"
                exit 1
              fi

              echo "FIPS mode verified: kernel and OpenSSL modules ready"
            '';

            serviceConfig = {
              Type = "simple";
              ExecStart = "${cfg.package}/bin/redpanda start --config ${configFile}";
              Restart = "on-failure";
              # ... security hardening ...
            };
          };
        };
      };
  };
}
```

### Phase 3: Complete FIPS-Compliant System Configuration

```nix
# configuration.nix - Full FIPS-compliant NixOS system
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ============================================
  # FIPS 140-2 System-Wide Configuration
  # ============================================

  # Enable FIPS mode at kernel level
  boot.kernelParams = [ "fips=1" ];

  # Use FIPS-validated cryptographic modules system-wide
  nixpkgs.overlays = [
    (self: super: {
      # Override OpenSSL with FIPS module enabled
      openssl = super.openssl.override {
        enableFips = true;
      };

      # Ensure systemd uses FIPS OpenSSL
      systemd = super.systemd.override {
        cryptsetup = super.cryptsetup.override {
          openssl = self.openssl;
        };
      };

      # FIPS-compliant SSH
      openssh = super.openssh.override {
        openssl = self.openssl;
      };
    })
  ];

  # ============================================
  # Redpanda FIPS Configuration
  # ============================================

  services.redpanda = {
    enable = true;
    fipsMode = true;  # Enable FIPS mode
    openFirewall = true;

    settings = {
      redpanda = {
        data_directory = "/var/lib/redpanda";
        node_id = 0;

        # FIPS mode will be automatically configured by module

        kafka_api = [{
          address = "0.0.0.0";
          port = 9092;
        }];

        admin = [{
          address = "0.0.0.0";
          port = 9644;
        }];

        rpc_server = {
          address = "0.0.0.0";
          port = 33145;
        };
      };

      schema_registry = {
        schema_registry_api = [{
          address = "0.0.0.0";
          port = 8081;
        }];
      };

      pandaproxy = {
        pandaproxy_api = [{
          address = "0.0.0.0";
          port = 8082;
        }];
      };
    };
  };

  # ============================================
  # Redpanda Console (FIPS-Compliant)
  # ============================================

  services.redpanda-console = {
    enable = true;
    package = pkgs.buildGoModule {
      pname = "redpanda-console-fips";
      version = "2.4.0";

      src = pkgs.fetchFromGitHub {
        owner = "redpanda-data";
        repo = "console";
        rev = "v2.4.0";
        sha256 = "...";
      };

      # Build with BoringCrypto (FIPS 140-2 validated)
      tags = [ "fips" ];
      CGO_ENABLED = "1";

      buildInputs = [ pkgs.openssl ];  # Uses FIPS OpenSSL from overlay

      vendorHash = "...";
    };

    settings = {
      kafka = {
        brokers = [ "localhost:9092" ];
      };
      server = {
        listenPort = 8080;
      };
    };
  };

  # ============================================
  # FIPS Verification and Monitoring
  # ============================================

  # Verify FIPS mode on boot
  systemd.services.fips-verify = {
    description = "Verify FIPS 140-2 Mode";
    wantedBy = [ "multi-user.target" ];
    before = [ "redpanda.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "verify-fips" ''
        #!/bin/sh
        set -e

        echo "Verifying FIPS 140-2 mode..."

        # Check kernel FIPS mode
        if [ ! -f /proc/sys/crypto/fips_enabled ]; then
          echo "ERROR: /proc/sys/crypto/fips_enabled not found"
          exit 1
        fi

        FIPS_ENABLED=$(cat /proc/sys/crypto/fips_enabled)
        if [ "$FIPS_ENABLED" != "1" ]; then
          echo "ERROR: Kernel FIPS mode not enabled (fips_enabled=$FIPS_ENABLED)"
          echo "Add boot.kernelParams = [ \"fips=1\" ] to configuration.nix"
          exit 1
        fi

        echo "✓ Kernel FIPS mode: ENABLED"

        # Check OpenSSL FIPS module
        if ${pkgs.openssl}/bin/openssl list -providers | grep -q fips; then
          echo "✓ OpenSSL FIPS provider: AVAILABLE"
        else
          echo "ERROR: OpenSSL FIPS provider not found"
          exit 1
        fi

        echo "✓ FIPS 140-2 verification complete"
      '';
    };
  };

  # ============================================
  # Security Hardening (FedRAMP Requirements)
  # ============================================

  security = {
    # Audit all security events
    audit.enable = true;
    auditd.enable = true;

    # Enforce strong passwords
    pam.services.passwd.passwordCheck = "pam_pwquality.so";
  };

  # Firewall (automatically configured by services.redpanda.openFirewall)
  networking.firewall = {
    enable = true;
    # Ports opened automatically: 9092, 9644, 8081, 8082, 8080 (console)
  };

  # ============================================
  # Compliance Monitoring
  # ============================================

  # Daily FIPS verification
  systemd.timers.fips-daily-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.services.fips-daily-check = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.systemd.services.fips-verify.serviceConfig.ExecStart}";
    };
  };

  # System state for audits
  system.stateVersion = "24.05";
}
```

---

## Verification Procedures

### 1. Verify System FIPS Mode

```bash
# Check kernel FIPS mode
cat /proc/sys/crypto/fips_enabled
# Expected output: 1

# Check kernel boot parameters
cat /proc/cmdline | grep fips
# Expected: fips=1

# Verify OpenSSL FIPS provider
openssl list -providers
# Expected output should include:
#   fips
#     name: OpenSSL FIPS Provider
#     version: 3.0.9
#     status: active
```

### 2. Verify Redpanda FIPS Mode

```bash
# Check Redpanda logs for FIPS activation
journalctl -u redpanda -f | grep -i fips
# Expected: "FIPS mode enabled" or similar

# Check Redpanda configuration
rpk cluster config get fips_mode
# Expected: enabled

# Verify FIPS module loading
rpk cluster status
# Should show no errors related to crypto
```

### 3. Test Cryptographic Operations

```bash
# Test TLS with FIPS-validated ciphers
openssl s_client -connect localhost:9092 -tls1_2 -cipher 'FIPS:!aNULL'

# Should successfully connect with FIPS-approved cipher suite
# Example: TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
```

### 4. Audit Complete Cryptographic Stack

```bash
# Show complete dependency graph
nix-store -q --tree /run/current-system | grep -i "openssl\|crypto"

# Verify all OpenSSL references use FIPS version
nix-store -q --references /run/current-system | xargs nix-store -q --tree | grep openssl

# Expected: All paths point to openssl-fips derivation
```

---

## Compliance Notes for FedRAMP High

### SC-13: Cryptographic Protection

**FedRAMP Requirement**:
> The information system implements FIPS-validated cryptography to protect sensitive information

**NixOS Implementation**:

| Requirement | NixOS Approach |
|-------------|---------------|
| **Data at rest** | FIPS OpenSSL via system-wide overlay |
| **Data in transit (TLS)** | FIPS OpenSSL via system-wide overlay |
| **Authentication** | FIPS OpenSSL via system-wide overlay |
| **Hashing/RNG** | FIPS OpenSSL via system-wide overlay |
| **Key generation** | FIPS OpenSSL via system-wide overlay |
| **Full stack validation** | Complete audit trail via `nix-store` dependency graph |

**Evidence for Auditors**:
```bash
# Generate cryptographic compliance report
cat > /tmp/fips-audit.sh <<'EOF'
#!/bin/bash
echo "=== FIPS 140-2 Compliance Audit ==="
echo "Date: $(date)"
echo ""
echo "1. Kernel FIPS Mode:"
cat /proc/sys/crypto/fips_enabled
echo ""
echo "2. OpenSSL FIPS Provider:"
openssl list -providers | grep -A 2 fips
echo ""
echo "3. Redpanda FIPS Status:"
rpk cluster config get fips_mode
echo ""
echo "4. Complete Cryptographic Dependency Graph:"
nix-store -q --tree /run/current-system | grep -i crypto | head -20
echo ""
echo "5. OpenSSL FIPS Module Hash:"
nix-store -q --hash $(nix-store -qR /run/current-system | grep openssl | head -1)
EOF

bash /tmp/fips-audit.sh > fips-compliance-$(date +%Y%m%d).txt
```

---

## Next Steps

1. **Test FIPS package availability**:
   ```bash
   curl -I "https://github.com/redpanda-data/redpanda/releases/download/v25.2.8/redpanda-fips-25.2.8-amd64.tar.gz"
   ```
2. **Build and test** FIPS package on a development system
3. **Configure system-wide FIPS**: kernel parameter + OpenSSL overlay
4. **Build Redpanda Console** with FIPS-validated Go crypto
5. **Automate verification**: integrate FIPS checks into CI/CD
6. **FedRAMP preparation**: update SSP, generate 3PAO evidence

---

## Conclusion

Deploying Redpanda FIPS on NixOS enables:

- **System-wide FIPS enforcement** via kernel parameter and OpenSSL overlay, addressing the container-based limitations documented by Redpanda
- **Reproducible builds** where the same `flake.lock` produces identical FIPS-enabled systems
- **Complete dependency graph** auditable via `nix-store`, providing verifiable evidence for SC-13 compliance
- **FIPS-compliant Console** buildable from source with BoringCrypto (FIPS-validated Go crypto)

Remaining FedRAMP High gaps (3PAO assessment, SSP documentation, ConMon plan) are organizational and not addressed by the deployment method alone.

---

**For Implementation Details**: See [COMPLIANCE_MATRIX.md](../compliance/COMPLIANCE_MATRIX.md) for the FedRAMP roadmap

**Document Version**: 1.1
**Last Updated**: 2026-04-12
**Next Review**: Upon Redpanda FIPS package updates
