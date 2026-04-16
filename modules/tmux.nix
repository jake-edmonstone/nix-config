{ pkgs, isCerebras, ... }:

let
  clip = if isCerebras then "xclip -selection clipboard" else "pbcopy";
in
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 50000;

    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuum;
        extraConfig = "set -g @continuum-restore 'on'";
      }
    ];

    extraConfig = ''
      set -gq allow-passthrough on

      # Terminal settings (Ghostty)
      set -as terminal-overrides ',xterm-ghostty:Tc'
      set -as terminal-overrides ',xterm-256color:Tc'
      set -as terminal-features 'xterm-ghostty:RGB:usstyle:overline:strikethrough:extkeys'
      set -s extended-keys on

      # Bell
      set -g bell-action any
      set -g visual-bell off

      # Inlined from tmux-sensible
      set -g display-time 4000
      set -g status-interval 5
      set -g status-keys emacs
      set -g focus-events on
      setw -g aggressive-resize on

      # Copy Mode
      unbind [
      bind Escape copy-mode
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${clip}"
      bind P paste-buffer
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "${clip}"

      # Sensible binds
      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Smart pane switching with awareness of Vim splits, SSH, and fzf
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
          | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf|ssh|mosh?)(diff)?$'"
      bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h'  'select-pane -L'
      bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j'  'select-pane -D'
      bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k'  'select-pane -U'
      bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l'  'select-pane -R'
      bind-key -n C-\\ if-shell "$is_vim" 'send-keys C-\\' 'select-pane -l'
      bind-key -T prefix l send-keys -R C-l \; clear-history

      # Pop-ups
      bind s display-popup -E -w 80% -h 70% -T ' Sessions ' -S 'fg=#bd93f9' -b rounded tmux-session-picker
      bind w display-popup -w 80% -h 80% -d "#{pane_current_path}"
      unbind k
      bind g run "open-github"

      bind N switch-client -l

      set -g status-position top
      bind-key x confirm-before -p "kill-pane #P? (y/n)" kill-pane
      set -g detach-on-destroy off
      set -g renumber-windows on
      set -s set-clipboard on

      # Pane borders
      set -g pane-border-lines heavy
      set -g pane-border-style 'fg=#6272a4'
      set -g pane-active-border-style 'fg=#bd93f9'

      # Status line (Dracula)
      set -g status-justify centre
      set -g status-style fg=colour250,bg=default
      set -g message-style fg=colour250,bg=default
      set -g message-command-style fg=colour250,bg=default

      set -g @PURPLE "#BD93F9"

      set -g status-left-length 60
      set -g status-left '#[fg=colour250]working on #[fg=#{@PURPLE},bold]#S#[default]'
      set -g status-right ""

      set -g window-status-style fg=colour244,bg=default
      set -g window-status-format ' #[fg=colour244]#I #[fg=colour250]#W '
      set -g window-status-current-format ' #[bg=#{@PURPLE},fg=black,bold] #I:#W #[bg=default,fg=#{@PURPLE}]'
    '';
  };
}
