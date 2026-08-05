{ pkgs, ... }:

let
  globalPython = pkgs.python3.withPackages (
    ps: with ps; [
      numpy
      matplotlib
      scikit-learn
      torch
      torchvision
      pandas
      nbclient
      nbformat
      jupyter
      jupyterlab
      jupyterlab-lsp
      jupyterlab-vim
      python-lsp-server
      ipykernel
      jupytext
    ]
  );
in
{
  home.packages = [ globalPython ];
}
