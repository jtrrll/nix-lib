{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.edit;
in
{
  options.programs.edit = {
    enable = lib.mkEnableOption "edit";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The edit package to use";
      default = pkgs.edit;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
