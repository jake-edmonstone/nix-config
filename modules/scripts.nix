{ config, lib, ... }:

let
  repo = "${config.home.homeDirectory}/nix-config/scripts";
  scripts = builtins.attrNames (builtins.readDir ../scripts);
in
{
  # Mutable symlinks — scripts can be edited without rebuilding, and new ones
  # dropped in ../scripts auto-deploy to ~/.local/bin/
  home.file = lib.listToAttrs (map (name:
    lib.nameValuePair ".local/bin/${name}" {
      source = config.lib.file.mkOutOfStoreSymlink "${repo}/${name}";
    }
  ) scripts);
}
