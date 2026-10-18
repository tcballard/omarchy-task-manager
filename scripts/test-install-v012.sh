#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
repo=tcballard/omarchy-task-manager
run=38545446855
artifact=11884681461
head=384322478a2e7155f138edd897c7b418469c64d4
merge=29f50d058e63e1a1200362c536c0c7f7739f0048
zip_sha=aa38e44841dca2586c3e33e77df37787837e51311da64ad99e36413e3a068cf8
pkg_sha=724396a9d950fceeda6c1dfe79f93201f9db8e192942124e968b67c86a74b87b
name=omarchy-task-manager
version=0.1.2-1
mode=${1:-install}
[[ $# -le 1 && $mode =~ ^(install|--check)$ ]] || { echo 'Usage: test-install-v012.sh [--check]' >&2; exit 2; }
die() { printf 'Stopped: %s\n' "$*" >&2; exit 1; }
[[ $(id -u) != 0 ]] || die 'Run as your desktop user, without sudo. Only pacman uses sudo.'
for tool in gh jq bsdtar sha256sum pacman pacman-conf ldd timeout flock systemctl pgrep; do
  command -v "$tool" >/dev/null || die "Missing $tool. Install its native package first; no system packages have been changed."
done
[[ $(uname -m) == x86_64 ]] || die 'This artifact supports x86_64 only.'
command -v omarchy-version >/dev/null || die 'This test installer requires an Omarchy environment.'
gh auth status >/dev/null 2>&1 || die 'GitHub artifact access requires gh auth login (no release download is substituted).'
state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-task-manager/test-builds
mkdir -p "$state"
exec 9>"$state/install.lock"
flock -n 9 || die 'Another test installation is running.'
work=$(mktemp -d "$state/$run.XXXXXXXX")
exec > >(exec 9>&-; tee "$work/install.log") 2>&1
printf 'Test workspace: %s\n' "$work"
rollback_ready=false
transaction_started=false
was_active=false
recover() {
  local status=$?
  trap - EXIT
  if (( status != 0 )); then
    if $transaction_started && $rollback_ready; then
      printf 'Installation did not complete. Restoring the previous package…\n'
      exec 9>&-
      if ! bash "$work/revert.sh"; then
        printf 'Automatic recovery failed. Retry: bash %q\n' "$work/revert.sh" >&2
      fi
    fi
    printf 'Stopped; see %s/install.log\n' "$work" >&2
  fi
  exit "$status"
}
trap recover EXIT
omarchy-version | tee "$work/omarchy-version.txt"
pacman -Q qt6-base qt6-declarative qt6-wayland qt6-svg glibc gcc-libs | tee "$work/runtime.txt"
pacman-conf > "$work/pacman.conf.txt"
gh api "repos/$repo/actions/runs/$run" > "$work/run.json"
jq -e --arg head "$head" '.head_sha == $head and .status == "completed" and .conclusion == "success"' "$work/run.json" >/dev/null || die 'CI run identity or result differs.'
gh api "repos/$repo/actions/artifacts/$artifact" > "$work/artifact.json"
jq -e --arg head "$head" --arg digest "sha256:$zip_sha" --argjson run "$run" \
  '.name == "arch-development-package" and .expired == false and .digest == $digest and .workflow_run.id == $run and .workflow_run.head_sha == $head' \
  "$work/artifact.json" >/dev/null || die 'Artifact expired or provenance differs. A new artifact needs a new reviewed pin.'
gh api "repos/$repo/actions/artifacts/$artifact/zip" > "$work/artifact.zip"
printf '%s  %s\n' "$zip_sha" "$work/artifact.zip" | sha256sum -c -
mkdir "$work/assets"
bsdtar -xf "$work/artifact.zip" -C "$work/assets"
(cd "$work/assets" && sha256sum -c SHA256SUMS)
assets=$work/assets
grep -Fx "Commit: $merge" "$assets/BUILD-INFO.txt" >/dev/null || die 'Build merge commit differs.'
grep -Fx "Workflow run: $run" "$assets/BUILD-INFO.txt" >/dev/null || die 'Build run differs.'
pkg=$assets/$name-$version-x86_64.pkg.tar.zst
printf '%s  %s\n' "$pkg_sha" "$pkg" | sha256sum -c -
[[ $(pacman -Qp "$pkg") == "$name $version" ]] || die 'Package identity differs.'
bsdtar -xOf "$pkg" .PKGINFO > "$work/PKGINFO"
grep -Fx 'arch = x86_64' "$work/PKGINFO" >/dev/null || die 'Package architecture differs.'
bsdtar -xOf "$pkg" .BUILDINFO > "$work/BUILDINFO"
cmp "$work/BUILDINFO" "$assets/PACKAGE-BUILDINFO.txt"
mapfile -t deps < <(sed -n 's/^depend = //p' "$work/PKGINFO")
(( ${#deps[@]} > 0 )) || die 'Package has no dependency metadata.'
pacman -T "${deps[@]}" > "$work/missing-dependencies.txt" || die "Missing dependencies; see $work/missing-dependencies.txt. Use your normal complete Omarchy update; this installer never upgrades libraries or switches channels."
for qt in qt6-base qt6-declarative qt6-wayland qt6-svg; do
  installed=$(pacman -Q "$qt")
  [[ ${installed#* } == 6.12.* ]] || die "$qt is ${installed#* }; this CI binary requires the Qt 6.12 family. Keep your current channel. A build against your snapshot is needed; do not force this package or upgrade Qt alone."
done
unset LD_PRELOAD LD_LIBRARY_PATH QT_PLUGIN_PATH QML_IMPORT_PATH QML2_IMPORT_PATH QT_QPA_PLATFORM_PLUGIN_PATH
mkdir "$work/stage"
bsdtar -xf "$pkg" -C "$work/stage"
for exe in "$work/stage/usr/bin/$name" "$work/stage/usr/lib/$name/$name-core"; do
  ldd -r "$exe" > "$work/$(basename "$exe").ldd.txt" 2>&1 || die 'Runtime linker check failed.'
  if grep -E 'not found|undefined symbol' "$work/$(basename "$exe").ldd.txt"; then die 'Missing libraries or symbols. No packages changed.'; fi
done
smoke() {
  local exe=$1 isolated
  isolated=$(mktemp -d "$work/smoke.XXXXXXXX")
  mkdir "$isolated/runtime"
  env HOME="$isolated" XDG_CONFIG_HOME="$isolated/config" XDG_STATE_HOME="$isolated/state" \
    XDG_DATA_HOME="$isolated/data" XDG_CACHE_HOME="$isolated/cache" XDG_RUNTIME_DIR="$isolated/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 20s "$exe" --smoke
}
smoke "$work/stage/usr/bin/$name" > "$work/preinstall-smoke.log" 2>&1 || die 'Isolated Qt launch failed; see preinstall-smoke.log. Nothing installed.'
if [[ $mode == --check ]]; then
  printf 'Preflight passed; nothing installed. Live desktop acceptance is still pending.\n'
  exit 0
fi
command -v sudo >/dev/null || die 'sudo is required for the native package transaction.'
[[ -n ${XDG_RUNTIME_DIR:-} && -n ${WAYLAND_DISPLAY:-} ]] || die 'Run from a terminal in your Omarchy desktop session.'
systemctl --user show-environment >/dev/null || die 'Cannot reach the desktop user service manager.'
if pgrep -u "$(id -u)" -f '^(/[^ ]*/)?omarchy-task-manager( |$)' >/dev/null; then die 'Close the Task Manager window before installing.'; fi
old=$(pacman -Q "$name" 2>/dev/null || true)
[[ $old != "$name $version" ]] || die 'This version is already installed; retain the original workspace and revert.sh.'
mkdir "$work/previous"
if [[ -n $old ]]; then
  [[ $old == "$name "* ]] || die 'Unexpected previous package identity.'
  mapfile -t caches < <(pacman-conf CacheDir)
  previous=
  for cache in "${caches[@]}"; do
    for candidate in "$cache/$name-"*.pkg.tar.*; do
      [[ -f $candidate && $candidate != *.sig ]] || continue
      if [[ $(pacman -Qp "$candidate" 2>/dev/null) == "$old" ]]; then previous=$candidate; break 2; fi
    done
  done
  if [[ -z $previous ]]; then
    sudo pacman -Sw --noconfirm --nodeps --cachedir "$work/previous" "$name" || die 'Could not save the previous package; refusing upgrade.'
    for candidate in "$work/previous/$name-"*.pkg.tar.*; do
      [[ -f $candidate && $candidate != *.sig ]] || continue
      if [[ $(pacman -Qp "$candidate" 2>/dev/null) == "$old" ]]; then previous=$candidate; break; fi
    done
  fi
  [[ -n $previous ]] || die 'The exact installed version is unavailable for rollback. No upgrade performed.'
  cp "$previous" "$work/previous.pkg.tar.zst"
  (cd "$work" && sha256sum previous.pkg.tar.zst > rollback.sha256)
fi
printf '%s\n' "$old" > "$work/previous-version.txt"
systemctl --user is-active --quiet "$name-monitor.service" && was_active=true
printf '%s\n' "$was_active" > "$work/monitor-was-active.txt"
cat > "$work/revert.sh" <<'REVERT'
#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
exec 9>../install.lock
flock -n 9 || { echo 'Another test installation is running.' >&2; exit 1; }
name=omarchy-task-manager
old=$(cat previous-version.txt)
current=$(pacman -Q "$name" 2>/dev/null || true)
if [[ $current == "$old" ]]; then
  if [[ $(cat monitor-was-active.txt) == true ]]; then systemctl --user start "$name-monitor.service"; fi
  echo 'Previous package is already installed.'; exit 0
fi
[[ $current == "$name 0.1.2-1" ]] || { echo 'Installed version changed since this test; refusing rollback.' >&2; exit 1; }
if pgrep -u "$(id -u)" -f '^(/[^ ]*/)?omarchy-task-manager( |$)' >/dev/null; then echo 'Close Task Manager before reverting.' >&2; exit 1; fi
if [[ -n $old ]]; then sha256sum -c rollback.sha256; fi
if systemctl --user is-active --quiet "$name-monitor.service"; then systemctl --user stop "$name-monitor.service"; fi
if [[ -n $old ]]; then sudo pacman -U --noconfirm "$PWD/previous.pkg.tar.zst"; else sudo pacman -R --noconfirm "$name"; fi
systemctl --user daemon-reload
if [[ $(cat monitor-was-active.txt) == true ]]; then systemctl --user start "$name-monitor.service"; fi
echo 'Previous package restored. Preferences and history retained.'
REVERT
chmod 700 "$work/revert.sh"
rollback_ready=true
printf 'Revert at any time with: bash %q\n' "$work/revert.sh"
transaction_started=true
if $was_active; then systemctl --user stop "$name-monitor.service"; fi
sudo pacman -U "$pkg"
[[ $(pacman -Q "$name") == "$name $version" ]] || die 'Installed version differs.'
pacman -Qk "$name"
systemctl --user daemon-reload
smoke "/usr/bin/$name" > "$work/installed-smoke.log" 2>&1 || die 'Installed launch failed.'
if $was_active; then systemctl --user start "$name-monitor.service"; fi
transaction_started=false
printf 'Installed v0.1.2 test build. Open Task Manager from the launcher.\n'
printf 'Live XPS acceptance and all channel compatibility remain unverified.\n'
printf 'Revert: bash %q\nEvidence: %s\n' "$work/revert.sh" "$work"
