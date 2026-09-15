{ lib, ... }:
{
  options.meta.description = lib.mkOption {
    type = lib.types.str;
    default = "";
    example = "A custom configuration for a specific context";
    description = "A short description of this configuration.";
  };
}
