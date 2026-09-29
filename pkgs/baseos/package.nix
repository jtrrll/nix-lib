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
      image = "sha256-QqTHaRsBWxRnEx8r0Fd7XkwOxwgKe3gdF2i7lDq6UZQ=";
      update = "sha256-AefPxOCzk7lnCStWTB2ZzqMrn98FxiBIYw4m5qbABF0=";
    };
    rg34xx = {
      image = "sha256-np71OsGpLsYnGv24r6TZ4SYJRazfVPJ/5UERIYh0Wy4=";
      update = "sha256-32pH12EzskOUbnUYnaMTuY1b4COHDLJL6VCENWLqHEc=";
    };
    rg34xxsp = {
      image = "sha256-Ey1DThsrcc+EPlI9DA5ACTQhuQZtPV0qXFhW+3Lsel4=";
      update = "sha256-RifLHOImTPl/y+Ik6EA1169N7hC6fbK8mJGY1wI0PNY=";
    };
    rg35xxh = {
      image = "sha256-iDePG0BzikI0Jtc+DZ3cZ2en95NqLqMCZGxYuTIrko8=";
      update = "sha256-8B7anZxwAfYbH4mRLn5KVHkaxzW+uBCwwi9e7cI5zzM=";
    };
    rg35xxplus = {
      image = "sha256-e68/a6DGwW0yeV1jo24tSv3udz4ANEXqib8/cvgSTEY=";
      update = "sha256-WJVd4WP701aS9yfLD/8Hb24uab+QnLtu/1JZ2pv9BTM=";
    };
    rg35xxpro = {
      image = "sha256-XEGGYaPRlCt2fSbr65fA5HMEsHaFsQdqAlOYIHaBjEs=";
      update = "sha256-Z5RgVWLQlAT/L1+lrMQty16LuDx34EdZN222YbzySxk=";
    };
    rg35xxsp = {
      image = "sha256-Jj4v1uffHRd/PeTXmst1x7IixK0Xx47Cz4WOh/DIlzg=";
      update = "sha256-ut3H/hCCz3/eGBaK4MrRdVNh+YR9MUqCUSOHc9JElOA=";
    };
    rg40xxh = {
      image = "sha256-SKfeCYxXwjj8YB7gT/KdvqBDqHUD3DGOxHk9Ja+H5XM=";
      update = "sha256-lrNmVA5Ne7TOmVmFbgwOVxNNB4JgppWpgMK0wAW85+Q=";
    };
    rg40xxv = {
      image = "sha256-mJWAn5hhJDzK9/G95uDixARJmMzpHzO+BCLCpGDpjog=";
      update = "sha256-YgFfCWXN1/4lDVo91W0kt4OAsQy6uuACyAYbG8JNBvY=";
    };
    rgcubexx = {
      image = "sha256-NUcG8StV3OcJgtJQyikOg5a46AzJBNv5lMssW24aCNY=";
      update = "sha256-u+9cYLokqmXPZ3hL7ilynKWeCG4fSJ+jwc5azlQ5zC8=";
    };
    rgsp = {
      image = "sha256-ObGEhnxmKKOdCxl9cLBsB+t0/tLz1UobJ+NyusVi3xI=";
      update = "sha256-JbfbEFk3Hh5DEXUM2yWVqGL8k7MPEt6EZHR75IZ4SvA=";
    };
  };
  supportedDevices = builtins.attrNames hashes;
  deviceHashes =
    hashes.${device}
      or (throw "Unsupported BaseOS device '${device}'; supported devices: ${lib.concatStringsSep ", " supportedDevices}");
  meta = {
    homepage = "https://github.com/pvaibhav/BaseOS";
    license = lib.licenses.unfree;
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
    version = "1.3.0";

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
