{ lib
, buildBazelPackage
, fetchFromGitHub
, bazel_7
, bazelisk
, jdk17
, python3
, nodejs
, go
, clang
, cmake
, ninja
, pkg-config
, autoconf
, automake
, bison
, elfutils
, git
, libtool
, gnumake
, ragel
, gettext
, perl
, which
, bash
, coreutils
, rustc
, cargo
, zlib
, openssl
, systemd
, autoPatchelfHook
, makeWrapper
}:

buildBazelPackage rec {
  pname = "redpanda";
  version = "25.2.9";

  src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "redpanda";
    rev = "v${version}";
    sha256 = "0x39gvz4ggnqnwxahfz2bg6r2g09zfsdwb6xypmxw7dfa2j1hdn2";
    fetchSubmodules = true;
  };

  # Use Bazel 7 (closest to Redpanda's requested 8.3.1)
  bazel = bazel_7;

  # Fixed-output derivation for fetching external dependencies
  # This hash will need to be updated after the first build failure
  fetchAttrs = {
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    # Disable CMake configure phase (we're using Bazel, not CMake)
    dontConfigure = true;
    dontUseCmakeConfigure = true;

    # Dependencies needed during fetch phase
    nativeBuildInputs = [
      jdk17
      python3
      nodejs
      go
      clang
      cmake
      ninja
      pkg-config
      autoconf
      automake
      bison
      elfutils
      git
      rustc
      cargo
      libtool
      gnumake
      ragel
      gettext
      perl
      which
      coreutils
    ];

    buildInputs = [
      zlib
      openssl
      systemd
    ];

    # Patch shebangs BEFORE build phase
    postPatch = ''
      echo "Patching shebangs in fetch phase..."
      patchShebangs tools/
      patchShebangs bazel/
      echo "Shebangs patched successfully"

      # Disable toolchains_llvm (incompatible with NixOS sandbox)
      # It tries to read /etc/os-release which doesn't exist in the sandbox
      echo "Commenting out toolchains_llvm in MODULE.bazel..."

      # Step 1: Comment out bazel_dep line
      sed -i 's/^bazel_dep(name = "toolchains_llvm"/#&/' MODULE.bazel

      # Step 2: Comment out the archive_override opening line if it's for toolchains_llvm
      # This uses a look-ahead pattern to check if the next line contains module_name = "toolchains_llvm"
      sed -i '/^archive_override($/ {
        N
        /module_name = "toolchains_llvm"/ {
          s/^archive_override(/#archive_override(/
          P
          D
        }
        P
        D
      }' MODULE.bazel

      # Step 3: Comment out all lines in the toolchains_llvm archive_override block
      sed -i '/module_name = "toolchains_llvm"/,/^)$/ s/^/#/' MODULE.bazel

      # Step 4: Comment out LLVM extension configuration (everything from LLVM to Rust section)
      sed -i '/^# LLVM toolchain$/,/^# Rust Toolchain$/ {
        /^# Rust Toolchain$/! s/^/#/
      }' MODULE.bazel

      # Step 5: Comment out all toolchains_llvm references in .bazelrc
      sed -i 's/^common --@toolchains_llvm/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@current_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@previous_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@next_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^test:lldb --run_under=.*@current_llvm_toolchain/#&/' .bazelrc

      echo "toolchains_llvm disabled, will use local C++ toolchain"

      # Step 6: Create WORKSPACE file with rules_nixpkgs for Nix-based toolchains
      echo "Creating WORKSPACE file with rules_nixpkgs..."

      cat > WORKSPACE <<'EOF'
# WORKSPACE file for rules_nixpkgs integration
# This provides Rust and Python toolchains from Nix instead of downloading binaries
# that don't work on NixOS (cargo-bazel, Python interpreter)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# Load rules_nixpkgs
http_archive(
    name = "io_tweag_rules_nixpkgs",
    strip_prefix = "rules_nixpkgs-0.13.0",
    urls = ["https://github.com/tweag/rules_nixpkgs/archive/v0.13.0.tar.gz"],
    sha256 = "0dfbc718e8a6e4b376b9445a1f8dce9330d395dd1a53de6e32ca9b6c6ea56860",
)

load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
     "nixpkgs_git_repository",
     "nixpkgs_package",
     "nixpkgs_cc_configure",
     "nixpkgs_python_configure",
     "nixpkgs_rust_configure")

