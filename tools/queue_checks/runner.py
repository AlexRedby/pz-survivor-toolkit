"""One guarded native game lifecycle; only processes created here are stopped."""
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time

from .report import events, read_json, verify_manifest, write_json


LOCK = Path("/tmp/pz-queue-native-launch.lock")
GAME_PROCESS = re.compile(r"\b(?:ToolkitSmokeLauncher|zombie\.network\.GameServer|zombie\.gameStates\.MainScreenState)\b")


def stop(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass  # The child may exit between poll and kill; still reap it.
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=10)


def run(root):
    if sys.platform != "darwin":
        raise ValueError("Native GUI launch currently supports macOS; reports/matrix work on any platform")
    import fcntl
    root = Path(root).resolve()
    selection, runtime = read_json(root / "selection.json"), read_json(root / "runtime.json")
    changed = verify_manifest(root, "source-manifest.json", True) + verify_manifest(root, "snapshot-hashes.json")
    if changed:
        raise ValueError("\n".join(changed))
    if list(root.glob("*-launch.log")) or (root / "execution.json").exists():
        raise ValueError("Run directory has already launched; prepare a fresh snapshot")
    with LOCK.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Another native run holds " + str(LOCK)) from error
        process_list = subprocess.check_output(["/bin/ps", "-axo", "pid=,command="], text=True)
        collisions = [line for line in process_list.splitlines() if GAME_PROCESS.search(line)]
        if collisions:
            raise RuntimeError("Existing game process; no launch performed:\n" + "\n".join(collisions))
        if selection["kind"] == "mp":
            for port in selection["ports"]:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as check:
                    check.bind(("127.0.0.1", port))
        processes, streams, displayed = {}, [], set()
        execution = {"status": "running", "processes": {}, "peer_disconnected": False}
        game = Path(runtime["game"])
        base = [runtime["java"], "-Djava.awt.headless=true", "--enable-native-access=ALL-UNNAMED",
                "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED", "-Dzomboid.steam=0",
                "-Djava.library.path=.", "-Xmx2048m", "-XX:+UseZGC", "-XX:-OmitStackTraceInFastThrow"]

        def text(role):
            path = root / (role + "-launch.log")
            return path.read_text(errors="replace") if path.is_file() else ""

        def launch(role):
            config = runtime["roles"][role]
            cache = Path(config["cache"])
            if not re.search(r"^voiceEnable=false$", (cache / "options.ini").read_text(), re.M):
                raise ValueError("VOIP must be disabled before launch: " + role)
            loader = []
            if "ZombieBuddy" in selection["mods"]:
                loader = ["-javaagent:" + str(game / "ZombieBuddy.jar") + "=config_dir=" + str(cache / "zombie-buddy") + ",policy=deny-new,verbosity=1"]
            if role == "server":
                settings = (cache / "Server" / (runtime["server_name"] + ".ini")).read_text()
                if not re.search(r"^VoiceEnable=false$", settings, re.M):
                    raise ValueError("Server VOIP must be disabled")
                arguments = ["-cp", "projectzomboid.jar", "zombie.network.GameServer", "-servername", runtime["server_name"], "-adminpassword", "smoke-local-only"]
            else:
                arguments = ["-XstartOnFirstThread", "-cp", str(config["classes"]) + os.pathsep + "projectzomboid.jar", "ToolkitSmokeLauncher"]
            command = base + loader + arguments + ["-nosteam", "-novoip", "-cachedir=" + str(cache)]
            if role != "server":
                command = ["launchctl", "asuser", str(os.getuid())] + command
            stream = (root / (role + "-launch.log")).open("w")
            streams.append(stream)
            environment = {key: value for key, value in os.environ.items() if key not in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS")}
            process = subprocess.Popen(command, cwd=game, env=environment, stdout=stream, stderr=subprocess.STDOUT, stdin=subprocess.PIPE, text=True, start_new_session=True)
            processes[role] = process
            execution["processes"][role] = {"pid": process.pid}
            print(role + " PID " + str(process.pid), flush=True)

        def interrupted(signum, frame):
            raise KeyboardInterrupt("Native run interrupted by signal " + str(signum))

        previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
        guard = None
        try:
            guard = subprocess.Popen(["/usr/bin/caffeinate", "-diu", "-w", str(os.getpid())])
            if selection["kind"] == "mp":
                launch("server")
                deadline = time.monotonic() + 120
                while "[QUEUE_TEST] SERVER_READY" not in text("server"):
                    if processes["server"].poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("Server readiness failed")
                    time.sleep(1)
            clients = ["client1"] if selection["kind"] == "sp" else ["client1", "client2"]
            for role in clients:
                launch(role)
            deadline = time.monotonic() + selection["timeout_seconds"]
            while time.monotonic() < deadline:
                current = {role: text(role) for role in processes}
                # A writer may be halfway through its final JSON line; final audit remains strict.
                records = {role: events(current[role] if current[role].endswith("\n") else current[role].rsplit("\n", 1)[0] if "\n" in current[role] else "") for role in clients}
                for role in clients:
                    for event in records[role]:
                        key = (role, str(event))
                        if key not in displayed:
                            displayed.add(key)
                            print(role + " " + str(event), flush=True)
                if any("[QUEUE_TEST] FAIL " in value for value in current.values()):
                    raise RuntimeError("Native fixture failed; see complete log audit")
                if "client2" in current and "PATIENT_DISCONNECT_REQUEST patient=client1 doctor=client2" in current["client2"] and not execution["peer_disconnected"]:
                    completed = [event for event in records["client1"] if event["event"] == "complete"]
                    actual = [event.get("id") for event in records["client1"] if event["event"] == "case"]
                    if len(completed) != 1 or completed[0].get("failed") != 0 or actual != selection["cases"]:
                        raise RuntimeError("Patient may disconnect only after completing its doctor checks")
                    stop(processes["client1"])
                    execution["peer_disconnected"] = True
                if all(any(event["event"] == "complete" for event in records[role]) for role in clients):
                    execution["status"] = "completed"
                    break
                for role, process in processes.items():
                    if process.poll() is not None and not (role == "client1" and execution["peer_disconnected"]):
                        raise RuntimeError("Game process stopped unexpectedly: " + role)
                if guard.poll() is not None:
                    raise RuntimeError("Display guard stopped")
                time.sleep(2)
            else:
                raise RuntimeError("Bounded native run deadline expired")
        except (Exception, KeyboardInterrupt) as error:
            execution.update(status="failed", error=str(error))
        finally:
            for role, process in reversed(list(processes.items())):
                stop(process)
                execution["processes"][role]["exit_code"] = process.returncode
            for stream in streams:
                stream.close()
            if guard is not None:
                guard.terminate(); guard.wait(timeout=5)
            for sig, handler in previous.items():
                signal.signal(sig, handler)
            write_json(root / "execution.json", execution)
        return execution
