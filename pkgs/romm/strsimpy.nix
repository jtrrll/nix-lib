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
    hash = "sha256:0842eb57f7af86c882a59a1bc8721ec2580a267e563fd0503ced2972040372c9";
  };

  build-system = [ setuptools ];

  pythonImportsCheck = [ "strsimpy" ];

  meta = {
    description = "String similarity and distance measures";
    homepage = "https://github.com/luozhouyang/python-string-similarity";
    license = lib.licenses.mit;
  };
}
