# Standalone rpk CLI build via buildGoModule.
# Independent from the Bazel C++ server build — builds only the Go CLI.
# Version and hashes are updated by scripts/update.sh.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
}:

let
  # Updated by scripts/update.sh — must match a tagged release
  version = "26.1.9";
  rev = "v${version}";
in
buildGoModule {
  pname = "redpanda-rpk";
  inherit version;

  src = fetchFromGitHub {
    owner = "redpanda-data";
    repo = "redpanda";
    inherit rev;
    hash = "sha256-UrrFK4VjnovSH1ahmQPaKM/uZP0BA35ckvN4ELnfG10=";
  };

  modRoot = "src/go/rpk";

  # To update: change version above, then run:
  #   nix build .#redpanda-rpk 2>&1 | grep "got:"
  # and replace this hash with the "got:" value.
  vendorHash = "sha256-UrrFK4VjnovSH1ahmQPaKM/uZP0BA35ckvN4ELnfG10=";

  ldflags =
    let
      versionPkg = "github.com/redpanda-data/redpanda/src/go/rpk/pkg/cli/version";
      containerPkg = "github.com/redpanda-data/redpanda/src/go/rpk/pkg/cli/container/containerutil";
    in
    [
      "-s" "-w"
      "-X ${versionPkg}.version=${version}"
      "-X ${versionPkg}.rev=${rev}"
      "-X ${containerPkg}.tag=v${version}"
    ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    for shell in bash fish zsh; do
      $out/bin/rpk generate shell-completion $shell > rpk.$shell
      installShellCompletion rpk.$shell
    done
  '';

  # Network-dependent tests cannot run in the Nix sandbox
  doCheck = false;

  meta = {
    description = "Redpanda CLI (rpk) — Kafka-compatible streaming platform management tool";
    homepage = "https://redpanda.com/";
    license = lib.licenses.bsl11;
    platforms = lib.platforms.linux;
    mainProgram = "rpk";
  };
}
