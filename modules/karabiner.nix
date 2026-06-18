{ pkgs, ... }:

let
  karabinerConfig = pkgs.formats.json { };
  karabinerDir = pkgs.runCommand "karabiner-config" { } ''
    mkdir -p $out
    ln -s ${
      karabinerConfig.generate "karabiner.json" {
        global = {
          check_for_updates_on_startup = false;
          show_in_menu_bar = true;
          show_profile_name_in_menu_bar = false;
        };

        profiles = [
          {
            name = "Default";
            selected = true;

            complex_modifications = {
              parameters = {
                "basic.to_if_alone_timeout_milliseconds" = 250;
                "basic.to_if_held_down_threshold_milliseconds" = 100;
              };
              rules = [
                {
                  description = "Caps Lock: tap Escape, hold Control";
                  manipulators = [
                    {
                      type = "basic";
                      from = {
                        key_code = "caps_lock";
                        modifiers.optional = [ "any" ];
                      };
                      to = [
                        {
                          key_code = "left_control";
                          lazy = true;
                        }
                      ];
                      to_if_alone = [
                        { key_code = "escape"; }
                      ];
                      to_if_held_down = [
                        { key_code = "left_control"; }
                      ];
                      parameters = {
                        "basic.to_if_alone_timeout_milliseconds" = 250;
                        "basic.to_if_held_down_threshold_milliseconds" = 100;
                      };
                    }
                  ];
                }
              ];
            };

            devices = [ ];
            fn_function_keys = [ ];
            simple_modifications = [ ];
            virtual_hid_keyboard = {
              keyboard_type_v2 = "ansi";
              caps_lock_delay_milliseconds = 0;
            };
          }
        ];
      }
    } $out/karabiner.json
  '';
in
{
  xdg.configFile."karabiner".source = karabinerDir;
}
