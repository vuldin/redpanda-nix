#!/usr/bin/env bash
# Publish compliance artifacts to stable paths for distribution
# Copies versioned artifacts to compliance/current/ with predictable names
# Usage: ./scripts/publish-compliance-artifacts.sh [version]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPLIANCE_DIR="${SCRIPT_DIR}/compliance"
CURRENT_DIR="${COMPLIANCE_DIR}/current"

# Auto-detect version from default.nix if not provided
get_current_version() {
    grep 'version = ' "${SCRIPT_DIR}/default.nix" | head -1 | cut -d'"' -f2
}

main() {
    local version="${1:-$(get_current_version)}"

    if [ -z "$version" ]; then
        echo "Error: Could not determine version" >&2
        exit 1
    fi

    echo "Publishing compliance artifacts for version ${version}"

    mkdir -p "$CURRENT_DIR"

    local found=0

    # Copy CycloneDX SBOM
    if [ -f "$COMPLIANCE_DIR/redpanda-${version}-sbom.json" ]; then
        cp "$COMPLIANCE_DIR/redpanda-${version}-sbom.json" "$CURRENT_DIR/sbom-cyclonedx.json"
        echo "  sbom-cyclonedx.json"
        found=$((found + 1))
    fi

    # Copy SPDX SBOM
    if [ -f "$COMPLIANCE_DIR/redpanda-${version}-sbom.spdx.json" ]; then
        cp "$COMPLIANCE_DIR/redpanda-${version}-sbom.spdx.json" "$CURRENT_DIR/sbom-spdx.json"
        echo "  sbom-spdx.json"
        found=$((found + 1))
    fi

    # Copy SLSA provenance
    if [ -f "$COMPLIANCE_DIR/redpanda-${version}-provenance.json" ]; then
        cp "$COMPLIANCE_DIR/redpanda-${version}-provenance.json" "$CURRENT_DIR/provenance-slsa.json"
        echo "  provenance-slsa.json"
        found=$((found + 1))
    fi

    # Copy vulnerability scan
    if [ -f "$COMPLIANCE_DIR/redpanda-${version}-vulnerabilities.csv" ]; then
        cp "$COMPLIANCE_DIR/redpanda-${version}-vulnerabilities.csv" "$CURRENT_DIR/vulnerabilities.csv"
        echo "  vulnerabilities.csv"
        found=$((found + 1))
    fi

    # Run aggregate SBOM if the script exists and source SBOMs are present
    if [ -x "${SCRIPT_DIR}/scripts/aggregate-sboms.sh" ] && [ -f "$CURRENT_DIR/sbom-cyclonedx.json" ]; then
        echo "  Generating aggregate SBOM..."
        "${SCRIPT_DIR}/scripts/aggregate-sboms.sh" \
            --version "$version" \
            --output "$CURRENT_DIR/sbom-aggregate.json" 2>/dev/null \
            && echo "  sbom-aggregate.json" \
            || echo "  (aggregate SBOM skipped — jq may not be installed)"
    fi

    # Write version metadata
    cat > "$CURRENT_DIR/VERSION" <<EOF
version=${version}
published=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    if [ "$found" -eq 0 ]; then
        echo ""
        echo "No versioned artifacts found for v${version}."
        echo "Run './scripts/update.sh ${version}' first to generate them."
        exit 1
    fi

    echo ""
    echo "Published ${found} artifact(s) to compliance/current/"
}

main "$@"
