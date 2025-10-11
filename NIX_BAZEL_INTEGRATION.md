# Nix + Bazel Integration for Redpanda
## Combining Reproducible Builds with Incremental Compilation

**Document Version**: 1.0
**Last Updated**: 2025-10-10
**Reference**: https://nix-bazel.build/

---

## Overview

**Nix + Bazel** is a powerful combination for building Redpanda from source, especially when you need:
- Reproducible builds (Nix strength)
- Incremental compilation (Bazel strength)
- Fine-grained build caching
- Multi-language support (C++, Go, etc.)

**Use Case for This Project**: While the current Redpanda NixOS package uses pre-built binaries from GitHub releases, **Nix + Bazel would enable building Redpanda from source** for:
1. **FIPS compliance** - Building with FIPS-validated libraries
2. **Custom patches** - Applying organization-specific modifications
3. **Reproducible development** - Consistent dev environments across teams
4. **Faster iteration** - Incremental rebuilds during development

---

## What is Nix + Bazel?

### Bazel
- Multi-language build system with **incremental** and **remote** builds
- Fine-grained dependency tracking (rebuilds only what changed)
- Hermetic builds with strict sandboxing
- Used by Google, Uber, Dropbox for monorepo builds

### Nix
- **Package manager** and **configuration language**
- Access to **nixpkgs** - one of the largest package registries
- Fully reproducible builds
- Isolated environments without internet access during build

### Combined Benefits

| Feature | Bazel Alone | Nix Alone | **Nix + Bazel** |
|---------|-------------|-----------|-----------------|
| **Incremental builds** | ✅ Excellent | ❌ Poor | ✅ **Best of both** |
| **Reproducibility** | 🟡 Good | ✅ Excellent | ✅ **Excellent** |
| **Package management** | ❌ Manual | ✅ Excellent | ✅ **Excellent** |
| **Dev environment** | 🟡 Manual setup | ✅ Automatic | ✅ **Automatic** |
| **Build caching** | ✅ Excellent | 🟡 Coarse | ✅ **Fine-grained** |
| **Multi-language** | ✅ Excellent | 🟡 Good | ✅ **Excellent** |

---

## Why Consider Nix + Bazel for Redpanda?

### Scenario 1: Building Redpanda from Source (FIPS)

**Challenge**: FedRAMP High requires FIPS 140-2 validated cryptography. While Redpanda provides `redpanda-fips` packages, you may need to:
- Verify the FIPS build yourself
- Apply custom patches while maintaining FIPS compliance
- Build with specific FIPS-validated library versions

**Solution**: Use Nix + Bazel to build Redpanda from source

```nix
# default.nix - Build Redpanda from source with Nix + Bazel
{ pkgs ? import <nixpkgs> {}
, useFips ? false
}:

let
  # Bazel installed via Nix
  bazel = pkgs.bazel_6;

  # FIPS-validated dependencies
  openssl-fips = pkgs.openssl.override { enableFips = true; };

in pkgs.stdenv.mkDerivation rec {
  pname = "redpanda-from-source${if useFips then "-fips" else ""}";
  version = "25.2.8";

  src = pkgs.fetchFromGitHub {
    owner = "redpanda-data";
    repo = "redpanda";
    rev = "v${version}";
    sha256 = "...";
  };

  nativeBuildInputs = [
    bazel
    pkgs.python3
    pkgs.git
  ];

  buildInputs = [
    pkgs.zlib
    pkgs.systemd
  ] ++ pkgs.lib.optionals useFips [
    openssl-fips
  ];

  # Configure Bazel to use Nix-provided dependencies
  preConfigure = ''
    # Create .bazelrc for Nix integration
    cat > .bazelrc.local <<EOF
    # Use Nix-provided C++ toolchain
    build --action_env=CC=${pkgs.stdenv.cc}/bin/cc
    build --action_env=CXX=${pkgs.stdenv.cc}/bin/c++

    # Use Nix-provided libraries
    build --action_env=CPATH=${pkgs.lib.makeSearchPath "include" buildInputs}
    build --action_env=LIBRARY_PATH=${pkgs.lib.makeSearchPath "lib" buildInputs}

    # FIPS mode flags
    ${pkgs.lib.optionalString useFips ''
      build --copt=-DOPENSSL_FIPS
      build --linkopt=-L${openssl-fips}/lib
    ''}

    # Sandboxing configuration
    build --spawn_strategy=local
    build --strategy=Javac=local
    build --strategy=Closure=local
    EOF
  '';

  buildPhase = ''
    # Bazel build with Nix environment
    bazel build //src/v/redpanda:redpanda \
      --verbose_failures \
      --sandbox_debug \
      --config=release

    # Build rpk CLI
    bazel build //src/go/rpk:rpk
  '';

  installPhase = ''
    mkdir -p $out/bin

    # Copy Bazel build outputs
    cp bazel-bin/src/v/redpanda/redpanda $out/bin/
    cp bazel-bin/src/go/rpk/rpk $out/bin/

    # Verify FIPS if enabled
    ${pkgs.lib.optionalString useFips ''
      # Check that binary links to FIPS OpenSSL
      if ! ldd $out/bin/redpanda | grep -q ${openssl-fips}; then
        echo "ERROR: redpanda not linked to FIPS OpenSSL"
        exit 1
      fi
    ''}
  '';

  meta = with pkgs.lib; {
    description = "Redpanda built from source with Bazel";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
```

