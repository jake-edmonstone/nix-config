_:

let
  palette = (import ../theme.nix).palette;
in

{
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultCommand = "fd --hidden --strip-cwd-prefix";
    fileWidget = {
      command = "fd --hidden --strip-cwd-prefix";
      options = [ "--preview 'bat -n --color=always --line-range :500 {}'" ];
    };
    changeDirWidget = {
      command = "fd --type=d --hidden --strip-cwd-prefix";
      options = [ "--preview 'eza --tree --color=always {} | head -200'" ];
    };
    colors = {
      fg = palette.foreground;
      hl = palette.purple;
      "fg+" = palette.foreground;
      "bg+" = "-1";
      "hl+" = palette.purple;
      prompt = palette.green;
      pointer = palette.pink;
      marker = palette.pink;
      border = palette.comment;
    };
    defaultOptions = [ "--gutter=' '" ];
  };
}
