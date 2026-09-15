{ config, ... }:
{
  config.perSystem =
    let
      inherit (config.flake) nixosModules;
      inherit (config) processedFlake;
    in
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      renderValue =
        v:
        if v ? _type && v._type == "literalExpression" then
          v.text
        else if v ? _type && v._type == "literalMD" then
          v.text
        else
          lib.generators.toJSON { } v;
      renderOption =
        opt:
        let
          inherit (opt) name;
          default = if opt ? default then renderValue opt.default else null;
          rawDesc = opt.description or null;
          firstLine = if rawDesc == null then null else lib.head (lib.splitString "\n" (lib.trim rawDesc));
          details = lib.concatStrings [
            (lib.optionalString (firstLine != null) " - ${firstLine}")
            (lib.optionalString (opt ? type && opt.type ? description) " (`${opt.type.description}`)")
            (lib.optionalString (default != null) " (default: `${default}`)")
          ];
        in
        "  - `${name}`${details}";
      filterOpts =
        excludePrefixes:
        lib.filter (opt: !(lib.any (prefix: lib.hasPrefix prefix opt.name) excludePrefixes));
      optionsForModules =
        {
          modules,
          excludePrefixes,
          evalModules ? lib.evalModules,
        }:
        let
          eval = evalModules { inherit modules; };
        in
        filterOpts excludePrefixes (lib.optionAttrSetToDocList eval.options);
      renderModuleOptions =
        opts: if opts == [ ] then "" else lib.concatStringsSep "\n" (map renderOption opts);
      nixosModuleOptions =
        moduleName:
        optionsForModules {
          modules = [
            nixosModules.${moduleName}
            {
              config._module = {
                args.pkgs = pkgs.extend config.flake.overlays.default;
                check = false;
              };
            }
          ];
          excludePrefixes = [
            "_module"
          ];
        };
      outputsMarkdown =
        let
          isPerSystem =
            name:
            let
              val = processedFlake.${name};
            in
            lib.isAttrs val && val ? ${system};
          outputNames = lib.pipe (lib.attrNames processedFlake) [
            (lib.sort lib.lessThan)
          ];
          describedOutputs = [
            "apps"
            "legacyPackages"
          ];
          # `legacyPackages` is all of nixpkgs plus our overlay; only surface the
          # packages our overlay actually introduces.
          overlayPackageNames =
            let
              legacy = pkgs.extend config.flake.overlays.default;
              added = lib.filterAttrs (_: lib.isDerivation) (config.flake.overlays.default legacy pkgs);
            in
            lib.attrNames added;
          attrNamesFor =
            name:
            let
              val = processedFlake.${name};
            in
            if name == "legacyPackages" then
              overlayPackageNames
            else if isPerSystem name then
              let
                perSysVal = val.${system};
                tried = builtins.tryEval (
                  if lib.isDerivation perSysVal then
                    [ ]
                  else if lib.isAttrs perSysVal then
                    lib.attrNames perSysVal
                  else
                    [ ]
                );
              in
              if tried.success then tried.value else [ ]
            else if lib.isAttrs val then
              let
                tried = builtins.tryEval (lib.attrNames val);
              in
              if tried.success then tried.value else [ ]
            else
              [ ];
          formatAttr =
            outputName: attrName:
            let
              optionsMd =
                if outputName == "nixosModules" then renderModuleOptions (nixosModuleOptions attrName) else "";
              description =
                if lib.elem outputName describedOutputs then
                  let
                    val =
                      if isPerSystem outputName then
                        processedFlake.${outputName}.${system}.${attrName}
                      else
                        processedFlake.${outputName}.${attrName};
                  in
                  if lib.isDerivation val then
                    val.meta.description or null
                  else if lib.isAttrs val && val ? config.meta.description then
                    val.config.meta.description
                  else if lib.isAttrs val && val ? meta && lib.isAttrs val.meta then
                    val.meta.description or null
                  else
                    null
                else
                  null;
              descSuffix = lib.optionalString (description != null) " - ${description}";
            in
            if optionsMd == "" then
              "- `${attrName}`${descSuffix}"
            else
              "- `${attrName}`${descSuffix}\n${optionsMd}";
          formatSection =
            name:
            let
              attrs = lib.sort lib.lessThan (attrNamesFor name);
            in
            if attrs == [ ] then
              "### `${name}`"
            else
              lib.concatStrings [
                "### `${name}`\n\n"
                "<details>\n<summary>Show ${toString (lib.length attrs)}</summary>\n\n"
                "${lib.concatStringsSep "\n\n" (map (formatAttr name) attrs)}\n\n"
                "</details>"
              ];
        in
        lib.concatStringsSep "\n\n" (map formatSection outputNames);
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

            Then import it with a nixpkgs `lib`. It returns an
            attribute set of `lib`, `modules`, and `overlays`:

            ```nix
            inputs:
            let
              inherit (import inputs.nix-lib { inherit (inputs.nixpkgs) lib; })
                lib
                modules
                overlays
                ;
            in
            {
              # Apply the package overlay to access the new packages and extended lib.
              nixpkgs' = import inputs.nixpkgs {
                inherit system;
                overlays = [ overlays.default ];
              };

              # Access reusable modules, grouped by class.
              # Each class exposes its individual modules and a `default` that imports all of them.
              myNixosConfiguration = lib.nixosSystem {
                modules = [
                  modules.nixos.default
                  {
                    nixpkgs.overlays = [ overlays.default ];
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
