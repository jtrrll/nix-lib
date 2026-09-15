{ lib, ... }:
{
  options.tests = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    default = { };
    description = "Tests associated with this host. Each value is a derivation that succeeds if the test passes.";
  };
}
