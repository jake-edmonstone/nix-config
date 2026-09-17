{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../../home/common.nix ];

  targets.genericLinux = {
    enable = true;
    # This profile is used on a headless server; do not wrap GUI programs in
    # nixGL or pull in graphics-driver integration.
    gpu.enable = false;
  };

  home.packages = with pkgs; [
    # Keep the command-line toolchain in lockstep with Neovim's clangd.
    # Clang 22 handles this machine's GCC 15 / C++23 projects correctly.
    llvmPackages_22.clang-tools
    gdb
    netcat-openbsd
    trash-cli
  ];

  # Bazel's outputs and action cache are large and fully rebuildable. The
  # engine documents this /scratch layout; keeping it here prevents a future
  # Home Manager switch from silently returning them to the small root disk.
  home.file.".bazelrc" = {
    force = true;
    text = ''
      startup --output_user_root=/scratch/bazel-cache
      build --disk_cache=/scratch/bazel-disk-cache
      build --experimental_disk_cache_gc_max_age=14d
      build --experimental_disk_cache_gc_max_size=250G
    '';
  };

  programs = {
    home-manager.enable = true;
    lazygit.enableBashIntegration = false;

    bash = {
      enable = true;
      # bashrcExtra runs before Home Manager's interactive-shell guard, so SSH
      # commands retain AlmaLinux's setup and can find the Nix profile without
      # being replaced by Fish.
      bashrcExtra = ''
        if [[ -r /etc/bashrc ]]; then
          source /etc/bashrc
        fi
        source ${pkgs.nix}/etc/profile.d/nix.sh
        source ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh

        if [[ -d "$HOME/.bashrc.d" ]]; then
          for rc in "$HOME"/.bashrc.d/*; do
            [[ -f "$rc" ]] && source "$rc"
          done
          unset rc
        fi
      '';

      initExtra = lib.mkOrder 3000 ''
        # Keep the directory-managed login shell unchanged, but replace
        # interactive Bash with Fish. A Bash subshell launched from Fish stays
        # in Bash instead of immediately looping back.
        if [[ $- == *i* && -z ''${BASH_EXECUTION_STRING:-} ]]; then
          parent_command="$(ps -o comm= -p "$PPID" | tr -d '[:space:]')"
          if [[ "$parent_command" != fish ]]; then
            exec ${config.programs.fish.package}/bin/fish
          fi
          unset parent_command
        fi
      '';
    };
  };
}
