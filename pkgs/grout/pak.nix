{
  lib,
  stdenvNoCC,
  patchelf,
  nukeReferences,
  jq,
  grout,
  SDL2_gfx,
}:
stdenvNoCC.mkDerivation {
  pname = "grout-pak";
  inherit (grout) src version;

  nativeBuildInputs = [
    patchelf
    nukeReferences
    jq
  ];

  dontConfigure = true;
  dontBuild = true;
  dontPatchShebangs = true;

  # The target has no Nix store; reject any references left in the packaged files.
  allowedReferences = [ ];

  installPhase = ''
    runHook preInstall

    staging="$out/.pak-staging"
    mkdir -p "$staging/lib"

    install -Dm755 ${grout}/bin/grout "$staging/grout"
    patchelf --set-interpreter /lib/ld-linux-aarch64.so.1 --set-rpath '$ORIGIN/lib' "$staging/grout"

    cp -L ${lib.getLib SDL2_gfx}/lib/libSDL2_gfx-1.0.so.0 "$staging/lib/libSDL2_gfx-1.0.so.0"
    chmod u+w "$staging/lib/libSDL2_gfx-1.0.so.0"
    patchelf --remove-rpath "$staging/lib/libSDL2_gfx-1.0.so.0"
    nuke-refs "$staging/grout" "$staging/lib/libSDL2_gfx-1.0.so.0"

    runHook postInstall
    rmdir "$staging"
  '';

  meta = {
    description = "RomM grout client packaged for a retro handheld";
    homepage = "https://grout.romm.app/";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
