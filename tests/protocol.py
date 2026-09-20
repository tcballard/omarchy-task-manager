#!/usr/bin/env python3
"""Real worker protocol/action tests. Hyprland server is a test double, not live acceptance."""
import json, os, pathlib, signal, socket, subprocess, sys, tempfile, threading, time
binary = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="task-manager-test-") as tmp:
    runtime = pathlib.Path(tmp)
    sockpath = runtime / "hypr/test/.socket.sock"
    sockpath.parent.mkdir(parents=True)
    server = None
    try:
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(sockpath)); server.listen(); server.settimeout(.2)
    except PermissionError:
        if server: server.close()
        server = None
        print("SKIP: compositor IPC tests; host blocks Unix sockets")
    child = subprocess.Popen(["sleep", "60"])
    alive = True
    requests = []
    def respond():
        while alive:
            try: conn, _ = server.accept()
            except socket.timeout: continue
            except OSError: break
            with conn:
                request = conn.recv(8192).decode(); requests.append(request)
                if request == "j/clients":
                    conn.sendall(json.dumps([dict(pid=child.pid,address="0xabcd",title="Disposable test",**{"class":"Test App"})]).encode())
                else: conn.sendall(b"ok")
    thread = threading.Thread(target=respond, daemon=True); 
    if server: thread.start()
    config = runtime / "config/omarchy/current/theme"; config.mkdir(parents=True)
    (config/"colors.toml").write_text('background = "#ffffff"\nforeground = "#111111"\naccent = "#2255aa"\n')
    env = dict(os.environ, XDG_RUNTIME_DIR=tmp, HYPRLAND_INSTANCE_SIGNATURE="test", XDG_CONFIG_HOME=str(runtime/"config"), XDG_STATE_HOME=str(runtime/"state"), XDG_CONFIG_DIRS=str(runtime/"system-config"))
    worker = subprocess.Popen([binary],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    def request(v):
        worker.stdin.write(json.dumps(v)+"\n");worker.stdin.flush()
        # Select prevents a broken worker from hanging the test suite.
        import select
        assert select.select([worker.stdout],[],[],8)[0], "worker timed out"
        return json.loads(worker.stdout.readline())
    try:
        first=request(dict(op="sample"));assert first["kind"]=="snapshot"
        assert first["system"]["cpu"][0]["usage"] is None
        assert first["theme"]["background"]=="#ffffff"
        row=next(p for p in first["processes"] if p["id"]["pid"]==child.pid)
        if server:
            app=next(a for a in first["apps"] if any(t["pid"]==child.pid for t in a["targets"]))
            assert app["count"]==1 and not app["protected"]
        stale=dict(row["id"],start=row["id"]["start"]+1)
        assert not request(dict(op="signal",targets=[stale],force=True))["results"][0]["ok"]
        assert child.poll() is None
        selfrow=next(p for p in first["processes"] if p["id"]["pid"]==worker.pid)
        assert not request(dict(op="signal",targets=[selfrow["id"]]))["results"][0]["ok"]
        if server:
            assert request(dict(op="window",id=row["id"],address="0xabcd",close=True))["results"][0]["ok"]
            assert "/dispatch closewindow address:0xabcd" in requests
            assert request(dict(op="window",id=row["id"],address="0xdead",close=True))["kind"]=="error"
        time.sleep(.12)
        second=request(dict(op="sample"));assert 0<=second["system"]["cpu"][0]["usage"]<=100
        reset_sample=request(dict(op="sample",reset=True))
        assert reset_sample["system"]["continuous"] is False
        assert reset_sample["system"]["cpu"][0]["usage"] is None
        assert all(p["cpu"] is None for p in reset_sample["processes"])
        # Atomic theme replacement, as performed by Omarchy.
        old=config.with_name("old");config.rename(old);config.mkdir()
        (config/"colors.toml").write_text('background = "#101010"\nforeground = "invalid"\n')
        changed=request(dict(op="sample"));assert changed["theme"]=={}, "malformed palette must fall back as a complete set"
        # Details pin a PID + start time; stale identities never disclose another process.
        inspected=request(dict(op="inspect",id=row["id"]));assert inspected["kind"]=="inspection"
        assert inspected["data"]["process"]["id"]==row["id"]
        assert request(dict(op="inspect",id=stale))["kind"]=="error"
        assert request(dict(op="manage",category="process",verb="nice",id=stale,nice=10))["kind"]=="error"
        assert request(dict(op="manage",category="process",verb="nice",id=row["id"],nice=99))["kind"]=="error"
        assert request(dict(op="manage",category="process",verb="affinity",id=row["id"],cpus=[]))["kind"]=="error"
        for verb in ["suspend","resume"]:
            r=request(dict(op="manage",category="process",verb=verb,id=row["id"]));assert r["kind"]=="action",r
        nice=request(dict(op="manage",category="process",verb="nice",id=row["id"],nice=10));assert nice["kind"]=="action",nice
        assert os.getpriority(os.PRIO_PROCESS,child.pid)==10
        cpus=sorted(os.sched_getaffinity(child.pid))
        affinity=request(dict(op="manage",category="process",verb="affinity",id=row["id"],cpus=[cpus[0]]));assert affinity["kind"]=="action",affinity
        assert os.sched_getaffinity(child.pid)=={cpus[0]}
        assert request(dict(op="manage",category="service",scope="user",verb="stop",key="dbus.service"))["kind"]=="error"
        assert request(dict(op="manage",category="service",scope="user",verb="stop",key="--bad.service"))["kind"]=="error"
        assert request(dict(op="manage",category="session",uid=os.getuid()+1,session="1",verb="logout"))["kind"]=="error"
        assert request(dict(op="manage",category="restart",targets=[],desktop_file="/tmp/no.desktop"))["kind"]=="error"
        # Disable a system autostart entry using an atomic per-user override.
        system_startup=runtime/"system-config/autostart";system_startup.mkdir(parents=True)
        source=system_startup/"sample.desktop";original="[Desktop Entry]\nType=Application\nName=Sample\nExec=sleep 1\n[Desktop Action test]\nName=Test\nExec=true\n"
        source.write_text(original)
        startup=request(dict(op="sample",page="startup"));assert any(r["key"]=="sample.desktop" for r in startup["management"]["rows"])
        assert request(dict(op="manage",category="startup",key="sample.desktop",enabled=False))["kind"]=="action"
        override=runtime/"config/autostart/sample.desktop";assert "Hidden=true" in override.read_text();assert source.read_text()==original
        assert request(dict(op="manage",category="startup",key="sample.desktop",enabled=True))["kind"]=="action"
        assert "Hidden=false" in override.read_text();assert "[Desktop Action test]" in override.read_text()
        assert request(dict(op="manage",category="startup",key="../bad.desktop",enabled=False))["kind"]=="error"
        h=request(dict(op="sample",page="history"));assert len(h["usage"]["rows"])>0
        assert request(dict(op="manage",category="history",verb="reset"))["kind"]=="action"
        assert json.loads((runtime/"state/omarchy-task-manager/history.json").read_text())["rows"]==[]
        for page in ["services","system-services","users","performance"]:
            sample=request(dict(op="sample",page=page));assert sample["kind"]=="snapshot" and sample["management_page"]==page
        print("PASS: inspection; suspend/resume; nice; affinity; startup override; history reset; management validation")
        assert request(dict(op="signal",targets=[row["id"]],force=False))["results"][0]["ok"]
        child.wait(timeout=3)
        assert not request(dict(op="signal",targets=[row["id"]],force=True))["results"][0]["ok"]
        assert request(dict(op="bad"))["kind"]=="error"
        print("PASS: live metrics; PID mismatch; self protection; theme replacement; disposable termination; protocol errors")
        if server: print("PASS: app attribution and window identity through test compositor")
        worker.terminate()
        assert worker.wait(timeout=3) == 0
        assert json.loads((runtime/"state/omarchy-task-manager/history.json").read_text())["rows"]
        print("PASS: worker SIGTERM exits and persists history with stdin still open")
    finally:
        if child.poll() is None: child.kill();child.wait()
        worker.stdin.close()
        try: worker.wait(timeout=3)
        except subprocess.TimeoutExpired: worker.kill();worker.wait();raise
        alive=False
        if server: thread.join(timeout=1);server.close()
