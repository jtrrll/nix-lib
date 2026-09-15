{ lib, ... }:
{
  config.perSystem =
    { pkgs, ... }:
    let
      failures = lib.concatLists (
        lib.mapAttrsToList (
          file: suites:
          lib.concatLists (
            lib.mapAttrsToList (
              suite: cases:
              map (failure: failure // { name = "${file}.${suite}.${failure.name}"; }) (lib.runTests cases)
            ) suites
          )
        ) ((import ../lib).tests { inherit lib; })
      );
    in
    {
      checks.lib = pkgs.runCommandLocal "lib-tests" { } (
        if failures == [ ] then
          "touch $out"
        else
          ''
            echo "lib unit tests failed:" >&2
            ${lib.concatMapStringsSep "\n" (
              failure:
              ''echo "  ${failure.name}: expected '${lib.generators.toPretty { } failure.expected}', got '${
                lib.generators.toPretty { } failure.result
              }'" >&2''
            ) failures}
            exit 1
          ''
      );
    };
}
