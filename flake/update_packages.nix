{
  config.perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Packages that manage their own dependencies (e.g. Go modules, Cargo
      # crates, or an upstream release tracked via nix-update) instead of
      # relying on dependabot.
      updatable = lib.filterAttrs (_: pkg: (pkg.passthru or { }) ? updateScript) config.packages;

      # `updateScript` is either a self-contained derivation (as produced by
      # `writeShellApplication`) or a list of strings `[ executable arg... ]`
      # (as produced by nixpkgs' `nix-update-script`).
      toCommand =
        script:
        if lib.isList script then
          lib.escapeShellArgs (map toString script)
        else
          lib.escapeShellArg (lib.getExe script);

      commands = lib.mapAttrsToList (_: pkg: toCommand pkg.passthru.updateScript) updatable;
    in
    {
      config.apps.update-packages = {
        meta.description = "Runs each package's own updateScript";
        type = "app";
        program = pkgs.writeShellApplication {
          name = "update-packages";
          text = ''
            status=0
            ${lib.concatMapStringsSep "\n" (command: ''
              echo "==> ${command}"
              if ! ${command}; then
                echo "::error::${command} failed" >&2
                status=1
              fi
            '') commands}
            exit "$status"
          '';
        };
      };
    };
}
