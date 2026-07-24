{
  description = "Jake's system configuration";

  # ---------------------------------------------------------------------------
  # First-time bootstrap (before nh and REBUILD_FLAKE_ATTR are in the shell env)
  # is handled by install.sh:
  #
  #     Darwin: ./install.sh
  #     Linux:  REBUILD_FLAKE_ATTR=<attr> ./install.sh
  #             (attr = "jbedmons@uwaterloo" or "jakee@jakee-vm")
  #
  # After the first successful activation, `rebuild` (fish function in
  # modules/fish.nix) works bare via `nh` — nh is installed by Home Manager and
  # $REBUILD_FLAKE_ATTR is set by HM via home.sessionVariables in each host
  # module.
  # ---------------------------------------------------------------------------

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

    # TODO: temporary Neovim nightly pin for watcher-backed 'autoread'
    # (neovim/neovim#37971). Remove this input and the Darwin HM package
    # override once nixpkgs neovim includes that commit.
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

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
      neovim-nightly-overlay,
      nix-homebrew,
      codex-cli,
      ...
    }:
    let
      # TODO: temporary tmux 3.7 redraw regression workaround.
      # tmux 3.7 through 3.7b causes Codex output to corrupt tmux popup
      # rendering on this setup, especially flickering/cutting off the popup
      # title border while Codex is streaming. Remove this overlay once nixpkgs
      # ships a fixed tmux newer than 3.7b.
      tmuxOverlay = final: prev: {
        tmux = prev.tmux.overrideAttrs (_old: {
          version = "3.6a";
          src = prev.fetchFromGitHub {
            owner = "tmux";
            repo = "tmux";
            rev = "refs/tags/3.6a";
            hash = "sha256-VwOyR9YYhA/uyVRJbspNrKkJWJGYFFktwPnnwnIJ97s=";
          };
        });
      };
      # TODO: nixpkgs#539664 applies the wrong upstream patch, leaving
      # mcp-nixos' test_read_text_file flaky on Darwin. Remove this overlay
      # once nixpkgs applies utensils/mcp-nixos@d7ebc7b itself.
      mcpNixosOverlay = final: prev: {
        mcp-nixos = prev.mcp-nixos.overridePythonAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (final.fetchpatch {
              url = "https://github.com/utensils/mcp-nixos/commit/d7ebc7bfae70eaf20d54e87cf42764a1d57c35ef.patch";
              hash = "sha256-2kLVknbL3BqxgDmIU4oaiQquij2slnoSiWD6JWRTW1c=";
            })
          ];
        });
      };
      codexOverlay = [ codex-cli.overlays.default ];
      overlays = codexOverlay ++ [
        tmuxOverlay
        mcpNixosOverlay
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
        inherit overlays;
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
          { nixpkgs.overlays = overlays; }
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
              users.jbedm = {
                imports = [ ./home/darwin.nix ];

                # TODO: temporary Neovim nightly pin for watcher-backed
                # 'autoread' (neovim/neovim#37971). Revert to nixpkgs neovim
                # once that package includes the commit.
                programs.neovim.package = neovim-nightly-overlay.packages.aarch64-darwin.default;
              };
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