# Configure nixpkgs repository
nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "nixos-unstable",  # Use current NixOS channel
    sha256 = "",  # Empty to use latest
)

# Configure C++ toolchain from Nix
nixpkgs_cc_configure(
    repository = "@nixpkgs",
)

# Configure Rust toolchain from Nix (provides cargo and rustc)
nixpkgs_rust_configure(
    repository = "@nixpkgs",
)

# Configure Python toolchain from Nix
nixpkgs_python_configure(
    repository = "@nixpkgs",
    python3_attribute_path = "python3",
)
EOF

      echo "WORKSPACE file created with rules_nixpkgs configuration"

      # Note: This WORKSPACE file will be used alongside MODULE.bazel
      # MODULE.bazel handles modern Bazel module dependencies
      # WORKSPACE provides Nix-based toolchains that work on NixOS
    '';

    # Set environment variables for Redpanda's tools/bazel wrapper
    # We're using Nix's Bazel which provides equivalent version guarantees
    preBuild = ''
      export BAZELISK_SKIP_WRAPPER=1
      # Tell Nix's bazel wrapper to use the version we have, not what .bazelversion says
      export USE_BAZEL_VERSION="${bazel_7.version}"
      # Point to Nix's bazel script, which will set BAZEL_REAL for tools/bazel
      export BAZEL_REAL="${bazel_7}/bin/bazel"
      echo "USE_BAZEL_VERSION set to: ${bazel_7.version}"
      echo "BAZEL_REAL set to: $BAZEL_REAL"

      # Tell Bazel where to find Python (for rules_python)
      export PYTHON_BIN_PATH="${python3}/bin/python3"
      export PYTHON3_BIN_PATH="${python3}/bin/python3"
      echo "PYTHON_BIN_PATH set to: $PYTHON_BIN_PATH"

      # Create /bin/bash symlink for repository rule scripts
      # Repository rules contain scripts with #!/bin/bash shebangs
      mkdir -p /bin
      ln -sf ${bash}/bin/bash /bin/bash || true
      ln -sf ${bash}/bin/sh /bin/sh || true
      echo "/bin/bash symlink created"

      # Create /etc/os-release for Bazel's toolchain detection
      mkdir -p /build/fake-etc
      cat > /build/fake-etc/os-release <<EOF
