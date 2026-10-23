{
  cacert,
  curl,
  device ? "rgsp",
  fetchurl,
  git,
  lib,
  python3Packages,
  stdenvNoCC,
  unzip,
}:
let
  hashes = {
    rg28xx = {
      image = "sha256-yclEkHnhaGN2D9JGP8gGbcBEnttPItnHy1ohD8kONHE=";
      update = "sha256-e3GdrBDhnIkvVtZClkZiZVZ0rO3Oanbb30c8iHUm/yg=";
    };
    rg34xx = {
      image = "sha256-0RT3oOQVwTlup8LQknxJYTvOPJH28q58kTpF37QGBao=";
      update = "sha256-4169QE7D4vdvpcgDAuS1o0ZzxI3czeZyHQXDmRPcwA4=";
    };
    rg34xxsp = {
      image = "sha256-tJaDTch3NXcdYlCEF+psbg39gRwwZiZK1zJ/PEUytEY=";
      update = "sha256-QAaup9VZXCGyIE+Aqezw4mwpAS9dBpcafsfu2Q0ISS4=";
    };
    rg35xxh = {
      image = "sha256-E78vRCGe5JRz5/5e8Qs+/FIQ6rkXALvBLgYUU6JThSI=";
      update = "sha256-Vv1NZN5r0GyBWWgGg5aFbVkJETZ5AVMOFLj1QYBZ/kc=";
    };
    rg35xxplus = {
      image = "sha256-YApLWCATbcLdFWvvzBQuJYuI8azNl7jXrumOLVYVDO4=";
      update = "sha256-NgsrHBGuq0OemuWS3ITug++BaoIL8BmFjNd7fewOjJ0=";
    };
    rg35xxpro = {
      image = "sha256-mdZXZ8qPJxfV1zAnAFLmQYXOL/mtnYlND33h/nyVQOE=";
      update = "sha256-cWoKS/ocINASYnIETNJmDaNMAxymytnZxr0lPSDMCJM=";
    };
    rg35xxsp = {
      image = "sha256-DZPt/5OMHKKRvwsMWigfoICmYOTQ+33D73iMJyS3Ym0=";
      update = "sha256-QVxaRqftaqli+S40y+fxUhLYiwlor5jJuDJvn1ND1do=";
    };
    rg40xxh = {
      image = "sha256-9Pugrwbf9mRA8B59ynwKe1UfXLBuY6xrTjUWoy07Q+8=";
      update = "sha256-PaURWM6zD26ZVLGO89GzzbL8Om9ryK2Qbffxj1S8n5Q=";
    };
    rg40xxv = {
      image = "sha256-whaL225ge+zwAWj8YOlVYUfjDVM4uzv+QKGv7QkFjPI=";
      update = "sha256-P06U43+u5S8YSKXcg2yTCGyiKtNPYRIv0mkmBBfgnZo=";
    };
    rgcubexx = {
      image = "sha256-Q7furv5kmS1JLUqROmR4rkOUUiI1JRsG1Tdv1tdCGtU=";
      update = "sha256-6QLgTK5d56nRF3uAVZbzXMtYKSCgFWVsgtfNiK5zT/M=";
    };
    rgsp = {
      image = "sha256-/L4uDTlLq9OyTzXpaFul4gbBRYNGL1BkpVs7NaXb/iQ=";
      update = "sha256-fk6epXtsUrtSvWJxlgFyY+YHJpGlTGbkQOhfrwPxprE=";
    };
  };
  supportedDevices = builtins.attrNames hashes;
  deviceHashes =
    hashes.${device}
      or (throw "Unsupported BaseOS device '${device}'; supported devices: ${lib.concatStringsSep ", " supportedDevices}");
  meta = {
    homepage = "https://github.com/pvaibhav/BaseOS";
    license = lib.licenses.unfree;
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
  };
in
stdenvNoCC.mkDerivation (
  finalAttrs:
  let
    releaseUrl = "https://github.com/pvaibhav/BaseOS/releases/download/v${finalAttrs.version}/baseos-${device}-${finalAttrs.version}";
  in
  {
    pname = "baseos-${device}";
    version = "1.4.0";

    src = fetchurl {
      url = "${releaseUrl}.img.zip";
      hash = deviceHashes.image;
    };

    nativeBuildInputs = [ unzip ];
    dontUnpack = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      unzip -p "$src" baseos-${device}.img > "$out/baseos-${device}-${finalAttrs.version}.img"

      runHook postInstall
    '';

    passthru = {
      inherit supportedDevices;
      updateScript = python3Packages.buildPythonApplication {
        pname = "update-baseos";
        inherit (finalAttrs) version;
        src = ./update.py;
        pyproject = false;
        dontUnpack = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          install -Dm755 "$src" "$out/bin/update-baseos"
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
        meta.mainProgram = "update-baseos";
      };
      update = stdenvNoCC.mkDerivation {
        pname = "baseos-${device}-update";
        inherit (finalAttrs) version;

        src = fetchurl {
          url = "${releaseUrl}.bosupd";
          hash = deviceHashes.update;
        };

        dontUnpack = true;
        dontFixup = true;

        installPhase = ''
          runHook preInstall

          install -Dm644 "$src" "$out/baseos-${device}-${finalAttrs.version}.bosupd"

          runHook postInstall
        '';

        meta = meta // {
          description = "BaseOS update for the Anbernic ${device}";
        };
      };
    };

    meta = meta // {
      description = "Bootable BaseOS image for the Anbernic ${device}";
    };
  }
)
