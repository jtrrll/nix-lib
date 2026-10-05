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


def asset_hash(assets: dict[str, dict], name: str) -> str:
    asset = assets.get(name)
    if asset is None:
        fail(f"missing BaseOS asset: {name}")
    digest = asset.get("digest") or ""
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        fail(f"missing SHA-256 digest for BaseOS asset: {name}")
    return "sha256-" + base64.b64encode(bytes.fromhex(digest[7:])).decode("ascii")


def replace_once(source: str, pattern: str, replacement: str) -> str:
    updated, count = re.subn(pattern, lambda _: replacement, source)
    if count != 1:
        fail(f"expected exactly one match for {pattern!r}, found {count}")
    return updated


def write_if_changed(path: Path, original: str, updated: str) -> None:
    if updated == original:
        print("BaseOS is already up to date")
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


def main(path: Path) -> None:
    release = json.loads(
        subprocess.run(
            [
                "curl",
                "-fsSL",
                "https://api.github.com/repos/pvaibhav/BaseOS/releases/latest",
            ],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout
    )
    tag = release.get("tag_name") or ""
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        fail(f"unexpected BaseOS release tag: {tag!r}")
    version = tag[1:]
    assets = {asset["name"]: asset for asset in release["assets"]}
    if len(assets) != len(release["assets"]):
        fail("BaseOS release contains duplicate asset names")

    original = path.read_text()
    hashes_section = re.search(r"(?ms)^  hashes = \{\n(.*?)^  \};$", original)
    if hashes_section is None:
        fail("BaseOS hash table not found")
    devices = re.findall(r"(?m)^    ([a-z0-9]+) = \{$", hashes_section.group(1))
    if not devices or len(devices) != len(set(devices)):
        fail("BaseOS device list is empty or contains duplicates")

    updated = replace_once(
        original, r'(?m)^    version = "[0-9.]+";$', f'    version = "{version}";'
    )
    for device in devices:
        image = asset_hash(assets, f"baseos-{device}-{version}.img.zip")
        update = asset_hash(assets, f"baseos-{device}-{version}.bosupd")
        pattern = (
            rf"(?m)^    {device} = \{{\n"
            r'      image = "sha256-[^"]+";\n'
            r'      update = "sha256-[^"]+";\n'
            r"    \};$"
        )
        replacement = (
            f"    {device} = {{\n"
            f'      image = "{image}";\n'
            f'      update = "{update}";\n'
            "    };"
        )
        updated = replace_once(updated, pattern, replacement)

    write_if_changed(path, original, updated)


if __name__ == "__main__":
    if len(sys.argv) > 2:
        fail("usage: update-baseos [baseos-package.nix]")
    if len(sys.argv) == 2:
        package_path = Path(sys.argv[1])
    else:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        package_path = Path(root) / "pkgs/baseos/package.nix"
    main(package_path)
