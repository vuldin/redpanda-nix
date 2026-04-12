# Minimal OCI container image for Redpanda.
# Produces a stream script (pipe to `docker load`) rather than a tarball.
# ~313 MB minimal, ~327 MB with debug tools (bash/coreutils).
#
# Usage:
#   nix build .#redpanda-image && ./result | docker load
#   docker run -p 9092:9092 -p 9644:9644 redpanda:nix
#
# Adapted from https://github.com/redpanda-data/redpanda/pull/29919
# by randomizedcoder.
{
  lib,
  dockerTools,
  cacert,
  tzdata,
  bash,
  coreutils,
  redpandaDrv,
  debug ? false,
}:

dockerTools.streamLayeredImage {
  name = "redpanda";
  tag = let
    version = redpandaDrv.version or "unknown";
  in "${version}${if debug then "-debug" else ""}";
  maxLayers = 120;

  contents =
    [
      redpandaDrv
      cacert
      tzdata
    ]
    ++ lib.optionals debug [
      bash
      coreutils
    ];

  fakeRootCommands = ''
    mkdir -p ./var/lib/redpanda/data
    mkdir -p ./etc/redpanda
  '';

  config = {
    Entrypoint = [
      "${redpandaDrv}/bin/redpanda"
      "--redpanda-cfg=${redpandaDrv}/etc/redpanda/redpanda.yaml"
    ];
    Cmd = [
      "--default-log-level=info"
      "--smp=1"
    ];
    ExposedPorts = {
      "9092/tcp" = { };   # Kafka API
      "9644/tcp" = { };   # Admin API
      "33145/tcp" = { };  # Internal RPC
      "8082/tcp" = { };   # Pandaproxy (REST)
      "8081/tcp" = { };   # Schema Registry
    };
    Env = [
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
    Volumes = {
      "/var/lib/redpanda/data" = { };
    };
  };
}
