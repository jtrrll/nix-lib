{
  androidenv,
  fetchFromGitHub,
  git,
  jdk17,
  lib,
  mkShell,
  python3,
  runCommand,
  writableTmpDirAsHomeHook,
}:
let
  python = python3.withPackages (ps: [
    ps.adb-shell
    ps.cryptography
    ps.rsa
  ]);

  # launcher/app/build.gradle: compileSdk 34; AGP 8.5.2 defaults to build-tools 34.0.0.
  android = androidenv.composeAndroidPackages {
    platformVersions = [ "34" ];
    buildToolsVersions = [ "34.0.0" ];
    includeEmulator = false;
    includeSystemImages = false;
    includeNDK = false;
  };
  androidHome = "${android.androidsdk}/libexec/android-sdk";

  # Upstream's scripts run tools/venv/bin/python, and Gradle reads the SDK from launcher/local.properties.
  # Both are refreshed on every entry so they never point at a garbage-collected store path.
  shellHook = ''
    cleanyourtv_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    if [ -f "$cleanyourtv_root/tools/tv.py" ]; then
      if [ -e "$cleanyourtv_root/tools/venv" ] && [ ! -L "$cleanyourtv_root/tools/venv" ]; then
        echo "cleanyourtv-shell: leaving your own $cleanyourtv_root/tools/venv in place" >&2
      else
        ln -sfn ${python} "$cleanyourtv_root/tools/venv"
      fi
      cleanyourtv_properties="$cleanyourtv_root/launcher/local.properties"
      if [ ! -f "$cleanyourtv_properties" ] || grep -q '^sdk.dir=/nix/store/' "$cleanyourtv_properties"; then
        echo "sdk.dir=$ANDROID_HOME" > "$cleanyourtv_properties"
      fi
      unset cleanyourtv_properties
    else
      echo "cleanyourtv-shell: run this from a cleanyourtv checkout (git clone https://github.com/Gathin23/cleanyourtv)" >&2
    fi
    unset cleanyourtv_root
  '';

  # The release whose tools, launcher and tests this shell is checked against.
  upstreamSrc = fetchFromGitHub {
    owner = "Gathin23";
    repo = "cleanyourtv";
    tag = "v3.2.0";
    hash = "sha256-X0x+Qtsbch2iIswnyQYS8mvtzqKGa5s6YrvzQMb5f2k=";
  };
in
mkShell {
  name = "cleanyourtv-shell";

  packages = [
    android.androidsdk
    android.platform-tools
    git
    jdk17
    python
  ];

  env = {
    ANDROID_HOME = androidHome;
    ANDROID_SDK_ROOT = androidHome;
    JAVA_HOME = jdk17.home;
  };

  inherit shellHook;

  # Only `nix build` runs this; `nix develop` never builds the shell itself.
  phases = [
    "buildPhase"
    "checkPhase"
  ];
  doCheck = true;
  nativeCheckInputs = [ writableTmpDirAsHomeHook ];
  checkPhase = ''
    runHook preCheck

    java -version 2>&1 | grep -F 'version "17.'
    adb version
    [ -d "$ANDROID_HOME/platforms/android-34" ]
    [ -d "$ANDROID_HOME/build-tools/34.0.0" ]

    # Runs the shellHook in a fresh checkout, then upstream's test suite through the tools/venv it linked.
    # Several upstream tests read the git index (tracked files, ignore rules, file modes).
    cp -r ${upstreamSrc} checkout
    chmod -R u+w checkout
    cd checkout
    patchShebangs --build tools launcher
    git init --quiet
    git add --all

    ${shellHook}

    [ "$(readlink tools/venv)" = ${python} ]
    grep -Fx "sdk.dir=$ANDROID_HOME" launcher/local.properties
    tools/venv/bin/python -m unittest discover -s tests

    runHook postCheck
  '';

  # Free inputs only, so nix-lib's checks run it although they never build the shell itself.
  passthru.tests.requirements = runCommand "test-cleanyourtv-shell-requirements" { } ''
    PYTHONPATH=${python3.pkgs.packaging}/${python3.sitePackages} \
      ${python.interpreter} ${./check_requirements.py} ${upstreamSrc}/tools/requirements.txt
    touch $out
  '';

  meta = {
    description = "Shell with ADB, Python, JDK 17 and the Android SDK for following cleanyourtv's PROMPT.md";
    homepage = "https://github.com/Gathin23/cleanyourtv";
    license = lib.licenses.unfree;
    maintainers = [ lib.maintainers.jtrrll ];
    platforms = lib.platforms.darwin ++ [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
