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
}:
let
  handheldSDL2 = callPackage ./sdl2.nix { };
  mkNextUIPak =
    sdl2: spec:
    let
      image = SDL2_image.override { SDL2 = sdl2; };
      ttf = SDL2_ttf.override { SDL2 = sdl2; };
      gfx = SDL2_gfx.override { SDL2 = sdl2; };
    in
    callPackage ./pak.nix {
      grout = callPackage ./package.nix {
        SDL2 = sdl2;
        SDL2_image = image;
        SDL2_ttf = ttf;
        SDL2_gfx = gfx;
      };
      SDL2 = sdl2;
      SDL2_gfx = gfx;
      spec = spec // {
        name = "NextUI";
      };
    };
in
buildGoModule (finalAttrs: {
  pname = "grout";
  version = "5.2.0.0";

  src = fetchFromGitHub {
    owner = "rommapp";
    repo = "grout";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kikwYNbvnCvWla6jZKwbbKCN/3X7vAX06uf7XBVaKjQ=";
  };

  vendorHash = "sha256-earNKxaG8FCkBo5qQWK4ismu+PznPph+asgMg6jRTlc=";

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
      attrPath = "grout";
      extraArgs = [
        "--flake"
        "--version-regex"
        "v([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)"
      ];
    };

    # Firmware "pak" bundles for running grout on retro handhelds.
    paks =
      let
        specs = import ./paks.nix { inherit (finalAttrs) src; };
      in
      lib.mapAttrs' (
        name: spec:
        lib.nameValuePair (lib.toLower name) (
          if name == "NextUI" then
            mkNextUIPak handheldSDL2 spec
          else
            callPackage ./pak.nix {
              grout = finalAttrs.finalPackage;
              spec = spec // {
                inherit name;
              };
            }
        )
      ) specs;
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
