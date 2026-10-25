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
      overlays = [ codex-cli.overlays.default ];
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

      # Bootstrap with the CLI from the same locked nix-darwin input.
      packages.aarch64-darwin.darwin-rebuild = nix-darwin.packages.aarch64-darwin.darwin-rebuild;

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

                # TODO: temporary Neovim nightly pin for watcher-backed
                # 'autoread' (neovim/neovim#37971). Revert to nixpkgs neovim
                # once that package includes the commit.
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
            modules = [ ./hosts/gts ];
          };
    };
}
