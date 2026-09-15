{
  description = "A reusable Nix library for jtrrll's repositories";

  inputs = {
    # keep-sorted start block=yes
    devenv.url = "github:cachix/devenv/main";
    files = {
      flake = false;
      url = "github:mightyiam/files/master";
    };
    flake-parts.url = "github:hercules-ci/flake-parts/main";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    terranix.url = "github:terranix/terranix/main";
    treefmt-nix = {
      flake = false;
      url = "github:numtide/treefmt-nix/main";
    };
    # keep-sorted end
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        ...
      }:
      let
        default = import ./. { inherit lib; };
      in
      {
        imports = [
          inputs.devenv.flakeModule
          (inputs.files + "/flake-module.nix")
          inputs.flake-parts.flakeModules.modules
          inputs.flake-parts.flakeModules.touchup
          inputs.terranix.flakeModule
          (inputs.treefmt-nix + "/flake-module.nix")
          default.modules.flake.default
        ]
        ++ default.lib.modules.nixFilesInDir {
          path = ./flake;
          recurse = true;
        };

        config = {
          flake = {
            inherit (default) lib modules overlays;
          };
          perSystem = {
            terranix.exportDevShells = false;
          };
          systems = [
            # keep-sorted start
            "aarch64-darwin"
            "aarch64-linux"
            "x86_64-linux"
            # keep-sorted end
          ];
          touchup = {
            any.enable = lib.mkDefault false;
            attr = {
              # keep-sorted start block=yes
              apps.enable = true;
              checks.enable = true;
              devShells.enable = true;
              formatter.enable = true;
              legacyPackages.enable = true;
              overlays.enable = true;
              # keep-sorted end
            };
          };
        };
      }
    );
}
