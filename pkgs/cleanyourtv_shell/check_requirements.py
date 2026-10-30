"""Fail when this Python environment does not satisfy a pip requirements file.

Usage: python check_requirements.py <requirements.txt>

An exact pin (==) only has to match on major.minor, because nixpkgs often trails upstream's patch
releases. Every other specifier must hold as written.
"""

import importlib.metadata
import sys
from pathlib import Path

from packaging.requirements import Requirement
from packaging.specifiers import Specifier
from packaging.version import Version


def parse_requirements(text: str) -> list[Requirement]:
    lines = (line.split("#", 1)[0].strip() for line in text.splitlines())
    requirements = []
    for line in filter(None, lines):
        if line.startswith("-"):
            raise ValueError(f"unsupported requirements option: {line!r}")
        requirements.append(Requirement(line))
    return requirements


def satisfies(installed: Version, specifier: Specifier) -> bool:
    if specifier.operator == "==" and not specifier.version.endswith(".*"):
        return installed.release[:2] == Version(specifier.version).release[:2]
    return specifier.contains(installed, prereleases=True)


def violations(requirement: Requirement) -> list[str]:
    try:
        installed = Version(importlib.metadata.version(requirement.name))
    except importlib.metadata.PackageNotFoundError:
        return [f"{requirement}: {requirement.name} is not installed"]
    return [
        f"{requirement}: installed {requirement.name} {installed} does not satisfy {specifier}"
        for specifier in requirement.specifier
        if not satisfies(installed, specifier)
    ]


def main(requirements_file: Path) -> int:
    requirements = [
        requirement
        for requirement in parse_requirements(requirements_file.read_text())
        if requirement.marker is None or requirement.marker.evaluate()
    ]
    if not requirements:
        raise ValueError(f"{requirements_file} lists no requirements for this platform")

    problems = [problem for requirement in requirements for problem in violations(requirement)]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    for requirement in requirements:
        print(f"{requirement}: {importlib.metadata.version(requirement.name)}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(Path(sys.argv[1])))
