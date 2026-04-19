{ ... }:

{
  imports = [
    ./common.nix
    ../hosts/uwaterloo
  ];

  # Student CS machines are interchangeable (ubuntu2404-001, ubuntu2404-002, …)
  # so $USER@$(hostname) won't reliably match the flake attr. The rebuild()
  # function in modules/zsh.nix reads REBUILD_FLAKE_ATTR and appends
  # "#$REBUILD_FLAKE_ATTR" to the --flake arg when set.
  home.sessionVariables.REBUILD_FLAKE_ATTR = "jbedmons@uwaterloo";
}
