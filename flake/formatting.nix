{ config, ... }:
{
  config.perSystem = {
    config.treefmt = {
      imports = [ config.flake.modules.treefmt.default ];
      programs = {
        biome.enable = true;
        gofumpt.enable = true;
        keep-sorted.enable = true;
        rustfmt = {
          enable = true;
          edition = "2024";
        };
      };
    };
  };
}
