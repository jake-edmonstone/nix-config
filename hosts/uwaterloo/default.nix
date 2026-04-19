{ ... }:

{
  home.username = "jbedmons";
  home.homeDirectory = "/u0/jbedmonstone";

  # Intentionally minimal:
  # - Ubuntu 24.04 uses standard en_US.UTF-8 (no Cerebras-style lowercase fix).
  # - No institutional bashrc to lazy-source (course setups like /u/cs241/setup
  #   are intentionally not carried over).
  # - Home is on CephFS at /u0/jbedmonstone; not as fast as local disk but
  #   tolerable for ~/.cache and nix store. No fast-FS relocation target exists.
  # - LDAP-backed NSS (passwd: files ldap). If nix's glibc can't resolve the
  #   user inside the chroot, add a $USER fallback similar to the p10k fix.
}
