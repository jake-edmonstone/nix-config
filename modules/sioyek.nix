{ config, ... }:

{
  # Sioyek is packaged in nixpkgs and tracks the upstream development branch
  # (currently version string "2.0.0-unstable-2026-04-08"), which is ~3 years
  # and many macOS-codesigning fixes ahead of the last tagged release 2.0.0
  # (Dec 2022). The Homebrew cask is deprecated — its 2.0 build no longer
  # passes macOS Gatekeeper and Homebrew will disable it on 2026-09-01.
  # https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/s/sioyek.rb
  programs.sioyek = {
    enable = true;

    # History navigation (vim-style, backspace broken on macOS)
    bindings = {
      prev_state = "<C-o>";
      next_state = "<C-i>";
    };

    # Dracula theme (UI only — PDF content renders normally). All values are
    # strings per the home-manager option type; RGB floats are space-separated.
    config = {
      # Background (area around the PDF pages)
      background_color = "0.15686 0.16471 0.21176";
      dark_mode_background_color = "0.15686 0.16471 0.21176";

      # Custom colors (active via startup_commands)
      custom_background_color = "0.15686 0.16471 0.21176";
      custom_text_color = "0.97255 0.97255 0.94902";

      # UI
      ui_text_color = "0.97255 0.97255 0.94902";
      ui_background_color = "0.15686 0.16471 0.21176";
      ui_selected_text_color = "0.97255 0.97255 0.94902";
      ui_selected_background_color = "0.26667 0.27843 0.35294";
      status_bar_color = "0.15686 0.16471 0.21176";
      status_bar_text_color = "0.97255 0.97255 0.94902";
      status_bar_font_size = "14";

      # Highlights (Dracula palette)
      text_highlight_color = "0.94510 0.98039 0.54902";
      visual_mark_color = "0.15686 0.16471 0.21176 0.8";
      search_highlight_color = "0.94510 0.98039 0.54902";
      link_highlight_color = "0.38431 0.44706 0.64314";
      synctex_highlight_color = "0.31373 0.98039 0.48235";

      highlight_color_a = "1.00000 0.72157 0.42353";
      highlight_color_b = "0.31373 0.98039 0.48235";
      highlight_color_c = "0.54510 0.91373 0.99216";
      highlight_color_d = "1.00000 0.47451 0.77647";
      highlight_color_e = "0.74118 0.57647 0.97647";
      highlight_color_f = "1.00000 0.33333 0.33333";
      highlight_color_g = "0.94510 0.98039 0.54902";

      # Page separator
      page_separator_width = "2";
      page_separator_color = "0.26667 0.27843 0.35294";

      # Dark titlebar
      macos_titlebar_color = "0.15686 0.16471 0.21176";
      macos_dark_titlebar_color = "0.15686 0.16471 0.21176";

      # Font
      ui_font = "Maple Mono NF";
      font_size = "14";
    };
  };

  # Sioyek on macOS reads from ~/Library/Application Support/sioyek/, not the XDG
  # path. Redirect via symlink so the programs.sioyek-managed XDG configs are used.
  # (Module is only imported from home/darwin.nix, so no platform guard needed.)
  home.file."Library/Application Support/sioyek".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/sioyek";
}
