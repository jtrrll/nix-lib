{
  cmake,
  fetchurl,
  lib,
  ninja,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "grout-sdl2";
  version = "2.28.5";

  src = fetchurl {
    url = "https://github.com/libsdl-org/SDL/releases/download/release-2.28.5/SDL2-2.28.5.tar.gz";
    hash = "sha256-MyyzfQviDLlUFznGH3m65aR3Qn15roXjUgia/a9mZuQ=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];
  cmakeFlags = [
    (lib.cmakeBool "SDL_SHARED" true)
    (lib.cmakeBool "SDL_STATIC" false)
    (lib.cmakeBool "SDL_TEST" false)
    (lib.cmakeBool "SDL_X11" false)
    (lib.cmakeBool "SDL_WAYLAND" false)
    (lib.cmakeBool "SDL_KMSDRM" false)
    (lib.cmakeBool "SDL_ALSA" false)
    (lib.cmakeBool "SDL_PULSEAUDIO" false)
    (lib.cmakeBool "SDL_HIDAPI" false)
  ];

  postInstall = ''
    sed -i \
      -e "s|^libdir=.*|libdir=$out/lib|" \
      -e "s|^includedir=.*|includedir=$out/include|" \
      "$out/lib/pkgconfig/sdl2.pc"
  '';

  meta = {
    license = lib.licenses.zlib;
    platforms = lib.platforms.linux;
  };
}
