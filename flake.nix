{
  description = "Jake's system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Determinate Nix's nix-darwin module — handles nix-darwin interop,
    # exposes GC tuning + custom nix.conf via determinateNix options.
    # (No nixpkgs.follows — docs explicitly warn against it to keep
    # FlakeHub Cache artifacts usable.)
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Tracks upstream @anthropic-ai/claude-code within ~30 min via hourly
    # GitHub Actions. The nixpkgs claude-code trails by 5-10 versions.
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tracks upstream openai/codex hourly (native Rust binary, no Node dep).
    # Same maintainer / pattern as claude-code above.
    codex-cli = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      determinate,
      nix-darwin,
      home-manager,
      nix-homebrew,
      claude-code,
      codex-cli,
      ...
    }:
    let
      sharedOverlays = [
        claude-code.overlays.default
        codex-cli.overlays.default
      ];
      # `nix fmt` — RFC 166 formatter wrapped in treefmt so `nix fmt .` works
      # without the "passing directories is deprecated" warning current nix emits
      # for bare pkgs.nixfmt as a formatter. nixfmt-tree is the documented
      # zero-setup wrapper for exactly this case.
      formatterFor = system: (import nixpkgs { inherit system; }).nixfmt-tree;
      # Shared nixpkgs instance for Linux homeConfigurations (Cerebras + UWaterloo).
      linuxPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = sharedOverlays;
      };
    in
    {

      formatter.aarch64-darwin = formatterFor "aarch64-darwin";
      formatter.x86_64-linux = formatterFor "x86_64-linux";

      # Host-trait flags threaded through every module via extraSpecialArgs.
      # - isDarwin: macOS (nix-darwin + full nix daemon).
      # - isRootlessLinux: Linux using nix-user-chroot (no daemon, no root).
      # - isCerebras: refinement of isRootlessLinux for the Cerebras host
      #   specifically — implies EFS home, fast NFS at /net/jakee-vm/..., and
      #   the corporate /cb/user_env/bashrc-latest env.
      # Exactly one of isDarwin / isRootlessLinux should be true per host.
      # Future daemon-Linux hosts would set both to false.
      darwinConfigurations."Jakes-MacBook" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./hosts/darwin
          determinate.darwinModules.default
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          { nixpkgs.overlays = sharedOverlays; }
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "bak";
              extraSpecialArgs = {
                isDarwin = true;
                isRootlessLinux = false;
                isCerebras = false;
              };
              users.jbedm = import ./home/darwin.nix;
            };
          }
        ];
      };

      # Keyed as "<user>@<hostname>" where hostname is stable, so bare
      # `home-manager switch --flake .` auto-resolves via $USER@$(hostname).
      # On hosts where hostname churns (UWaterloo student CS), the attr uses a
      # logical name instead and `rebuild()` reads REBUILD_FLAKE_ATTR from
      # home.sessionVariables to target it.
      homeConfigurations."jakee@jakee-vm" = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = {
          isDarwin = false;
          isRootlessLinux = true;
          isCerebras = true;
        };
        modules = [ ./hosts/cerebras ];
      };

      homeConfigurations."jbedmons@uwaterloo" = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = {
          isDarwin = false;
          isRootlessLinux = true;
          isCerebras = false;
        };
        modules = [ ./hosts/uwaterloo ];
      };
    };
}
