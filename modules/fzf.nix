{ ... }:

{
  programs.fzf = {
    enable = true;
    # Disabled: HM's implementation does `source <(fzf --zsh)` which forks fzf
    # once per shell startup. We source the static plugin files directly from
    # modules/zsh.nix mkOrder 650 instead. Saves ~6 ms per spawn (more under EDR).
    enableZshIntegration = false;
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
    defaultOptions = [ "--gutter=' '" ];
  };
}
