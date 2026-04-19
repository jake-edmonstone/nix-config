{ pkgs, ... }:

let
  # AnkiWeb shared addon 688199788 is AnKing-VIP/AnkiRecolor ("ReColor"), a
  # Python addon that restyles Anki's Qt + card chrome. The addon directory
  # needs the full upstream source plus a meta.json carrying the user's
  # color choices. Previously we deployed only meta.json, which is why the
  # theme never applied — without __init__.py + support files, Anki reads
  # the metadata but has no code to execute.
  ankiRecolorSrc = pkgs.fetchFromGitHub {
    owner = "AnKing-VIP";
    repo = "AnkiRecolor";
    rev = "3.3"; # latest release (2025-08-11); matches version pinned in meta.json
    hash = "sha256-TbDUVCfqDXQmCwRgDW+hLZPfIElQAW2wFFgWOc3iKiU=";
  };

  # Merge upstream's src/addon/ with our Dracula-palette meta.json into one
  # deploy-ready directory. Read-only at runtime (store path); Anki doesn't
  # write to addon dirs — user state goes to Anki2/<profile>/collection.*.
  ankiRecolor = pkgs.runCommandLocal "anki-addon-recolor-688199788" { } ''
    cp -r ${ankiRecolorSrc}/src/addon $out
    chmod -R +w $out
    cp ${../config/anki/addons21/688199788/meta.json} $out/meta.json
  '';
in

{
  home.packages = [ pkgs.anki-bin ];

  home.file = {
    # AnkiRecolor — full addon body + our Dracula meta.json (one directory symlink)
    "Library/Application Support/Anki2/addons21/688199788".source = ankiRecolor;

    # Custom titlebar addon (tiny in-repo Python addon)
    "Library/Application Support/Anki2/addons21/dracula_titlebar".source =
      ../config/anki/addons21/dracula_titlebar;
  };
}
