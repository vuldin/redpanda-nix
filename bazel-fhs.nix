# Bazel build using FHS environment to handle binary compatibility
# This solves the cargo-bazel and rules_python downloaded binary issues

{ lib
, stdenv
, buildFHSEnv
, fetchFromGitHub
, bazel_7
, jdk17
, python3
, nodejs
, go
, clang
, gcc
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
, glibc
, autoPatchelfHook
, makeWrapper
}:

let
  version = "25.2.9";

  src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "redpanda";
    rev = "v${version}";
    sha256 = "0x39gvz4ggnqnwxahfz2bg6r2g09zfsdwb6xypmxw7dfa2j1hdn2";
    fetchSubmodules = true;
  };

  # Create an FHS environment for Bazel to run in
  # This provides /lib, /usr/lib structure that downloaded binaries expect
  bazelFHS = buildFHSEnv {
    name = "bazel-fhs-redpanda";
    targetPkgs = pkgs: [
      bazel_7
      jdk17
      python3
      nodejs
      go
      clang
      gcc
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
      bash
      coreutils
      zlib
      openssl
      systemd
      glibc
      stdenv.cc.cc.lib
    ];
    multiPkgs = pkgs: [ zlib stdenv.cc.cc.lib ];

    # This script will be run inside the FHS environment
    runScript = writeShellScript "build-redpanda.sh" ''
      set -e

      # Copy source to writable location
      cp -r ${src} ./source
      chmod -R u+w ./source
      cd ./source

      # Patch shebangs
      patchShebangs tools/ bazel/

      # Disable toolchains_llvm (incompatible with Nix sandbox)
      echo "Patching MODULE.bazel..."
      sed -i 's/^bazel_dep(name = "toolchains_llvm"/#&/' MODULE.bazel
      sed -i '/^archive_override(/,/module_name = "toolchains_llvm"/ {
        /module_name = "toolchains_llvm"/! s/^/#/
      }' MODULE.bazel
      sed -i '/module_name = "toolchains_llvm"/,/^)$/ s/^/#/' MODULE.bazel
      sed -i '/^# LLVM toolchain$/,/^# Rust Toolchain$/ {
        /^# Rust Toolchain$/! s/^/#/
      }' MODULE.bazel

      # Patch .bazelrc
      sed -i 's/^common --@toolchains_llvm/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@current_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@previous_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^common --extra_toolchains=@next_llvm_toolchain/#&/' .bazelrc
      sed -i 's/^test:lldb --run_under=.*@current_llvm_toolchain/#&/' .bazelrc

      echo "Building with Bazel in FHS environment..."
      bazel build //src/v/redpanda:redpanda \
        --config=release \
        --jobs=auto \
        --verbose_failures \
        --action_env=CC=${clang}/bin/clang \
        --action_env=CXX=${clang}/bin/clang++ \
        --action_env=PYTHON_BIN_PATH=${python3}/bin/python3

      echo "Build completed successfully!"
      ls -la bazel-bin/src/v/redpanda/
    '';
  };
in

stdenv.mkDerivation {
  pname = "redpanda";
  inherit version src;

  nativeBuildInputs = [
    bazelFHS
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    zlib
    openssl
    systemd
    stdenv.cc.cc.lib
  ];

  buildPhase = ''
    echo "Running Bazel build in FHS environment..."
    ${bazelFHS}/bin/bazel-fhs-redpanda
  '';

  installPhase = ''
    echo "Installing redpanda binary..."
    mkdir -p $out/bin
    # TODO: Copy binary from bazel-bin after build completes
    echo "Installation phase - need to extract binary from FHS build"
  '';

  meta = with lib; {
    description = "Redpanda - Kafka API compatible streaming platform";
    homepage = "https://redpanda.com";
    license = licenses.bsl11;
    platforms = platforms.linux;
  };
}
