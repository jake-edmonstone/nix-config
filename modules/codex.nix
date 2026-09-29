{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.home.homeDirectory;
  theme = import ../theme.nix;
  chromeTheme = palette: {
    accent = palette.pink;
    contrast = 60;
    fonts = {
      code = "Maple Mono NF";
      ui = "SF Pro Text";
    };
    ink = palette.foreground;
    opaqueWindows = false;
    semanticColors = {
      diffAdded = palette.green;
      diffRemoved = palette.red;
      skill = palette.pink;
    };
    surface = palette.background;
  };
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
      model = "gpt-6-sol";
      model_reasoning_effort = "high";
      service_tier = "default";
      sandbox_mode = "danger-full-access";
      approval_policy = "never";
      approvals_reviewer = "user";

      tui = {
        vim_mode_default = true;
        theme = if theme.isDark then "dracula" else "catppuccin-latte";
      };

      notice = {
        hide_full_access_warning = true;
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
        "/scratch/dev/engine".trust_level = "trusted";
        "/scratch/dev".trust_level = "trusted";
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        "${home}/Library/Mobile Documents/com~apple~CloudDocs".trust_level = "trusted";
      };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      desktop = {
        appearanceTheme = theme.mode;
        appearanceLightCodeThemeId = "catppuccin";
        appearanceDarkCodeThemeId = "dracula";
        appearanceLightChromeTheme = chromeTheme theme.palettes.light;
        appearanceDarkChromeTheme = chromeTheme theme.palettes.dark;
      };
    };
  };
}
