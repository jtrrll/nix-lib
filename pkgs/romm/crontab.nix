{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:
buildPythonPackage rec {
  pname = "crontab";
  version = "1.0.5";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-+A4BtPByGXY6mGn5Jt0XFHJ455ZakoCJvKbT3ICuRtU=";
  };

  build-system = [ setuptools ];

  pythonImportsCheck = [ "crontab" ];

  meta = {
    description = "Parse and use crontab schedules in Python";
    homepage = "https://github.com/josiahcarlson/parse-crontab";
    license = lib.licenses.lgpl21Only;
  };
}
