{ ... }:

{
  imports = [ ../../home/common.nix ];

  home = {
    username = "jbedmons";
    homeDirectory = "/u0/jbedmonstone";

    # Student CS machines are interchangeable (ubuntu2404-001, ubuntu2404-002, …)
    # so $USER@$(hostname) won't reliably match the flake attr. The rebuild()
    # function in modules/fish.nix reads REBUILD_FLAKE_ATTR and appends
    # "#$REBUILD_FLAKE_ATTR" to the --flake arg when set.
    sessionVariables.REBUILD_FLAKE_ATTR = "jbedmons@uwaterloo";
  };

  # targets.genericLinux.enable (in home/common.nix) auto-enables GPU driver
  # wrapping for non-NixOS hosts. The non-nixos-gpu derivation's unpack phase
  # fails under nix-portable's proot runtime (filesystem syscall emulation
  # doesn't handle `cp -p` on setup files correctly). Disable explicitly —
  # UW CS is headless ssh anyway, no GPU to wrap.
  targets.genericLinux.gpu.enable = false;

  # Intentionally minimal beyond the above:
  # - Ubuntu 24.04 uses standard en_US.UTF-8 (no Cerebras-style lowercase fix).
  # - No institutional bashrc to lazy-source (course setups like /u/cs241/setup
  #   are intentionally not carried over).
  # - Home is on CephFS at /u0/jbedmonstone; not as fast as local disk but
  #   tolerable for ~/.cache and nix store. No fast-FS relocation target exists.
  # - LDAP-backed NSS (passwd: files ldap). Fish uses the inherited $USER for
  #   prompt context, avoiding getpwuid-backed $USERNAME differences.
}
