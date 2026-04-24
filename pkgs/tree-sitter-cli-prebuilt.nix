# Tree-sitter CLI, prebuilt from upstream GitHub releases.
#
# nvim-treesitter's `main` branch health check hard-requires CLI >= v0.26.1,
# but nixpkgs still ships 0.25.10 (no PR bumping it yet). Upstream publishes
# prebuilt, statically-dispatched binaries, so we just grab those rather than
# re-bootstrap the rust build.
#
# Declared as a standalone package with pname `tree-sitter` so it shadows
# nixpkgs's older version on PATH when listed first in home.packages.
{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  stdenvNoCC,
}:

let
  version = "0.26.8";
  sources = {
    "aarch64-darwin" = {
      suffix = "macos-arm64";
      hash = "sha256-Ak4s7jRyNSTWLUG95NK0ryPIu+AjbhFsecCzfZV1iJ4=";
    };
    "x86_64-darwin" = {
      suffix = "macos-x64";
      hash = "sha256-0NqieQVMHRztsI9cp4S0Uc6x8Oawg7ES0HMXlYrnf+A=";
    };
    "aarch64-linux" = {
      suffix = "linux-arm64";
      hash = "sha256-4znWUzsggw3RZm/jIK/4XTAbP1mWSjg2hwt39IJ/mhc=";
    };
    "x86_64-linux" = {
      suffix = "linux-x64";
      hash = "sha256-l1SjKADwuXAVJ4LfF3tKR8cR405lGnrOs4TYvSn6E24=";
    };
  };
  platform =
    sources.${stdenv.hostPlatform.system}
      or (throw "tree-sitter-cli-prebuilt: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "tree-sitter";
  inherit version;

  src = fetchurl {
    url = "https://github.com/tree-sitter/tree-sitter/releases/download/v${version}/tree-sitter-${platform.suffix}.gz";
    inherit (platform) hash;
  };

  dontUnpack = true;

  # Linux binaries are dynamically linked against upstream-build-env glibc
  # and libgcc_s; patch them to nixpkgs's interpreter and point auto-patchelf
  # at stdenv.cc.cc.lib for libgcc_s.so.1. Darwin binaries use stable
  # libSystem so they don't need touching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ (lib.getLib stdenv.cc.cc) ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    gunzip -c $src > $out/bin/tree-sitter
    chmod +x $out/bin/tree-sitter
    runHook postInstall
  '';

  meta = {
    description = "Tree-sitter CLI (prebuilt upstream release, for nvim-treesitter main branch)";
    homepage = "https://github.com/tree-sitter/tree-sitter";
    license = lib.licenses.mit;
    mainProgram = "tree-sitter";
    platforms = lib.attrNames sources;
  };
}
