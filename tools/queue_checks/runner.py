"""One guarded native game lifecycle; only processes created here are stopped."""
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

from .report import events, read_json, verify_manifest, write_json
from . import adapters, admission, pack, worlds, coop
from .native import font_preload


LOCK = Path("/tmp/pz-queue-native-launch.lock")


def stop(process, owned_host_group=False):
    if process.poll() is not None and not owned_host_group:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass  # The child may exit between poll and kill; still reap it.
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=10)
    if owned_host_group:
        # The client may exit before a TERM-resistant CoopServer in its original group.
        deadline = time.monotonic() + 5
        while True:
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                break
            if time.monotonic() >= deadline:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                break
            time.sleep(0.1)


def _verify_initial_settings(root, selection, runtime):
    manifest = root / 'initial-settings.json'
    if manifest.is_symlink() or not manifest.is_file():
        raise ValueError('Prepared initial settings are missing or symlinked')
    expected = read_json(manifest)
    roles = adapters.roles(selection)
    required = {role + '/options.ini' for role in roles}
    if selection['kind'] == 'mp':
        name = runtime.get('server_name')
        if not isinstance(name, str) or not re.fullmatch('[A-Za-z0-9_.-]+', name) or name in ('.', '..'):
            raise ValueError('Invalid prepared server name')
        required.update('server/Server/' + name + suffix for suffix in ('.ini', '_SandboxVars.lua'))
        if coop.enabled(selection):
            required.update('client1/Server/' + name + suffix for suffix in ('.ini', '_SandboxVars.lua'))
    if not isinstance(expected, dict) or not required <= expected.keys():
        raise ValueError('Prepared initial settings are missing or invalid')
    for name, text in expected.items():
        if not isinstance(name, str) or not isinstance(text, str):
            raise ValueError('Invalid prepared initial settings entry')
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or path.as_posix() != name or not (
                name in required or selection['kind'] == 'mp' and len(path.parts) == 3 and path.parts[:2] in (
                    [('server', 'Server'), ('client1', 'Server')] if coop.enabled(selection) else [('server', 'Server')])):
            raise ValueError('Prepared initial settings path escapes owned settings: ' + name)
        if any((root / Path(*path.parts[:index])).is_symlink() for index in range(1, len(path.parts) + 1)):
            raise ValueError('Prepared initial settings cannot contain symlinks: ' + name)
        if not (root / path).is_file() or (root / path).read_bytes() != text.encode('utf-8'):
            raise ValueError('Prepared initial settings changed before launch: ' + name)


def _verify_live_inputs(root, selection, runtime):
    _verify_initial_settings(root, selection, runtime)
    locked = selection.get('options', {}).get('pack_lock')
    if locked:
        pack.validate(locked, runtime['project'], runtime['game'], selection['mods'])
    template = selection.get('options', {}).get('world_template')
    if template:
        _path, state = worlds.validate(template, selection, Path(runtime['game']))
        if worlds._state(root, adapters.roles(selection)) != state['files']:
            raise ValueError('Restored world changed before its first launch; prepare a fresh copy')
    return {'pack_lock': bool(locked), 'world_template': bool(template)}


