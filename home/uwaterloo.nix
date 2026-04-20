{ config, lib, ... }:

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

  # Claude Code TUI input freezes on UW: Ink's mouse-tracking init over SSH
  # through proot breaks keystroke handling — TUI renders but never accepts
  # input and burns 90%+ CPU. Disable mouse tracking on this host only.
  # See anthropics/claude-code#23326, #17787, #22948.
  # Cerebras works over ssh without this, so keep the default (mouse on)
  # there — presumably because nix-user-chroot doesn't munge terminal ioctls
  # the way nix-portable's proot does.
  home.file.".claude/settings.json".text = lib.mkForce (builtins.toJSON (
    lib.recursiveUpdate
      (import ../config/claude/settings.nix { inherit config; })
      { env.CLAUDE_CODE_DISABLE_MOUSE = "1"; }
  ));
}