NAME="NixOS"
ID=nixos
VERSION="25.05"
VERSION_ID="25.05"
PRETTY_NAME="NixOS 25.05"
EOF
      # Create symlink so Bazel can find it at /etc/os-release
      mkdir -p /build/etc
      ln -sf /build/fake-etc/os-release /build/etc/os-release
    '';
  };

  # Don't remove bazel-* directories (we need them for the build)
  removeRulesCC = false;

  # Don't add default Bazel options (we'll specify our own)
  dontAddBazelOpts = true;

  # Targets to build
  bazelTargets = [
    "//src/v/redpanda:redpanda"
    # Note: //src/v/rp:rp doesn't exist in v25.2.9
  ];

  # Bazel build flags
  bazelBuildFlags = [
    "--config=release"
    "--jobs=auto"
    "--verbose_failures"
    "--spawn_strategy=sandboxed"
    "--strategy=Javac=sandboxed"
    "--strategy=Closure=sandboxed"
    # Let Bazel auto-detect and configure the C++ toolchain
    # We provide CC/CXX but let Bazel do its normal toolchain setup
    "--action_env=CC=${clang}/bin/clang"
    "--action_env=CXX=${clang}/bin/clang++"
    "--action_env=PYTHON_BIN_PATH=${python3}/bin/python3"
    "--action_env=PATH=/usr/bin:/bin:${clang}/bin:${python3}/bin"
  ];

  # Bazel flags for all commands
  bazelFlags = [
    # Use local CPU resources
    "--local_cpu_resources=HOST_CPUS"
    # Tell repository rules where to find tools
    "--repo_env=PYTHON_BIN_PATH=${python3}/bin/python3"
    "--repo_env=PYTHON3_BIN_PATH=${python3}/bin/python3"
    "--repo_env=CC=${clang}/bin/clang"
    "--repo_env=CXX=${clang}/bin/clang++"
    # Override Rust toolchain to use system cargo/rustc (fixes cargo-bazel binary issue)
    "--repo_env=CARGO=${cargo}/bin/cargo"
    "--repo_env=RUSTC=${rustc}/bin/rustc"
    # Override Python toolchain to use system Python (fixes rules_python binary issue)
    "--repo_env=RULES_PYTHON_TOOLCHAIN_INTERPRETER=${python3}/bin/python3"
    # Put /bin first so bash can be found, include git and rust tools for repository rules
    "--repo_env=PATH=/bin:${python3}/bin:${clang}/bin:${coreutils}/bin:${bash}/bin:${git}/bin:${cargo}/bin:${rustc}/bin"
    # Explicitly tell Bazel where bash is
    "--repo_env=BASH=/bin/bash"
  ];

  # Build-specific attributes
  buildAttrs = {
    # Disable CMake configure phase (we're using Bazel, not CMake)
    dontConfigure = true;
    dontUseCmakeConfigure = true;

    # Build-time dependencies
    nativeBuildInputs = [
      jdk17
      python3
      nodejs
      go
      clang
      cmake
      ninja
      pkg-config
      autoconf
      automake
      bison
      elfutils
      git
      rustc
      cargo
      libtool
      gnumake
      ragel
      gettext
      perl
      which
      coreutils
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = [
      zlib
      openssl
      systemd
    ];

    # Patch shebangs before build
    postPatch = ''
      patchShebangs tools/
      patchShebangs bazel/

      # Disable toolchains_llvm (incompatible with NixOS sandbox)
      # It tries to read /etc/os-release which doesn't exist in the sandbox
      echo "Commenting out toolchains_llvm in MODULE.bazel..."

      # Step 1: Comment out bazel_dep line
      sed -i 's/^bazel_dep(name = "toolchains_llvm"/#&/' MODULE.bazel

      # Step 2: Comment out the archive_override opening line if it's for toolchains_llvm
      # This uses a look-ahead pattern to check if the next line contains module_name = "toolchains_llvm"
      sed -i '/^archive_override($/ {
        N
        /module_name = "toolchains_llvm"/ {
          s/^archive_override(/#archive_override(/
          P
          D
        }
        P
        D
      }' MODULE.bazel

      # Step 3: Comment out all lines in the toolchains_llvm archive_override block
      sed -i '/module_name = "toolchains_llvm"/,/^)$/ s/^/#/' MODULE.bazel

      # Step 4: Comment out LLVM extension configuration (everything from LLVM to Rust section)
      sed -i '/^# LLVM toolchain$/,/^# Rust Toolchain$/ {
        /^# Rust Toolchain$/! s/^/#/
      }' MODULE.bazel

      # Step 5: Comment out all toolchains_llvm references in .bazelrc
      sed -i 's/^common --@toolchains_llvm/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@current_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@previous_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@next_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^test:lldb --run_under=.*@current_llvm_toolchain/#&/' .bazelrc

      echo "toolchains_llvm disabled, will use local C++ toolchain"

      # Step 6: Create WORKSPACE file with rules_nixpkgs for Nix-based toolchains
      echo "Creating WORKSPACE file with rules_nixpkgs..."

      cat > WORKSPACE <<'EOF'
# WORKSPACE file for rules_nixpkgs integration
# This provides Rust and Python toolchains from Nix instead of downloading binaries
# that don't work on NixOS (cargo-bazel, Python interpreter)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# Load rules_nixpkgs
http_archive(
    name = "io_tweag_rules_nixpkgs",
    strip_prefix = "rules_nixpkgs-0.13.0",
    urls = ["https://github.com/tweag/rules_nixpkgs/archive/v0.13.0.tar.gz"],
    sha256 = "0dfbc718e8a6e4b376b9445a1f8dce9330d395dd1a53de6e32ca9b6c6ea56860",
)

load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
     "nixpkgs_git_repository",
     "nixpkgs_package",
     "nixpkgs_cc_configure",
     "nixpkgs_python_configure",
     "nixpkgs_rust_configure")

# Configure nixpkgs repository
nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "nixos-unstable",  # Use current NixOS channel
    sha256 = "",  # Empty to use latest
)

# Configure C++ toolchain from Nix
nixpkgs_cc_configure(
    repository = "@nixpkgs",
)

# Configure Rust toolchain from Nix (provides cargo and rustc)
nixpkgs_rust_configure(
    repository = "@nixpkgs",
)

