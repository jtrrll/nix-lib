{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:
buildNpmPackage (finalAttrs: {
  pname = "romm-frontend";
  version = "5.2.0";

  src = fetchFromGitHub {
    owner = "rommapp";
    repo = "romm";
    tag = finalAttrs.version;
    hash = "sha256-ixRgaDnyHzHWJjvC5yB6pD88aUgwtnkF6H7snAFODrE=";
  };

  sourceRoot = "${finalAttrs.src.name}/frontend";

  npmDepsHash = "sha256-k3MYizMevOfYJGRlu650bx1ERUkMBYdvg/JctmdwATo=";

  makeCacheWritable = true;

  passthru.updateScript = nix-update-script {
    attrPath = "romm.passthru.frontend";
    extraArgs = [ "--flake" ];
  };

  # vite build omits the static `assets/` tree, merge it in for a static deployment.
  installPhase = ''
    runHook preInstall
    cp -r dist $out
    mkdir -p $out/assets
    cp -r assets/. $out/assets/
    runHook postInstall
  '';

  meta = {
    description = "Static frontend assets for RomM";
    homepage = "https://romm.app";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
