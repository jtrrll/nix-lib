{
  lib,
  buildPythonPackage,
  fetchPypi,
  inflate64,
}:
buildPythonPackage rec {
  pname = "zipfile-inflate64";
  version = "0.1";
  format = "wheel";

  src = fetchPypi {
    pname = "zipfile_inflate64";
    inherit version format;
    dist = "py3";
    python = "py3";
    hash = "sha256-tETzrqkEBh1wLtvtWPlS5UShnc8g8u2EvYic9Ea4e30=";
  };

  dependencies = [ inflate64 ];

  pythonImportsCheck = [ "zipfile_inflate64" ];

  meta = {
    description = "Drop-in replacement for zipfile that supports Deflate64 decompression";
    homepage = "https://github.com/matmair/zipfile-inflate64";
    license = lib.licenses.psfl;
  };
}
