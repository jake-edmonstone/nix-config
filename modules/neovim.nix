{ config, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    # withRuby/withPython3 default to false at home.stateVersion >= 26.05
  };

  # Deploy entire nvim config as a mutable symlink (instant edits, lazy.nvim can write lockfile)
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles-nix/config/nvim";
}
