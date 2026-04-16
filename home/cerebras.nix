{ ... }:

{
  imports = [
    ./common.nix
  ];

  # No macOS-only packages (anki-bin, ghostty-bin, ghostty module)
  # No Hammerspoon, no Sioyek Library symlink

  home.username = "jakee";
  home.homeDirectory = "/home/jakee";
}
