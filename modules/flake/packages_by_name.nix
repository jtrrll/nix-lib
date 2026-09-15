{
  config,
  lib,
  ...
}:
{
  options.packagesByName = {
    enable = lib.mkEnableOption "package discovery by name";
    path = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./by_name";
      description = ''
        Directory containing packages, each either a `<name>/package.nix` file
        (directory style) or a flat `<name>.nix` file. Every package is
        called and exposed as `perSystem.packages.<name>`. When `null`, no packages are wired up.
      '';
    };

    overlays = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo (lib.types.functionTo lib.types.attrs));
      default = [ ];
      description = ''
        Overlays applied to `pkgs` before each package is called. Use this to
        extend the package set or `pkgs.lib` for the package definitions. These
        compose into the overlay's `final`, so their effects (e.g. a `lib`
        extension) are visible to consumers of `flake.overlays.default`. The
        discovered packages are always added to `final`, so packages may
        reference one another.
      '';
    };

    transform = lib.mkOption {
      type = lib.types.functionTo (
        lib.types.functionTo (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "The attribute name of the package.";
              };
              package = lib.mkOption {
                type = lib.types.either lib.types.package (lib.types.functionTo lib.types.package);
                description = ''
                  The package, or a builder function. Only actual packages are exposed via
                  `perSystem.packages` and checked by the package checks;
                  builder functions are only added to `flake.overlays.default`.
                '';
              };
            };
          }
        )
      );
      default = name: package: { inherit name package; };
      defaultText = lib.literalExpression "name: package: { inherit name package; }";
      description = ''
        Applied to each discovered package as `name: package: { name; package; }`.
        Use it to rename packages and/or add common metadata or otherwise
        post-process every package. The returned `name` becomes the attribute
        name (in `perSystem.packages` and `flake.overlays.default`) and the
        returned `package` is the value. Defaults to identity.
      '';
    };
  };

  config =
    let
      discoveredPackages =
        pkgs:
        lib.pipe config.packagesByName.path [
          (
            path:
            lib.optionalAttrs (path != null) (
              lib.packagesFromDirectoryRecursive {
                inherit (pkgs) callPackage;
                directory = path;
              }
            )
          )
          (lib.mapAttrs' (
            name: pkg:
            let
              result = config.packagesByName.transform name pkg;
            in
            lib.nameValuePair result.name result.package
          ))
        ];
    in
    lib.mkIf config.packagesByName.enable {
      flake.overlays.default = lib.composeManyExtensions (
        config.packagesByName.overlays ++ [ (final: _prev: discoveredPackages final) ]
      );
      perSystem =
        { pkgs, ... }:
        {
          config.packages = lib.filterAttrs (_: lib.isDerivation) (
            discoveredPackages (pkgs.extend config.flake.overlays.default)
          );
        };
    };
}
