{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.bonsai;
in
{
  options.programs.bonsai = {
    enable = lib.mkEnableOption "a bonsai tree screensaver";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.bonsai ];
  };
}
