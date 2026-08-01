{ config, lib, ... }:

let
  repo = "${config.home.homeDirectory}/nix-config/scripts";
  # Filter to regular files only — otherwise a stray .DS_Store / subdir / symlink
  # in ../scripts becomes a deployed entry in ~/.local/bin/.
  scripts = lib.attrNames (lib.filterAttrs (_: t: t == "regular") (builtins.readDir ../scripts));
in
{
  # Mutable symlinks — tracked scripts can be edited without rebuilding. New
  # scripts appear in the flake and deploy after they are added to Git's index.
  home.file = lib.listToAttrs (
    map (
      name:
      lib.nameValuePair ".local/bin/${name}" {
        source = config.lib.file.mkOutOfStoreSymlink "${repo}/${name}";
      }
    ) scripts
  );
}
