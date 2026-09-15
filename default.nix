{
  lib,
}:
let
  libOverlay = (import ./lib).overlay;
  lib' = lib.extend libOverlay;
in
let
  lib = lib';
in
{
  inherit lib;

  modules = lib.mapAttrs (_: lib.modules.aggregate) (
    lib.modules.modulesByClassAndName {
      path = ./modules;
      transform = class: name: module: {
        class = lib.strings.snakeToCamel class;
        name = lib.replaceStrings [ "_" ] [ "-" ] name;
        inherit module;
      };
    }
  );
  overlays.default =
    final: prev:
    {
      lib = prev.lib.extend libOverlay;
    }
    // lib.mapAttrs' (name: lib.nameValuePair (lib.replaceStrings [ "_" ] [ "-" ] name)) (
      lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ./pkgs;
      }
    );
}
