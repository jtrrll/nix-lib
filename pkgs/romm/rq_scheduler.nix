{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  crontab,
  freezegun,
  python-dateutil,
  rq,
}:
buildPythonPackage {
  pname = "rq-scheduler";
  version = "0.14.0-unstable-2025-05-17";
  pyproject = true;

  # RomM depends on a fork adding username/SSL support to the RQ scheduler.
  src = fetchFromGitHub {
    owner = "adamantike";
    repo = "rq-scheduler";
    rev = "134c2eb1b8c65510bc1b8fdfdbe787decef890f2";
    hash = "sha256-V/Tnxm3AeDtmE0Tyyfh6f0H2f1d13+Scs/gXpZDRnZI=";
  };

  build-system = [ setuptools ];

  dependencies = [
    crontab
    freezegun
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
