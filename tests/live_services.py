#!/usr/bin/env python3
"""Real systemd acceptance using only a uniquely named disposable unit.

Run separately from portable tests. Requires a live system/user manager; absence
is a failure, never a skip. System scope requires root on a disposable CI VM.
"""
import argparse
import json
import os
from pathlib import Path
import pwd
import select
import subprocess
import tempfile
import time
import uuid


class Worker:
    def __init__(self, binary, as_user=None):
        self.tmp = tempfile.TemporaryDirectory(prefix="task-manager-service-worker-")
        prefix = []
        if as_user:
            account = pwd.getpwnam(as_user)
            os.chown(self.tmp.name, account.pw_uid, account.pw_gid)
            prefix = ["/usr/sbin/runuser", "-u", as_user, "--"]
        env = dict(os.environ, XDG_CONFIG_HOME=self.tmp.name + "/config",
                   XDG_STATE_HOME=self.tmp.name + "/state")
        self.process = subprocess.Popen(prefix + [str(binary)], env=env,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        text=True)

    def request(self, value):
        self.process.stdin.write(json.dumps(value) + "\n")
        self.process.stdin.flush()
        assert select.select([self.process.stdout], [], [], 12)[0], "worker timed out"
        line = self.process.stdout.readline()
        assert line, "worker exited before responding"
        return json.loads(line)

    def close(self):
        self.process.stdin.close()
        try:
            assert self.process.wait(timeout=5) == 0
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.tmp.cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda x: Path(x).resolve())
    parser.add_argument("--scope", choices=["user", "system"], required=True)
    args = parser.parse_args()
    if args.scope == "system":
        assert os.geteuid() == 0 and os.environ.get("GITHUB_ACTIONS") == "true", \
            "system-scope fixture is restricted to a disposable root CI job"
        directory = Path("/run/systemd/system")
        target = "multi-user.target"
    else:
        assert os.geteuid() != 0, "user-scope fixture must be unprivileged"
        directory = Path.home() / ".config/systemd/user"
        target = "default.target"
    ctl = ["/usr/bin/systemctl", "--no-pager", "--no-ask-password"]
    if args.scope == "user":
        ctl.append("--user")

    def systemctl(*arguments, check=True):
        return subprocess.run(ctl + list(arguments), check=check, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=10).stdout.strip()

    # is-system-running may report degraded; show confirms the manager is real
    # and reachable without treating unrelated failed units as this test's failure.
    assert systemctl("show", "--property=Version", "--value"), "no live systemd manager"
    name = "task-manager-check-" + uuid.uuid4().hex + ".service"
    path = directory / name
    directory.mkdir(parents=True, exist_ok=True)
    marker = "task-manager-live-service-check"
    unit = ("[Unit]\nDescription=Disposable Task Manager integration fixture\n"
            "[Service]\nType=exec\n"
            f"ExecStart=/bin/sh -c 'echo {marker}; exec /usr/bin/sleep infinity'\n"
            "StandardOutput=journal\nStandardError=journal\n"
            f"[Install]\nWantedBy={target}\n")
    worker = None
    with path.open("x") as f:
        f.write(unit)
    try:
        systemctl("daemon-reload")
        worker = Worker(args.binary)

        def action(verb):
            result = worker.request(dict(op="manage", category="service", scope=args.scope,
                                         key=name, verb=verb))
            assert result["kind"] == ("inspection" if verb == "logs" else "action"), result
            if verb != "logs":
                assert all(r["ok"] for r in result["results"]), result
            return result

        page = "services" if args.scope == "user" else "system-services"
        def row():
            result = worker.request(dict(op="sample", page=page))
            assert result["kind"] == "snapshot", result
            assert not result["management"].get("error"), result["management"]
            return next(r for r in result["management"]["rows"] if r["key"] == name)

        assert row()["state"] == "inactive"
        action("start")
        assert systemctl("is-active", name) == "active"
        assert row()["state"] == "active"
        first = systemctl("show", name, "--property=InvocationID", "--value")
        action("restart")
        second = systemctl("show", name, "--property=InvocationID", "--value")
        assert first and second and first != second, "restart did not create a new invocation"
        # Journal delivery is asynchronous. Poll within a fixed deadline.
        deadline = time.monotonic() + 8
        while marker not in action("logs")["data"]["logs"]:
            assert time.monotonic() < deadline, "fixture journal entry not visible"
            time.sleep(0.1)
        action("enable")
        assert systemctl("is-enabled", name) == "enabled"
        assert row()["enabled"] == "enabled"
        action("disable")
        assert systemctl("is-enabled", name, check=False) in ("disabled", "static")
        if args.scope == "system":
            denied = Worker(args.binary, as_user="nobody")
            try:
                result = denied.request(dict(op="manage", category="service", scope="system",
                                             key=name, verb="stop"))
                assert result["kind"] == "error", result
                assert systemctl("is-active", name) == "active", "denied action changed service"
            finally:
                denied.close()
        action("stop")
        assert systemctl("is-active", name, check=False) == "inactive"
        assert row()["state"] == "inactive"
        # App-level protection is exercised without issuing a systemd mutation.
        result = worker.request(dict(op="manage", category="service", scope=args.scope,
                                     key="dbus.service", verb="stop"))
        assert result["kind"] == "error" and "protected" in result["message"], result
        print(f"PASS: real {args.scope} service inventory/start/restart/stop/enable/disable/journal/protection")
        if args.scope == "system":
            print("PASS: unprivileged system-service mutation denied; service remained active")
    finally:
        try:
            if worker:
                worker.close()
        finally:
            try:
                systemctl("disable", "--now", name, check=False)
            finally:
                path.unlink(missing_ok=True)
                systemctl("daemon-reload")
                systemctl("reset-failed", name, check=False)
    assert not path.exists()
    assert systemctl("show", name, "--property=LoadState", "--value") == "not-found"
    print(f"PASS: {args.scope} fixture removed")


if __name__ == "__main__":
    main()
