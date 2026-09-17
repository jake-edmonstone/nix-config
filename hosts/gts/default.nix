{
  config,
  lib,
  ...
}:

{
  imports = [ ./home.nix ];

  home = {
    username = "jedmonstone";
    homeDirectory = "/home/STRIKETECH/jedmonstone";
    # GTS intercepts HTTPS with a CA installed in AlmaLinux's system trust
    # bundle. Nix otherwise uses its bundled Mozilla roots and rejects it.
    sessionVariables = {
      NIX_SSL_CERT_FILE = "/etc/pki/tls/certs/ca-bundle.crt";
      # Some build helpers use Python requests rather than Nix's fetcher.
      REQUESTS_CA_BUNDLE = "/etc/pki/tls/certs/ca-bundle.crt";
    };
  };

  programs = {
    bash.initExtra = lib.mkOrder 2900 ''
      module purge
      module load gcc/15.2.0
    '';

    git = {
      settings.user = {
        name = "Jake Edmonstone";
        email = "jedmonstone@striketechnologies.com";
      };
      includes = [
        {
          condition = "gitdir:${config.home.homeDirectory}/nix-config/";
          contents.user = {
            name = "jake-edmonstone";
            email = "jbedmonstone@gmail.com";
          };
        }
      ];
    };

    # The GTS machine has no local graphical session. Keep Tinymist available
    # for editing while preventing typst-preview.nvim from launching a browser.
    neovim.initLua = lib.mkBefore ''
      vim.g.headless_server = true
    '';
  };
}