def run(root, resource_wait=300):
    if sys.platform == 'win32':
        from .windows import run as run_windows
        return run_windows(root, resource_wait)
    if sys.platform != "darwin":
        raise ValueError("Native GUI launch currently supports macOS; reports/matrix work on any platform")
    root = Path(root).resolve()
    selection, runtime = read_json(root / "selection.json"), read_json(root / "runtime.json")
    hosted = coop.enabled(selection)
    adapter = adapters.get(selection['suite'])
    changed = verify_manifest(root, "source-manifest.json", True) + verify_manifest(root, "snapshot-hashes.json")
    if changed:
        raise ValueError("\n".join(changed))
    if list(root.glob("*-launch.log")) or (root / "execution.json").exists():
        raise ValueError("Run directory has already launched; prepare a fresh snapshot")
    if adapter:
        adapter.validate(selection)
    _verify_live_inputs(root, selection, runtime)
    with admission.acquire(root, selection, runtime, resource_wait, legacy_lock=LOCK) as resources:
        changed = verify_manifest(root, 'source-manifest.json', True) + verify_manifest(root, 'snapshot-hashes.json')
        if changed:
            raise ValueError('Inputs changed while waiting for resources:\n' + '\n'.join(changed))
        input_guards = _verify_live_inputs(root, selection, runtime)
        processes, streams, displayed = {}, [], set()
        execution = {"status": "running", "processes": {}, "peer_disconnected": False, 'attachments': [],
                     'resources': resources, 'input_guards': input_guards}
        game = Path(runtime["game"])
        base = [runtime["java"], "-Djava.awt.headless=true", "--enable-native-access=ALL-UNNAMED",
                "--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED", "-Dzomboid.steam=0",
                "-Djava.library.path=.", "-Xmx" + str(resources["budget"]["heap_mib"]) + "m", "-XX:+UseZGC", "-XX:-OmitStackTraceInFastThrow"]

        def text(role):
            if hosted and role == 'server':
                coop.mirror_logs(root)
            path = root / (role + "-launch.log")
            return path.read_text(errors="replace") if path.is_file() else ""

        def launch(role):
            config = runtime["roles"][role]
            cache = Path(config["cache"])
            if not re.search(r"^voiceEnable=false$", (cache / "options.ini").read_text(), re.M):
                raise ValueError("VOIP must be disabled before launch: " + role)
            if hosted and role == 'client1' and not re.search(r'^VoiceEnable=false$',
                    (cache / 'Server' / (runtime['server_name'] + '.ini')).read_text(), re.M):
                raise ValueError('Host server VOIP must be disabled')
            loader = []
            if "ZombieBuddy" in selection["mods"]:
                loader = ["-javaagent:" + str(game / "ZombieBuddy.jar") + "=config_dir=" + str(cache / "zombie-buddy") + ",policy=deny-new,verbosity=1" + (font_preload(cache, selection) if role != "server" else "")]
            if role == "server":
                settings = (cache / "Server" / (runtime["server_name"] + ".ini")).read_text()
                if not re.search(r"^VoiceEnable=false$", settings, re.M):
                    raise ValueError("Server VOIP must be disabled")
                arguments = ["-cp", "projectzomboid.jar", "zombie.network.GameServer", "-servername", runtime["server_name"], "-adminpassword", "smoke-local-only"]
            else:
                arguments = ["-XstartOnFirstThread", "-cp", str(config["classes"]) + os.pathsep + "projectzomboid.jar", "ToolkitSmokeLauncher"]
            command = base + loader + arguments + ["-nosteam", "-novoip", "-cachedir=" + str(cache)]
            if hosted and role == 'client1':
                command = base + ['-Dtoolkit.test.hostCache=' + str(cache)] + arguments + ["-nosteam", "-novoip", "-cachedir=" + str(cache)]
            if role != "server":
                command = ["launchctl", "asuser", str(os.getuid())] + command
            stream = (root / (role + "-launch.log")).open("w")
            streams.append(stream)
            environment = {key: value for key, value in os.environ.items() if key not in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS")}
            if hosted and role == 'client1' and loader:
                environment['JDK_JAVA_OPTIONS'] = coop.loader_options(loader[0])
            extra_env = config.get('env', {})
            allowed_env = {'PZ_CART_RUNTIME_FILE', 'PZ_CART_COMMAND_FILE', 'PZ_CART_TEST_PAD'}
            if selection['suite'] == 'basement-hall' and selection['kind'] == 'sp' and role == 'client1':
                allowed_env.add('PZ_BASEMENT_HALL_CACHE')
            if (set(extra_env) - allowed_env
                    or any(not isinstance(value, str) or not Path(value).is_absolute()
                           for name, value in extra_env.items() if name != 'PZ_CART_TEST_PAD')
                    or 'PZ_CART_TEST_PAD' in extra_env and extra_env['PZ_CART_TEST_PAD'] not in ('true', 'false')
                    or 'PZ_BASEMENT_HALL_CACHE' in extra_env and extra_env['PZ_BASEMENT_HALL_CACHE'] != str(cache)):
                raise ValueError('Invalid fixture-owned client environment')
            environment.update(extra_env)
            process = subprocess.Popen(command, cwd=game, env=environment, stdout=stream, stderr=subprocess.STDOUT, stdin=subprocess.PIPE, text=True, start_new_session=True)
            processes[role] = process
            execution["processes"][role] = {"pid": process.pid}
            print(role + " PID " + str(process.pid), flush=True)

        attached = {}
        def probe(role, spec, argument):
            process = processes[role]
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before probe attachment: ' + role)
            # Attachment always targets this invocation's Popen object, never a discovered/read PID.
            with (root / (role + '-probes.log')).open('a') as log:
                subprocess.run([runtime['java'], '--enable-native-access=ALL-UNNAMED', '-cp', spec['classpath'],
                                spec.get('class', 'AttachWoodenWheelProbe'), str(process.pid), spec['jar'], argument],
                               check=True, stdout=log, stderr=subprocess.STDOUT, timeout=20,
                               env={key: value for key, value in os.environ.items() if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')})

        cleaning = False
        def interrupted(signum, frame):
            message = "Native run interrupted by signal " + str(signum)
            execution.update(status='failed', interrupted=True)
            if not cleaning:
                raise KeyboardInterrupt(message)
            execution['error'] = '; '.join(filter(None, (execution.get('error'), message)))

        previous = {}
        guard = None
        cleaning = False
        try:
            for sig in (signal.SIGINT, signal.SIGTERM):
                previous[sig] = signal.getsignal(sig)
                signal.signal(sig, interrupted)
            guard = subprocess.Popen(["/usr/bin/caffeinate", "-diu", "-w", str(os.getpid())])
            if selection["kind"] == "mp":
                launch('client1' if hosted else 'server')
                deadline = time.monotonic() + (180 if hosted else 120)
                while (runtime.get('fixture', {}).get('server_ready', '[QUEUE_TEST] SERVER_READY') not in text("server")
                       or hosted and '[QUEUE_TEST] HOST_CHILD ' not in text('client1')):
                    if processes['client1' if hosted else 'server'].poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("Server readiness failed")
                    time.sleep(1)
                if hosted:
                    execution['processes']['server'] = {'pid': coop.child(text('client1'), processes['client1'].pid),
                                                        'parent_role': 'client1', 'cache': str(root / 'client1')}
            clients = adapters.roles(selection, False)
            for index, role in enumerate(clients):
                if index:
                    time.sleep(runtime.get('fixture', {}).get('client_launch_stagger_seconds', 0))
                if role not in processes:
                    launch(role)
            deadline = time.monotonic() + selection["timeout_seconds"]
            while time.monotonic() < deadline:
                current = {role: text(role) for role in adapters.roles(selection)}
                # A writer may be halfway through its final JSON line; final audit remains strict.
                records = {role: events(current[role] if current[role].endswith("\n") else current[role].rsplit("\n", 1)[0] if "\n" in current[role] else "") for role in clients}
                for role in clients:
                    for event in records[role]:
                        key = (role, str(event))
                        if key not in displayed:
                            displayed.add(key)
                            print(role + " " + str(event), flush=True)
                failure_markers = ['[QUEUE_TEST] FAIL ', *runtime.get('fixture', {}).get('failure_markers', [])]
                if any(marker in value for value in current.values() for marker in failure_markers):
                    raise RuntimeError("Native fixture failed; see complete log audit")
                for role, specs in runtime.get('fixture', {}).get('attach', {}).items():
                    if role not in clients:
                        raise RuntimeError('Probe target is not an owned client: ' + role)
                    if role in attached or not all(spec['ready'] in current[role] for spec in specs):
                        continue
                    attached[role] = []
                    for spec in specs:
                        probe(role, spec, spec['output'])
                        attached[role].append(spec)
                        execution['attachments'].append({'role': role, 'jar': spec['jar']})
                    (root / role / 'Lua/queue-probes-ready.txt').write_text('ready\n')
                if "client2" in current and "PATIENT_DISCONNECT_REQUEST patient=client1 doctor=client2" in current["client2"] and not execution["peer_disconnected"]:
                    completed = [event for event in records["client1"] if event["event"] == "complete"]
                    actual = [event.get("id") for event in records["client1"] if event["event"] == "case"]
                    if len(completed) != 1 or completed[0].get("failed") != 0 or actual != selection["cases"]:
                        raise RuntimeError("Patient may disconnect only after completing its doctor checks")
                    stop(processes["client1"])
                    execution["peer_disconnected"] = True
                finished = all(adapter.complete(selection, role, current[role]) if adapter else any(event["event"] == "complete" for event in records[role]) for role in clients)
                if runtime.get('fixture', {}).get('manual') and all(process.poll() == 0 for process in processes.values()):
                    execution.update(status='completed', manual=True)
                    break
                if finished:
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
            execution.update(status="failed", error=str(error), interrupted=isinstance(error, KeyboardInterrupt))
        finally:
            # Cleanup signals record failure without interrupting bounded waits or losing the report.
            cleaning = True
            try:
                for role, specs in attached.items():
                    for spec in specs:
                        if processes[role].poll() is None:
                            try:
                                probe(role, spec, 'stop')
                            except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                                execution.update(status='failed', error='Probe close failed: ' + str(error))
                for role, process in reversed(list(processes.items())):
                    if role == 'server' and process.poll() is None:
                        try:
                            process.stdin.write('save\nquit\n'); process.stdin.flush()
                            process.wait(timeout=30)
                        except (AttributeError, BrokenPipeError, OSError, subprocess.TimeoutExpired):
                            pass
                    try:
                        stop(process, owned_host_group=hosted and role == 'client1')
                    except (OSError, subprocess.SubprocessError) as error:
                        execution.setdefault('cleanup_errors', []).append(role + ': ' + str(error))
                    execution["processes"][role]["exit_code"] = process.returncode
                for stream in streams:
                    try:
                        stream.close()
                    except OSError as error:
                        execution.setdefault('cleanup_errors', []).append('launch log: ' + str(error))
                if hosted:
                    try:
                        coop.mirror_logs(root)
                        remaining = admission.owned({'caches': [str(root / 'client1')]}, admission.host.sample())
                        execution['host_cleanup'] = {'remaining_pids': [row['pid'] for row in remaining]}
                        if remaining:
                            execution.setdefault('cleanup_errors', []).append('Owned Host processes survived group cleanup')
                    except OSError as error:
                        execution.setdefault('cleanup_errors', []).append('Host log capture: ' + str(error))
                    except RuntimeError as error:
                        execution.setdefault('cleanup_errors', []).append('Host cleanup audit: ' + str(error))
                if guard is not None:
                    try:
                        guard.terminate(); guard.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        try:
                            guard.kill(); guard.wait(timeout=5)
                        except (OSError, subprocess.SubprocessError) as error:
                            execution.setdefault('cleanup_errors', []).append('display guard: ' + str(error))
                    except (OSError, subprocess.SubprocessError) as error:
                        execution.setdefault('cleanup_errors', []).append('display guard: ' + str(error))
                if execution.get('cleanup_errors'):
                    execution.update(status='failed', error='; '.join([execution.get('error', ''), *execution['cleanup_errors']]))
                write_json(root / "execution.json", execution)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
        return execution
