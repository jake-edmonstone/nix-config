{
  pkgs,
  lib,
  isRootlessLinux,
  ...
}:

{
  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "tide";
        inherit (pkgs.fishPlugins.tide) src;
      }
      {
        name = "fzf-fish";
        inherit (pkgs.fishPlugins.fzf-fish) src;
      }
    ];

    shellAliases = {
      grep = "grep --ignore-case --color=auto";
    };

    shellAbbrs = {
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

      rebuild = ''
        switch (uname -s)
          case Darwin
            nh darwin switch "$DOTFILES" -H "$REBUILD_FLAKE_ATTR" $argv
          case Linux
            nh home switch "$DOTFILES" -c "$REBUILD_FLAKE_ATTR" $argv
          case '*'
            echo "rebuild: unsupported OS: "(uname -s) >&2
            return 1
        end
      '';

      _cursor_blinking_block = {
        onEvent = "fish_prompt";
        body = ''
          isatty stdout
          and printf '\e[?25h\e[1 q'
        '';
      };

      _tide_item_context = ''
        set -q SSH_TTY; or return
        test "$PWD" = "$HOME"; or return

        string match -qr "^(?<h>(\.?[^\.]*){0,$tide_context_hostname_parts})" @$hostname
        set -l host (string replace -r '^@' "" -- $h)
        set -l context (set_color 8BE9FD)$USER(set_color normal)" in "(set_color BD93F9)$host(set_color normal)" in"
        set -fx tide_context_color normal
        _tide_print_item context $context
      '';

      _fzf_search_directory_depth_1 = ''
        set -lx fzf_fd_opts --max-depth 1
        _fzf_search_directory
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
      "ctrl-x,ctrl-e".command = "edit_command_buffer";
      ctrl-f.command = "_fzf_search_directory_depth_1";
    };

    shellInit = ''
      set -g fish_greeting

      ${lib.optionalString isRootlessLinux ''
        if set -q NP_ENTERED; and not command -q nix
          fish_add_path --global ${pkgs.nix}/bin
        end
      ''}

      set -g fish_color_normal F8F8F2
      set -g fish_color_command 50FA7B
      set -g fish_color_keyword FF79C6
      set -g fish_color_quote F1FA8C
      set -g fish_color_redirection 8BE9FD --bold
      set -g fish_color_end FF79C6
      set -g fish_color_error FF5555
      set -g fish_color_param F8F8F2
      set -g fish_color_comment 6272A4 --italics
      set -g fish_color_selection F8F8F2 --background=44475A
      set -g fish_color_search_match F8F8F2 --background=44475A --bold
      set -g fish_color_operator FF79C6
      set -g fish_color_escape 8BE9FD
      set -g fish_color_autosuggestion 6272A4
      set -g fish_color_cancel FF5555
      set -g fish_color_cwd BD93F9
      set -g fish_color_cwd_root FF5555
      set -g fish_color_user 50FA7B
      set -g fish_color_host 8BE9FD
      set -g fish_color_host_remote FFB86C
      set -g fish_color_status FF5555
      set -g fish_color_valid_path --underline
      set -g fish_color_history_current --bold
      set -g fish_pager_color_progress 6272A4
      set -g fish_pager_color_prefix BD93F9 --bold --underline
      set -g fish_pager_color_completion F8F8F2
      set -g fish_pager_color_description F1FA8C --italics
      set -g fish_pager_color_selected_background --background=44475A
      set -g fish_pager_color_selected_prefix FF79C6 --bold --underline
      set -g fish_pager_color_selected_completion F8F8F2
      set -g fish_pager_color_selected_description F1FA8C

      set -g tide_left_prompt_items context pwd git jobs python nix_shell cmd_duration status newline character
      set -g tide_right_prompt_items
      set -g tide_prompt_add_newline_before true
      set -g tide_prompt_transient_enabled false
      set -g tide_prompt_pad_items false
      set -g tide_prompt_min_cols 40

      set -g tide_left_prompt_frame_enabled false
      set -g tide_left_prompt_prefix ""
      set -g tide_left_prompt_separator_diff_color " "
      set -g tide_left_prompt_separator_same_color " "
      set -g tide_left_prompt_suffix " "
      set -g tide_right_prompt_frame_enabled false
      set -g tide_right_prompt_prefix " "
      set -g tide_right_prompt_separator_diff_color " "
      set -g tide_right_prompt_separator_same_color " "
      set -g tide_right_prompt_suffix ""
      set -g tide_prompt_icon_connection " "

      set -l tide_bold_lambda (printf '\e[1mλ\e[22m')
      set -g tide_character_icon $tide_bold_lambda
      set -g tide_character_vi_icon_default $tide_bold_lambda
      set -g tide_character_vi_icon_replace $tide_bold_lambda
      set -g tide_character_vi_icon_visual $tide_bold_lambda
      set -g tide_character_color 50FA7B
      set -g tide_character_color_failure FF5555
      set -g tide_status_icon "✔"
      set -g tide_status_icon_failure "✘"
      set -g tide_status_color 50FA7B
      set -g tide_status_color_failure FF5555
      set -g tide_status_bg_color normal
      set -g tide_status_bg_color_failure normal

      set -g tide_pwd_icon
      set -g tide_pwd_icon_home
      set -g tide_pwd_icon_unwritable ""
      set -g tide_pwd_bg_color normal
      set -g tide_pwd_color_dirs BD93F9
      set -g tide_pwd_color_anchors BD93F9
      set -g tide_pwd_color_truncated_dirs BD93F9
      set -g tide_pwd_markers .bzr .citc .git .hg .node-version .python-version .ruby-version .shorten_folder_marker .svn .terraform bun.lockb Cargo.toml composer.json CVS go.mod package.json build.zig

      set -g tide_git_icon (set_color white)on(set_color FF79C6)
      set -g tide_git_bg_color normal
      set -g tide_git_bg_color_unstable normal
      set -g tide_git_bg_color_urgent normal
      set -g tide_git_color_branch FF79C6
      set -g tide_git_color_conflicted FF5555
      set -g tide_git_color_dirty FFB86C
      set -g tide_git_color_operation FF5555
      set -g tide_git_color_staged FFB86C
      set -g tide_git_color_stash 50FA7B
      set -g tide_git_color_untracked 50FA7B
      set -g tide_git_color_upstream 50FA7B
      set -g tide_git_truncation_length 64
      set -g tide_git_truncation_strategy

      set -g tide_jobs_icon ""
      set -g tide_jobs_color 50FA7B
      set -g tide_jobs_bg_color normal
      set -g tide_jobs_number_threshold 1

      set -g tide_python_icon
      set -g tide_python_color 8BE9FD
      set -g tide_python_bg_color normal
      set -g tide_nix_shell_icon ""
      set -g tide_nix_shell_color 8BE9FD
      set -g tide_nix_shell_bg_color normal

      set -g tide_cmd_duration_icon
      set -g tide_cmd_duration_color F1FA8C
      set -g tide_cmd_duration_bg_color normal
      set -g tide_cmd_duration_decimals 0
      set -g tide_cmd_duration_threshold 3000

      set -g tide_context_always_display false
      set -g tide_context_bg_color normal
      set -g tide_context_color_default 8BE9FD
      set -g tide_context_color_root FF5555
      set -g tide_context_color_ssh 8BE9FD
      set -g tide_context_hostname_parts 1
    '';

    interactiveShellInit = ''
      fish_user_key_bindings
    '';
  };
}
