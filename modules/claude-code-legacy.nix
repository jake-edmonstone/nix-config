{ pkgs, lib, ... }:

# Claude Code CLI pinned to the last pure-JS release (v2.1.112, Feb 2026).
#
# Starting v2.1.113 Anthropic switched claude to a Bun-compiled single-file
# native ELF (~100 MB). The Bun binary's TTY/setRawMode/DSR handling
# deadlocks under nix-portable's proot runtime — see research notes at the
# top of home/uwaterloo.nix. v2.1.112 is the last version that ships a
# plain Node.js cli.js with zero runtime dependencies (only optional image
# deps we skip), making it safe to run under any Node.
#
# Wrapper hardcodes env escape hatches that help under proot:
#   DISABLE_AUTOUPDATER — keeps the in-process updater from silently
#     upgrading us back to a broken Bun build
#   UV_USE_IO_URING=0  — forces libuv to use epoll; io_uring syscalls
#     pass through proot unregistered and can deadlock
#   CLAUDE_CODE_DISABLE_MOUSE — suppresses mouse-capture escape sequences
#     (belt-and-suspenders; not sufficient alone but cheap)

let
  version = "2.1.112";

  claude-code-legacy = pkgs.stdenv.mkDerivation {
    pname = "claude-code-legacy";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      hash = "sha256-hDeZaepToOX9IxqPd96+THyxfdlx9ICdENM/muyl3gk=";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    # Skip stdenv's default unpackPhase — it does `chmod -R u+w` on the
    # unpacked tree which fails under nix-portable's proot runtime
    # (proot doesn't handle fchmodat2 correctly — DavHau/nix-portable#148).
    # Same failure class as `non-nixos-gpu`. We unpack manually in
    # installPhase with --no-same-permissions so tar also skips any
    # per-file chmod and nothing triggers the proot bug.
    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/claude-code
      tar -xzf $src -C $out/lib/claude-code --strip-components=1 --no-same-permissions
      mkdir -p $out/bin
      makeWrapper ${pkgs.nodejs_20}/bin/node $out/bin/claude \
        --add-flags "$out/lib/claude-code/cli.js" \
        --set-default DISABLE_AUTOUPDATER 1 \
        --set-default UV_USE_IO_URING 0 \
        --set-default CLAUDE_CODE_DISABLE_MOUSE 1 \
        --prefix PATH : ${lib.makeBinPath [ pkgs.nodejs_20 pkgs.git pkgs.ripgrep ]}
      runHook postInstall
    '';

    meta = {
      description = "Claude Code CLI pinned to last pure-JS release (pre-Bun)";
      homepage = "https://github.com/anthropics/claude-code";
      license = lib.licenses.unfree;
      platforms = lib.platforms.all;
    };
  };
in
{
  home.packages = [ claude-code-legacy ];
}
