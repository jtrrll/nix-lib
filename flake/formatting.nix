{ config, ... }:
{
  config.perSystem = {
    config.treefmt = {
      imports = [ config.flake.modules.treefmt.default ];
      programs.keep-sorted.enable = true;
    };
  };
}
