{ config, ... }:
{
  config.perSystem =
    { lib, pkgs, ... }:
    let
      overlay = config.flake.overlays.default;
      legacyPackages = pkgs.extend overlay;
      # Only the derivations introduced by our overlay (drops `lib` and the
      # rest of nixpkgs), so the checks don't try to build all of legacyPackages.
      overlayPackages = lib.filterAttrs (_: lib.isDerivation) (overlay legacyPackages pkgs);
    in
    {
      inherit legacyPackages;
      packageBuildChecks = {
        enable = true;
        packages = overlayPackages;
      };
      packagePassthruTestsChecks = {
        enable = true;
        packages = overlayPackages;
      };
      packageMetadataChecks = {
        enable = true;
        packages = overlayPackages;
        checks = [
          (
            meta:
            if meta ? description then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "A description must be set";
              }
          )
          (
            meta:
            if lib.hasPrefix meta.name (meta.description or "") then
              {
                success = false;
                error = "The description should not repeat the package name";
              }
            else
              {
                success = true;
                error = null;
              }
          )
          (
            meta:
            if
              lib.substring 0 1 (meta.description or "")
              == lib.toUpper (lib.substring 0 1 (meta.description or ""))
            then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The first word of the description should be capitalized";
              }
          )
          (
            meta:
            if lib.hasInfix "\n" (meta.description or "") then
              {
                success = false;
                error = "The description should not contain newlines";
              }
            else
              {
                success = true;
                error = null;
              }
          )
          (
            meta:
            if lib.hasSuffix "." (meta.description or "") then
              {
                success = false;
                error = "The description should not end with punctuation";
              }
            else
              {
                success = true;
                error = null;
              }
          )
          (
            meta:
            if meta ? homepage then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "A homepage must be set";
              }
          )
          (
            meta:
            if meta ? license then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "A license must be set";
              }
          )
          (
            meta:
            if meta.license.free or false then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The license must be free";
              }
          )
          (
            meta:
            if meta ? maintainers then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The maintainers must be set";
              }
          )
          (
            meta:
            if lib.isList (meta.maintainers or [ ]) then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The maintainers must be a list";
              }
          )
          (
            meta:
            if (lib.length (meta.maintainers or [ ])) > 0 then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "At least one maintainer must be set";
              }
          )
          (
            meta:
            if meta ? platforms then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The supported platforms must be set";
              }
          )
          (
            meta:
            if lib.isList (meta.platforms or [ ]) then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The supported platforms must be a list";
              }
          )
          (
            meta:
            if meta ? sourceProvenance then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The source provenance must be set";
              }
          )
          (
            meta:
            if lib.isList (meta.sourceProvenance or [ ]) then
              {
                success = true;
                error = null;
              }
            else
              {
                success = false;
                error = "The source provenance must be a list";
              }
          )
        ];
      };
    };
}
