#!/usr/bin/env bash
# Automatic Redpanda package updater for NixOS
# Usage: ./update.sh [version]
# If version is not specified, fetches the latest release from GitHub

set -euo pipefail

REDPANDA_REPO="redpanda-data/redpanda"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to get latest release version from GitHub
get_latest_version() {
    echo "Fetching latest Redpanda release..." >&2
    curl -s "https://api.github.com/repos/${REDPANDA_REPO}/releases/latest" | \
        grep '"tag_name":' | \
        sed -E 's/.*"v([^"]+)".*/\1/'
}

# Function to download and hash a file
get_sha256() {
    local url="$1"
    echo "Downloading and hashing: $url" >&2

    # Use nix-prefetch-url if available, otherwise use nix-shell
    if command -v nix-prefetch-url &> /dev/null; then
        nix-prefetch-url --type sha256 "$url"
    else
        # Fallback: use nix-shell with nix package
        nix-shell -p nix --run "nix-prefetch-url --type sha256 '$url'"
    fi
}

# Function to get asset URL for a specific version and architecture
get_asset_url() {
    local version="$1"
    local arch="$2"
    echo "https://github.com/${REDPANDA_REPO}/releases/download/v${version}/redpanda-${version}-amd64.tar.gz"
}

# Main update logic
main() {
    local version="${1:-}"

    if [ -z "$version" ]; then
        version=$(get_latest_version)
        if [ -z "$version" ]; then
            echo "Error: Could not fetch latest version" >&2
            exit 1
        fi
    fi

    echo "Updating to Redpanda version: $version"

    # Get download URLs
    local url_x86_64=$(get_asset_url "$version" "amd64")

    echo "Fetching SHA256 for x86_64..."
    local sha256_x86_64=$(get_sha256 "$url_x86_64")

    # Generate default.nix
    cat > "${SCRIPT_DIR}/default.nix" << EOF
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, zlib
, openssl
, systemd
}:

stdenv.mkDerivation rec {
  pname = "redpanda";
  version = "${version}";

  src = fetchurl {
    url = "https://github.com/redpanda-data/redpanda/releases/download/v\${version}/redpanda-\${version}-amd64.tar.gz";
    sha256 = "${sha256_x86_64}";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    zlib
    openssl
    systemd
  ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p \$out/bin
    mkdir -p \$out/lib

    # Install binaries
    cp -r opt/redpanda/bin/* \$out/bin/

    # Install libraries if they exist
    if [ -d "opt/redpanda/lib" ]; then
      cp -r opt/redpanda/lib/* \$out/lib/
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
EOF

    echo "✓ Generated default.nix for version ${version}"

    # Update flake.nix if it exists
    if [ -f "${SCRIPT_DIR}/flake.nix" ]; then
        echo "Updating version in flake.nix..."
        sed -i "s/version = \".*\"/version = \"${version}\"/" "${SCRIPT_DIR}/flake.nix"
        echo "✓ Updated flake.nix"
    fi

    echo ""
    echo "Package updated successfully!"
    echo "Version: ${version}"
    echo "SHA256: ${sha256_x86_64}"
    echo ""
    echo "You can now build the package with:"
    echo "  nix-build"
    echo "or if using flakes:"
    echo "  nix build"
}

main "$@"
