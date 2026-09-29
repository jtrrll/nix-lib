#!/usr/bin/env python3
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def replace_once(source: str, pattern: str, replacement: str) -> str:
    updated, count = re.subn(pattern, lambda _: replacement, source)
    if count != 1:
        fail(f"expected exactly one match for {pattern!r}, found {count}")
    return updated


def main(path: Path) -> None:
    releases = json.loads(
        subprocess.run(
            [
                "curl",
                "-fsSL",
                "https://api.github.com/repos/pvaibhav/NextUI/releases?per_page=100",
            ],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout
    )
    candidates = [
        release
        for release in releases
        if release.get("tag_name", "").startswith("h700-")
        and not release.get("draft")
        and release.get("published_at")
    ]
    if not candidates:
        fail("no published H700 NextUI release found")
    release = max(candidates, key=lambda candidate: candidate["published_at"])
    tag = release["tag_name"]
    assets = [
        (
            asset,
            re.fullmatch(
                r"NextUI-v([0-9]+(?:\.[0-9]+){2})-(h700-[a-z0-9.-]+)\.zip",
                asset["name"],
            ),
        )
        for asset in release["assets"]
    ]
    matches = [
        (asset, match) for asset, match in assets if match and match.group(2) == tag
    ]
    if len(matches) != 1:
        fail(
            f"expected exactly one H700 NextUI archive in release {tag}, found {len(matches)}"
        )
    asset, match = matches[0]
    digest = asset.get("digest") or ""
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        fail(f"missing SHA-256 digest for NextUI archive: {asset['name']}")
    hash_value = "sha256-" + base64.b64encode(bytes.fromhex(digest[7:])).decode("ascii")

    original = path.read_text()
    version = f"{match.group(1)}-{tag.removeprefix('h700-')}"
    updated = replace_once(
        original,
        r'(?m)^  version = "[0-9]+(?:\.[0-9]+){2}-[a-z0-9.-]+";$',
        f'  version = "{version}";',
    )
    updated = replace_once(
        updated, r'(?m)^      hash = "sha256-[^"]+";$', f'      hash = "{hash_value}";'
    )

    if updated == original:
        print("NextUI H700 is already up to date")
        return
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, delete=False
    ) as temporary:
        temporary.write(updated)
    try:
        os.chmod(temporary.name, path.stat().st_mode)
        os.replace(temporary.name, path)
    finally:
        if os.path.exists(temporary.name):
            os.unlink(temporary.name)


if __name__ == "__main__":
    if len(sys.argv) > 2:
        fail("usage: update-nextui-h700 [nextui-package.nix]")
    if len(sys.argv) == 2:
        package_path = Path(sys.argv[1])
    else:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        package_path = Path(root) / "pkgs/nextui_h700/package.nix"
    main(package_path)
