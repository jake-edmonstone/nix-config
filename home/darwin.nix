{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ../modules/ghostty.nix
  ];

  home.username = "jbedm";
  home.homeDirectory = "/Users/jbedm";

  home.packages = with pkgs; [
    anki-bin
  ];

  # Hammerspoon config (mutable symlink for live editing)
  home.file.".hammerspoon".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles-nix/config/hammerspoon";

  # Sioyek macOS reads from ~/Library/Application Support/sioyek/
  home.file."Library/Application Support/sioyek".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.xdg.configHome}/sioyek";

  # Raycast: one-shot import on fresh install (same pattern as chezmoi install.sh)
  home.activation.importRaycast = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _rayconfig="${config.home.homeDirectory}/dotfiles-nix/dotfiles/raycast.rayconfig"
    _marker="${config.xdg.configHome}/.raycast_imported"
    if [[ -f "$_rayconfig" ]] && [[ ! -f "$_marker" ]]; then
      open "$_rayconfig" && touch "$_marker"
    fi
  '';
}
