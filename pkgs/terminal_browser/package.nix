{
  alsa-lib,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  coreutils,
  cups,
  dbus,
  expat,
  fetchurl,
  glib,
  gtk3,
  lib,
  libGL,
  libgbm,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  makeWrapper,
  nix-update-script,
  nspr,
  nss,
  pango,
  stdenv,
  stdenvNoCC,
  systemd,
  testers,
  versionCheckHook,
  vulkan-loader,
}:
let
  sources = {
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha256-Ea+8HAzAuNErte/8LiuvCFB90yRW1uAFKCTBvDDBCPA=";
    };
    x86_64-darwin = {
      target = "darwin-x64";
      hash = "sha256-+Ru2Afk7KVm3aySm5LdlyretNaiFuXwHvqof0Hc/awU=";
    };
    aarch64-linux = {
      target = "linux-arm64";
      hash = "sha256-afJqdr3MYeR4JzOqG5/LbgZ3SsnWsN8+n7sKpKuw9rw=";
    };
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha256-JE6ZW1VO2yn2bPB/f4MKdoha5qb6Iz3sU5gL+wpQlUE=";
    };
  };
  inherit (stdenvNoCC.hostPlatform) system;
  source = sources.${system} or (throw "terminal-browser: no prebuilt release for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "terminal-browser";
  version = "0.15.3";

  src = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${finalAttrs.version}/terminal-browser-${source.target}.tar.gz";
    inherit (source) hash;
  };

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    stdenv.cc.cc.lib
  ];

  runtimeDependencies = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    libGL
    systemd
    vulkan-loader
  ];

  # The macOS tarball carries AppleDouble `._*` files that GNU tar extracts as
  # regular files, which the app bundle's code signature rejects as additions.
  postUnpack = ''
    find . -name '._*' -type f -delete
  '';

  dontConfigure = true;
  dontBuild = true;

  # Rewriting the Electron app bundle would invalidate its code signature.
  dontFixup = stdenvNoCC.hostPlatform.isDarwin;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec $out/bin
    cp -r . $out/libexec/terminal-browser
    makeWrapper $out/libexec/terminal-browser/bin/terminal-browser $out/bin/terminal-browser \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}

    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    updateScript = nix-update-script {
      attrPath = "legacyPackages.${stdenvNoCC.hostPlatform.system}.terminal-browser";
      extraArgs = [
        "--flake"
        "--version-regex"
        "^v(\\d+\\.\\d+\\.\\d+)$"
      ];
    };
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      version = "v${finalAttrs.version}";
    };
  };

  meta = {
    description = "Real browser that runs inside your terminal";
    homepage = "https://github.com/zenbu-labs/terminal-browser";
    changelog = "https://github.com/zenbu-labs/terminal-browser/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "terminal-browser";
    maintainers = [ lib.maintainers.jtrrll ];
    platforms = lib.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
