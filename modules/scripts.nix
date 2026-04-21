{ config, lib, ... }:

let
  repo = "${config.home.homeDirectory}/nix-config/scripts";
  # Filter to regular files only — otherwise a stray .DS_Store / subdir / symlink
  # in ../scripts becomes a deployed entry in ~/.local/bin/.
  scripts = lib.attrNames (lib.filterAttrs (_: t: t == "regular") (builtins.readDir ../scripts));
in
{
  # Mutable symlinks — scripts can be edited without rebuilding, and new ones
  # dropped in ../scripts auto-deploy to ~/.local/bin/
  home.file = lib.listToAttrs (
    map (
      name:
      lib.nameValuePair ".local/bin/${name}" {
        source = config.lib.file.mkOutOfStoreSymlink "${repo}/${name}";
      }
    ) scripts
  );
}
