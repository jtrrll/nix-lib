{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:
buildPythonPackage rec {
  pname = "crontab";
  version = "1.0.4";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256:715b0e5e105bc62c9683cbb93c1cc5821e07a3e28d17404576d22dba7a896c92";
  };

  build-system = [ setuptools ];

  pythonImportsCheck = [ "crontab" ];

  meta = {
    description = "Parse and use crontab schedules in Python";
    homepage = "https://github.com/josiahcarlson/parse-crontab";
    license = lib.licenses.lgpl21Only;
  };
}
