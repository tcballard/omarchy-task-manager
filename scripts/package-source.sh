#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dest="$root/dist"
mkdir -p "$dest"
version=$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["package"]["version"])' "$root/Cargo.toml")
name="omarchy-task-manager-$version"
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/$name"
for path in Cargo.toml Cargo.lock rust-toolchain.toml CMakeLists.txt LICENSE AGENTS.md PRODUCT.md RELEASE_NOTES.md README.md FEATURES.md SCOPE.md ARCHITECTURE.md CREDITS.md VERIFICATION.md HARDENING.md HARDENING.sha256 .github docs src ui packaging tests scripts; do
  cp -a -- "$root/$path" "$stage/$name/"
done
tar --sort=name --mtime='2026-09-20 00:00:00Z' --owner=0 --group=0 --numeric-owner -czf "$dest/$name.tar.gz" -C "$stage" "$name"
cp "$root/packaging/PKGBUILD" "$dest/PKGBUILD"
digest=$(sha256sum "$dest/$name.tar.gz" | cut -d ' ' -f1)
sed -i "s/SOURCE_DIGEST/$digest/" "$dest/PKGBUILD"
printf 'Source and local PKGBUILD: %s\n' "$dest"
recipe="$stage/repository/pkgbuilds/omarchy-task-manager"
mkdir -p "$recipe/.omarchy"
cp "$dest/PKGBUILD" "$recipe/PKGBUILD"
cp "$root/packaging/omarchy/package.json" "$recipe/.omarchy/package.json"
tar --sort=name --mtime='2026-09-20 00:00:00Z' --owner=0 --group=0 --numeric-owner -czf "$dest/$name-omarchy-pkgs.tar.gz" -C "$stage/repository" pkgbuilds
printf 'Omarchy repository contribution: %s\n' "$dest/$name-omarchy-pkgs.tar.gz"
