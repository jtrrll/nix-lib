{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  crontab,
  python-dateutil,
  rq,
}:
buildPythonPackage {
  pname = "rq-scheduler";
  version = "0.14.0-unstable-2025";
  pyproject = true;

  # RomM depends on a fork adding username/SSL support to the RQ scheduler.
  src = fetchFromGitHub {
    owner = "adamantike";
    repo = "rq-scheduler";
    rev = "39583cb2a00c6faa12ef34c7277893064a83c4de";
    hash = "sha256-VOgMuzSDwCIWOlWc2+dxZHXqO3IigTi0F7ZRAzbgzLE=";
  };

  build-system = [ setuptools ];

  dependencies = [
    crontab
    python-dateutil
    rq
  ];

  # Tests require a running Redis instance.
  doCheck = false;

  pythonImportsCheck = [ "rq_scheduler" ];

  meta = {
    description = "Lightweight library that adds job scheduling capabilities to RQ (RomM fork)";
    homepage = "https://github.com/adamantike/rq-scheduler";
    license = lib.licenses.mit;
  };
}
