{
  cacert,
  curl,
  fetchurl,
  git,
  lib,
  python3Packages,
  stdenvNoCC,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nextui-h700";
  version = "6.14.0-rc10";

  src =
    let
      versionParts = lib.splitString "-" finalAttrs.version;
      releaseTag = "h700-${lib.concatStringsSep "-" (lib.tail versionParts)}";
    in
    fetchurl {
      url = "https://github.com/pvaibhav/NextUI/releases/download/${releaseTag}/NextUI-v${lib.head versionParts}-${releaseTag}.zip";
      hash = "sha256-mrF5J+y1euX+KR/V6NDvFdPBNkfYJBqVVwhbcvmiU5U=";
    };

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    unzip -q "$src" -d "$out"

    runHook postInstall
  '';

  passthru.updateScript = python3Packages.buildPythonApplication {
    pname = "update-nextui-h700";
    inherit (finalAttrs) version;
    src = ./update.py;
    pyproject = false;
    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/update-nextui-h700"
      runHook postInstall
    '';

    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [
        curl
        git
      ])
      "--set"
      "SSL_CERT_FILE"
      "${cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
    meta.mainProgram = "update-nextui-h700";
  };

  meta = {
    description = "NextUI frontend card contents for Anbernic H700 handhelds";
    homepage = "https://github.com/pvaibhav/NextUI";
    license = {
      fullName = "PolyForm Noncommercial License 1.0.0";
      shortName = "polyform-noncommercial-1.0.0";
      url = "https://polyformproject.org/licenses/noncommercial/1.0.0";
      free = false;
      redistributable = true;
    };
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
