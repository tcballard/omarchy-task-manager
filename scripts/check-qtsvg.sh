#!/usr/bin/env bash
# Read-only dependency evidence. Exit 0: fixed; 1: affected; 2: unverified.
set -euo pipefail
export LC_ALL=C
probe= backport=
while (($#)); do
  case "$1" in
    --icon-probe|--backport-evidence)
      (($# >= 2)) || { echo 'Missing option value' >&2; exit 2; }
      if [[ $1 == --icon-probe ]]; then probe=$2; else backport=$2; fi
      shift 2 ;;
    *) echo 'Usage: check-qtsvg.sh --icon-probe ./build/icon-test [--backport-evidence FILE]' >&2; exit 2 ;;
  esac
done
unverified() { printf 'SECURITY_RESULT=unverified\nReason: %s\n' "$*"; exit 2; }
printf 'CVE: CVE-2026-8168\nAdvisory: https://www.qt.io/blog/security-advisory-cve-2026-8168\n'
printf 'UTC: %s\nArchitecture: %s\n' "$(date -u +%FT%TZ)" "$(uname -m)"
printf 'Evidence scope: this process/environment only; not XPS or channel acceptance\n'
[[ -x $probe ]] || unverified 'Build and supply the icon-test executable from this checkout'
sha256sum -- "$probe"
if ! output=$(timeout 30s "$probe"); then unverified 'Ordinary SVG icon probe failed'; fi
printf '%s\n' "$output"
grep -Fxq 'ICON_RENDER_RESULT=pass' <<< "$output" || unverified 'No icon rendering result'
command -v pacman >/dev/null || unverified 'No pacman package evidence; manually review vendor packages on this OS'
identity=$(pacman -Q qt6-svg) || unverified 'qt6-svg is not installed'
printf 'Installed package: %s\n' "$identity"
[[ $identity == 'qt6-svg '* && $identity != *$'\n'* ]] || unverified 'Unexpected package identity'
version=${identity#qt6-svg }
pacman -Qi qt6-svg || unverified 'Package metadata unavailable'
pacman -Qkk qt6-svg || unverified 'Package file integrity check failed'
mapfile -t files < <(sed -n 's/^QT_SVG_RUNTIME_FILE=//p' <<< "$output" | sort -u)
((${#files[@]} >= 2)) || unverified 'QtSvg library and SVG plugin mappings are required'
library=false plugin=false
for file in "${files[@]}"; do
  [[ -f $file ]] || unverified "Runtime file missing or replaced: $file"
  owner=$(pacman -Qoq -- "$file") || unverified "Unowned runtime file: $file"
  [[ $owner == qt6-svg ]] || unverified "Unexpected runtime file owner: $owner"
  sha256sum -- "$file"
  [[ $file == */libQt6Svg.so.* ]] && library=true
  [[ $file == */libqsvgicon.so || $file == */libqsvg.so ]] && plugin=true
done
$library && $plugin || unverified 'Incomplete runtime QtSvg provenance'
# Only final releases in the fixed branches qualify by version. In particular,
# 6.9/6.10 are not made safe by being numerically greater than 6.8.9.
fixed=false
if [[ $version =~ ^([0-9]+:)?6\.([0-9]+)\.([0-9]+)-[0-9]+(\.[0-9]+)*$ ]]; then
  minor=$((10#${BASH_REMATCH[2]})) patch=$((10#${BASH_REMATCH[3]}))
  if (( (minor == 8 && patch >= 9) || (minor == 11 && patch >= 2) || minor >= 12 )); then fixed=true; fi
fi
if $fixed; then
  printf 'BACKPORT_STATUS=not-required (upstream fixed release)\nSECURITY_RESULT=fixed-upstream\n'
  exit 0
fi
if [[ -n $backport ]]; then
  [[ -r $backport ]] || unverified 'Backport evidence is unreadable'
  # Attestation is data, never sourced/executed. Require an exact package-release
  # match and a human review of ALL branch fixes, not just a CVE mention.
  grep -Fxq "package=$identity" "$backport" || unverified 'Backport evidence package/release mismatch'
  grep -Fxq 'cve=CVE-2026-8168' "$backport" || unverified 'Wrong backport advisory'
  grep -Fxq 'complete-branch-fix-set=yes' "$backport" || unverified 'Complete fix set not attested'
  grep -Eq '^vendor-evidence=https://[^[:space:]]+$' "$backport" || unverified 'Vendor evidence URL required'
  grep -Eq '^reviewed-by=.+$' "$backport" || unverified 'Named reviewer required'
  cat -- "$backport"
  sha256sum -- "$backport"
  printf 'BACKPORT_STATUS=operator-reviewed (attestation; URL not automatically verified)\nSECURITY_RESULT=fixed-vendor-backport\n'
  exit 0
fi
printf 'BACKPORT_STATUS=unverified (no complete vendor fix-set evidence supplied)\n'
if [[ $version =~ ^([0-9]+:)?6\.([0-9]+)\.([0-9]+)-[0-9]+(\.[0-9]+)*$ ]]; then
  printf 'SECURITY_RESULT=affected-unless-backported\n'; exit 1
fi
unverified 'Unrecognized or prerelease QtSvg version'
