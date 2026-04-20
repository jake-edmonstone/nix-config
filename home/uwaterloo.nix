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

  # targets.genericLinux.enable (in home/common.nix) auto-enables GPU driver
  # wrapping for non-NixOS hosts. The non-nixos-gpu derivation's unpack phase
  # fails under nix-portable's proot runtime (filesystem syscall emulation
  # doesn't handle `cp -p` on setup files correctly). Disable explicitly —
  # UW CS is headless ssh anyway, no GPU to wrap.
  targets.genericLinux.gpu.enable = false;
}
