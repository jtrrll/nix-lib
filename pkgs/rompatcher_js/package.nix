{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  makeWrapper,
  nix-update-script,
  nodejs_24,
  runCommand,
}:
buildNpmPackage (finalAttrs: {
  pname = "rompatcher-js";
  version = "3.2.1";
  outputs = [
    "out"
    "lib"
  ];
  propagatedBuildOutputs = [ ];

  src = fetchFromGitHub {
    owner = "marcrobledo";
    repo = "RomPatcher.js";
    tag = "v${finalAttrs.version}";
    hash = "sha256-LJnNlBCzOTkAE5bWowa8RhDiPWvyURK1pUvtftWQ9fE=";
    postFetch = ''
      cd "$out"
      rm -rf \
        legacy \
        webapp \
        rom-patcher-js/modules/bz2 \
        index.html \
        index_template.html \
        _cache_service_worker.js \
        manifest.json \
        .gitignore \
        .nojekyll
    '';
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace-fail '"version": "3.0.0"' '"version": "${finalAttrs.version}"'
    substituteInPlace index.js \
      --replace-fail \
        "const RomPatcher = require('./rom-patcher-js/RomPatcher');" \
        "const RomPatcher = require('./rom-patcher-js/RomPatcher');
    program.name('rompatcher-js');"
  '';

  npmDepsHash = "sha256-4a4G2no2vol0gRl3NKlHyVM9xWUPwAf/Ha8pB/8DbLI=";
  makeCacheWritable = true;
  nodejs = nodejs_24;

  dontNpmBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    output="$(node test.js)"
    echo "$output"
    if grep -q '×' <<< "$output"; then
      echo "rom-patcher-js self-test reported failures"
      exit 1
    fi

    runHook postCheck
  '';

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $lib/share/rompatcher-js
    cp -r rom-patcher-js $lib/share/rompatcher-js/

    mkdir -p $out/bin $out/libexec/rompatcher-js
    cp index.js package.json $out/libexec/rompatcher-js/
    cp -r node_modules $out/libexec/rompatcher-js/
    ln -s $lib/share/rompatcher-js/rom-patcher-js $out/libexec/rompatcher-js/rom-patcher-js
    makeWrapper ${lib.getExe nodejs_24} $out/bin/rompatcher-js \
      --add-flags $out/libexec/rompatcher-js/index.js

    runHook postInstall
  '';

  passthru = {
    updateScript = nix-update-script { };
    tests.help = runCommand "test-rompatcher-js-help" { } ''
      ${lib.getExe finalAttrs.finalPackage} --help | grep -F "Usage: rompatcher-js"
      touch $out
    '';
  };

  meta = {
    description = "Browser and CLI ROM patching tool";
    homepage = "https://github.com/marcrobledo/RomPatcher.js";
    license = [
      lib.licenses.mit
      lib.licenses.bsd3
    ];
    mainProgram = "rompatcher-js";
    maintainers = [ lib.maintainers.jtrrll ];
    outputsToInstall = [ "out" ];
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
