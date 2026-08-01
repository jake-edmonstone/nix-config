{
  description = "Jake's system configuration";

  # Run ./install.sh for first-time setup. Afterwards, /etc/nix-darwin points
  # here, so `sudo darwin-rebuild switch` activates the configuration.

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
      tmuxOverlay = _: prev: {
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
    in
    {

      formatter.aarch64-darwin = formatterFor "aarch64-darwin";

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
    };
}
