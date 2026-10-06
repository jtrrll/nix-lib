{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:
buildNpmPackage (finalAttrs: {
  pname = "romm-frontend";
  version = "5.3.1";

  src = fetchFromGitHub {
    owner = "rommapp";
    repo = "romm";
    tag = finalAttrs.version;
    hash = "sha256-ijfp4L4GdGbr4FcBo83xVnGEksXawrkK3rYe8/Is+NU=";
  };

  sourceRoot = "${finalAttrs.src.name}/frontend";

  npmDepsHash = "sha256-x8Chw4nMoyq0M+m4XhIgqNu8Lgr4U7w38V7CYrd1zK4=";

  makeCacheWritable = true;

  passthru.updateScript = nix-update-script {
    attrPath = "legacyPackages.${stdenv.hostPlatform.system}.romm.passthru.frontend";
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