### Scenario 2: Redpanda Development Environment

**Challenge**: Developers need consistent C++, Go, Python toolchains plus Redpanda dependencies

**Solution**: Nix provides the environment, Bazel handles the build

```nix
# flake.nix - Development environment
{
  description = "Redpanda development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Bazel build system
            bazel_6
            bazelisk  # Bazel version manager

            # Redpanda dependencies
            clang_16
            llvmPackages_16.libcxx
            cmake
            ninja
            pkg-config

            # Languages
            go_1_21
            python311
            nodejs_20

            # Tools
            git
            ripgrep
            jq

            # FIPS (optional)
            (openssl.override { enableFips = true; })
          ];

          shellHook = ''
            echo "Redpanda development environment loaded"
            echo "Bazel version: $(bazel version | head -1)"
            echo "Go version: $(go version)"
            echo "Clang version: $(clang --version | head -1)"

            # Configure Bazel to use Nix dependencies
            export CC=${pkgs.clang_16}/bin/clang
            export CXX=${pkgs.clang_16}/bin/clang++

            echo ""
            echo "Ready to build Redpanda:"
            echo "  bazel build //src/v/redpanda:redpanda"
          '';
        };

        # Optional: Provide Bazel as a package
        packages.bazel = pkgs.bazel_6;
      }
    );
}
```

**Usage**:
```bash
# Enter dev environment
nix develop

# Build Redpanda
bazel build //src/v/redpanda:redpanda

# Incremental rebuild (only changed files)
# Make a code change...
bazel build //src/v/redpanda:redpanda
# ✅ Much faster than full nix-build
```

---

## Integration with rules_nixpkgs

For tighter Bazel-Nix integration, use **rules_nixpkgs**:

```python
# WORKSPACE - Bazel workspace configuration
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# Load rules_nixpkgs
http_archive(
    name = "io_tweag_rules_nixpkgs",
    url = "https://github.com/tweag/rules_nixpkgs/archive/v0.11.1.tar.gz",
    sha256 = "...",
    strip_prefix = "rules_nixpkgs-0.11.1",
)

load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_local_repository", "nixpkgs_package")

# Use local nixpkgs
nixpkgs_local_repository(
    name = "nixpkgs",
    nix_file = "//:nixpkgs.nix",
)

# Import specific packages from Nix
nixpkgs_package(
    name = "openssl",
    repository = "@nixpkgs",
    nix_file_content = """
      with import <nixpkgs> {};
      openssl.override { enableFips = true; }
    """,
)

nixpkgs_package(
    name = "zlib",
    repository = "@nixpkgs",
)
```

**Benefits**:
- Bazel can directly use Nix packages
- Ensures exact same dependencies in Bazel and Nix builds
- Simplifies WORKSPACE file (no manual dependency management)

---

## When to Use Nix + Bazel vs. Pure Nix

### Use Pure Nix (Current Approach) When:
✅ **Packaging pre-built binaries** (current Redpanda package)
✅ **Simple updates** (just new version + hash)
✅ **System integration focus** (NixOS module, systemd service)
✅ **Reproducibility is primary goal**

