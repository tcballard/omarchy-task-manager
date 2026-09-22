#!/usr/bin/env python3
"""Real collector/worker lifecycle, without an installed service or GUI."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

core = str(Path(sys.argv[1]).resolve())

def until(fn, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = fn()
            if value:
                return value
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(.05)
    raise AssertionError('Timed out waiting for collector')

with tempfile.TemporaryDirectory() as root:
    env = dict(os.environ, XDG_RUNTIME_DIR=root, XDG_STATE_HOME=root, XDG_CONFIG_HOME=root)
    cache = Path(root) / 'omarchy-task-manager-monitor/history.json'
    collector = subprocess.Popen([core, '--monitor'], env=env)
    def read():
        return json.loads(cache.read_text())
    def snapshot():
        request = json.dumps(dict(op='sample', page='summary', background_history=True)) + '\n'
        result = subprocess.run([core], input=request, capture_output=True, text=True, env=env, timeout=10, check=True)
        return json.loads(result.stdout)['background']
    try:
        history = until(lambda: (h if len((h := read())['points']) >= 3 else None))
        assert history['version'] == 1 and len(history['points']) <= 61
        assert set(history) == {'version', 'updated', 'points'}
        assert {'cpu', 'memory', 'time'} <= set(history['points'][-1])
        assert cache.stat().st_mode & 0o777 == 0o600
        assert cache.parent.stat().st_mode & 0o777 == 0o700
        first = snapshot()
        assert len(first['points']) >= 3
        until(lambda: read()['updated'] > first['updated'])
        reopened = snapshot()
        assert reopened['points'][0]['time'] == first['points'][0]['time']
        assert reopened['updated'] > first['updated']
        duplicate = subprocess.run([core, '--monitor'], env=env, capture_output=True, timeout=3)
        assert duplicate.returncode != 0 and collector.poll() is None
        collector.send_signal(signal.SIGSTOP)
        time.sleep(3.2)
        assert snapshot() is None
        collector.send_signal(signal.SIGCONT)
        until(lambda: snapshot())
        collector.terminate()
        collector.wait(timeout=3)
        assert not cache.exists() and snapshot() is None
        collector = subprocess.Popen([core, '--monitor'], env=env)
        fresh = until(lambda: read())
        assert fresh['points'][0]['time'] > reopened['updated']
        collector.kill()
        collector.wait(timeout=3)
        assert cache.exists() and snapshot() is None
        # Simulate package removal using a disposable executable copy.
        removable = Path(root) / 'removable-core'
        shutil.copy2(core, removable)
        collector = subprocess.Popen([str(removable), '--monitor'], env=env)
        until(lambda: (h if (h := read())['updated'] > fresh['updated'] else None))
        removable.unlink()
        collector.wait(timeout=3)
        assert collector.returncode == 0 and not cache.exists()
    finally:
        if collector.poll() is None:
            collector.send_signal(signal.SIGCONT)
            collector.terminate()
            collector.wait(timeout=3)
print('Background lifecycle: reopen, duplicate, expiry, stop, restart, crash and removal passed')
