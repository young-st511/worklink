"""Opt-in real SSH QA using disposable local and remote directories only.
WORKLINK_TEST_SSH_HOST=<existing alias> python3 scripts/ssh-integration.py
Never writes SSH configuration, installs services or prints the real hostname.
"""
import hashlib
import json
import os
from pathlib import Path
import queue
import shlex
import subprocess
import tempfile
import threading
import time

host = os.environ.get("WORKLINK_TEST_SSH_HOST")
if not host:
    raise SystemExit("Set WORKLINK_TEST_SSH_HOST to an existing SSH alias.")
ssh = ["/usr/bin/ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host]
bundled_core = Path(".build/Worklink.app/Contents/Resources/worklink")
binary = (bundled_core if bundled_core.exists() else Path(".build/worklink")).resolve()

def command(text):
    return subprocess.run(ssh + [text], capture_output=True, text=True, check=True, timeout=20).stdout.strip()

remote_dir = command("mktemp -d /tmp/worklink-qa.XXXXXX")
if not remote_dir.startswith("/tmp/worklink-qa.") or not all(c.isalnum() or c in "/.-" for c in remote_dir):
    raise RuntimeError("Unexpected temporary path")
fixture = None
app = None
try:
    subprocess.run(["/usr/bin/scp", "-q", str(binary), f"{host}:{remote_dir}/worklink"], check=True, timeout=30)
    wrapper = "#!/bin/sh\nexport WORKLINK_DATA_DIR=" + shlex.quote(remote_dir + "/data") + "\nexec " + shlex.quote(remote_dir + "/worklink") + ' "$@"\n'
    subprocess.run(ssh + [f"cat > {shlex.quote(remote_dir + '/helper')}; chmod 700 {shlex.quote(remote_dir + '/helper')}"], input=wrapper, text=True, check=True, timeout=10)
    server = """import http.server,threading,sys,socket
class H(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(b'<title>Worklink QA</title><p>remote tunnel verified</p>')
 def log_message(self,*a): pass
class V6(http.server.ThreadingHTTPServer): address_family=socket.AF_INET6
s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
port=s.server_port
thread=threading.Thread(target=s.serve_forever,daemon=True);thread.start()
print(port,flush=True)
for family in sys.stdin:
 s.shutdown();s.server_close();thread.join()
 s=V6(('::1',port),H) if family.strip()=='v6' else http.server.ThreadingHTTPServer(('127.0.0.1',port),H)
 thread=threading.Thread(target=s.serve_forever,daemon=True);thread.start()
s.shutdown();s.server_close();thread.join()
"""
    subprocess.run(ssh + [f"cat > {shlex.quote(remote_dir + '/fixture.py')}"], input=server, text=True, check=True, timeout=10)
    fixture = subprocess.Popen(ssh + [f"python3 -u {shlex.quote(remote_dir + '/fixture.py')}"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    remote_port = int(fixture.stdout.readline().strip())
    with tempfile.TemporaryDirectory(prefix="worklink-qa-local-") as root:
        env = dict(os.environ, WORKLINK_DATA_DIR=root)
        app = subprocess.Popen([str(binary), "ui", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        events = queue.Queue()
        def reader():
            for line in app.stdout:
                events.put(json.loads(line))
        threading.Thread(target=reader, daemon=True).start()
        last_state = None
        def wait(predicate, seconds=20):
            global last_state
            until = time.monotonic() + seconds
            while time.monotonic() < until:
                try:
                    event = events.get(timeout=min(1, until-time.monotonic()))
                except queue.Empty:
                    continue
                if event.get("state"):
                    last_state = event["state"]
                if predicate(event):
                    return event
            raise AssertionError("QA state timeout: " + json.dumps(last_state))
        def send(method, **kwargs):
            app.stdin.write(json.dumps(dict(id=method, method=method, **kwargs)) + "\n");app.stdin.flush()
        state = wait(lambda e: e["kind"] == "state")["state"]
        parse = json.loads(subprocess.check_output([str(binary), "parse", str(remote_port)], text=True))
        import socket
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0));local_port = sock.getsockname()[1]
        port_id = "a" * 32
        config = state["config"]
        config["hosts"] = [dict(name=host, helper=remote_dir + "/helper")]
        config["image_host"] = host
        config["ports"] = [dict(id=port_id, name="QA preview", host=host, endpoint=parse["endpoint"], local_port=local_port, enabled=True)]
        send("save_config", config=config)
        saved = wait(lambda e: e.get("id") == "save_config")
        assert not saved.get("error"), saved
        send("environment", available=True, low_power=False)
        send("toggle", on=True)
        wait(lambda e: e.get("state") and any(p["status"]=="ready" for p in e["state"]["ports"]))
        import urllib.request
        assert b"remote tunnel verified" in urllib.request.urlopen(f"http://localhost:{local_port}/", timeout=5).read()
        with socket.create_connection(("::1", local_port), timeout=5) as ipv6:
            ipv6.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
            response=b""
            while True:
                chunk=ipv6.recv(4096)
                if not chunk: break
                response+=chunk
            assert b"remote tunnel verified" in response
        for family, target in [("v6", "::1"), ("v4", "127.0.0.1")]:
            fixture.stdin.write(family + "\n");fixture.stdin.flush()
            wait(lambda e: e.get("state") and any(p["id"]==port_id and p["status"]=="ready" and p.get("remote_host")==target for p in e["state"]["ports"]))
            assert b"remote tunnel verified" in urllib.request.urlopen(f"http://localhost:{local_port}/", timeout=5).read()
        send("title", port_id=port_id)
        wait(lambda e: e.get("id")=="title" and not e.get("error"))
        image = Path(root) / "original.png"
        payload = bytes(range(256)) * 1024
        image.write_bytes(payload)
        send("upload", path=str(image), extension="png", clipboard_count=41)
        complete = wait(lambda e: e["kind"]=="upload_complete")["job"]
        path = complete["remote_path"]
        actual = command("shasum -a 256 " + shlex.quote(path)).split()[0]
        assert actual == hashlib.sha256(payload).hexdigest()
        assert image.read_bytes() == payload
        assert not list((Path(root)/"queue").glob("*.png"))
        send("copy_path", job_id=complete["id"])
        copy = wait(lambda e: e.get("id")=="copy_path")
        assert copy["result"]==path and not copy.get("error")
        send("restore_original", job_id=complete["id"])
        restored = wait(lambda e: e.get("id")=="restore_original")
        assert not restored.get("error"), restored
        scratch = Path(restored["result"]["path"])
        assert scratch.read_bytes() == payload
        scratch.unlink()
        # Explicit file batches retain original names, including Unicode, duplicate basenames and empty files.
        file_sources = []
        for index, data in enumerate([b"original file bytes" * 16384, b"second same basename", b""]):
            folder = Path(root) / ("files-" + str(index));folder.mkdir()
            source = folder / ("한글 sample.csv" if index < 2 else "empty.txt")
            source.write_bytes(data);file_sources.append(source)
        send("send_files", paths=[str(source) for source in file_sources])
        uploaded = wait(lambda e: e.get("id")=="send_files", seconds=40)
        assert not uploaded.get("error"), uploaded
        assert len(uploaded["result"]) == 3, uploaded
        for source, remote_file in zip(file_sources, uploaded["result"]):
            assert remote_file["name"] == source.name and Path(remote_file["path"]).name == source.name
            actual = command("shasum -a 256 " + shlex.quote(remote_file["path"])).split()[0]
            assert actual == hashlib.sha256(source.read_bytes()).hexdigest()
        assert uploaded["result"][0]["path"] != uploaded["result"][1]["path"]
        send("copy_file_path", job_id=uploaded["result"][0]["id"])
        copied_file = wait(lambda e: e.get("id")=="copy_file_path")
        assert copied_file.get("result") == uploaded["result"][0]["path"], copied_file
        print(json.dumps(dict(explicit_file_batch=True, original_file_sha256=True, unicode_name=True, duplicate_basename=True, empty_file=True, file_path_recopy=True)))
        send("toggle", on=False)
        wait(lambda e: e.get("state") and not e["state"]["on"])
        app.stdin.close();app.wait(timeout=10)
        assert app.returncode==0, app.stderr.read()
        if os.environ.get("WORKLINK_QA_NATIVE") == "1":
            source_png = Path('.build/previews/on-light.png').resolve()
            for preserve in (False, True):
                native_env = dict(env, WORKLINK_QA_IMAGE_PATH=str(source_png), WORKLINK_QA_PRESERVE="1" if preserve else "0")
                native = subprocess.run(['.build/Worklink.app/Contents/MacOS/Worklink','--qa-transfer'],capture_output=True,text=True,env=native_env,timeout=30)
                assert native.stdout.strip(), dict(native_exit=native.returncode,native_error=native.stderr[-4000:])
                result = json.loads(native.stdout.strip().splitlines()[-1])
                assert result['path_replaced'] == (not preserve), result
                assert result['original_preserved'] == preserve, result
                assert result['manual_path_copied'] and result['original_restored'] and result['restore_no_reupload'] and result['scratch_removed'], result
                assert result['sha256'] == hashlib.sha256(source_png.read_bytes()).hexdigest(), result
                print(json.dumps(dict(native_app_pipeline=True, preserve_mode=preserve, original_png_sha256=True, manual_path_copy=True, original_restored=True, restore_no_reupload=True, scratch_removed=True)))
        print(json.dumps(dict(real_ssh=True, tunnel_http=True, remote_family_switch=True, native_loopback_v4_v6=True, title=True, original_sha256=True, local_original_preserved=True, queue_deleted_after_ack=True, remote_path_recopy=True, remote_original_download=True, off_shutdown=True)))
finally:
    if app and app.poll() is None:
        app.terminate();app.wait(timeout=10)
    if fixture:
        if fixture.stdin:
            fixture.stdin.close()
        try:
            fixture.wait(timeout=5)
        except subprocess.TimeoutExpired:
            fixture.terminate();fixture.wait(timeout=5)
    command("rm -rf -- " + shlex.quote(remote_dir))
