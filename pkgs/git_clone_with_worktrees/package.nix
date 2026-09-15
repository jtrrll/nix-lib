{
  gum,
  git,
  lib,
  writeShellApplication,
}:
writeShellApplication rec {
  meta = {
    inherit (git.meta) platforms;
    description = "Clones a bare git repo and creates worktrees for each given suffix";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = name;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
  name = "git-clone-with-worktrees";
  runtimeInputs = [
    git
    gum
  ];
  text = ''
    usage() {
      printf "Usage: git-clone-with-worktrees [--bare-dest <path>] [--worktree-dest <path>] <url> <suffix>...\n" >&2
    }

    bare_dest=""
    worktree_dest=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --bare-dest)
          bare_dest="$2"
          shift 2
          ;;
        --worktree-dest)
          worktree_dest="$2"
          shift 2
          ;;
        -*)
          printf "Unknown option: %s\n" "$1" >&2
          usage
          exit 1
          ;;
        *)
          break
          ;;
      esac
    done

    if [ $# -lt 1 ]; then
      usage
      exit 1
    fi

    url="$1"
    shift

    if [ $# -eq 0 ] && [ -n "$worktree_dest" ]; then
      read -ra suffixes <<< "$(gum input --placeholder "Worktree names (space-separated)")"
    else
      suffixes=("$@")
    fi

    name="$(basename "$url" .git)"

    bare_dest="''${bare_dest:+$bare_dest/}$name"

    git clone --bare "$url" "$bare_dest"
    git -C "$bare_dest" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    if [ -z "$worktree_dest" ]; then
      exit 0
    fi

    worktree_prefix="$worktree_dest/$name"

    default_branch="$(git --git-dir="$bare_dest" ls-remote --symref origin HEAD | awk '/^ref:/ { sub(/.*\//, "", $2); print $2 }')"

    git -C "$bare_dest" worktree add "$worktree_prefix" "$default_branch"

    for suffix in "''${suffixes[@]}"; do
      git -C "$bare_dest" worktree add --detach "$worktree_prefix~$suffix"
    done
  '';
}
