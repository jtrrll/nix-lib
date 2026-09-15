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
      cfg = config.nixosConfigurationBuildChecks;
    in
    {
      options.nixosConfigurationBuildChecks = {
        enable = lib.mkEnableOption "NixOS configuration build checks";
        extraModules = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          default = [ ];
          description = "Extra modules applied to each NixOS configuration before building it for this system.";
        };
        nixosConfigurations = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = processedFlake.nixosConfigurations;
          description = "The NixOS configurations to check";
        };
      };

      config.checks = lib.mkIf cfg.enable (
        lib.mapAttrs' (
          name: nixos:
          lib.nameValuePair "nixosConfigurations:${name}/build" (
            if cfg.extraModules == [ ] then
              nixos.config.system.build.toplevel
            else
              (nixos.extendModules { modules = cfg.extraModules; }).config.system.build.toplevel
          )
        ) cfg.nixosConfigurations
      );
    }
  );
}