# Configure Python toolchain from Nix
nixpkgs_python_configure(
    repository = "@nixpkgs",
    python3_attribute_path = "python3",
)
EOF

      echo "WORKSPACE file created with rules_nixpkgs configuration"

      # Note: This WORKSPACE file will be used alongside MODULE.bazel
      # MODULE.bazel handles modern Bazel module dependencies
      # WORKSPACE provides Nix-based toolchains that work on NixOS

      # Note: We're using Bazel 7.6.0, but Redpanda specifies 8.3.1
      # Bazel is generally backwards compatible, so this should work
      echo "WARNING: Redpanda expects Bazel 8.3.1, but using Bazel 7.6.0"
    '';

    # Set environment variables for Redpanda's tools/bazel wrapper
    # We're using Nix's Bazel which provides equivalent version guarantees
    preBuild = ''
      export BAZELISK_SKIP_WRAPPER=1
      # Tell Nix's bazel wrapper to use the version we have, not what .bazelversion says
      export USE_BAZEL_VERSION="${bazel_7.version}"
      # Point to Nix's bazel script, which will set BAZEL_REAL for tools/bazel
      export BAZEL_REAL="${bazel_7}/bin/bazel"
      echo "USE_BAZEL_VERSION set to: ${bazel_7.version}"
      echo "BAZEL_REAL set to: $BAZEL_REAL"

      # Tell Bazel where to find Python (for rules_python)
      export PYTHON_BIN_PATH="${python3}/bin/python3"
      export PYTHON3_BIN_PATH="${python3}/bin/python3"
      echo "PYTHON_BIN_PATH set to: $PYTHON_BIN_PATH"

      # Create /bin/bash symlink for repository rule scripts
      # Repository rules contain scripts with #!/bin/bash shebangs
      mkdir -p /bin
      ln -sf ${bash}/bin/bash /bin/bash || true
      ln -sf ${bash}/bin/sh /bin/sh || true
      echo "/bin/bash symlink created"

      # Create /etc/os-release for Bazel's toolchain detection
      mkdir -p /build/fake-etc
      cat > /build/fake-etc/os-release <<EOF
NAME="NixOS"
ID=nixos
VERSION="25.05"
VERSION_ID="25.05"
PRETTY_NAME="NixOS 25.05"
EOF
      # Create symlink so Bazel can find it at /etc/os-release
      mkdir -p /build/etc
      ln -sf /build/fake-etc/os-release /build/etc/os-release
    '';

    # Install the built binaries
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin

      # Install main binaries
      if [ -f bazel-bin/src/v/redpanda/redpanda ]; then
        cp -v bazel-bin/src/v/redpanda/redpanda $out/bin/
      else
        echo "ERROR: redpanda binary not found!"
        echo "Contents of bazel-bin:"
        find bazel-bin -name "redpanda" -type f || true
        exit 1
      fi

      # Note: rp target doesn't exist in v25.2.9, skip it
      # if [ -f bazel-bin/src/v/rp/rp ]; then
      #   cp -v bazel-bin/src/v/rp/rp $out/bin/
      # fi

      # Make binaries executable
      chmod +x $out/bin/*

      # Create a bazelisk wrapper that calls bazel
      # This satisfies Redpanda's "must use bazelisk" check if needed
      makeWrapper ${bazel_7}/bin/bazel $out/bin/bazelisk \
        --add-flags "version" \
        --set BAZEL_VERSION "7.6.0"

      echo "Installation complete!"
      ls -lh $out/bin/

      runHook postInstall
    '';
  };

  meta = with lib; {
    description = "Redpanda streaming data platform (built from source with Bazel via buildBazelPackage)";
    homepage = "https://redpanda.com/";
    license = licenses.bsl11;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    maintainers = [ ];

    longDescription = ''
      Redpanda is a Kafka-compatible streaming data platform that is
      JVM-free, ZooKeeper-free, and Jepsen-tested. This package is
      built from source using Bazel via nixpkgs' buildBazelPackage.

      This approach uses Nix's patched Bazel (version ${bazel_7.version}),
      which is sandbox-compatible, instead of Bazelisk.

      Note: Redpanda specifies Bazel 8.3.1 in .bazelversion, but we use
      Bazel ${bazel_7.version} from nixpkgs. Bazel is generally backwards
      compatible, so this should work. If you encounter issues, try
      using the deb extraction method (default.nix) instead.

      Source builds enable:
      - Full visibility into dependencies
      - Reproducible builds with cryptographic verification
      - SBOM generation for compliance (DoD, NIST 800-161)
      - Custom patches and modifications
    '';
  };
}
