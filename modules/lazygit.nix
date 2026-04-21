_:

{
  programs.lazygit = {
    enable = true;

    settings = {
      disableStartupPopups = true;
      gui = {
        wrapLinesInStagingView = false;
        theme = {
          activeBorderColor = [
            "#FF79C6"
            "bold"
          ];
          inactiveBorderColor = [ "#BD93F9" ];
          searchingActiveBorderColor = [
            "#8BE9FD"
            "bold"
          ];
          optionsTextColor = [ "#6272A4" ];
          selectedLineBgColor = [ "#6272A4" ];
          inactiveViewSelectedLineBgColor = [ "bold" ];
          cherryPickedCommitFgColor = [ "#6272A4" ];
          cherryPickedCommitBgColor = [ "#8BE9FD" ];
          markedBaseCommitFgColor = [ "#8BE9FD" ];
          markedBaseCommitBgColor = [ "#F1FA8C" ];
          unstagedChangesColor = [ "#FF5555" ];
          defaultFgColor = [ "#F8F8F2" ];
        };
      };
      git = {
        pagers = [
          {
            pager = "delta --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format=\"lazygit-edit://{path}:{line}\"";
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
