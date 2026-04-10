#!/usr/bin/env bash
# Collect SOC 2 / NIST audit evidence into a timestamped tarball
# Usage: ./scripts/collect-evidence.sh [--days N] [--output DIR]
#
# Collects:
#   CC8.1  - Git audit trail
#   CC7.2  - Nix store integrity verification
#   CC6.1  - systemd service hardening config
#   CC7.1  - journald log excerpt
#   SR-4   - SBOM/provenance artifacts
#   SR-3   - Nix dependency closure
#   SC-13  - FIPS status check
#
# Output: evidence/evidence-YYYY-MM-DD.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAYS=90
OUTPUT_DIR="${SCRIPT_DIR}/evidence"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --days) DAYS="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--days N] [--output DIR]"
            echo "  --days N     Audit period in days (default: 90)"
            echo "  --output DIR Output directory (default: evidence/)"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

DATE=$(date -u +"%Y-%m-%d")
EVIDENCE_DIR="${OUTPUT_DIR}/evidence-${DATE}"
SUMMARY="${EVIDENCE_DIR}/summary.txt"

mkdir -p "$EVIDENCE_DIR"

pass_count=0
fail_count=0
skip_count=0

log_result() {
    local control="$1"
    local status="$2"
    local detail="$3"
    echo "[$status] $control: $detail" >> "$SUMMARY"
    case "$status" in
        PASS) pass_count=$((pass_count + 1)) ;;
        FAIL) fail_count=$((fail_count + 1)) ;;
        SKIP) skip_count=$((skip_count + 1)) ;;
    esac
}

echo "=== Collecting Audit Evidence (${DATE}) ==="
echo "Audit period: ${DAYS} days"
echo ""

cat > "$SUMMARY" <<EOF
Audit Evidence Collection Report
Date: ${DATE}
Audit Period: ${DAYS} days
Collector: $(whoami)@$(hostname)
Repository: ${SCRIPT_DIR}

Controls Evaluated:
EOF

# CC8.1 — Git audit trail
echo "Collecting git audit trail (CC8.1)..."
if git -C "$SCRIPT_DIR" log --since="${DAYS} days ago" \
    --format='"%H","%an","%ae","%aI","%s"' > "$EVIDENCE_DIR/git-audit-trail.csv" 2>/dev/null; then
    commit_count=$(wc -l < "$EVIDENCE_DIR/git-audit-trail.csv")
    log_result "CC8.1 Change Management" "PASS" "Git audit trail: ${commit_count} commits in ${DAYS} days"
else
    log_result "CC8.1 Change Management" "FAIL" "Could not export git log"
fi

# CC7.2 — Nix store integrity
echo "Verifying Nix store integrity (CC7.2)..."
if command -v nix-store &>/dev/null; then
    if nix-store --verify --check-contents 2>"$EVIDENCE_DIR/nix-store-verify.txt"; then
        log_result "CC7.2 Tamper Detection" "PASS" "nix-store --verify passed"
    else
        log_result "CC7.2 Tamper Detection" "FAIL" "nix-store --verify found issues (see nix-store-verify.txt)"
    fi
else
    log_result "CC7.2 Tamper Detection" "SKIP" "nix-store not available"
fi

# CC6.1 — systemd hardening
echo "Collecting systemd hardening config (CC6.1)..."
if systemctl show redpanda --no-pager > "$EVIDENCE_DIR/systemd-hardening.txt" 2>/dev/null; then
    # Check key hardening flags
    local_pass=true
    for flag in NoNewPrivileges ProtectSystem PrivateTmp ProtectHome; do
        if ! grep -q "${flag}=" "$EVIDENCE_DIR/systemd-hardening.txt"; then
            local_pass=false
        fi
    done
    if [ "$local_pass" = true ]; then
        log_result "CC6.1 Least Privilege" "PASS" "systemd hardening flags present"
    else
        log_result "CC6.1 Least Privilege" "FAIL" "Some hardening flags missing"
    fi
else
    log_result "CC6.1 Least Privilege" "SKIP" "redpanda service not running"
fi

# CC7.1 — journald logs
echo "Collecting journald logs (CC7.1)..."
if journalctl -u redpanda --since="${DAYS} days ago" --no-pager > "$EVIDENCE_DIR/journald-redpanda.log" 2>/dev/null; then
    line_count=$(wc -l < "$EVIDENCE_DIR/journald-redpanda.log")
    log_result "CC7.1 Audit Logging" "PASS" "journald: ${line_count} log lines in ${DAYS} days"
else
    log_result "CC7.1 Audit Logging" "SKIP" "No journald logs available (service may not be running)"
