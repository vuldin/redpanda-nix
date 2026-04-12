# GitHub Actions Workflows

This directory contains automated workflows for the Redpanda NixOS package.

## Workflows

### 1. Update Redpanda (`update-redpanda.yml`)

**Purpose**: Automatically check for new Redpanda releases and create pull requests with updated packages.

**Triggers**:
- **Scheduled**: Runs weekly on Monday at 9 AM UTC
- **Manual**: Can be triggered via workflow_dispatch with optional version input

**What it does**:
1. Checks GitHub API for latest Redpanda release
2. Compares with current version in `deb.nix`
3. If update available:
   - Runs `update.sh` to generate new package
   - Generates compliance artifacts (SBOM, provenance, vulnerability scan)
   - Builds package to verify it works
   - Creates a new branch `update-redpanda-{version}`
   - Commits changes
   - Opens a pull request with detailed changelog
   - Adds compliance artifact summary as PR comment

**Compliance Features**:
- ✅ Automated SBOM generation (CycloneDX + SPDX)
- ✅ SLSA v1.0 provenance attestation
- ✅ Vulnerability scanning (CVE detection)
- ✅ All artifacts committed to `compliance/` directory

**Manual Trigger**:
```bash
# Via GitHub UI: Actions → Update Redpanda Package → Run workflow
# Optionally specify version (e.g., "25.2.8")
```

**Permissions Required**:
- `contents: write` - To commit changes
- `pull-requests: write` - To create PRs

---

### 2. CI (`ci.yml`)

**Purpose**: Continuous integration testing for all commits and pull requests.

**Triggers**:
- **Push**: To `main` or `master` branches
- **Pull Request**: Against `main` or `master` branches

**Jobs**:

#### `check-formatting`
- Validates Nix flake structure
- Runs `nix flake check`
- Checks formatting (if configured)

#### `build-x86_64`
- Builds Redpanda package for x86_64-linux
- Verifies binary outputs (redpanda, rpk)
- Tests basic functionality

#### `build-examples`
- Validates all example configurations
- Ensures examples are syntactically correct
- Checks NixOS module syntax

#### `check-compliance`
- Verifies compliance artifacts exist (for PRs)
- Checks for SBOM files (CycloneDX, SPDX)
- Checks for SLSA provenance
- Checks for vulnerability scans
- Lists all compliance artifacts

#### `documentation-check`
- Ensures required documentation exists
- Checks for broken links in README
- **CRITICAL**: Verifies dev examples have compliance warnings
- **CRITICAL**: Verifies TLS example is marked PRODUCTION

#### `compliance-status`
- Extracts compliance framework table from README
- Displays current compliance scores in PR

#### `summary`
- Aggregates all job results
- Provides pass/fail summary

---

## Configuration

### Secrets Required

None! These workflows use `GITHUB_TOKEN` which is automatically provided.

### Customization

#### Change Update Schedule

Edit `update-redpanda.yml`:
```yaml
schedule:
  - cron: '0 9 * * 1'  # Weekly on Monday at 9 AM UTC
  # Change to: '0 9 * * *' for daily
```

#### Change Branch Names

Edit `update-redpanda.yml`:
```yaml
BRANCH_NAME="update-redpanda-${{ needs.check-update.outputs.new_version }}"
# Change prefix: "auto-update-redpanda-..."
```

#### Add More Architectures

When ARM64 runners become available, add to `ci.yml`:
```yaml
build-aarch64:
  runs-on: ubuntu-latest-arm64  # Future
  steps:
    # Same as build-x86_64
```

---

## Compliance Integration

These workflows satisfy:

| Requirement | Implementation |
|-------------|----------------|
| **NIST SP 800-161** (SR-3) | Automated SBOM generation with every update |
| **NIST SP 800-161** (SR-4) | SLSA v1.0 provenance for supply chain tracking |
| **DoD SBOM Management** | CycloneDX and SPDX formats generated |
| **NIST CSF 2.0** (GV.SC-10) | Automated vulnerability monitoring |
| **SOC 2** (CC8.1) | Change management with audit trail (git history) |

---

## Troubleshooting

### Workflow fails with "nix command not found"

Check that `cachix/install-nix-action` is using the correct version:
```yaml
- uses: cachix/install-nix-action@v25
```

### Update workflow creates PR but no compliance artifacts

Check `update.sh` runs successfully:
1. Ensure `sbomnix` can be installed via `nix profile`
2. Check that package builds before compliance generation
3. Look for errors in "Run update script" step

### CI fails on example validation

Examples are NixOS modules and require NixOS-specific evaluation. The CI
gracefully skips NixOS-specific checks on Ubuntu runners.

### Documentation check fails

Ensure dev examples have compliance warnings:
```nix
# ⚠️  WARNING: NO TLS ENCRYPTION - NOT COMPLIANT FOR PRODUCTION
```

And TLS example has production marker:
```nix
# (PRODUCTION)
```

---

## Testing Locally

### Test Update Workflow

```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Run update script
./update.sh

# Build package
nix build
```

### Test CI Checks

```bash
# Check flake
nix flake check --show-trace

# Build package
nix build --show-trace

# Validate examples (basic syntax check)
for f in examples/*.nix; do
  nix-instantiate --parse "$f" > /dev/null && echo "✅ $f"
done
```

---

## GitHub Actions Badge

Add to README.md:

```markdown
[![CI](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci.yml)
[![Update Redpanda](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/update-redpanda.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/update-redpanda.yml)
```

---

## Future Enhancements

Potential improvements:
- [ ] Add cachix for faster Nix builds
- [ ] Add multi-architecture builds (ARM64) when runners available
- [ ] Add NixOS VM tests for module validation
- [ ] Add Dependabot for GitHub Actions version updates
- [ ] Add security scanning (Snyk, GitHub CodeQL)
- [ ] Add changelog generation from git commits

---

**Last Updated**: 2025-10-10
**Maintained By**: Automated workflows + manual review