**Example**: Current `update.sh` + `default.nix` workflow

### Use Nix + Bazel When:
✅ **Building from source** (FIPS requirements)
✅ **Active development** (incremental builds save hours)
✅ **Custom patches** (need to rebuild frequently)
✅ **Large C++ projects** (Bazel excels at C++ builds)
✅ **Multi-language repos** (C++, Go, Python in one build)

**Example**: Building Redpanda from source with FIPS-validated libraries

---

## Implementation Roadmap

### Phase 1: Evaluation (Week 1-2)

**Goal**: Determine if Nix + Bazel is worth the complexity

**Actions**:
1. Clone Redpanda repo: `git clone https://github.com/redpanda-data/redpanda`
2. Review `WORKSPACE` and `BUILD.bazel` files
3. Estimate build time with Bazel vs. Nix
4. **Decision**: If FIPS source builds are required, proceed. Otherwise, stick with current binary approach.

### Phase 2: Proof of Concept (Week 3-4)

**Goal**: Build Redpanda with Nix + Bazel

**Actions**:
1. Create `shell.nix` or `flake.nix` dev environment
2. Configure Bazel to use Nix-provided dependencies
3. Build: `nix develop --command bazel build //src/v/redpanda:redpanda`
4. Verify binary works

### Phase 3: Integration (Month 2)

**Goal**: Integrate into existing NixOS module

**Actions**:
1. Add `buildFromSource` option to NixOS module
2. Update `default.nix` to support both binary and source builds
3. Add CI/CD for source builds
4. Document build process

### Phase 4: FIPS Validation (Month 3)

**Goal**: Build FIPS-compliant Redpanda from source

**Actions**:
1. Build with FIPS OpenSSL: `useFips = true`
2. Verify FIPS module loading
3. Test cryptographic operations
4. Document for FedRAMP compliance

---

## Limitations and Considerations

### Supported Platforms
- ✅ **Linux**: Full support
- ✅ **macOS**: Full support
- ❌ **Windows**: Not supported

### Current Limitations (from nix-bazel.build)
- **Limited language toolchain support**: Some languages may require additional configuration
- **Bazel remote execution not supported**: Cannot use remote build clusters (yet)
- **Experimental**: Nix + Bazel integration is still evolving

### Build Time Comparison

**Initial Build**:
- Pure Nix (from source): 30-60 minutes (all dependencies)
- Nix + Bazel (from source): 30-60 minutes (first time)

**Incremental Rebuild (1 file changed)**:
- Pure Nix: 30-60 minutes (rebuilds everything)
- **Nix + Bazel**: 1-5 minutes ✅ **Huge improvement**

**Decision**: Use Nix + Bazel if you're doing **active development** or **frequent custom builds**.

---

## Conclusion

### For This Project (Redpanda NixOS Package)

**Current Approach (Recommended for Most Users)**:
- ✅ Use pre-built Redpanda binaries from GitHub releases
- ✅ Simple `update.sh` + `default.nix` workflow
- ✅ Fast deployment (no compilation)
- ✅ Works for 95% of use cases

**Nix + Bazel Approach (Recommended for FedRAMP/FIPS)**:
- ✅ Build from source with FIPS-validated libraries
- ✅ Incremental builds for development
- ✅ Complete control over build process
- ✅ Necessary for **FedRAMP High compliance** if building from source

**Recommendation**:
1. **Default**: Use current binary-based approach (documented in README.md)
2. **FIPS/FedRAMP**: Add optional source build support with Nix + Bazel (see [REDPANDA_FIPS_NIXOS.md](./REDPANDA_FIPS_NIXOS.md))
3. **Development**: Provide `devShells.bazel` in flake.nix for contributors

---

## Resources

- **Official Documentation**: https://nix-bazel.build/
- **rules_nixpkgs**: https://github.com/tweag/rules_nixpkgs
- **Redpanda Source**: https://github.com/redpanda-data/redpanda
- **Bazel Documentation**: https://bazel.build/
- **Nix Manual**: https://nixos.org/manual/nix/stable/

---

**Document Version**: 1.0
**Last Updated**: 2025-10-10
**Next Steps**: Evaluate if FIPS source builds are required for your deployment
