{
  lib,
  stdenvNoCC,
  patchelf,
  jq,
  grout,
  SDL2,
  SDL2_gfx,
  glibc,
  tzdata,
  iana-etc,
  mailcap,
  spec,
}:
let
  # Loader path on the target rootfs; the binary is repointed here so it runs
  # without a Nix store. Overridable per firmware via `spec.loader`.
  loader = spec.loader or "/lib/ld-linux-aarch64.so.1";
in
stdenvNoCC.mkDerivation {
  pname = "grout-pak-${lib.toLower spec.name}";
  inherit (grout) version;

  inherit (grout) src;

  nativeBuildInputs = [ patchelf ] ++ lib.optional (spec.name == "NextUI") jq;

  dontConfigure = true;
  dontBuild = true;
  dontPatchShebangs = true;

  # This artifact runs on a device with no Nix store,
  # so it must not have a runtime dependency on the store.
  # patchelf can't scrub every embedded string because Go's stdlib bakes in default fallback paths.
  # They're allowed here explicitly so genuinely new store references are still caught.
  allowedReferences = [
    glibc
    SDL2
    tzdata
    iana-etc
    mailcap
  ];

  installPhase = ''
    runHook preInstall

    workdir="$(mktemp -d)"
    appdir="$workdir/${spec.appDir}"
    mkdir -p "$appdir/lib"

    install -Dm755 ${grout}/bin/grout "$appdir/grout"
    patchelf --set-interpreter ${loader} --set-rpath '$ORIGIN/lib' "$appdir/grout"

    cp -L ${lib.getLib SDL2_gfx}/lib/libSDL2_gfx-1.0.so.0 "$appdir/lib/libSDL2_gfx-1.0.so.0"
    chmod u+w "$appdir/lib/libSDL2_gfx-1.0.so.0"
    patchelf --remove-rpath "$appdir/lib/libSDL2_gfx-1.0.so.0"

    cp ${spec.launchSource} "$workdir/${spec.launchDest}"
    ${lib.concatMapStringsSep "\n" (a: ''cp -R ${a.src} "$appdir/${a.dest}"'') spec.assets}
    ${lib.optionalString (spec.name == "NextUI") ''
      jq '.platforms |= (. + ["h700"] | unique)' "$appdir/pak.json" > "$appdir/pak.json.tmp"
      mv "$appdir/pak.json.tmp" "$appdir/pak.json"
    ''}

    chmod -R u+w "$workdir"
    chmod a+x "$appdir/grout" "$workdir/${spec.launchDest}"

    mkdir -p "$out"
    ${spec.package "$workdir" "$out"}

    runHook postInstall
  '';

  meta = {
    description = "RomM grout client packaged as a ${spec.name} app";
    homepage = "https://grout.romm.app/";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
