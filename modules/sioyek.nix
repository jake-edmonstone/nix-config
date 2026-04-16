{ config, lib, pkgs, ... }:

{
  xdg.configFile = {
    "sioyek/keys_user.config".source = ../config/sioyek/keys_user.config;
    "sioyek/prefs_user.config".source = ../config/sioyek/prefs_user.config;
  };

  # Sioyek on macOS reads from ~/Library/Application Support/sioyek/,
  # not the XDG path. Redirect via symlink so the XDG configs are used.
  home.file = lib.optionalAttrs pkgs.stdenv.isDarwin {
    "Library/Application Support/sioyek".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/sioyek";
  };
}
