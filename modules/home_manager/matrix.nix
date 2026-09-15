{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.matrix;
in
{
  options.programs.matrix = {
    enable = lib.mkEnableOption "a matrix rain screensaver";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.matrix ];
  };
}
