#!/usr/bin/env bash
# Read-only publication evidence; errors never mean a package is absent.
set -euo pipefail
expected=${1:?Usage: check-channels.sh PACKAGE_VERSION (for example 0.1.2-1)}
[[ $expected =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || exit 2
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
printf 'Checked UTC: %s\nExpected: %s (x86_64)\n' "$(date -u +%FT%TZ)" "$expected"
result=0
for channel in edge rc stable; do
  url="https://pkgs.omarchy.org/$channel/x86_64/omarchy.db?$(date +%s)"
  if ! curl --fail --location --silent --show-error --max-time 60 "$url" -o "$scratch/$channel.db" ||
     ! tar -tf "$scratch/$channel.db" > "$scratch/$channel.list"; then
    printf '%s: UNVERIFIED (database could not be read)\n' "$channel"
    result=1
    continue
  fi
  entry=$(awk '/^omarchy-task-manager-[0-9][^/]*\/desc$/ {print}' "$scratch/$channel.list")
  if [[ -z $entry ]]; then
    printf '%s: absent\n' "$channel"
    result=1
    continue
  fi
  if [[ $entry == *$'\n'* ]] || ! tar -xOf "$scratch/$channel.db" "$entry" > "$scratch/desc"; then
    printf '%s: UNVERIFIED (ambiguous or unreadable entry)\n' "$channel"
    result=1
    continue
  fi
  version=$(awk '/^%VERSION%$/ {getline; print}' "$scratch/desc")
  printf '%s: %s | %s | database sha256: %s\n' "$channel" "${version:-UNVERIFIED}" "$url" "$(sha256sum "$scratch/$channel.db" | cut -d ' ' -f1)"
  [[ $version == "$expected" ]] || result=1
done
exit "$result"
