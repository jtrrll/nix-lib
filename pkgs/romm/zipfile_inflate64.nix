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
    hash = "sha256:b444f3aea904061d702edbed58f952e544a19dcf20f2ed84bd889cf446b87b7d";
  };

  dependencies = [ inflate64 ];

  pythonImportsCheck = [ "zipfile_inflate64" ];

  meta = {
    description = "Drop-in replacement for zipfile that supports Deflate64 decompression";
    homepage = "https://github.com/matmair/zipfile-inflate64";
    license = lib.licenses.psfl;
  };
}
