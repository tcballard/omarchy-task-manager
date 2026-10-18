#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture"/{bin,assets,package/usr/bin,package/usr/lib/omarchy-task-manager}
export FIXTURE=$fixture
name=omarchy-task-manager
printf 'pkgname = %s\npkgver = 0.1.2-1\narch = x86_64\ndepend = qt6-base\n' "$name" > "$fixture/package/.PKGINFO"
echo 'fixture build info' > "$fixture/package/.BUILDINFO"
echo fixture > "$fixture/package/usr/bin/$name"
echo fixture > "$fixture/package/usr/lib/$name/$name-core"
tar -czf "$fixture/assets/$name-0.1.2-1-x86_64.pkg.tar.zst" -C "$fixture/package" .PKGINFO .BUILDINFO usr
cp "$fixture/package/.BUILDINFO" "$fixture/assets/PACKAGE-BUILDINFO.txt"
printf 'Commit: 29f50d058e63e1a1200362c536c0c7f7739f0048\nWorkflow run: 38545446855\n' > "$fixture/assets/BUILD-INFO.txt"
(cd "$fixture/assets"; sha256sum ./* > SHA256SUMS; zip -q "$fixture/artifact.zip" ./*)
zip_sha=$(sha256sum "$fixture/artifact.zip" | cut -d' ' -f1)
pkg_sha=$(sha256sum "$fixture/assets/$name-0.1.2-1-x86_64.pkg.tar.zst" | cut -d' ' -f1)
sed -e "s/^zip_sha=.*/zip_sha=$zip_sha/" -e "s/^pkg_sha=.*/pkg_sha=$pkg_sha/" "$root/scripts/test-install-v012.sh" > "$fixture/installer.sh"
export ZIP_SHA=$zip_sha
cat > "$fixture/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
tool=$(basename "$0")
case $tool in
  id) echo 1000 ;;
  uname) echo x86_64 ;;
  omarchy-version) echo fixture-omarchy ;;
  gh)
    [[ $1 != auth ]] || exit 0
    case $2 in
      */zip) if [[ $SCENARIO == corrupt ]]; then echo corrupt; else cat "$FIXTURE/artifact.zip"; fi ;;
      */artifacts/*) jq -n --arg digest "sha256:$ZIP_SHA" --arg scenario "$SCENARIO" '{name:"arch-development-package",expired:($scenario == "expired"),digest:$digest,workflow_run:{id:38545446855,head_sha:(if $scenario == "wrong-source" then "wrong" else "384322478a2e7155f138edd897c7b418469c64d4" end)}}' ;;
      */runs/*) echo '{"head_sha":"384322478a2e7155f138edd897c7b418469c64d4","status":"completed","conclusion":"success"}' ;;
    esac ;;
  pacman-conf) if [[ ${1:-} == CacheDir ]]; then echo "$CASE/cache"; else echo fixture-config; fi ;;
  pacman)
    case $1 in
      -Q)
        if [[ $2 == omarchy-task-manager ]]; then cat "$CASE/installed"; else
          for dep in "${@:2}"; do
            qt=6.12.0-1; [[ $SCENARIO != old-qt ]] || qt=6.11.2-1
            echo "$dep $qt"
          done
        fi ;;
      -Qp)
        if [[ $2 == *previous* || $2 == *cache* ]]; then echo 'omarchy-task-manager 0.1.1-1'; else echo 'omarchy-task-manager 0.1.2-1'; fi ;;
      -T) [[ $SCENARIO != missing-dep ]] ;;
      -U)
        echo "upgrade $*" >> "$CASE/mutations"
        if [[ $* == *previous* ]]; then echo 'omarchy-task-manager 0.1.1-1' > "$CASE/installed"; else
          [[ $SCENARIO != transaction-fail ]] || exit 1
          echo 'omarchy-task-manager 0.1.2-1' > "$CASE/installed"
        fi ;;
      -R) echo remove >> "$CASE/mutations"; : > "$CASE/installed" ;;
      -Sw) echo download >> "$CASE/downloads"; exit 1 ;;
      -Qk) exit 0 ;;
      *) echo "Unexpected pacman: $*" >&2; exit 1 ;;
    esac ;;
  systemctl)
    if [[ $2 == is-active ]]; then [[ -f $CASE/active ]]; exit; fi
    if [[ $2 == stop ]]; then rm -f "$CASE/active"; echo stop >> "$CASE/services"; fi
    if [[ $2 == start ]]; then touch "$CASE/active"; echo start >> "$CASE/services"; fi ;;
  ldd) if [[ $SCENARIO == missing-symbol ]]; then echo 'undefined symbol: fixture'; fi ;;
  timeout)
    if [[ $SCENARIO == pre-smoke-fail ]]; then exit 1; fi
    if [[ $SCENARIO == post-smoke-fail && $2 == /usr/bin/* ]]; then exit 1; fi ;;
  sudo) exec "$@" ;;
  pgrep) [[ $SCENARIO == app-open ]] ;;
  bsdtar)
    if [[ $2 == *.zip ]]; then unzip -q "$2" -d "$4"; else tar "$@"; fi ;;
  *) echo "Unexpected mock: $tool" >&2; exit 1 ;;
esac
MOCK
chmod +x "$fixture/bin/mock"
for tool in id uname omarchy-version gh pacman-conf pacman systemctl ldd timeout sudo pgrep bsdtar; do ln -s mock "$fixture/bin/$tool"; done
export PATH="$fixture/bin:$PATH"
export WAYLAND_DISPLAY=wayland-fixture
run_case() {
  export SCENARIO=$1 CASE=$fixture/$1
  mkdir -p "$CASE/cache" "$CASE/state" "$CASE/runtime"
  export XDG_STATE_HOME=$CASE/state XDG_RUNTIME_DIR=$CASE/runtime
  echo 'omarchy-task-manager 0.1.1-1' > "$CASE/installed"
  touch "$CASE/active"
  [[ $1 == no-backup ]] || echo old-package > "$CASE/cache/omarchy-task-manager-previous.pkg.tar.zst"
  if [[ $1 == fresh ]]; then : > "$CASE/installed"; rm "$CASE/active"; fi
  local status=0
  bash "$fixture/installer.sh" "${@:2}" > "$CASE/output" 2>&1 || status=$?
  local work
  work=$(find "$CASE/state" -name previous-version.txt -printf '%h\n' | head -1)
  case $1 in
    success|fresh)
      if ((status != 0)); then cat "$CASE/output"; exit 1; fi
      [[ $(cat "$CASE/installed") == 'omarchy-task-manager 0.1.2-1' ]]
      bash "$work/revert.sh" >> "$CASE/output" 2>&1
      if [[ $1 == fresh ]]; then [[ ! -s $CASE/installed ]]; else
        [[ $(cat "$CASE/installed") == 'omarchy-task-manager 0.1.1-1' && -f $CASE/active ]]
      fi ;;
    check)
      (( status == 0 )); [[ ! -f $CASE/mutations ]] ;;
    post-smoke-fail|transaction-fail)
      (( status != 0 )); [[ $(cat "$CASE/installed") == 'omarchy-task-manager 0.1.1-1' && -f $CASE/active ]] ;;
    tamper-rollback|changed-version)
      (( status == 0 ))
      if [[ $1 == tamper-rollback ]]; then echo corrupt >> "$work/previous.pkg.tar.zst"; else echo 'omarchy-task-manager 0.1.3-1' > "$CASE/installed"; fi
      if bash "$work/revert.sh" >> "$CASE/output" 2>&1; then echo 'Unsafe rollback succeeded'; exit 1; fi
      [[ $(wc -l < "$CASE/mutations") == 1 ]] ;;
    *)
      (( status != 0 )); [[ ! -f $CASE/mutations && ! -f $CASE/services ]]
      [[ $(cat "$CASE/installed") == 'omarchy-task-manager 0.1.1-1' ]]
      case $1 in
        corrupt) reason='FAILED' ;;
        expired|wrong-source) reason='Artifact expired or provenance differs' ;;
        old-qt) reason='requires the Qt 6.12 family' ;;
        missing-dep) reason='Missing dependencies' ;;
        missing-symbol) reason='Missing libraries or symbols' ;;
        pre-smoke-fail) reason='Isolated Qt launch failed' ;;
        app-open) reason='Close the Task Manager window' ;;
        no-backup) reason='Could not save the previous package' ;;
      esac
      grep -F "$reason" "$CASE/output" >/dev/null ;;
  esac
  echo "PASS: $1"
}
for scenario in corrupt expired wrong-source old-qt missing-dep missing-symbol pre-smoke-fail app-open no-backup success fresh post-smoke-fail transaction-fail tamper-rollback changed-version; do run_case "$scenario"; done
run_case check --check
