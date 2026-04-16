{ config, ... }:

{
  # Mutable symlink so edits to init.lua take effect without a rebuild
  home.file.".hammerspoon".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles-nix/config/hammerspoon";
}
