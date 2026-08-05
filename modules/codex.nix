{ config, pkgs, ... }:

let
  home = config.home.homeDirectory;
in

{
  programs.mcp = {
    enable = true;
    servers.nixos = {
      command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
    };
  };

  programs.codex = {
    enable = true;
    package = pkgs.codex;
    enableMcpIntegration = true;

    settings = {
      model = "gpt-5.6-sol";
      model_reasoning_effort = "medium";
      sandbox_mode = "danger-full-access";
      approval_policy = "never";

      tui = {
        vim_mode_default = true;
        theme = "dracula";
      };

      desktop = {
        appearanceTheme = "dark";
        appearanceDarkCodeThemeId = "dracula";
        appearanceDarkChromeTheme = {
          accent = "#ff79c6";
          contrast = 60;
          fonts = {
            code = "Maple Mono NF";
            ui = "SF Pro Text";
          };
          ink = "#f8f8f2";
          opaqueWindows = false;
          semanticColors = {
            diffAdded = "#50fa7b";
            diffRemoved = "#ff5555";
            skill = "#ff79c6";
          };
          surface = "#282a36";
        };
      };

      notice = {
        hide_gpt5_1_migration_prompt = true;
        "hide_gpt-5.1-codex-max_migration_prompt" = true;
        model_migrations."gpt-5.3-codex" = "gpt-5.4";
      };

      plugins."github@openai-curated".enabled = true;

      projects = {
        "${home}/nix-config".trust_level = "trusted";
        "${home}/work".trust_level = "trusted";
        "${home}/work/academic/undergrad/4A/cs350".trust_level = "trusted";
        "${home}/work/research/drp-presentation".trust_level = "trusted";
        "${home}/projects/jake-edmonstone.github.io".trust_level = "trusted";
        "${home}/projects".trust_level = "trusted";
        "${home}/misc".trust_level = "trusted";
        "${home}".trust_level = "trusted";
      };
    };

  };
}
