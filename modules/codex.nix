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
      approvals_reviewer = "user";
      sandbox_mode = "danger-full-access";
      approval_policy = "never";

      tui = {
        vim_mode_default = true;
        theme = "dracula";
      };

      notice = {
        hide_gpt5_1_migration_prompt = true;
        "hide_gpt-5.1-codex-max_migration_prompt" = true;
        model_migrations."gpt-5.3-codex" = "gpt-5.4";
      };

      plugins."github@openai-curated".enabled = true;

      projects = {
        "${home}/nix-config".trust_level = "trusted";
        "${home}/typst".trust_level = "trusted";
        "${home}/cs350".trust_level = "trusted";
        "${home}/projects".trust_level = "trusted";
        "${home}/Misc".trust_level = "trusted";
        "${home}".trust_level = "trusted";
      };
    };

    skills = ../config/skills;
  };
}
