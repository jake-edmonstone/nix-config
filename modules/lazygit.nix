_:

let
  theme = import ../theme.nix;
  inherit (theme) palette;
  selectedLine = if theme.isDark then palette.comment else palette.selection;
in

{
  programs.lazygit = {
    enable = true;
    enableFishIntegration = false;

    settings = {
      disableStartupPopups = true;
      promptToReturnFromSubprocess = false;
      gui = {
        wrapLinesInStagingView = false;
        theme = {
          activeBorderColor = [
            palette.pink
            "bold"
          ];
          inactiveBorderColor = [ palette.purple ];
          searchingActiveBorderColor = [
            palette.cyan
            "bold"
          ];
          optionsTextColor = [ palette.comment ];
          selectedLineBgColor = [ selectedLine ];
          inactiveViewSelectedLineBgColor = [ "bold" ];
          cherryPickedCommitFgColor = [ palette.comment ];
          cherryPickedCommitBgColor = [ palette.cyan ];
          markedBaseCommitFgColor = [ palette.cyan ];
          markedBaseCommitBgColor = [ palette.yellow ];
          unstagedChangesColor = [ palette.red ];
          defaultFgColor = [ palette.foreground ];
        };
      };
      git = {
        diffRenderers = [
          {
            command = "delta --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format=\"lazygit-edit://{path}:{line}\"";
          }
        ];
      };
      os = {
        editPreset = "nvim-remote";
        edit = ''[ -n "$NVIM" ] && nvim --server "$NVIM" --remote-send "<C-\><C-n><cmd>close<cr>" && nvim --server "$NVIM" --remote {{filename}} || nvim {{filename}}'';
        editAtLine = ''[ -n "$NVIM" ] && nvim --server "$NVIM" --remote-send "<C-\><C-n><cmd>close<cr>" && nvim --server "$NVIM" --remote {{filename}} && nvim --server "$NVIM" --remote-send ":{{line}}<CR>" || nvim +{{line}} {{filename}}'';
      };
    };
  };
}
