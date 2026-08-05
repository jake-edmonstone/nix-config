_:

{
  programs.github-copilot-cli.enable = true;

  # Keep the Nix package authoritative while leaving Copilot's mutable login
  # and UI settings in its existing ~/.copilot/config.json.
  home.sessionVariables.COPILOT_AUTO_UPDATE = "false";
}
