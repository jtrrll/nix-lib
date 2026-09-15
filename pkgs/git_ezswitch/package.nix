{
  git,
  gum,
  lib,
  writeShellApplication,
}:
writeShellApplication rec {
  meta = {
    inherit (git.meta) platforms;
    description = "Interactively switches git branches";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = name;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
  name = "git-ezswitch";
  runtimeInputs = [
    git
    gum
  ];
  text = ''
    if [[ "$#" -eq 0 ]]; then
      branch=$(git branch --format="%(refname:short)" | gum filter)
      git switch "$branch"
    else
      git switch "$@"
    fi
  '';
}
