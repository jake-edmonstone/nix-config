{ lib, pkgs, ... }:

{
  imports = [
    ./common.nix
    ../modules/ghostty.nix
    ../modules/hammerspoon.nix
    ../modules/anki.nix
    ../modules/sioyek.nix
    ../modules/codex.nix
  ];

  # zoxide init — sourced from a nix-built static file instead of running
  # `zoxide init fish` at every shell startup. Mac only; on Cerebras zoxide is
  # installed but not integrated (the user doesn't use z/zi there; skipping
  # avoids adding another read path on an already-slow-fs host).
  programs.fish.interactiveShellInit = lib.mkOrder 680 ''
    source ${
      pkgs.runCommand "zoxide-init-fish" { } ''
        ${pkgs.zoxide}/bin/zoxide init fish > $out
      ''
    }
  '';
}
