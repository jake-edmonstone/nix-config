{
  config,
  lib,
  pkgs,
  ...
}:

let
  flatbuffersLanguageServerSrc = pkgs.fetchFromGitHub {
    owner = "smpanaro";
    repo = "flatbuffers-language-server";
    rev = "0.0.2";
    hash = "sha256-Qt52TkVxBou6ZrPHmls0Rv+x0JT3OWRhc8iWBzQk+Yw=";
  };

  # The server's FlatBuffers C++ submodule is omitted from GitHub source
  # archives, so bring in the exact revision recorded by its release.
  flatbuffersLanguageServerFlatbuffersSrc = pkgs.fetchFromGitHub {
    owner = "google";
    repo = "flatbuffers";
    rev = "82396fa0fe9a61e7a30bdd008e180d56f5e49ebf";
    hash = "sha256-O/8rTq/yrk2hxmms0OPbSp8a+cjWBZdZAJU9RdYO8kM=";
  };

  flatbuffersLanguageServer = pkgs.rustPlatform.buildRustPackage {
    pname = "flatbuffers-language-server";
    version = "0.0.2";
    src = flatbuffersLanguageServerSrc;

    # The release binary needs GLIBC_2.38 while GTS provides 2.34.  Build it
    # locally instead.  Cargo needs the internal CA during fixed-output
    # vendoring; Nix is configured to expose that certificate to sandboxes.
    cargoHash = "sha256-QFcPeqV8iD0e+vFyzsvgUMvG6LQ4s/gG79Zq8q4xNQw=";
    depsExtraArgs = {
      env.REQUESTS_CA_BUNDLE = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem";
    };

    postPatch = ''
      mkdir -p third_party
      rm -rf third_party/flatbuffers
      cp -R ${flatbuffersLanguageServerFlatbuffersSrc} third_party/flatbuffers
      chmod -R u+w third_party/flatbuffers
    '';

    nativeBuildInputs = [ pkgs.llvmPackages.libclang pkgs.llvmPackages.clang ];
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
  };

  # fcat is an engine Bazel target, not a package supplied by FlatBuffers.
  # Running it through Bazel keeps it aligned with the checkout's toolchains.
  # Preserve input paths relative to the caller, rather than the engine root.
  fcat = pkgs.writeShellScriptBin "fcat" ''
    original_pwd="$PWD"
    args=()
    for arg in "$@"; do
      if [[ "$arg" != /* && "$arg" != -* && -e "$original_pwd/$arg" ]]; then
        args+=("$original_pwd/$arg")
      else
        args+=("$arg")
      fi
    done

    cd /scratch/dev/engine
    exec /usr/bin/bazel run //marketaccess/logging/fcat:fcat -- "''${args[@]}"
  '';
in
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
    flatbuffers # provides flatc
    flatbuffersLanguageServer
    fcat
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
