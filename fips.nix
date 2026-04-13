{ lib
, stdenv
, fetchurl
, dpkg
, patchelf
}:

stdenv.mkDerivation rec {
  pname = "redpanda-fips";
  version = "26.1.4";

  # The base Redpanda deb (contains the actual binary + libraries)
  src = fetchurl {
    url = "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda_${version}-1/redpanda_${version}-1_amd64.deb";
    sha256 = "0k6zfllsjmjcli2zdhib2vgq0mxav56hyfwy0mbvhf9yx2nhafqs";
  };

  # The FIPS supplement deb (FIPS OpenSSL config + FIPS-validated openssl binary)
  fipsSrc = fetchurl {
    url = "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda-fips_${version}-1/redpanda-fips_${version}-1_amd64.deb";
    sha256 = "01ir6lfb5578k5bcddjv3wncrhbnpj36lmpbcg20lqmhdkdwnb1z";
  };

  nativeBuildInputs = [
    dpkg
    patchelf
  ];

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # Extract the base Redpanda deb
    dpkg-deb -x $src ./deb-contents

    # Extract the FIPS supplement deb (overlays onto same /opt/redpanda tree)
    dpkg-deb -x $fipsSrc ./deb-contents

    # Create output directories
    mkdir -p $out/bin
    mkdir -p $out/opt/redpanda/bin
    mkdir -p $out/opt/redpanda/lib
    mkdir -p $out/opt/redpanda/libexec
    mkdir -p $out/opt/redpanda/openssl

    # Copy the real binary from libexec
    cp deb-contents/opt/redpanda/libexec/redpanda $out/opt/redpanda/libexec/
    chmod +x $out/opt/redpanda/libexec/redpanda

    # Copy FIPS OpenSSL binary if present
    if [ -f "deb-contents/opt/redpanda/libexec/openssl-redpanda" ]; then
      cp deb-contents/opt/redpanda/libexec/openssl-redpanda $out/opt/redpanda/libexec/
      chmod +x $out/opt/redpanda/libexec/openssl-redpanda
    fi

    # Copy the bundled dynamic linker
    cp deb-contents/opt/redpanda/lib/ld.so $out/opt/redpanda/lib/
    chmod +x $out/opt/redpanda/lib/ld.so

    # Copy all libraries bundled with redpanda
    if [ -d "deb-contents/opt/redpanda/lib" ]; then
      cp -r deb-contents/opt/redpanda/lib/* $out/opt/redpanda/lib/
    fi

    # Copy FIPS OpenSSL configuration files
    if [ -d "deb-contents/opt/redpanda/openssl" ]; then
      cp -r deb-contents/opt/redpanda/openssl/* $out/opt/redpanda/openssl/
    fi

    # Fix hardcoded .include path for NixOS
    # The deb ships openssl.cnf with ".include /opt/redpanda/openssl/fipsmodule.cnf"
    # but on NixOS the file is at $out/opt/redpanda/openssl/fipsmodule.cnf.
    # Without this fix, the FIPS provider silently fails to load.
    if [ -f "$out/opt/redpanda/openssl/openssl.cnf" ]; then
      sed -i "s|\.include /opt/redpanda/openssl/fipsmodule\.cnf|.include $out/opt/redpanda/openssl/fipsmodule.cnf|g" \
        "$out/opt/redpanda/openssl/openssl.cnf"
    fi

    # Copy any additional files
    if [ -f "deb-contents/opt/redpanda/RELEASE-DATE.txt" ]; then
      cp deb-contents/opt/redpanda/RELEASE-DATE.txt $out/opt/redpanda/
    fi

    # Patch the interpreter path in the binary
    patchelf --set-interpreter "$out/opt/redpanda/lib/ld.so" $out/opt/redpanda/libexec/redpanda

    # Patch FIPS OpenSSL binary if present
    if [ -f "$out/opt/redpanda/libexec/openssl-redpanda" ]; then
      patchelf --set-interpreter "$out/opt/redpanda/lib/ld.so" $out/opt/redpanda/libexec/openssl-redpanda
    fi

    # Create wrapper script
    cat > $out/bin/redpanda << 'WRAPPEREOF'
#!/usr/bin/env bash
set -e

# Resolve symlinks to find the real script location in /nix/store
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "''${BASH_SOURCE[0]}")")" && pwd)"
REDPANDA_HOME="$(dirname "$SCRIPT_DIR")/opt/redpanda"

# Set LD_LIBRARY_PATH to use bundled libraries
export LD_LIBRARY_PATH="''${REDPANDA_HOME}/lib"

# Point OpenSSL to FIPS configuration
export OPENSSL_CONF="''${REDPANDA_HOME}/openssl/openssl.cnf"

exec -a "$0" "''${REDPANDA_HOME}/libexec/redpanda" "$@"
WRAPPEREOF
    chmod +x $out/bin/redpanda

    # Also create the opt/redpanda/bin wrapper for consistency
    cp $out/bin/redpanda $out/opt/redpanda/bin/redpanda

    # Create FIPS OpenSSL wrapper if the binary exists
    if [ -f "$out/opt/redpanda/libexec/openssl-redpanda" ]; then
      cat > $out/bin/openssl-redpanda << 'WRAPPEREOF'
#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
REDPANDA_HOME="$(dirname "$SCRIPT_DIR")/opt/redpanda"
export LD_LIBRARY_PATH="''${REDPANDA_HOME}/lib"
export OPENSSL_CONF="''${REDPANDA_HOME}/openssl/openssl.cnf"
exec -a "$0" "''${REDPANDA_HOME}/libexec/openssl-redpanda" "$@"
WRAPPEREOF
      chmod +x $out/bin/openssl-redpanda
      cp $out/bin/openssl-redpanda $out/opt/redpanda/bin/openssl-redpanda
    fi

    # Copy systemd service files if they exist
    if [ -d "deb-contents/usr/lib/systemd" ]; then
      mkdir -p $out/lib/systemd
      cp -r deb-contents/usr/lib/systemd/* $out/lib/systemd/ 2>/dev/null || true
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Redpanda streaming platform with FIPS 140-2 compliance";
    homepage = "https://redpanda.com/";
    license = licenses.bsl11;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];

    longDescription = ''
      Redpanda with FIPS 140-2 compliance for FedRAMP High deployments.

      This package combines the base Redpanda binary with the FIPS supplement,
      which provides FIPS-validated OpenSSL configuration and binary.

      Compliance:
      - FedRAMP High (FIPS 140-2 cryptography)
      - DoD IL4/IL5 (FIPS-compliant encryption)
      - NIST SP 800-53 (SC-13 cryptographic protection)
      - CJIS Section 5.10 (FIPS-validated encryption)

      Performance Note:
      - FIPS validation adds 10-30% overhead
      - Only use if FIPS 140-2 is required

      Usage:
        nix build .#redpanda-fips

      Documentation:
        https://docs.redpanda.com/current/manage/security/fips-compliance/
    '';
  };
}
