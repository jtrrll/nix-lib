{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  libx11,
  nix-update-script,
  testers,
  versionCheckHook,
}:
buildGoModule (finalAttrs: {
  pname = "slk";
  version = "0.27.0";

  src = fetchFromGitHub {
    owner = "gammons";
    repo = "slk";
    tag = "v${finalAttrs.version}";
    hash = "sha256-agYSmdwY8gXehMapB50g6dgs4KgombxGrbyMahYjVZk=";
  };

  vendorHash = "sha256-/J4gr4m9v6Y0Be8BU4wepIdl2sjoPh0pFCvJL2kIeLk=";

  subPackages = [ "cmd/slk" ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libx11 ];

  # X11 clipboard support `dlopen`s libX11 at runtime.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-rpath ${lib.makeLibraryPath [ libx11 ]} $out/bin/slk
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
    "-X main.commit=${finalAttrs.src.tag}"
    "-X main.date=1970-01-01T00:00:00Z"
  ];

  # The test suite serves fixtures from loopback httptest servers.
  __darwinAllowLocalNetworking = true;

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    updateScript = nix-update-script {
      attrPath = "legacyPackages.${stdenv.hostPlatform.system}.slk";
      extraArgs = [ "--flake" ];
    };
    tests.version = testers.testVersion { package = finalAttrs.finalPackage; };
  };

  meta = {
    description = "A blazingly fast Slack TUI";
    homepage = "https://github.com/gammons/slk";
    changelog = "https://github.com/gammons/slk/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    mainProgram = "slk";
    maintainers = [ lib.maintainers.jtrrll ];
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
