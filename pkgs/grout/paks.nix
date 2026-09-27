{
  ROCKNIX = _: _: {
    postInstall = ''
      mkdir -p "$out/Grout"
      mv "$staging/grout" "$staging/lib" "$out/Grout/"
      cp "$src/scripts/ROCKNIX/Grout.sh" "$out/Grout.sh"
      cp "$src/scripts/ROCKNIX/logo.png" "$src/README.md" "$src/LICENSE" "$out/Grout/"
      chmod a+x "$out/Grout.sh"
    '';
  };

  NextUI = _: _: {
    postInstall = ''
      mkdir -p "$out/Grout.pak"
      mv "$staging/grout" "$staging/lib" "$out/Grout.pak/"
      cp "$src/scripts/NextUI/launch.sh" "$src/README.md" "$src/LICENSE" "$src/pak.json" "$out/Grout.pak/"
      jq '.platforms |= (. + ["h700"] | unique)' "$out/Grout.pak/pak.json" > "$out/Grout.pak/pak.json.tmp"
      mv "$out/Grout.pak/pak.json.tmp" "$out/Grout.pak/pak.json"
      chmod a+x "$out/Grout.pak/launch.sh"
    '';
  };
}
