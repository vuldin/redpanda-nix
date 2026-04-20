{ lib
, stdenv
, fetchurl
, dpkg
, patchelf
}:

stdenv.mkDerivation rec {
  pname = "redpanda";
  version = "26.1.5";

  src = fetchurl {
    url = "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda_${version}-1/redpanda_${version}-1_amd64.deb";
    sha256 = "09p23jmhgh27y3qmslcp865ly5y53hxgsas22jcxlxhxc6cr7di5";
  };

  nativeBuildInputs = [
    dpkg
    patchelf
  ];

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # Extract the .deb package
    dpkg-deb -x $src ./deb-contents

    # Create output directories
    mkdir -p $out/bin
    mkdir -p $out/opt/redpanda/bin
    mkdir -p $out/opt/redpanda/lib
    mkdir -p $out/opt/redpanda/libexec

    # Copy the real binary from libexec
    cp deb-contents/opt/redpanda/libexec/redpanda $out/opt/redpanda/libexec/
    chmod +x $out/opt/redpanda/libexec/redpanda

    # Copy the bundled dynamic linker
    cp deb-contents/opt/redpanda/lib/ld.so $out/opt/redpanda/lib/
    chmod +x $out/opt/redpanda/lib/ld.so

    # Copy all libraries bundled with redpanda
    if [ -d "deb-contents/opt/redpanda/lib" ]; then
      cp -r deb-contents/opt/redpanda/lib/* $out/opt/redpanda/lib/
    fi

    # Copy any additional files
    if [ -f "deb-contents/opt/redpanda/RELEASE-DATE.txt" ]; then
      cp deb-contents/opt/redpanda/RELEASE-DATE.txt $out/opt/redpanda/
    fi

    # Patch the interpreter path in the binary
    patchelf --set-interpreter "$out/opt/redpanda/lib/ld.so" $out/opt/redpanda/libexec/redpanda

    # Create wrapper script
    cat > $out/bin/redpanda << 'INNEREOF'
#!/usr/bin/env bash
set -e

# Resolve symlinks to find the real script location in /nix/store
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "''${BASH_SOURCE[0]}")")" && pwd)"
REDPANDA_HOME="$(dirname "$SCRIPT_DIR")/opt/redpanda"

# Set LD_LIBRARY_PATH to use bundled libraries
export LD_LIBRARY_PATH="''${REDPANDA_HOME}/lib"

exec -a "$0" "''${REDPANDA_HOME}/libexec/redpanda" "$@"
INNEREOF
    chmod +x $out/bin/redpanda

    # Also create the opt/redpanda/bin wrapper for consistency
    cp $out/bin/redpanda $out/opt/redpanda/bin/redpanda

    # Copy systemd service files if they exist
    if [ -d "deb-contents/usr/lib/systemd" ]; then
      mkdir -p $out/lib/systemd
      cp -r deb-contents/usr/lib/systemd/* $out/lib/systemd/ 2>/dev/null || true
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Redpanda is a streaming data platform for developers";
    homepage = "https://redpanda.com/";
    license = licenses.bsl11;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
