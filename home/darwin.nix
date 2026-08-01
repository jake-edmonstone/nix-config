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

  home = {
    sessionVariables = {
      TYPST_IGNORE_SYSTEM_FONTS = "true";
      TYPST_FONT_PATHS = "/Library/Fonts/Nix Fonts";
    };

    packages = [ pkgs.gnused ];
  };

  programs.neovim.extraPackages = with pkgs; [
    tectonic # modern LaTeX engine (~80 MB vs texlive's ~4 GB)
    mermaid-cli # mmdc — Mermaid diagrams
  ];

  # zoxide init — sourced from a nix-built static file instead of running
  # `zoxide init fish` at every shell startup.
  programs.fish.interactiveShellInit = lib.mkOrder 680 ''
    source ${
      pkgs.runCommand "zoxide-init-fish" { } ''
        ${pkgs.zoxide}/bin/zoxide init fish > $out
      ''
    }
  '';
}
