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
      pkgs,
      system,
      ...
    }:
    let
      cfg = config.packageMetadataChecks;
    in
    {
      options.packageMetadataChecks = {
        enable = lib.mkEnableOption "package metadata checks";
        checks = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          default = [ ];
          description = "List of functions (meta -> { success: bool; error: nullable string; }) to validate package metadata";
        };
        packages = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          default = processedFlake.packages.${system};
          description = "The set of packages to check";
        };
      };

      config.checks = lib.mkIf cfg.enable (
        let
          checkPackageMetadata =
            { meta, name, ... }:
            let
              result = lib.pipe cfg.checks [
                (lib.map (check: {
                  inherit (check meta) success error;
                }))
                (lib.filter ({ success, ... }: !success))
              ];
            in
            if lib.length result == 0 then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = ''
                  Package `${name}` failed the following metadata checks:
                  ${lib.concatMapStringsSep "\n" ({ error, ... }: "- ${error}") result}
                '';
              };
        in
        lib.mapAttrs' (
          name: package:
          let
            result = checkPackageMetadata {
              inherit (package) meta;
              inherit name;
            };
          in
          lib.nameValuePair "packages:${name}/metadata" (
            pkgs.runCommand "check-metadata-${name}" { } (
              if result.success then
                "echo 'Package ${name} passed metadata validation' > $out"
              else
                ''
                  echo ${lib.escapeShellArg result.error} >&2
                  exit 1
                ''
            )
          )
        ) cfg.packages
      );
    }
  );
}
