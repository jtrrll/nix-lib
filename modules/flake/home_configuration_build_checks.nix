{
  config,
  flake-parts-lib,
  ...
}:
let
  inherit (config) processedFlake;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.homeConfigurationBuildChecks;
    in
    {
      options.homeConfigurationBuildChecks = {
        enable = lib.mkEnableOption "Home Manager configuration build checks";
        extraModules = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          default = [ ];
          description = "Extra modules applied to each Home Manager configuration before building it for this system.";
        };
        homeConfigurations = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = processedFlake.homeConfigurations;
          description = "The Home Manager configurations to check";
        };
      };

      config.checks = lib.mkIf cfg.enable (
        lib.mapAttrs' (
          name: hm:
          lib.nameValuePair "homeConfigurations:${name}/build" (
            if cfg.extraModules == [ ] then
              hm.activationPackage
            else
              (hm.extendModules { modules = cfg.extraModules; }).activationPackage
          )
        ) cfg.homeConfigurations
      );
    }
  );
}
