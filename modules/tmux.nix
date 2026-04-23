{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    shell = "${config.programs.zsh.package}/bin/zsh";
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 50000;
    focusEvents = true;
    aggressiveResize = false;
    sensibleOnTop = true; # sources tmux-sensible (display-time, status-interval, status-keys emacs, etc.)

    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuum;
        extraConfig = "set -g @continuum-restore 'on'";
      }
    ];

    extraConfig = ''
      set -s allow-passthrough on

      # Refresh HM-managed env vars on every client attach. After a
      # `home-manager switch` changes a sessionVariable (e.g. FZF_DEFAULT_OPTS),
      # detach+reattach pulls the new value from the client env into the
      # session env, so subsequent new-window/split-window inherit it. Without
      # this, a tmux server started before the rebuild keeps the stale value
      # forever (shells see __HM_SESS_VARS_SOURCED=1 and skip re-sourcing).
      set -ag update-environment 'FZF_DEFAULT_OPTS FZF_DEFAULT_COMMAND FZF_CTRL_T_OPTS FZF_CTRL_T_COMMAND FZF_ALT_C_OPTS FZF_ALT_C_COMMAND PATH'

      # Terminal settings (Ghostty). :RGB in terminal-features is the modern
      # (tmux 3.2+) replacement for the older :Tc terminal-override — one knob
      # covers truecolor for both xterm-ghostty and xterm-256color.
      set -as terminal-features 'xterm-ghostty:RGB:usstyle:overline:strikethrough:extkeys'
      # Tell tmux every outer terminal supports OSC52 clipboard. Combined with
      # `set-clipboard on` below, copying in copy-mode sends an OSC52 escape so
      # the outer terminal emulator (Ghostty locally, whatever's connected over
      # ssh remotely) writes to the system clipboard. No xclip/xsel/pbcopy
      # dependency — works headlessly, works over ssh, works in tmux splits.
      set -ag terminal-features '*:clipboard'
      set -s extended-keys on

      # Bell
      set -g bell-action any
      set -g visual-bell off

      # Copy Mode — OSC52 via set-clipboard on (see terminal-features above).
      # copy-selection-and-cancel writes to tmux's buffer AND sends OSC52.
      unbind [
      bind Escape copy-mode
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind P paste-buffer
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-and-cancel

      # Sensible binds
      bind r source-file ${config.xdg.configHome}/tmux/tmux.conf \; display "Reloaded!"
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
