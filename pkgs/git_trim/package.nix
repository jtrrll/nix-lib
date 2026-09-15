{
  git,
  gnugrep,
  gum,
  lib,
  uutils-coreutils-noprefix,
  writeShellApplication,
}:
writeShellApplication rec {
  meta = {
    inherit (git.meta) platforms;
    description = "Deletes all working git branches and updates main branch";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = name;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
  name = "git-trim";
  runtimeInputs = [
    git
    gnugrep
    gum
    uutils-coreutils-noprefix
  ];
  text = ''
    if [[ "$#" -ne 1 ]]; then
      echo "Usage: $(basename "$0") <main-branch>"
      exit 1
    fi
    main_branch="$1"

    gum confirm

    git switch "$main_branch"

    for branch in $(git branch --format="%(refname:short)" | grep -v "$main_branch"); do
        git branch -D "$branch"
    done

    git pull
  '';
}
