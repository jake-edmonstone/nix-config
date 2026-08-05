{ lib, ... }:

{
  home.file.".vimrc".source = ../config/vim/vimrc;

  # vimrc enables persistent undo and backups in these directories.
  home.activation.createVimDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.vim/undodir" "$HOME/.vim/backups"
  '';
}
