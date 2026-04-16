{ ... }:

{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --hidden --strip-cwd-prefix";
    fileWidgetCommand = "fd --hidden --strip-cwd-prefix";
    changeDirWidgetCommand = "fd --type=d --hidden --strip-cwd-prefix";
    fileWidgetOptions = [ "--preview 'bat -n --color=always --line-range :500 {}'" ];
    changeDirWidgetOptions = [ "--preview 'eza --tree --color=always {} | head -200'" ];
    colors = {
      fg = "#f8f8f2";
      hl = "#bd93f9";
      "fg+" = "#f8f8f2";
      "bg+" = "-1";
      "hl+" = "#bd93f9";
      prompt = "#50fa7b";
      pointer = "#ff79c6";
      marker = "#ff79c6";
      border = "#6272a4";
    };
    defaultOptions = [ "--gutter= " ];
  };
}
