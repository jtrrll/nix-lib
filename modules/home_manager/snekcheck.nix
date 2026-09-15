{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.snekcheck;
in
{
  options.programs.snekcheck = {
    enable = lib.mkEnableOption "snekcheck";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The snekcheck package to use";
      default = pkgs.snekcheck;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
