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
      image = "sha256-2jy0MJrHcnjc2pl41xPJ0jnAu5SxPLK01MMlhhp6Suo=";
      update = "sha256-CR/4igjaSksPHXCVskBtdOthEpnTkJJQHCa8i9zgDcc=";
    };
    rg34xx = {
      image = "sha256-qFaE3hG/hcu0XPV5Vjy++SP/xNih8oEtEjAsRp6AvjE=";
      update = "sha256-EwTSTS4V/JG1Y3ZUaW6/0n4gblzpNnKH3W6u21X0fL8=";
    };
    rg34xxsp = {
      image = "sha256-9ct54LmHT7y7QxfBzZz59Ol9JCu7ekdA/Lk2nJYHovc=";
      update = "sha256-5MQLK+HY3IpWNWGY2218d7P/l+3Y1P0PzB7/JY+zE2E=";
    };
    rg35xxh = {
      image = "sha256-qZfxLSEgjXePfpIoeY3hS0r4IbHfszORIzoWmvW6RT0=";
      update = "sha256-xbJonVFAvumaazaIYN4PYlKleCuxJNyVBRL50p5faw4=";
    };
    rg35xxplus = {
      image = "sha256-u8NxLbjITfhDUNxOc7gATSm26seNPS32UMxWSI7+8qI=";
      update = "sha256-jWwfYGuh2oLsiOncHoN+zrFvmiSTajnCnH0CyPWm/DU=";
    };
    rg35xxpro = {
      image = "sha256-Bwl/D6poYKcJoQdoMvuXfHnx+SiDZGXMixtU2pdt6jg=";
      update = "sha256-L2v1woWf7pQKWa46BFnxW8YX9LZssTol4XV+ah+/djA=";
    };
    rg35xxsp = {
      image = "sha256-jroZvaLsSXC0NFQJQLV3eE9buORh/8autpf0m12j/JI=";
      update = "sha256-qFIpDBxsmSlpxhZnnVNJ9QMg7EdEE5KdcqEfpPnLG58=";
    };
    rg40xxh = {
      image = "sha256-fulrLMvIfd+4WGBM359Xr7GNsJgYQek0QCtIxJN5XN4=";
      update = "sha256-6uSbVFRINqOX4UBjk+fQKe32VtOmNIQu6odg0ORpoRE=";
    };
    rg40xxv = {
      image = "sha256-EMKRlVegEpHit1VVflg2Dv3LtK1CGe3hipdUUEA8fpI=";
      update = "sha256-6SHkFN1U6MxzKWJuvPMcZvbjZyF0cHfaQ4Dh3ERLh3w=";
    };
    rgcubexx = {
      image = "sha256-bw/u6VP1UMTdZwcV2zi/+poH48V9ST0pWY3o/D+cAxE=";
      update = "sha256-cjw7hewd7YaKqyDuxkeGPO0N2MlmoQkddI5L/m2gzlU=";
    };
    rgsp = {
      image = "sha256-+0+SSdRFH8Cl2e7ZRxd7JHJMLCmD62wMq99Blj3fhyw=";
      update = "sha256-IpqSocT27ePx1n3qNqRMu5orIfykSmZt7ZPuIKntkk0=";
    };
  };
  supportedDevices = lib.attrNames hashes;
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
    version = "1.5.4";

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
