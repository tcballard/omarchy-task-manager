#!/usr/bin/env python3
"""Exercise the source -> repository recipe handoff without evaluating PKGBUILD."""
import hashlib
import json
import pathlib
import re
import subprocess
import tarfile
import tomllib

root = pathlib.Path(__file__).resolve().parents[1]
version = tomllib.loads((root / "Cargo.toml").read_text())["package"]["version"]
name = f"omarchy-task-manager-{version}"
dist = root / "dist"

def generate():
    subprocess.run([str(root / "scripts/package-source.sh")], check=True)
    return {
        filename: hashlib.sha256((dist / filename).read_bytes()).hexdigest()
        for filename in (f"{name}.tar.gz", f"{name}-omarchy-pkgs.tar.gz", "PKGBUILD")
    }

first = generate()
assert first == generate(), "Packaging output is not reproducible"
recipe = (dist / "PKGBUILD").read_text()
assert f"pkgver={version}\n" in recipe
assert f"sha256sums=('{first[name + '.tar.gz']}')" in recipe
assert 'source=("$url/releases/download/v$pkgver/$pkgname-$pkgver.tar.gz")' in recipe
assert "SOURCE_DIGEST" not in recipe and "SKIP" not in recipe
with tarfile.open(dist / f"{name}.tar.gz") as archive:
    paths = archive.getnames()
    assert all(p == name or p.startswith(name + "/") for p in paths)
    assert not any(".." in pathlib.PurePosixPath(p).parts for p in paths)
    assert not any(p.startswith(name + "/dist/") for p in paths)
    assert archive.extractfile(name + "/LICENSE")
    cargo = tomllib.loads(archive.extractfile(name + "/Cargo.toml").read().decode())
    assert cargo["package"]["version"] == version
with tarfile.open(dist / f"{name}-omarchy-pkgs.tar.gz") as archive:
    prefix = "pkgbuilds/omarchy-task-manager/"
    files = {member.name: member for member in archive.getmembers() if member.isfile()}
    assert set(files) == {prefix + "PKGBUILD", prefix + ".omarchy/package.json"}
    assert archive.extractfile(prefix + "PKGBUILD").read().decode() == recipe
    metadata = json.load(archive.extractfile(prefix + ".omarchy/package.json"))
    assert metadata["source"] == "local" and metadata["release_ring"] == "fast"
    assert "channels" not in metadata, "An edge-only pin would block RC/stable publication"
    watch = metadata["upstream"]["watch"]
    assert watch["github"] == "tcballard/omarchy-task-manager"
    assert watch["allow_prerelease"] is True
    pattern = re.compile(watch["pattern"])
    assert pattern.fullmatch("v" + version).group("version") == version
    assert not pattern.fullmatch("v" + version + "-unfinished")
print("Reproducible source and Omarchy recipe: checksum, version and layout verified")
