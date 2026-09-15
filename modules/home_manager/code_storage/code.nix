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
  config = lib.mkIf cfg.enable (
    let
      codeDir = cfg.directory;
      maintainCodeDir = pkgs.writeShellApplication rec {
        meta.mainProgram = name;
        name = "maintain-code-dir";
        runtimeInputs = [
          config.programs.git.package
          pkgs.uutils-coreutils-noprefix
          pkgs.uutils-findutils
        ];
        text = ''
          printf "[maintain-code-dir] removing non-repos from %s...\n" "${codeDir}"
          find "${codeDir}" -mindepth 1 -maxdepth 1 | while read -r entry; do
            if [ -d "$entry" ] && git -C "$entry" rev-parse --git-dir >/dev/null 2>&1; then
              continue
            fi
            if [ "$entry" = "${codeDir}/${baseNameOf config.home.file.code.target}" ]; then
              continue
            fi
            printf "[maintain-code-dir] removing non-repo: %s\n" "$entry"
            rm -rf "$entry"
          done

          printf "[maintain-code-dir] converting non-bare repos in %s...\n" "${codeDir}"
          find "${codeDir}" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
            if [ -d "$dir/.git" ]; then
              printf "[maintain-code-dir] converting to bare: %s\n" "$dir"
              tmp="$(mktemp -d)"
              mv "$dir/.git" "$tmp/git"
              rm -rf "$dir"
              mv "$tmp/git" "$dir"
              rm -rf "$tmp"
              git -C "$dir" config core.bare true
            fi
          done

          printf "[maintain-code-dir] scanning %s...\n" "${codeDir}"
          find "${codeDir}" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
            if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
              printf "[maintain-code-dir] maintaining: %s\n" "$dir"
              if ! git -C "$dir" maintenance run; then
                printf "[maintain-code-dir] maintenance failed: %s\n" "$dir"
              fi
              printf "[maintain-code-dir] pruning worktrees: %s\n" "$dir"
              if ! git -C "$dir" worktree prune; then
                printf "[maintain-code-dir] worktree prune failed: %s\n" "$dir"
              fi
            fi
          done
        '';
      };
    in
    {
      home.file.code = {
        target = "code/README.md";
        text = ''
          # ~/code

          Bare git repositories.

          ## Daily Maintenance

          1. Remove non-repo entries
          2. Convert non-bare repos to bare
          3. Run `git maintenance` (includes prefetch)
          4. Prune stale worktree references

        '';
      };
      assertions = [
        (lib.hm.darwin.assertInterval "services.codeStorage.frequency" cfg.frequency pkgs)
      ];

      launchd.agents.maintain-code-dir = {
        enable = true;
        config = {
          ProgramArguments = [ (lib.getExe maintainCodeDir) ];
          ProcessType = "Background";
          RunAtLoad = true;
          StartCalendarInterval = lib.hm.darwin.mkCalendarInterval cfg.frequency;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/maintain-code-dir/launchd-stdout.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/maintain-code-dir/launchd-stderr.log";
        };
      };

      systemd.user = {
        services.maintain-code-dir = {
          Unit.Description = "Git fetch and maintenance for all repos in ~/code";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe maintainCodeDir;
          };
        };
        timers.maintain-code-dir = {
          Unit.Description = "Git fetch and maintenance for all repos in ~/code";
          Install.WantedBy = [ "timers.target" ];
          Timer = {
            OnCalendar = cfg.frequency;
            Persistent = true;
          };
        };
      };
    }
  );
}
