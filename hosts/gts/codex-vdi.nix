{ config, pkgs, ... }:

{
  home.packages = [
    pkgs.curl
    pkgs.gost
  ];

  home.file.".local/bin/codex-vdi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/scripts/gts/codex-vdi";

  systemd.user.services.codex-vdi-proxy = {
    Unit.Description = "Codex HTTP proxy through the Windows VDI SSH tunnel";

    Service = {
      ExecStart = "${pkgs.gost}/bin/gost -L=http://127.0.0.1:18181 -F=socks5://127.0.0.1:18080";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      UMask = "0077";
      UnsetEnvironment = "HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
