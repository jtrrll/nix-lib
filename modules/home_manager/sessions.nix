{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.sessions;
in
{
  options.programs.sessions = {
    enable = lib.mkEnableOption "development sessions bundling git worktrees and a zellij session";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.session;
      defaultText = lib.literalExpression "pkgs.session";
      description = "The `session` CLI package to install.";
    };

    directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/sessions";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/sessions"'';
      description = "Directory under which sessions and their worktrees live.";
    };

    codeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/code"'';
      description = ''
        Directory containing the bare git repositories that sessions check
        worktrees out from. Wire this to `services.codeStorage.directory` to
        keep the two in sync.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      sessionDir = cfg.directory;
      codeDir = cfg.codeDirectory;
      session = cfg.package.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          wrapProgram $out/bin/session \
            --set-default CODE_HOME "${codeDir}" \
            --set-default SESSION_HOME "${sessionDir}"
        '';
      });
    in
    {
      home.packages = [ session ];

      home.file.sessions = {
        target = "sessions/README.md";
        text = ''
          # ~/sessions

          Development sessions. Each session is one unit of work owning its own
          git worktrees and a zellij session, all keyed by the session slug.

          ```
          ~/sessions/<slug>/worktrees/<label>/   # git worktree on branch <slug>/<label>
          ~/sessions/<slug>/GOALS.md             # what this session is for
          ~/sessions/<slug>/agent/               # session-scoped agent memory/files
          ```

          Manage sessions with the `session` CLI:

          - `session new <name> [--repo <repo>[:<branch>] [--label <label>]]...`
          - `session attach <name>`
          - `session add-worktree <name> --repo <repo>[:<branch>] [--label <label>]`
          - `session ls`
          - `session rm <name>`

          State is the filesystem plus git; there is no manifest. Removing a
          session removes its worktrees, kills its zellij session, and prunes
          worktree refs in the bare repos under `${codeDir}`.
        '';
      };

      programs.opencode = lib.mkIf config.programs.opencode.enable {
        context = ''
          # Sessions

          Development work is organized into sessions under `${sessionDir}`.
          Each session owns git worktrees at `${sessionDir}/<slug>/worktrees/<label>`,
          checked out from the bare repos in `${codeDir}`.

          Within a session directory:
          - `GOALS.md` describes what the session is trying to accomplish; read
            it first and keep it updated.
          - `agent/` is scratch space for session-scoped memory, notes, and
            generated files.

          Use the `session` CLI to create, list, and remove sessions.
          Never create worktrees by hand; always go through `session`.
        '';
        settings.permission = {
          external_directory."${sessionDir}/**" = "allow";
          edit."${sessionDir}/**" = "ask";
        };
      };
    }
  );
}
