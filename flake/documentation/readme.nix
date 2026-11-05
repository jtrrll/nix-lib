{
  config.perSystem =
    {
      lib,
      pkgs,
      ...
    }:
    let
      nixLib = import ../.. { inherit lib; };

      renderSection =
        name: items:
        lib.concatStrings [
          "### `${name}`\n\n"
          "<details>\n<summary>Show ${toString (lib.length items)}</summary>\n\n"
          "${lib.concatStringsSep "\n\n" items}\n\n"
          "</details>"
        ];
      renderEntry =
        name: children:
        lib.concatStringsSep "\n" ([ "- `${name}`" ] ++ map (child: "  - ${child}") children);

      modulesMarkdown = renderSection "modules" (
        lib.mapAttrsToList (
          class: modules: renderEntry class (map (name: "`${name}`") (lib.attrNames modules))
        ) nixLib.modules
      );

      overlayContents = {
        lib =
          let
            extended = lib.extend nixLib.overlays.lib;
          in
          map (name: "`${name}`") (lib.attrNames (nixLib.overlays.lib extended lib));
        pkgs =
          let
            extended = pkgs.extend nixLib.overlays.pkgs;
            packages = lib.filterAttrs (_: lib.isDerivation) (nixLib.overlays.pkgs extended pkgs);
          in
          lib.mapAttrsToList (
            name: package:
            "`${name}`${lib.optionalString (package.meta ? description) " - ${package.meta.description}"}"
          ) packages;
      };
      overlaysMarkdown = renderSection "overlays" (
        lib.mapAttrsToList renderEntry (lib.getAttrs (lib.attrNames nixLib.overlays) overlayContents)
      );

      outputsMarkdown = lib.concatStringsSep "\n\n" [
        modulesMarkdown
        overlaysMarkdown
      ];
    in
    {
      config = {
        files = {
          file."README.md".text = ''
            # nix-lib

            <!-- markdownlint-disable MD013 -->
            ![CI Status](https://img.shields.io/github/actions/workflow/status/jtrrll/nix-lib/ci.yaml?branch=main&label=ci&logo=github)
            ![License](https://img.shields.io/github/license/jtrrll/nix-lib?label=license&logo=googledocs&logoColor=white)
            <!-- markdownlint-enable MD013 -->

            A reusable Nix library for jtrrll's repositories.

            ## Usage

            This is a plain Nix library, not a flake. Add it as a `flake = false`
            input:

            ```nix
            {
              inputs = {
                nix-lib = {
                  flake = false;
                  url = "github:jtrrll/nix-lib";
                };
                nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
              };

              outputs = inputs: {
                ...
              };
            }
            ```

            Then import it with a nixpkgs `lib`. It returns an attribute set of
            `lib`, `modules`, and separate library and package `overlays`:

            ```nix
            inputs:
            let
              nix-lib = import inputs.nix-lib { lib = inputs.nixpkgs.lib; };
              inherit (nix-lib)
                lib
                modules
                overlays
                ;
            in
            {
              # Apply the package overlay to access the new packages and extended lib.
              nixpkgs' = import inputs.nixpkgs {
                inherit system;
                overlays = [ overlays.pkgs ];
              };

              # Access reusable modules, grouped by class.
              # Each class exposes its individual modules and a `default` that imports all of them.
              myNixosConfiguration = inputs.nixpkgs.lib.nixosSystem {
                inherit lib; # Use the extended library during NixOS module evaluation.
                modules = [
                  modules.nixos.default
                  {
                    nixpkgs.overlays = [ overlays.pkgs ];
                  }
                  {
                    ...
                  }
                ];
              };

              # Use the extended lib directly.
              transformedString = lib.strings.snakeToCamel "foo_bar";
            }
            ```

            ## Outputs

            ${outputsMarkdown}

            ## License

            This repository is licensed under the terms in [`LICENSE`](./LICENSE).

            That license covers the repository's own code (the library, overlays,
            and module definitions). It does **not** inherently apply to the
            packages built by this repository. Some of them package third-party
            software with its own licensing. Consult each package's individual
            license before use or redistribution.
          '';
          writer.app = true;
        };
      };
    };
}
