"""Linux development lifecycle used by the root justfile. No tunnel changes."""

import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / ".run"
DEVICE = os.environ.get("DEVICE", "fenix7s")


def listener(port):
    result = subprocess.run(
        ["lsof", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"], capture_output=True, text=True
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.strip())
    pids = set(result.stdout.split())
    if len(pids) > 1:
        raise RuntimeError(f"Multiple listeners on port {port}; stop them manually.")
    return int(pids.pop()) if pids else None


def command(pid):
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().decode().split("\0")
    except FileNotFoundError:
        return []  # A process can exit between ps/lsof and this read.


def in_repo(pid):
    return Path(f"/proc/{pid}/cwd").resolve() in (ROOT, ROOT / "backend")


def node_command():
    return ["node", *(f"--env-file={path}" for path in
                      ("backend/.env", "backend/.env.local") if Path(path).is_file())]


def server_port():
    return int(subprocess.check_output(
        [*node_command(), "-p", 'process.env.PORT || "8787"'], text=True
    ).strip())


def server_pid(port):
    pid = listener(port)
    if pid and not (in_repo(pid) and any(
        arg in ("backend/scripts/dev-server.ts", "scripts/dev-server.ts",
                str(ROOT / "backend/scripts/dev-server.ts")) for arg in command(pid)
    )):
        raise RuntimeError(f"Port {port} belongs to another service (PID {pid}); refusing to touch it.")
    return pid


def launch(args, log):
    RUN.mkdir(exist_ok=True)
    with (RUN / log).open("a") as output:
        return subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=output,
                                stderr=subprocess.STDOUT, start_new_session=True)


def server_start():
    port = server_port()
    if server_pid(port):
        print(f"Server already running on port {port}.")
        return
    process = launch([*node_command(), "backend/scripts/dev-server.ts"], "server.log")
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError("Server exited; see .run/server.log.")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1):
                print(f"Server ready on port {port} (PID {process.pid}).")
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("Server did not become healthy; see .run/server.log.")


def server_stop():
    port = server_port()
    pid = server_pid(port)
    if pid:
        os.kill(pid, signal.SIGTERM)
        for _ in range(100):
            if listener(port) != pid:
                print("Server stopped. Existing photo sessions have expired.")
                return
            time.sleep(0.1)
        raise RuntimeError(f"Server PID {pid} did not stop; no force-kill attempted.")
    print("Server is not running.")


def app_pids():
    result = subprocess.check_output(["ps", "-eo", "pid=,args="], text=True)
    pids = []
    for line in result.splitlines():
        pid, args = line.strip().split(maxsplit=1)
        if ("com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux" in args
                and in_repo(int(pid))
                and "com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux" in command(int(pid))):
            pids.append(int(pid))
    return pids


def app_start():
    if app_pids():
        print("Watch app launcher already running; use just app-restart to rebuild/reload.")
        return
    key = os.environ.get("GARMIN_KEY", str(Path.home() / ".Garmin/ConnectIQ/developer_key.der"))
    resources = RUN / "watch-resources"
    resources.mkdir(parents=True, exist_ok=True)
    config = subprocess.check_output([
        *node_command(), "-p", 'JSON.stringify({backendUrl: process.env.PUBLIC_BASE_URL || "", mockWalk: process.env.MOCK_WALK !== "0"})'
    ], text=True)
    (resources / "local-config.json").write_text(json.dumps(json.loads(config)))
    (resources / "resources.xml").write_text(
        '<resources><jsonData id="localConfig" filename="local-config.json"/></resources>\n'
    )
    (RUN / "local.jungle").write_text('base.resourcePath = $(base.resourcePath);watch-resources\n')
    output = ".run/touch-grass.prg"
    subprocess.run(["monkeyc", "-f", "touch-grass/monkey.jungle;.run/local.jungle", "-d", DEVICE,
                    "-o", output, "-y", key], check=True)
    if not listener(1234):
        process = launch(["connectiq"], "simulator.log")
        for _ in range(150):
            if listener(1234):
                break
            if process.poll() is not None:
                raise RuntimeError("Simulator exited; see .run/simulator.log.")
            time.sleep(0.2)
        else:
            raise RuntimeError("Simulator did not open port 1234; see .run/simulator.log.")
    process = launch(["monkeydo", output, DEVICE], "app.log")
    time.sleep(1)
    if process.poll() is not None:
        raise RuntimeError("App launcher exited; see .run/app.log.")
    print(f"Loading {DEVICE} app (PID {process.pid}); watch the simulator. Logs: .run/app.log")


def app_stop():
    pids = app_pids()
    if not pids:
        print("No watch app launcher from this repository is running.")
        return
    sdk = (Path.home() / ".Garmin/ConnectIQ/current-sdk.cfg").read_text().strip()
    application = ET.parse(ROOT / "touch-grass/manifest.xml").getroot()[0]
    app_id = application.attrib["id"].replace("-", "")
    # SDK 9.3's DeviceChannel.closeApp command, not a simulator/window kill.
    process = subprocess.Popen([str(Path(sdk) / "bin/shell")], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        process.stdin.write(f"ciq\n[2][0]closeApp {app_id}\n".encode())
        process.stdin.flush()
        received = b""
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if select.select([process.stdout], [], [], 0.2)[0]:
                chunk = os.read(process.stdout.fileno(), 4096)
                if not chunk:
                    break
                received += chunk
                if f"appTerminated {app_id}".upper().encode() in received.upper():
                    for _ in range(50):
                        if not app_pids():
                            print("Watch app stopped; simulator and saved settings retained.")
                            return
                        time.sleep(0.1)
                    raise RuntimeError("App stopped, but its launcher has not exited yet.")
        raise RuntimeError("Simulator did not confirm app termination; no process was force-killed.")
    finally:
        process.terminate()
        process.wait(timeout=5)


def status():
    port = server_port()
    pid = server_pid(port)
    print(f"Server: {'PID ' + str(pid) if pid else 'stopped'} (port {port})")
    print(f"Watch app launcher: {app_pids() or 'stopped'}")
    print(f"Simulator: {'listening' if listener(1234) else 'stopped'} (port 1234)")


if __name__ == "__main__":
    os.chdir(ROOT)
    actions = {"server-start": server_start, "server-stop": server_stop,
               "app-start": app_start, "app-stop": app_stop, "status": status}
    try:
        actions[sys.argv[1]]()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
