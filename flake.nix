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

  outputs = { nixpkgs, determinate, nix-darwin, home-manager, nix-homebrew, claude-code, codex-cli, ... }:
    let
      sharedOverlays = [ claude-code.overlays.default codex-cli.overlays.default ];
    in {

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
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.extraSpecialArgs = {
            isDarwin = true;
            isRootlessLinux = false;
            isCerebras = false;
          };
          home-manager.users.jbedm = import ./home/darwin.nix;
        }
      ];
    };

    # Keyed as "<user>@<hostname>" so bare `home-manager switch --flake .`
    # auto-resolves (home-manager's CLI tries $USER@$(hostname) variants).
    # Flags hardcoded because the attr key already names the host.
    homeConfigurations."jakee@jakee-vm" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = sharedOverlays;
      };
      extraSpecialArgs = {
        isDarwin = false;
        isRootlessLinux = true;
        isCerebras = true;
      };
      modules = [ ./home/cerebras.nix ];
    };
  };
}
