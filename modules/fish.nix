{
  pkgs,
  ...
}:

let
  theme = import ../theme.nix;
  color = name: theme.noHash theme.palette.${name};
in

{
  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "tide";
        inherit (pkgs.fishPlugins.tide) src;
      }
    ];

    shellAliases = {
      grep = "grep --ignore-case --color=auto";
    };

    shellAbbrs = {
      lg = "lazygit";
      ta = "tmux attach -t";
      tn = "tmux new -s";
      tls = "tmux ls";
      trn = "tmux rename-session";
    };

    functions = {
      mkcd = ''
        if test (count $argv) -eq 0
          echo "mkcd: missing arg" >&2
          return 2
        end
        mkdir -p -- $argv[1]; and cd -- $argv[1]
      '';

      _tide_item_context = ''
        set -q SSH_TTY; or return
        test "$PWD" = "$HOME"; or return

        string match -qr "^(?<h>(\.?[^\.]*){0,$tide_context_hostname_parts})" @$hostname
        set -l host (string replace -r '^@' "" -- $h)
        set -l context (set_color ${color "cyan"})$USER(set_color normal)" in "(set_color ${color "purple"})$host(set_color normal)" in"
        set -fx tide_context_color normal
        _tide_print_item context $context
      '';

      _tide_item_nix_shell = ''
        set -l nix_shell_label

        if set -q IN_NIX_SHELL
          set nix_shell_label $IN_NIX_SHELL
        else if string match -q '/nix/store/*' -- $PATH
          set nix_shell_label shell
        else
          return
        end

        _tide_print_item nix_shell $tide_nix_shell_icon' ' $nix_shell_label
      '';
    };

    binds = {
      edit-command-buffer-default = {
        name = "ctrl-x,ctrl-e";
        mode = "default";
        command = "edit_command_buffer";
      };
      edit-command-buffer-insert = {
        name = "ctrl-x,ctrl-e";
        mode = "insert";
        command = "edit_command_buffer";
      };
    };

    shellInit = ''
      # Neovim's LSP clients and watcher-backed autoread need more than macOS's
      # default 256 descriptors. Only raise the soft limit inherited by tools.
      ulimit -Sn 8192
    '';

    interactiveShellInit = ''
      set -g fish_greeting

      set -g fish_color_normal ${color "foreground"}
      set -g fish_color_command ${color "green"}
      set -g fish_color_keyword ${color "pink"}
      set -g fish_color_quote ${color "yellow"}
      set -g fish_color_redirection ${color "cyan"} --bold
      set -g fish_color_end ${color "pink"}
      set -g fish_color_error ${color "red"}
      set -g fish_color_param ${color "foreground"}
      set -g fish_color_comment ${color "comment"} --italics
      set -g fish_color_selection ${color "foreground"} --background=${color "selection"}
      set -g fish_color_search_match ${color "foreground"} --background=${color "selection"} --bold
      set -g fish_color_operator ${color "pink"}
      set -g fish_color_escape ${color "cyan"}
      set -g fish_color_autosuggestion ${color "comment"}
      set -g fish_color_cancel ${color "red"}
      set -g fish_color_cwd ${color "purple"}
      set -g fish_color_cwd_root ${color "red"}
      set -g fish_color_user ${color "green"}
      set -g fish_color_host ${color "cyan"}
      set -g fish_color_host_remote ${color "orange"}
      set -g fish_color_status ${color "red"}
      set -g fish_color_valid_path --underline
      set -g fish_color_history_current --bold
      set -g fish_pager_color_progress ${color "comment"}
      set -g fish_pager_color_prefix ${color "purple"} --bold --underline
      set -g fish_pager_color_completion ${color "foreground"}
      set -g fish_pager_color_description ${color "yellow"} --italics
      set -g fish_pager_color_selected_background --background=${color "selection"}
      set -g fish_pager_color_selected_prefix ${color "pink"} --bold --underline
      set -g fish_pager_color_selected_completion ${color "foreground"}
      set -g fish_pager_color_selected_description ${color "yellow"}

      # Tide renders in a separate `fish -c` process, so its configuration
      # must use Tide's intended universal scope to be visible there.
      set -U tide_left_prompt_items context pwd git jobs python nix_shell cmd_duration status newline character
      set -U tide_right_prompt_items
      set -U tide_prompt_add_newline_before true
      set -U tide_prompt_transient_enabled false
      set -U tide_prompt_pad_items false
      set -U tide_prompt_min_cols 40

      set -U tide_left_prompt_frame_enabled false
      set -U tide_left_prompt_prefix ""
      set -U tide_left_prompt_separator_diff_color " "
      set -U tide_left_prompt_separator_same_color " "
      set -U tide_left_prompt_suffix " "
      set -U tide_right_prompt_frame_enabled false
      set -U tide_right_prompt_prefix " "
      set -U tide_right_prompt_separator_diff_color " "
      set -U tide_right_prompt_separator_same_color " "
      set -U tide_right_prompt_suffix ""
      set -U tide_prompt_icon_connection " "

      set -l prompt_character (printf '\e[1mλ\e[22m')
      set -U tide_character_icon $prompt_character
      set -U tide_character_vi_icon_default $prompt_character
      set -U tide_character_vi_icon_replace $prompt_character
      set -U tide_character_vi_icon_visual $prompt_character
      set -U tide_character_color ${color "green"}
      set -U tide_character_color_failure ${color "red"}
      set -U tide_status_icon "✔"
      set -U tide_status_icon_failure "✘"
      set -U tide_status_color ${color "green"}
      set -U tide_status_color_failure ${color "red"}
      set -U tide_status_bg_color normal
      set -U tide_status_bg_color_failure normal

      set -U tide_pwd_icon
      set -U tide_pwd_icon_home
      set -U tide_pwd_icon_unwritable ""
      set -U tide_pwd_bg_color normal
      set -U tide_pwd_color_dirs ${color "purple"}
      set -U tide_pwd_color_anchors ${color "purple"}
      set -U tide_pwd_color_truncated_dirs ${color "purple"}
      set -U tide_pwd_markers .bzr .citc .git .hg .node-version .python-version .ruby-version .shorten_folder_marker .svn .terraform bun.lockb Cargo.toml composer.json CVS go.mod package.json build.zig

      set -U tide_git_icon (set_color ${color "foreground"})on(set_color ${color "pink"})
      set -U tide_git_bg_color normal
      set -U tide_git_bg_color_unstable normal
      set -U tide_git_bg_color_urgent normal
      set -U tide_git_color_branch ${color "pink"}
      set -U tide_git_color_conflicted ${color "red"}
      set -U tide_git_color_dirty ${color "orange"}
      set -U tide_git_color_operation ${color "red"}
      set -U tide_git_color_staged ${color "orange"}
      set -U tide_git_color_stash ${color "green"}
      set -U tide_git_color_untracked ${color "green"}
      set -U tide_git_color_upstream ${color "green"}
      set -U tide_git_truncation_length 64
      set -U tide_git_truncation_strategy

      set -U tide_jobs_icon ""
      set -U tide_jobs_color ${color "green"}
      set -U tide_jobs_bg_color normal
      set -U tide_jobs_number_threshold 1

      set -U tide_python_icon
      set -U tide_python_color ${color "cyan"}
      set -U tide_python_bg_color normal
      set -U tide_nix_shell_icon ""
      set -U tide_nix_shell_color ${color "cyan"}
      set -U tide_nix_shell_bg_color normal

      set -U tide_cmd_duration_icon
      set -U tide_cmd_duration_color ${color "yellow"}
      set -U tide_cmd_duration_bg_color normal
      set -U tide_cmd_duration_decimals 0
      set -U tide_cmd_duration_threshold 3000

      set -U tide_context_always_display false
      set -U tide_context_bg_color normal
      set -U tide_context_color_default ${color "cyan"}
      set -U tide_context_color_root ${color "red"}
      set -U tide_context_color_ssh ${color "cyan"}
      set -U tide_context_hostname_parts 1

      set -g fish_cursor_default block blink
      set -g fish_cursor_insert line blink
      set -g fish_cursor_replace_one underscore blink
      set -g fish_cursor_visual block blink

      fish_vi_key_bindings
      fish_user_key_bindings
    '';
  };
}
