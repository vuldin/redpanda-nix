# libxml2-static.nix — Pre-built static libxml2 for Bazel.
#
# Nixpkgs libxml2 ships shared libraries by default. Redpanda's Bazel
# build requires a static libxml2.a (see bazel/thirdparty/libxml2.BUILD).
# This override enables static and disables shared, with zlib support
# (matching the Bazel configure options) and no python/icu/http.
#
# Version is tracked from nixpkgs (currently 2.15.1, close to the pinned
# 2.14.6 in bazel/repositories.bzl — same soname ABI).
{ libxml2, lib }:

assert lib.assertMsg
  (lib.versionAtLeast libxml2.version "2.14" && lib.versionOlder libxml2.version "2.17")
  "libxml2 ${libxml2.version} may be incompatible with Bazel's pinned 2.14.x; check bazel/repositories.bzl";

(libxml2.override {
  enableStatic = true;
  enableShared = false;
  zlibSupport = true;
  pythonSupport = false;
  icuSupport = false;
  enableHttp = false;
}).overrideAttrs {
  # testModule tries to dlopen a shared plugin, which doesn't exist
  # in a static-only build. The upstream tests pass with shared libs.
  doCheck = false;
}
