{
  config,
  lib,
  pkgs,
  ...
}:

let
  theme = import ../theme.nix;
  inherit (theme) palette;
  statusText = if theme.isDark then "colour250" else palette.foreground;
  statusMuted = if theme.isDark then "colour244" else palette.comment;
  activeText = if theme.isDark then "black" else palette.background;
  pickerColors = lib.concatStringsSep "," [
    "bg+:-1"
    "border:${palette.comment}"
    "fg:${palette.foreground}"
    "fg+:${palette.foreground}"
    "header:${palette.comment}"
    "hl:${palette.purple}"
    "hl+:${palette.purple}"
    "label:${palette.purple}"
    "marker:${palette.pink}"
    "pointer:${palette.pink}"
    "prompt:${palette.green}"
  ];
in

{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    shell = "${config.programs.fish.package}/bin/fish";
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 50000;
    focusEvents = true;
    aggressiveResize = false;

    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          # Set before continuum loads; the plugin appends its autosave hook here.
          set -g status-right "#(${config.home.homeDirectory}/.local/bin/tmux-timewarrior-status '${palette.purple}' '${statusText}' '${statusMuted}')"
        '';
      }
    ];

    extraConfig = ''
      # Window option, not server option; `-s` errors before a session exists.
      set -g allow-passthrough on

      # Refresh HM-managed env vars on every client attach. After a
      # `home-manager switch` changes a sessionVariable (e.g. FZF_DEFAULT_OPTS),
      # detach+reattach pulls the new value from the client env into the
      # session env, so subsequent new-window/split-window inherit it. Without
      # this, a tmux server started before the rebuild keeps the stale value
      # forever (shells see __HM_SESS_VARS_SOURCED=1 and skip re-sourcing).
      set -ag update-environment 'FZF_DEFAULT_OPTS FZF_DEFAULT_COMMAND FZF_CTRL_T_OPTS FZF_CTRL_T_COMMAND FZF_ALT_C_OPTS FZF_ALT_C_COMMAND PATH'

      # Terminal settings (Ghostty). :RGB in terminal-features is the modern
      # (tmux 3.2+) replacement for the older :Tc terminal-override.
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

      # Explicitly retain the useful tmux-sensible behavior without loading a
      # plugin that otherwise duplicates Home Manager's tmux options.
      set -g status-interval 5
      set -g display-time 4000
      bind r source-file ${config.xdg.configHome}/tmux/tmux.conf \; display "Reloaded!"
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Smart pane switching with awareness of Vim splits, SSH, and fzf
      is_vim='#{m/r:^(g?(view|vim|vimdiff|nvim|nvimdiff|lvim)|fzf|ssh|mosh)$,#{pane_current_command}}'
      bind-key -n 'C-h' if-shell -F "$is_vim" 'send-keys C-h'  'select-pane -L'
      bind-key -n 'C-j' if-shell -F "$is_vim" 'send-keys C-j'  'select-pane -D'
      bind-key -n 'C-k' if-shell -F "$is_vim" 'send-keys C-k'  'select-pane -U'
      bind-key -n 'C-l' if-shell -F "$is_vim" 'send-keys C-l'  'select-pane -R'
      bind-key -n C-\\ if-shell -F "$is_vim" 'send-keys C-\\' 'select-pane -l'
      bind-key -T prefix l send-keys -R C-l \; clear-history

      # Pop-ups
      bind s display-popup -E -w 80% -h 70% -T ' Sessions ' -S 'fg=${palette.purple}' -b rounded tmux-session-picker '${pickerColors}'
      bind w display-popup -w 80% -h 80% -d "#{pane_current_path}"
      unbind k
      bind g run-shell -b -c "#{pane_current_path}" "gh browse"

      bind N switch-client -l

      set -g status-position top
      bind-key x confirm-before -p "kill-pane #P? (y/n)" kill-pane
      set -g detach-on-destroy off
      set -g renumber-windows on
      set -s set-clipboard on

      # Pane borders
      set -g pane-border-lines heavy
      set -g pane-border-style 'fg=${palette.comment}'
      set -g pane-active-border-style 'fg=${palette.purple}'

      # Status line
      set -g status-justify centre
      set -g status-style fg=${statusText},bg=default
      set -g message-style fg=${statusText},bg=default
      set -g message-command-style fg=${statusText},bg=default

      set -g @ACCENT "${palette.purple}"

      set -g status-left-length 60
      set -g status-left '#[fg=#{@ACCENT},bold]#S#[default]'
      set -g status-right-length 80

      set -g automatic-rename-format '#{?#{==:#{pane_current_command},codex-raw},codex,#{pane_current_command}}'
      set -g window-status-style fg=${statusMuted},bg=default
      set -g window-status-format ' #[fg=${statusMuted}]#I #[fg=${statusText}]#W '
      set -g window-status-current-format ' #[bg=#{@ACCENT},fg=${activeText},bold] #I:#W #[bg=default,fg=#{@ACCENT}]'
    '';
  };
}
