{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../modules/git.nix
    ../modules/fish.nix
    ../modules/tmux.nix
    ../modules/fzf.nix
    ../modules/lazygit.nix
    ../modules/neovim.nix
    ../modules/claude.nix
    ../modules/codex.nix
    ../modules/python.nix
    ../modules/jupyter.nix
    ../modules/nh.nix
    ../modules/copilot.nix
    ../modules/scripts.nix
    ../modules/vim.nix
    ../modules/zoxide.nix
  ];

  home = {
    # Compatibility pin for data/layout migrations, not the package release.
    stateVersion = "26.11";

    sessionVariables.TYPST_ROOT = "${config.home.homeDirectory}/work";

    sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

    packages = with pkgs; [
      typst
      nodejs
      ghc
      cmake
      docker-client
      mosh
      tree
      wget
      ffmpeg
      imagemagick
      ghostscript
      poppler-utils # provides pdftotext
      timewarrior
    ];

    file.".clang-format".source = ../config/clang/clang-format;

    # ~/.hushlogin must be a real empty file rather than a store symlink so
    # login services can read it directly.
    activation.writeHushlogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run truncate -s 0 "$HOME/.hushlogin"
    '';
  };

  # Configuration reference manuals are expensive to generate and available
  # online; ordinary package man pages remain enabled.
  manual.manpages.enable = false;

  programs = {
    man.generateCaches = false;

    bat = {
      enable = true;
      config.theme = "Dracula";
    };

    fd.enable = true;

    eza = {
      enable = true;
      icons = "always";
      enableFishIntegration = true; # generates ls, ll, la, lt, lla aliases
    };

    pandoc.enable = true;

    ripgrep.enable = true;
  };

  # Use standard XDG paths for tools such as lazygit. On Darwin, this also
  # avoids their fallback to ~/Library/Application Support.
  xdg.enable = true;

}
