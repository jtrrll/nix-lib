{ src }:
{
  ROCKNIX = {
    appDir = "Grout";
    launchSource = "${src}/scripts/ROCKNIX/Grout.sh";
    launchDest = "Grout.sh";
    assets = [
      {
        src = "${src}/scripts/ROCKNIX/logo.png";
        dest = "logo.png";
      }
    ];
    package = workdir: out: ''
      cp -R "${workdir}/." "${out}/"
    '';
  };

  NextUI = {
    appDir = "Grout.pak";
    launchSource = "${src}/scripts/NextUI/launch.sh";
    launchDest = "Grout.pak/launch.sh";
    assets = [
      {
        src = "${src}/pak.json";
        dest = "pak.json";
      }
      {
        src = "${src}/README.md";
        dest = "README.md";
      }
      {
        src = "${src}/LICENSE";
        dest = "LICENSE";
      }
    ];
    package = workdir: out: ''
      cp -R "${workdir}/." "${out}/"
    '';
  };
}
