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
  version = "25.2.8";

  src = fetchurl {
    url = "https://github.com/redpanda-data/redpanda/releases/download/v${version}/redpanda-${version}-amd64.tar.gz";
    sha256 = "";
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

    mkdir -p $out/bin
    mkdir -p $out/lib

    # Install binaries
    cp -r opt/redpanda/bin/* $out/bin/

    # Install libraries if they exist
    if [ -d "opt/redpanda/lib" ]; then
      cp -r opt/redpanda/lib/* $out/lib/
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
