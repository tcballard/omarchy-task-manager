#!/usr/bin/env python3
"""Keep the shipped app, source archive and package versions aligned."""
import pathlib
import re
import tomllib

root = pathlib.Path(__file__).resolve().parents[1]
def read(path):
    return (root / path).read_text()

version = tomllib.loads(read("Cargo.toml"))["package"]["version"]
assert re.fullmatch(r"\d+\.\d+\.\d+", version), version
packages = tomllib.loads(read("Cargo.lock"))["package"]
assert next(p["version"] for p in packages if p["name"] == "omarchy-task-manager-core") == version
expected = {
    "CMakeLists.txt": f"VERSION {version} LANGUAGES",
    "ui/main.cpp": f'app.setApplicationVersion("{version}")',
    "ui/Main.qml": f"v{version} · Preview",
    "packaging/PKGBUILD": f"pkgver={version}\n",
    "scripts/package-source.sh": f"name=omarchy-task-manager-{version}\n",
    "README.md": f"**v{version} preview.**",
    "RELEASE_NOTES.md": f"# v{version} —",
}
for path, marker in expected.items():
    assert marker in read(path), f"{path}: expected {marker!r}"
print(f"Release metadata aligned: v{version}")
