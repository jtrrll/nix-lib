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
      system,
      ...
    }:
    let
      cfg = config.packageBuildChecks;
    in
    {
      options.packageBuildChecks = {
        enable = lib.mkEnableOption "package build checks";
        packages = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          default = processedFlake.packages.${system};
          description = "The set of packages to check";
        };
      };

      config.checks = lib.mkIf cfg.enable (
        lib.mapAttrs' (name: package: lib.nameValuePair "packages:${name}/build" package) cfg.packages
      );
    }
  );
}
