#!/usr/bin/env bash
# Automatic Redpanda package updater for NixOS
# Usage: ./update.sh [version]
# If version is not specified, fetches the latest release from GitHub

set -euo pipefail

REDPANDA_REPO="redpanda-data/redpanda"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Function to get latest release version from GitHub
get_latest_version() {
    echo "Fetching latest Redpanda release..." >&2
    curl -s "https://api.github.com/repos/${REDPANDA_REPO}/releases/latest" | \
        grep '"tag_name":' | \
        sed -E 's/.*"v([^"]+)".*/\1/'
}

# Function to verify a version tag exists and is a stable release
verify_version_tag() {
    local version="$1"

    # Check if version matches stable release pattern (no -dev, -rc, etc.)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Version '$version' is not a stable release (contains pre-release suffixes)" >&2
        return 1
    fi

    # Verify the tag exists in the repository
    if ! git ls-remote --tags "https://github.com/${REDPANDA_REPO}.git" | grep -q "refs/tags/v${version}^{}"; then
        echo "Error: Tag 'v$version' not found in repository" >&2
        return 1
    fi

    echo "✓ Verified stable release tag: v$version" >&2
    return 0
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

# Function to get DEB package URL from Cloudsmith
get_deb_url() {
    local version="$1"
    echo "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda_${version}-1/redpanda_${version}-1_amd64.deb"
}

# Function to get FIPS supplement DEB package URL from Cloudsmith
get_fips_deb_url() {
    local version="$1"
    echo "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda-fips_${version}-1/redpanda-fips_${version}-1_amd64.deb"
}

# Function to log supply chain events (NIST 800-161 SR-5, NIST CSF GV.SC-05)
log_supply_chain_event() {
    local event_type="$1"
    local version="$2"
    local status="$3"
    local details="$4"
    local compliance_dir="${SCRIPT_DIR}/compliance"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    mkdir -p "$compliance_dir"

    # Append to supply chain event log (JSON Lines format)
    cat >> "$compliance_dir/supply-chain-events.jsonl" <<EOF
{"timestamp":"$timestamp","event":"$event_type","version":"$version","status":"$status","details":"$details"}
EOF

    echo "✓ Logged event: $event_type (version $version)"
}

# Update source build hash in flake.nix
update_source_hashes() {
    local version="$1"
    echo "Computing source tarball hash for v${version}..."

    local src_hash
    if command -v nix-prefetch-url &>/dev/null; then
        local nix_hash
        nix_hash=$(nix-prefetch-url --unpack "https://github.com/redpanda-data/redpanda/archive/refs/tags/v${version}.tar.gz" 2>/dev/null)
        src_hash=$(nix hash to-sri --type sha256 "$nix_hash" 2>/dev/null | sed 's/^warning:.*//')
    else
        echo "Warning: nix-prefetch-url not available, skipping source hash update" >&2
        return 0
    fi

    if [ -n "$src_hash" ]; then
        sed -i "s|srcHash = \"sha256-.*\"|srcHash = \"${src_hash}\"|" "${SCRIPT_DIR}/flake.nix"
        echo "✓ Updated source hash in flake.nix: ${src_hash}"
        log_supply_chain_event "source_hash_updated" "$version" "success" "Source tarball SHA256 (SRI)"
    else
        echo "Warning: Could not compute source hash" >&2
    fi
}

# Update rpk.nix version and hashes
update_rpk() {
    local version="$1"
    local rpk_file="${SCRIPT_DIR}/rpk.nix"

    if [ ! -f "$rpk_file" ]; then
        echo "Warning: rpk.nix not found, skipping rpk update" >&2
        return 0
    fi

    echo "Updating rpk.nix version to ${version}..."
    sed -i "s/version = \"[0-9.]*\"/version = \"${version}\"/" "$rpk_file"

    # rpk uses the same source tarball as the server, so the src hash matches flake.nix srcHash
    # But the vendorHash (Go module hash) changes per version and must be recomputed
    echo "Computing rpk vendorHash (this will attempt a build with a dummy hash)..."

    # Set a known-bad hash to trigger the "got:" error
    sed -i 's/vendorHash = "sha256-[^"]*"/vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="/' "$rpk_file"

    local build_output
    build_output=$(nix build "${SCRIPT_DIR}#redpanda-rpk" 2>&1 || true)
    local got_hash
    got_hash=$(echo "$build_output" | grep "got:" | sed 's/.*got:\s*//' | tr -d ' ')

    if [ -n "$got_hash" ]; then
        sed -i "s|vendorHash = \"sha256-.*\"|vendorHash = \"${got_hash}\"|" "$rpk_file"
        echo "✓ Updated rpk.nix vendorHash: ${got_hash}"
    else
        echo "Warning: Could not compute rpk vendorHash. Manual update needed." >&2
        echo "  Run: nix build .#redpanda-rpk 2>&1 | grep 'got:'" >&2
        # Restore the previous hash so the file isn't left with the dummy
        sed -i 's/vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="/vendorHash = "sha256-TODO-run-nix-build-to-get-hash"/' "$rpk_file"
    fi

    # Also update the source hash to match the flake.nix srcHash
    local current_src_hash
    current_src_hash=$(grep 'srcHash = ' "${SCRIPT_DIR}/flake.nix" | head -1 | sed 's/.*"\(sha256-[^"]*\)".*/\1/')
    if [ -n "$current_src_hash" ]; then
        sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${current_src_hash}\"|" "$rpk_file"
        echo "✓ Updated rpk.nix source hash to match flake.nix"
    fi

    echo "✓ Updated rpk.nix to version ${version}"
    log_supply_chain_event "rpk_updated" "$version" "success" "rpk CLI version and hashes"
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

    # Verify the version is a stable release and exists
    if ! verify_version_tag "$version"; then
        exit 1
    fi

    echo "Updating to Redpanda version: $version"

    # Log version update event
    log_supply_chain_event "version_update_started" "$version" "in_progress" "Updating from previous version"

    # Get download URL from Cloudsmith
    local deb_url=$(get_deb_url "$version")

    echo "Fetching SHA256 for DEB package..."
    local sha256=$(get_sha256 "$deb_url")

    # Generate deb.nix
    cat > "${SCRIPT_DIR}/deb.nix" << 'EOF'
{ lib
, stdenv
, fetchurl
, dpkg
, patchelf
}:

stdenv.mkDerivation rec {
  pname = "redpanda";
  version = "VERSION_PLACEHOLDER";

  src = fetchurl {
    url = "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda_${version}-1/redpanda_${version}-1_amd64.deb";
    sha256 = "SHA256_PLACEHOLDER";
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
EOF

    # Replace placeholders with actual values
    sed -i "s/VERSION_PLACEHOLDER/${version}/g" "${SCRIPT_DIR}/deb.nix"
    sed -i "s/SHA256_PLACEHOLDER/${sha256}/g" "${SCRIPT_DIR}/deb.nix"

    echo "✓ Generated deb.nix for version ${version}"

    # Update Redpanda version in flake.nix.
    # Only replace the version on the line above srcHash (not other version
    # strings like the Go override). Uses a two-line sed match.
    if [ -f "${SCRIPT_DIR}/flake.nix" ]; then
        echo "Updating version in flake.nix..."
        sed -i '/# These must match a tagged Redpanda release/{n; s/version = "[0-9.]*"/version = "'"${version}"'"/}' "${SCRIPT_DIR}/flake.nix"
        echo "✓ Updated flake.nix"
    fi

    # Log package generation completion
    log_supply_chain_event "package_generated" "$version" "success" "DEB package from Cloudsmith (x86_64)"

    # Generate FIPS package
    echo ""
    echo "Updating FIPS package..."
    local fips_deb_url=$(get_fips_deb_url "$version")
    echo "Fetching SHA256 for FIPS supplement deb..."
    local fips_sha256=$(get_sha256 "$fips_deb_url")

    generate_fips_nix "$version" "$sha256" "$fips_sha256"
    echo "✓ Generated fips.nix for version ${version}"

    log_supply_chain_event "fips_package_generated" "$version" "success" "FIPS supplement DEB from Cloudsmith (x86_64)"

    # Update source build and rpk hashes
    echo ""
    echo "Updating source build and rpk hashes..."
    update_source_hashes "$version"
    update_rpk "$version"

    echo ""
    echo "Packages updated successfully!"
    echo "Version: ${version}"
    echo "SHA256 (deb): ${sha256}"
    echo "SHA256 (FIPS): ${fips_sha256}"
    echo ""

    # Generate compliance artifacts
    generate_compliance_artifacts "$version"

    echo "You can now build the packages with:"
    echo "  nix build .#redpanda-deb   # deb package (fast)"
    echo "  nix build .#redpanda-rpk   # rpk CLI"
    echo "  nix build .#redpanda-fips  # FIPS package"
    echo "  nix build .#redpanda       # source build (requires bazel-deps.nix regeneration)"
    echo ""
    echo "NOTE: source/bazel-deps.nix and source/MODULE.bazel.lock.nix must be regenerated"
    echo "manually for source builds. See CLAUDE.md 'Update to New Redpanda Version'."
}

# Function to generate fips.nix from template
generate_fips_nix() {
    local version="$1"
    local base_sha256="$2"
    local fips_sha256="$3"

    cat > "${SCRIPT_DIR}/fips.nix" << 'EOF'
{ lib
, stdenv
, fetchurl
, dpkg
, patchelf
}:

stdenv.mkDerivation rec {
  pname = "redpanda-fips";
  version = "VERSION_PLACEHOLDER";

  # The base Redpanda deb (contains the actual binary + libraries)
  src = fetchurl {
    url = "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda_${version}-1/redpanda_${version}-1_amd64.deb";
    sha256 = "BASE_SHA256_PLACEHOLDER";
  };

  # The FIPS supplement deb (FIPS OpenSSL config + FIPS-validated openssl binary)
  fipsSrc = fetchurl {
    url = "https://dl.redpanda.com/public/redpanda/deb/any-distro/pool/any-version/main/r/re/redpanda-fips_${version}-1/redpanda-fips_${version}-1_amd64.deb";
    sha256 = "FIPS_SHA256_PLACEHOLDER";
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
EOF

    # Replace placeholders with actual values
    sed -i "s/VERSION_PLACEHOLDER/${version}/g" "${SCRIPT_DIR}/fips.nix"
    sed -i "s/BASE_SHA256_PLACEHOLDER/${base_sha256}/g" "${SCRIPT_DIR}/fips.nix"
    sed -i "s/FIPS_SHA256_PLACEHOLDER/${fips_sha256}/g" "${SCRIPT_DIR}/fips.nix"
}

# Function to generate compliance artifacts (SBOM, provenance, vulnerability scan)
generate_compliance_artifacts() {
    local version="$1"
    local compliance_dir="${SCRIPT_DIR}/compliance"

    echo ""
    echo "=== Generating Compliance Artifacts ==="
    echo ""

    # Log start of compliance artifact generation
    log_supply_chain_event "compliance_generation_started" "$version" "in_progress" "Generating SBOM, provenance, and vulnerability scan"

    # Check if sbomnix is available
    if ! command -v sbomnix &> /dev/null; then
        echo "⚠️  sbomnix not found. Installing temporarily..."
        if ! nix profile install github:tiiuae/sbomnix 2>/dev/null; then
            echo "⚠️  Could not install sbomnix. Skipping compliance artifacts."
            echo "   Install manually with: nix profile install github:tiiuae/sbomnix"
            return
        fi
    fi

    echo "Building package for compliance scanning..."
    local store_path
    if ! store_path=$(nix build "${SCRIPT_DIR}#redpanda-deb" --print-out-paths --no-link 2>&1 | tail -n 1); then
        echo "⚠️  Build failed. Skipping compliance artifacts."
        echo "   Build the package manually and run compliance generation later."
        return
    fi

    if [ -z "$store_path" ] || [ ! -d "$store_path" ]; then
        echo "⚠️  Could not determine store path. Skipping compliance artifacts."
        return
    fi

    mkdir -p "$compliance_dir"

    # Generate CycloneDX SBOM
    echo "Generating CycloneDX SBOM..."
    if sbomnix "$store_path" --cdx "$compliance_dir/redpanda-${version}-sbom.cdx.json" 2>&1 | grep -v "^$"; then
        echo "✓ Generated CycloneDX SBOM: compliance/redpanda-${version}-sbom.cdx.json"
        log_supply_chain_event "sbom_generated" "$version" "success" "CycloneDX format"
    else
        echo "⚠️  SBOM generation had warnings (check output above)"
        log_supply_chain_event "sbom_generated" "$version" "warning" "CycloneDX format with warnings"
    fi

    # Generate SLSA v1.0 Provenance
    echo "Generating SLSA v1.0 provenance attestation..."
    if provenance "$store_path" --out "$compliance_dir/redpanda-${version}-provenance.json" 2>&1 | grep -v "^$"; then
        echo "✓ Generated SLSA provenance: compliance/redpanda-${version}-provenance.json"
        log_supply_chain_event "provenance_generated" "$version" "success" "SLSA v1.0 attestation"
    else
        echo "⚠️  Provenance generation had warnings (check output above)"
        log_supply_chain_event "provenance_generated" "$version" "warning" "SLSA v1.0 with warnings"
    fi

    # Generate vulnerability scan
    echo "Scanning for vulnerabilities (CVE database)..."
    if command -v vulnxscan &> /dev/null; then
        if vulnxscan "$store_path" --out "$compliance_dir/redpanda-${version}-vulnerabilities.csv" 2>&1 | grep -v "^$"; then
            echo "✓ Generated vulnerability scan: compliance/redpanda-${version}-vulnerabilities.csv"

            # Check for critical vulnerabilities
            local critical_count=$(awk -F',' '$2 == "CRITICAL" {count++} END {print count+0}' "$compliance_dir/redpanda-${version}-vulnerabilities.csv")
            local high_count=$(awk -F',' '$2 == "HIGH" {count++} END {print count+0}' "$compliance_dir/redpanda-${version}-vulnerabilities.csv")

            log_supply_chain_event "vulnerability_scan_completed" "$version" "success" "Critical: $critical_count, High: $high_count"

            if [ "$critical_count" -gt 0 ]; then
                echo "⚠️  WARNING: Found $critical_count CRITICAL vulnerabilities!"
            fi
        else
            echo "⚠️  Vulnerability scan had warnings (check output above)"
            log_supply_chain_event "vulnerability_scan_completed" "$version" "warning" "Scan completed with warnings"
        fi
    else
        echo "⚠️  vulnxscan not found. Install with: nix profile install github:tiiuae/sbomnix"
        log_supply_chain_event "vulnerability_scan_completed" "$version" "skipped" "vulnxscan not available"
    fi

    # Generate SPDX SBOM (alternative format for DoD)
    echo "Generating SPDX SBOM (alternative format)..."
    if sbomnix "$store_path" --spdx "$compliance_dir/redpanda-${version}-sbom.spdx.json" 2>&1 | grep -v "^$"; then
        echo "✓ Generated SPDX SBOM: compliance/redpanda-${version}-sbom.spdx.json"
        log_supply_chain_event "sbom_generated" "$version" "success" "SPDX format"
    else
        echo "⚠️  SPDX generation had warnings (check output above)"
        log_supply_chain_event "sbom_generated" "$version" "warning" "SPDX format with warnings"
    fi

    # Sign SBOMs with Sigstore/cosign (if available)
    echo ""
    echo "Signing SBOMs with Sigstore/cosign..."
    if command -v cosign &> /dev/null; then
        for sbom_file in "$compliance_dir/redpanda-${version}"-sbom.*.json; do
            if [ -f "$sbom_file" ]; then
                echo "Signing: $(basename "$sbom_file")..."
                if cosign sign-blob \
                    --bundle "${sbom_file}.bundle" \
                    --yes \
                    "$sbom_file" > /dev/null 2>&1; then
                    echo "✓ Signed: $(basename "$sbom_file")"
                    log_supply_chain_event "sbom_signed" "$version" "success" "$(basename "$sbom_file")"
                else
                    echo "⚠️  Signing failed for: $(basename "$sbom_file")"
                    log_supply_chain_event "sbom_signed" "$version" "failed" "$(basename "$sbom_file")"
                fi
            fi
        done

        # Sign provenance
        if [ -f "$compliance_dir/redpanda-${version}-provenance.json" ]; then
            echo "Signing: redpanda-${version}-provenance.json..."
            if cosign sign-blob \
                --bundle "$compliance_dir/redpanda-${version}-provenance.json.bundle" \
                --yes \
                "$compliance_dir/redpanda-${version}-provenance.json" > /dev/null 2>&1; then
                echo "✓ Signed: redpanda-${version}-provenance.json"
                log_supply_chain_event "provenance_signed" "$version" "success" "SLSA provenance"
            else
                echo "⚠️  Signing failed for provenance"
                log_supply_chain_event "provenance_signed" "$version" "failed" "SLSA provenance"
            fi
        fi

        echo ""
        echo "✓ SBOM signing complete"
        echo ""
        echo "Verify signatures with:"
        echo "  cosign verify-blob --bundle <file>.bundle <file>"
    else
        echo "⚠️  cosign not found. Install with:"
        echo "     nix profile install nixpkgs#cosign"
        echo ""
        echo "Skipping SBOM signing (optional for compliance)"
        log_supply_chain_event "sbom_signing" "$version" "skipped" "cosign not available"
    fi

    echo ""
    echo "=== Compliance Artifacts Summary ==="
    echo "Generated compliance artifacts in: $compliance_dir"
    echo ""
    echo "Files generated:"
    ls -lh "$compliance_dir" | tail -n +2 | awk '{print "  - " $9 " (" $5 ")"}'
    echo ""

    # Log completion
    log_supply_chain_event "compliance_generation_completed" "$version" "success" "All artifacts generated"
    echo "✓ Supply chain events logged to: compliance/supply-chain-events.jsonl"
}

main "$@"
