{ lib, ... }:
let
  userShell = builtins.getEnv "SHELL";
in
{
  enterShell = lib.mkAfter (
    lib.optionalString (userShell != "") ''
      if [[ $- == *i* ]]; then
        export SHELL=${lib.escapeShellArg userShell}
        exec "$SHELL"
      fi
    ''
  );
}