fi

# SR-4 — SBOM/provenance artifacts
echo "Collecting SBOM/provenance artifacts (SR-4)..."
if [ -d "${SCRIPT_DIR}/compliance/current" ]; then
    cp -r "${SCRIPT_DIR}/compliance/current" "$EVIDENCE_DIR/compliance-artifacts"
    artifact_count=$(ls "$EVIDENCE_DIR/compliance-artifacts" 2>/dev/null | wc -l)
    log_result "SR-4 Provenance" "PASS" "${artifact_count} compliance artifacts collected"
elif ls "${SCRIPT_DIR}"/compliance/redpanda-*-sbom.json 1>/dev/null 2>&1; then
    mkdir -p "$EVIDENCE_DIR/compliance-artifacts"
    cp "${SCRIPT_DIR}"/compliance/redpanda-*-sbom*.json "$EVIDENCE_DIR/compliance-artifacts/" 2>/dev/null || true
    cp "${SCRIPT_DIR}"/compliance/redpanda-*-provenance.json "$EVIDENCE_DIR/compliance-artifacts/" 2>/dev/null || true
    cp "${SCRIPT_DIR}"/compliance/redpanda-*-vulnerabilities.csv "$EVIDENCE_DIR/compliance-artifacts/" 2>/dev/null || true
    log_result "SR-4 Provenance" "PASS" "Versioned compliance artifacts collected"
else
    log_result "SR-4 Provenance" "FAIL" "No SBOM/provenance artifacts found"
fi

# SR-3 — Dependency closure
echo "Collecting dependency closure (SR-3)..."
if [ -L "${SCRIPT_DIR}/result" ] && command -v nix-store &>/dev/null; then
    nix-store -qR "${SCRIPT_DIR}/result" > "$EVIDENCE_DIR/dependency-closure.txt" 2>/dev/null
    dep_count=$(wc -l < "$EVIDENCE_DIR/dependency-closure.txt")
    log_result "SR-3 Supply Chain Controls" "PASS" "Dependency closure: ${dep_count} store paths"
else
    log_result "SR-3 Supply Chain Controls" "SKIP" "No build result symlink (run 'nix build' first)"
fi

# SC-13 — FIPS status
echo "Checking FIPS status (SC-13)..."
if [ -L "${SCRIPT_DIR}/result-fips" ]; then
    fips_conf="${SCRIPT_DIR}/result-fips/opt/redpanda/openssl/openssl.cnf"
    if [ -f "$fips_conf" ] && grep -q '/nix/store/' "$fips_conf"; then
        grep '\.include' "$fips_conf" > "$EVIDENCE_DIR/fips-status.txt"
        include_path=$(grep '\.include' "$fips_conf" | sed 's/.*\.include //')
        if [ -f "$include_path" ]; then
            log_result "SC-13 FIPS Cryptography" "PASS" "FIPS provider configured and fipsmodule.cnf exists"
        else
            log_result "SC-13 FIPS Cryptography" "FAIL" "fipsmodule.cnf not found at referenced path"
        fi
    else
        log_result "SC-13 FIPS Cryptography" "FAIL" "openssl.cnf does not reference /nix/store/ path"
    fi
else
    log_result "SC-13 FIPS Cryptography" "SKIP" "No FIPS build (run 'nix build .#redpanda-fips --out-link result-fips')"
fi

# Supply chain event log
echo "Collecting supply chain event log..."
if [ -f "${SCRIPT_DIR}/compliance/supply-chain-events.jsonl" ]; then
    cp "${SCRIPT_DIR}/compliance/supply-chain-events.jsonl" "$EVIDENCE_DIR/"
    log_result "SR-5 Event Logging" "PASS" "Supply chain event log present"
else
    log_result "SR-5 Event Logging" "FAIL" "No supply chain event log"
fi

# Write summary footer
cat >> "$SUMMARY" <<EOF

Results: ${pass_count} PASS, ${fail_count} FAIL, ${skip_count} SKIP
Total controls evaluated: $((pass_count + fail_count + skip_count))
EOF

echo ""
echo "=== Evidence Collection Summary ==="
cat "$SUMMARY"
echo ""

# Create tarball
TARBALL="${OUTPUT_DIR}/evidence-${DATE}.tar.gz"
tar -czf "$TARBALL" -C "$OUTPUT_DIR" "evidence-${DATE}"
rm -rf "$EVIDENCE_DIR"

echo "Evidence package: ${TARBALL}"
echo "Size: $(du -h "$TARBALL" | cut -f1)"
