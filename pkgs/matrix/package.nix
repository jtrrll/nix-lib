{
  lib,
  neo,
  uutils-coreutils-noprefix,
  writeShellApplication,
}:
writeShellApplication rec {
  meta = {
    inherit (neo.meta) platforms;
    description = "A cyberpunk terminal screensaver";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = name;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
  name = "matrix";
  runtimeInputs = [
    neo
    uutils-coreutils-noprefix
  ];
  text = ''
    if [[ "$#" -ne 0 ]]; then
      echo "Usage: $(basename "$0")"
      exit 1
    fi

    neo \
      --async \
      --color green3 \
      --colormode 16 \
      --defaultbg \
      --fps 10 \
      --lingerms 1,1000 \
      --maxdpc 1
  '';
}
