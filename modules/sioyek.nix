{ config, pkgs, ... }:

{
  # Sioyek is packaged in nixpkgs and tracks the upstream development branch
  # (currently version string "2.0.0-unstable-2026-04-08"), which is ~3 years
  # and many macOS-codesigning fixes ahead of the last tagged release 2.0.0
  # (Dec 2022). The Homebrew cask is deprecated — its 2.0 build no longer
  # passes macOS Gatekeeper and Homebrew will disable it on 2026-09-01.
  # https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/s/sioyek.rb
  home.packages = [ pkgs.sioyek ];

  xdg.configFile = {
    "sioyek/keys_user.config".source = ../config/sioyek/keys_user.config;
    "sioyek/prefs_user.config".source = ../config/sioyek/prefs_user.config;
  };

  # Sioyek on macOS reads from ~/Library/Application Support/sioyek/,
  # not the XDG path. Redirect via symlink so the XDG configs are used.
  # (Module is only imported from home/darwin.nix, so no platform guard needed.)
  home.file."Library/Application Support/sioyek".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/sioyek";
}
