{
  cbonsai,
  lib,
  uutils-coreutils-noprefix,
  writeShellApplication,
}:
writeShellApplication rec {
  meta = {
    inherit (cbonsai.meta) platforms;
    description = "A botanical terminal screensaver";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = name;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
  name = "bonsai";
  runtimeInputs = [
    cbonsai
    uutils-coreutils-noprefix
  ];
  text = ''
    if [[ "$#" -ne 0 ]]; then
      echo "Usage: $(basename "$0")"
      exit 1
    fi

    sleep .25
    cbonsai \
      --base 2 \
      --infinite \
      --live \
      --seed "$RANDOM" \
      --time 0.7
  '';
}
