{ pkgs, ... }:

{
  home.packages = [ pkgs.anki-bin ];

  # Dracula theme + custom titlebar addon
  home.file."Library/Application Support/Anki2/addons21/688199788/meta.json".source =
    ../config/anki/addons21/688199788/meta.json;
  home.file."Library/Application Support/Anki2/addons21/dracula_titlebar".source =
    ../config/anki/addons21/dracula_titlebar;
}
