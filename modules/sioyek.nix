{ config, ... }:

let
  theme = import ../theme.nix;
  rgb =
    if theme.isDark then
      {
        background = "0.15686 0.16471 0.21176";
        foreground = "0.97255 0.97255 0.94902";
        selection = "0.26667 0.27843 0.35294";
        comment = "0.38431 0.44706 0.64314";
        red = "1.00000 0.33333 0.33333";
        orange = "1.00000 0.72157 0.42353";
        yellow = "0.94510 0.98039 0.54902";
        green = "0.31373 0.98039 0.48235";
        cyan = "0.54510 0.91373 0.99216";
        purple = "0.74118 0.57647 0.97647";
        pink = "1.00000 0.47451 0.77647";
      }
    else
      {
        background = "1.00000 0.98431 0.92157";
        foreground = "0.12157 0.12157 0.12157";
        selection = "0.81176 0.81176 0.87059";
        comment = "0.42353 0.40000 0.29412";
        red = "0.79608 0.22745 0.16471";
        orange = "0.63922 0.30196 0.07843";
        yellow = "0.51765 0.43137 0.08235";
        green = "0.07843 0.44314 0.03922";
        cyan = "0.01176 0.41569 0.58824";
        purple = "0.39216 0.29020 0.78824";
        pink = "0.63922 0.07843 0.30196";
      };
in

{
  # nixpkgs tracks Sioyek's development branch rather than the old 2.0 tag.
  # The Homebrew cask still uses that deprecated release, so keep this Nix-managed.
  # https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/s/sioyek.rb
  programs.sioyek = {
    enable = true;

    # History navigation (vim-style, backspace broken on macOS)
    bindings = {
      prev_state = "<C-o>";
      next_state = "<C-i>";
    };

    # Selected theme (UI only — PDF content renders normally). All values are
    # strings per the home-manager option type; RGB floats are space-separated.
    config = {
      # Background (area around the PDF pages)
      background_color = rgb.background;
      dark_mode_background_color = rgb.background;

      # Custom document recoloring, when toggled in Sioyek.
      custom_background_color = rgb.background;
      custom_text_color = rgb.foreground;

      # UI
      ui_text_color = rgb.foreground;
      ui_background_color = rgb.background;
      ui_selected_text_color = rgb.foreground;
      ui_selected_background_color = rgb.selection;
      status_bar_color = rgb.background;
      status_bar_text_color = rgb.foreground;
      status_bar_font_size = "14";

      # Highlights
      text_highlight_color = rgb.yellow;
      visual_mark_color = "${rgb.background} 0.8";
      search_highlight_color = rgb.yellow;
      link_highlight_color = rgb.comment;
      synctex_highlight_color = rgb.green;

      highlight_color_a = rgb.orange;
      highlight_color_b = rgb.green;
      highlight_color_c = rgb.cyan;
      highlight_color_d = rgb.pink;
      highlight_color_e = rgb.purple;
      highlight_color_f = rgb.red;
      highlight_color_g = rgb.yellow;

      # Page separator
      page_separator_width = "2";
      page_separator_color = rgb.selection;

      # Titlebar
      macos_titlebar_color = rgb.background;
      macos_dark_titlebar_color = rgb.background;

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
