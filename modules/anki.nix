{
  lib,
  pkgs,
  ...
}:

let
  ankiConnectSrc = pkgs.fetchgit {
    url = "https://git.sr.ht/~foosoft/anki-connect";
    rev = "25.11.9.0";
    hash = "sha256-cnAH4qIuxSJIM7vmSDU+eppnRi6Out9oSWHBHKCGLZI=";
  };

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
  # deploy-ready directory. Activation copies it into Anki's writable addon
  # directory because Anki stores addon configuration beside the code.
  ankiRecolor = pkgs.runCommandLocal "anki-addon-recolor-688199788" { } ''
    cp -r ${ankiRecolorSrc}/src/addon $out
    chmod -R +w $out
    cp ${../config/anki/addons21/688199788/meta.json} $out/meta.json
  '';
in

{
  home.packages = [ pkgs.anki-bin ];

  # Anki writes meta.json/config into add-on directories, so whole-directory
  # symlinks into /nix/store fail when Anki checks for updates. Copy pinned code
  # into writable add-on folders instead.
  home.activation.installAnkiAddons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    addons="$HOME/Library/Application Support/Anki2/addons21"
    install_addon() {
      id="$1"
      src="$2"
      meta_policy="$3"
      dest="$addons/$id"

      args=(
        --archive
        --delete
        --exclude config.json
        --exclude user_files/
      )
      if [ "$meta_policy" = preserve ]; then
        args+=(--exclude meta.json)
      fi

      run mkdir -p "$dest"
      run ${pkgs.rsync}/bin/rsync "''${args[@]}" "$src/" "$dest/"
      run chmod -R u+w "$dest"

      # Seed an addon's default config on first install, then leave Anki's
      # writable copy untouched on subsequent activations.
      if [ ! -e "$dest/config.json" ] && [ -e "$src/config.json" ]; then
        run cp "$src/config.json" "$dest/config.json"
      fi
      run chmod -R u+w "$dest"
    }

    install_addon 2055492159 ${ankiConnectSrc}/plugin preserve
    install_addon 688199788 ${ankiRecolor} replace
    install_addon dracula_titlebar ${../config/anki/addons21/dracula_titlebar} preserve

  '';
}
