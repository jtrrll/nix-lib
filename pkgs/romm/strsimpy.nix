{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:
buildPythonPackage rec {
  pname = "strsimpy";
  version = "0.2.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-CELrV/evhsiCpZobyHIewlgKJn5WP9BQPO0pcgQDcsk=";
  };

  build-system = [ setuptools ];

  pythonImportsCheck = [ "strsimpy" ];

  meta = {
    description = "String similarity and distance measures";
    homepage = "https://github.com/luozhouyang/python-string-similarity";
    license = lib.licenses.mit;
  };
}
