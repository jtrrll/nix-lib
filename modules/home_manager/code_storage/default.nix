{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.codeStorage;
in
{
  options.services.codeStorage = {
    enable = lib.mkEnableOption "self-maintaining directories for source code and worktrees";

    directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/code"'';
      description = ''
        Directory in which bare git repositories are stored.

        Other modules (e.g. `programs.sessions`) can reference this to locate
        the bare repos they check worktrees out from.
      '';
    };

    frequency = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      example = "weekly";
      description = ''
        The interval at which code storage maintenance runs.

        This value is passed to the systemd timer configuration
        as the `OnCalendar` option.

        The format is described in {manpage}`systemd.time(7)`.

        ${lib.hm.darwin.intervalDocumentation}
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      codeDir = cfg.directory;
      cloneWithWorktrees = lib.getExe (
        pkgs.git-clone-with-worktrees.override {
          git = config.programs.git.package;
        }
      );
    in
    {
      programs = {
        git.settings.alias.clone-bare = lib.removeSuffix "\n" ''
          !${cloneWithWorktrees} --bare-dest "${codeDir}"
        '';
        opencode = {
          context = ''
            # Code Storage

            Repositories are stored as bare clones in `${codeDir}`.

            Use `git clone-bare <url>` to add a repo. Never work directly in
            `${codeDir}`; create a session with the `session` CLI, which checks
            out worktrees from these bare repos.
          '';
          settings.permission = {
            external_directory = {
              "${codeDir}/**" = "allow";
            };
            edit = {
              "${codeDir}/**" = "deny";
            };
          };
        };
      };
    }
  );
}
