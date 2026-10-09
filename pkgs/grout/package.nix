{
  lib,
  stdenv,
  callPackage,
  buildGoModule,
  fetchFromGitHub,
  pkg-config,
  SDL2,
  SDL2_image,
  SDL2_ttf,
  SDL2_gfx,
  libx11,
  nix-update-script,
  runCommandLocal,
  romm,
}:
buildGoModule (finalAttrs: {
  pname = "grout";
  version = "5.3.1.3";

  src = fetchFromGitHub {
    owner = "rommapp";
    repo = "grout";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ET+bHN2czvFNEEs1ERuDc7zskWWiuoNRwt2vYM03f10=";
  };

  vendorHash = "sha256-vBMztRPRq4E3nwQUy/bwi4j1albw3y0WTQKqd1WxxJ8=";

  subPackages = [ "app" ];

  doCheck = stdenv.hostPlatform == stdenv.buildPlatform;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    SDL2
    SDL2_image
    SDL2_ttf
    SDL2_gfx
    libx11
  ];

  env.NIX_CFLAGS_COMPILE = toString [
    "-I${lib.getDev SDL2_image}/include/SDL2"
    "-I${lib.getDev SDL2_ttf}/include/SDL2"
    "-I${lib.getDev SDL2_gfx}/include/SDL2"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X grout/version.Version=${finalAttrs.version}"
    "-X grout/version.GitCommit=${finalAttrs.src.rev}"
    "-X grout/version.BuildType=Release"
  ];

  postInstall = ''
    mv $out/bin/app $out/bin/grout
  '';

  passthru = {
    updateScript = nix-update-script {
      attrPath = "legacyPackages.${stdenv.hostPlatform.system}.grout";
      extraArgs = [
        "--flake"
        "--version-regex"
        "v([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)"
      ];
    };

    tests.romm-version =
      let
        groutVersionComponents = lib.splitVersion finalAttrs.version;
        requiredRommVersion = lib.concatStringsSep "." (lib.take 3 groutVersionComponents);
      in
      runCommandLocal "check-grout-romm-version" { } (
        if lib.length groutVersionComponents < 3 then
          ''
            echo "Grout's version must contain at least three components; got ${finalAttrs.version}" >&2
            exit 1
          ''
        else if requiredRommVersion != romm.version then
          ''
            echo "Grout ${finalAttrs.version} requires RomM ${requiredRommVersion}, but nixpkgs' RomM is ${romm.version}" >&2
            exit 1
          ''
        else
          "touch $out"
      );

    # Firmware "pak" bundles for running grout on retro handhelds.
    paks =
      let
        # keep-sorted start block=yes
        SDL2' = callPackage ./sdl2.nix { };
        SDL2_image' = SDL2_image.override { SDL2 = SDL2'; };
        SDL2_ttf' = SDL2_ttf.override { SDL2 = SDL2'; };
        SDL2_gfx' = SDL2_gfx.override { SDL2 = SDL2'; };
        # keep-sorted end
        pak = callPackage ./pak.nix {
          grout = callPackage ./package.nix {
            SDL2 = SDL2';
            SDL2_image = SDL2_image';
            SDL2_ttf = SDL2_ttf';
            SDL2_gfx = SDL2_gfx';
          };
          SDL2_gfx = SDL2_gfx';
        };
      in
      lib.mapAttrs' (
        name: override:
        lib.nameValuePair (lib.toLower name) (
          pak.overrideAttrs (
            finalAttrs: previousAttrs:
            (override finalAttrs previousAttrs)
            // {
              pname = "grout-pak-${lib.toLower name}";
              meta = previousAttrs.meta // {
                description = "RomM grout client packaged as a ${name} app";
              };
            }
          )
        )
      ) (import ./paks.nix);
  };

  meta = {
    description = "RomM client for Linux retro handhelds";
    homepage = "https://grout.romm.app/";
    license = lib.licenses.mit;
    mainProgram = "grout";
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
