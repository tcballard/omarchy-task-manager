#!/usr/bin/env bash
# Command fixtures, not runtime/package/desktop acceptance.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
export fixture
mkdir -p "$fixture/bin"
printf 'fixture, not a library\n' > "$fixture/libQt6Svg.so.6.12.0"
printf 'fixture, not a plugin\n' > "$fixture/libqsvgicon.so"
cat > "$fixture/bin/pacman" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -Q) [[ ${missing:-0} != 1 ]] || exit 1; printf 'qt6-svg %s\n' "$version" ;;
  -Qi) printf 'Packager: command fixture\n' ;;
  -Qkk) [[ ${corrupt:-0} != 1 ]] ;;
  -Qoq) printf '%s\n' "${owner:-qt6-svg}" ;;
  *) exit 1 ;;
esac
SH
cat > "$fixture/bin/probe" <<'SH'
#!/usr/bin/env bash
[[ ${probe_failed:-0} != 1 ]] || exit 1
[[ ${no_result:-0} == 1 ]] || echo ICON_RENDER_RESULT=pass
echo QT_RUNTIME=fixture
printf 'QT_SVG_RUNTIME_FILE=%s/libQt6Svg.so.6.12.0\n' "$fixture"
[[ ${no_plugin:-0} == 1 ]] || printf 'QT_SVG_RUNTIME_FILE=%s/libqsvgicon.so\n' "$fixture"
SH
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
count=0
check() {
  local expected=$1 actual=0
  shift
  "$root/scripts/check-qtsvg.sh" --icon-probe "$fixture/bin/probe" "$@" > "$fixture/result" 2>&1 || actual=$?
  if [[ $actual != "$expected" ]]; then cat "$fixture/result"; echo "expected $expected, got $actual ($version)"; exit 1; fi
  count=$((count + 1))
}
for version in 6.8.9-1 6.8.10-2 6.11.2-1 6.11.3-2 6.12.0-1 6.13.0-1 1:6.8.9-2.1; do
  export version; check 0
  grep -Fxq SECURITY_RESULT=fixed-upstream "$fixture/result"
done
for version in 6.4.2-1 6.8.8-9 6.9.0-1 6.9.9-1 6.10.3-8 6.11.1-10; do
  export version; check 1
done
for version in 6.12.0beta1-1 6.12.0rc1-1 7.0.0-1 nonsense; do
  export version; check 2
done
export version=6.12.0-1
missing=1 check 2
corrupt=1 check 2
owner=custom-qt check 2
no_plugin=1 check 2
probe_failed=1 check 2
no_result=1 check 2
export version=6.4.2-15
cat > "$fixture/backport" <<'TXT'
package=qt6-svg 6.4.2-15
cve=CVE-2026-8168
complete-branch-fix-set=yes
vendor-evidence=https://vendor.example/immutable-package-recipe
reviewed-by=fixture reviewer
TXT
check 0 --backport-evidence "$fixture/backport"
grep -Fxq SECURITY_RESULT=fixed-vendor-backport "$fixture/result"
version=6.4.2-16 check 2 --backport-evidence "$fixture/backport"
sed -i '/complete-branch-fix-set/d' "$fixture/backport"
check 2 --backport-evidence "$fixture/backport"
check 2 --backport-evidence "$fixture/missing"
printf '%d QtSvg policy/provenance fixture scenarios passed (no real Qt execution)\n' "$count"
