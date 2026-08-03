{ lib, pkgs, ... }:

{
  imports = [
    ./common.nix
    ../modules/ghostty.nix
    ../modules/hammerspoon.nix
    ../modules/anki.nix
    ../modules/sioyek.nix
  ];

  home = {
    sessionVariables = {
      NH_SHOW_ACTIVATION_LOGS = "1";
      # Restrict Typst to nix-darwin's managed fonts. Unrestricted macOS font
      # discovery selects different New Computer Modern faces and changes PDFs.
      TYPST_IGNORE_SYSTEM_FONTS = "true";
      TYPST_FONT_PATHS = "/Library/Fonts/Nix Fonts";
    };

    sessionPath = lib.mkBefore [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
    ];

    # GNU sed fixes Fish completions that assume GNU extensions on macOS.
    packages = [ pkgs.gnused ];
  };

  # Inline `brew shellenv` output so we skip the ~100ms Ruby fork per shell.
  # nix-homebrew shell integration is disabled in hosts/darwin/default.nix.
  programs.fish.shellInit = ''
    set -gx HOMEBREW_PREFIX /opt/homebrew
    set -gx HOMEBREW_CELLAR /opt/homebrew/Cellar
    set -gx HOMEBREW_REPOSITORY /opt/homebrew
    set -q MANPATH; and set -gx MANPATH "" $MANPATH
    set -gx INFOPATH /opt/homebrew/share/info $INFOPATH
    set -gp fish_complete_path /opt/homebrew/share/fish/vendor_completions.d
  '';
}
