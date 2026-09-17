{
  description = "Jake's system configuration";

  # Run ./install.sh for first-time macOS setup, or ./install-alma.sh on the
  # GTS AlmaLinux host.

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

    # Neovim nightly provides watcher-backed 'autoread'
    # (neovim/neovim#37971) on both configured platforms.
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
      # tmux 3.7 through 3.7c causes Codex output to corrupt tmux popup
      # rendering on this setup, especially flickering/cutting off the popup
      # title border while Codex is streaming. Remove this overlay once nixpkgs
      # ships a release containing the upstream redraw fix.
      tmuxOverlay = _: prev: {
        tmux = prev.tmux.overrideAttrs (_old: {
          version = "3.6b";
          src = prev.fetchFromGitHub {
            owner = "tmux";
            repo = "tmux";
            rev = "refs/tags/3.6b";
            hash = "sha256-iW4K/OxSVpxVkyI5Dy6lzwVf/8nXyjcHtL76Ezmxavc=";
          };
        });
      };
      codexOverlay = [ codex-cli.overlays.default ];
      overlays = codexOverlay ++ [ tmuxOverlay ];
      # `nix fmt` — RFC 166 formatter wrapped in treefmt so `nix fmt .` works
      # without the "passing directories is deprecated" warning current nix emits
      # for bare pkgs.nixfmt as a formatter. nixfmt-tree is the documented
      # zero-setup wrapper for exactly this case.
      formatterFor = system: (import nixpkgs { inherit system; }).nixfmt-tree;
    in
    {

      formatter.aarch64-darwin = formatterFor "aarch64-darwin";
      formatter.x86_64-linux = formatterFor "x86_64-linux";

      # Expose the locked Home Manager CLI so install-alma.sh can bootstrap
      # without fetching an unrelated Home Manager revision.
      packages.x86_64-linux.home-manager = home-manager.packages.x86_64-linux.default;

      darwinConfigurations."Jakes-MacBook" = nix-darwin.lib.darwinSystem {
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
              users.jbedm = {
                imports = [ ./home/darwin.nix ];

                # Keep macOS on the same watcher-enabled Neovim build as Linux.
                programs.neovim.package = neovim-nightly-overlay.packages.aarch64-darwin.default;
              };
            };
          }
        ];
      };

      homeConfigurations."jedmonstone@jedmonstone-dev.striketechnologies.com" =
        home-manager.lib.homeManagerConfiguration
          {
            pkgs = import nixpkgs {
              system = "x86_64-linux";
              inherit overlays;
              config.allowUnfree = true;
            };
            modules = [
              ./hosts/gts
              {
                # Keep Linux on the same watcher-enabled Neovim nightly build
                # as macOS, rather than the nixpkgs release package.
                programs.neovim.package = neovim-nightly-overlay.packages.x86_64-linux.default;
              }
            ];
          };
    };
}
