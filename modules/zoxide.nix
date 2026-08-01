{ lib, pkgs, ... }:

{
  programs.zoxide = {
    enable = true;
    # Home Manager's integration runs `zoxide init fish | source` on every
    # shell startup. Source the same output from the Nix store instead.
    enableFishIntegration = false;
  };

  programs.fish.interactiveShellInit = lib.mkOrder 680 ''
    source ${
      pkgs.runCommand "zoxide-init-fish" { } ''
        ${pkgs.zoxide}/bin/zoxide init fish > $out
      ''
    }
  '';
}
