{
  config,
  lib,
  ...
}:
{
  options.services.musicLibrary = {
    enable = lib.mkEnableOption "a curated music library";
  };

  config = lib.mkIf config.services.musicLibrary.enable {
    home.file.musicLibrary = {
      target = "music_library/README.md";
      text = ''
        # ~/music_library

        A library directory for music.

      '';
    };
    programs.beets.settings = lib.mkIf config.programs.beets.enable {
      directory = "${config.home.homeDirectory}/music_library";
      library = "${config.home.homeDirectory}/music_library/library.db";
    };
  };
}
