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

  # zoxide init — sourced from a nix-built static file instead of the
  # `eval "$(zoxide init zsh)"` fork that programs.zoxide.enableZshIntegration
  # emits. Mac only; on Cerebras zoxide is installed but not integrated (the
  # user doesn't use z/zi there; skipping avoids adding another read path on
  # an already-slow-fs host).
  programs.zsh.initContent = lib.mkOrder 680 ''
    source ${
      pkgs.runCommand "zoxide-init-zsh" { } ''
        ${pkgs.zoxide}/bin/zoxide init zsh > $out
      ''
    }
  '';
}
