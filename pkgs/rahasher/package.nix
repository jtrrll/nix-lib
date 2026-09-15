{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "rahasher";
  version = "1.8.4";

  src = fetchFromGitHub {
    owner = "RetroAchievements";
    repo = "RALibretro";
    tag = finalAttrs.version;
    fetchSubmodules = true;
    hash = "sha256-UwA3m9BR3i69HY7QCbs6HjsIe02MIi8ACu4fZTaIVuo=";
  };

  enableParallelBuilding = true;

  # GCC 14+ makes implicit function declarations an error; the vendored
  # zlib-1.3.1 in libchdr relies on an implicit `lseek`. Downgrade to a warning.
  env.NIX_CFLAGS_COMPILE = "-Wno-error=implicit-function-declaration -Wno-implicit-function-declaration";

  # The Makefile derives `src/RA_BuildVer.h` from git metadata via a `.git/HEAD`
  # prerequisite, which `fetchFromGitHub` does not provide. Pre-generate the
  # header from `version` and stub `.git/HEAD` so make treats it as satisfied
  # and does not try to regenerate it from git.
  preBuild =
    let
      inherit (finalAttrs) version;
      # Upstream derives the revision from `git describe` as the number of
      # commits since the tag; building at the exact release tag means zero.
      revision = "0";
      full = "${version}.${revision}";
    in
    ''
      mkdir -p .git
      touch .git/HEAD
      {
        printf '#define RA_LIBRETRO_VERSION "%s"\n' "${full}"
        printf '#define RA_LIBRETRO_VERSION_SHORT "%s"\n' "${version}"
        printf '#define RA_LIBRETRO_VERSION_MAJOR %s\n' "${lib.versions.major version}"
        printf '#define RA_LIBRETRO_VERSION_MINOR %s\n' "${lib.versions.minor version}"
        printf '#define RA_LIBRETRO_VERSION_PATCH %s\n' "${lib.versions.patch version}"
        printf '#define RA_LIBRETRO_VERSION_REVISION %s\n' "${revision}"
        printf '#define RA_LIBRETRO_VERSION_PRODUCT "%s"\n' "${version}"
        printf '#define RA_LIBRETRO_VERSION_FULL "%s"\n' "${full}"
        printf '#define RA_LIBRETRO_VERSION_COMMIT_HASH "unknown"\n'
        printf '#define RA_LIBRETRO_VERSION_COMMIT_HASH_SHORT "unknown"\n'
      } > src/RA_BuildVer.h
      touch src/RA_BuildVer.h
    '';

  buildPhase = ''
    runHook preBuild
    make HAVE_CHD=1 -f ./Makefile.RAHasher
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bin64/RAHasher $out/bin/RAHasher
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    attrPath = "rahasher";
    extraArgs = [ "--flake" ];
  };

  meta = {
    description = "Hashing tool from RALibretro used by RomM for RetroAchievements";
    homepage = "https://github.com/RetroAchievements/RALibretro";
    license = lib.licenses.gpl3Only;
    mainProgram = "RAHasher";
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
