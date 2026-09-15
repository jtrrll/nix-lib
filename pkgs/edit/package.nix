{ lib, writers }:
lib.addMetaAttrs {
  description = "Launches a text editor";
  homepage = "https://github.com/jtrrll/nix-lib";
  license = lib.licenses.agpl3Plus;
  maintainers = [
    lib.maintainers.jtrrll
  ];
  platforms = lib.platforms.all;
  sourceProvenance = [ lib.sourceTypes.fromSource ];
} (writers.writeNuBin "edit" { } (lib.readFile ./edit.nu))
