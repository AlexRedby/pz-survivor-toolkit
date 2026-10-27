"""The real CoopServer shares its owner's cache; keep its evidence separate."""
from pathlib import Path
import re
import shutil
import time


def enabled(selection):
    options = selection.get('options', {})
    if not isinstance(options, dict):
        raise ValueError('Suite options must be an object')
    value = options.get('mp_host', False)
    if type(value) is not bool or value and selection.get('kind') != 'mp':
        raise ValueError('mp_host must be boolean and requires MP')
    if value and any(selection.get('options', {}).get(key) for key in ('seed_run', 'startup_connection')):
        raise ValueError('Host requires sealed world templates and the fixture client identities')
    return value


def stage(root, runtime):
    cache = Path(root) / 'client1'
    shutil.copytree(Path(root) / 'server/Server', cache / 'Server')
    runtime['host_cache'] = str(cache)


def loader_options(agent):
    # JDK_JAVA_OPTIONS is parsed again by Host's child JVM, including paths with spaces.
    if any(char in agent for char in ('"', '\n', '\r')):
        raise ValueError('Host loader options cannot contain quotes or newlines')
    return '"' + agent + '" --enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED'


def mirror_logs(root):
    root = Path(root)
    cache = root / 'client1'
    console = cache / 'coop-console.txt'
    if console.is_file():
        shutil.copyfile(console, root / 'server-launch.log')
    for path in (cache / 'Logs').rglob('*DebugLog-server.txt'):
        target = root / 'server/Logs' / path.relative_to(cache / 'Logs')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


def child(text, parent):
    matches = re.findall(r'\[QUEUE_TEST\] HOST_CHILD pid=(\d+) parent=(\d+)(?:\s|$)', text)
    if len(matches) != 1 or int(matches[0][1]) != parent or int(matches[0][0]) <= 0 or int(matches[0][0]) == parent:
        raise RuntimeError('Host did not prove one native child of the owned client')
    return int(matches[0][0])


def save_host(process, child_pid, read_text, timeout=35):
    """Ask the existing owner launcher to save/quit its proven native CoopMaster child."""
    if type(child_pid) is not int or child_pid <= 0 or child_pid == process.pid or process.poll() is not None:
        raise RuntimeError('Host save requires its live owner and proven child PID')
    try:
        process.stdin.write('QUEUE_HOST_SAVE_QUIT\n')
        process.stdin.flush()
    except (AttributeError, BrokenPipeError, OSError) as error:
        raise RuntimeError('Host save request failed: ' + str(error)) from error
    deadline = time.monotonic() + timeout
    while True:
        text = read_text()
        if '[QUEUE_TEST] FAIL host save' in text:
            raise RuntimeError('Host launcher refused or failed its save/quit request')
        matches = re.findall(r'\[QUEUE_TEST\] HOST_SAVED_EXIT pid=(\d+) exit=(-?\d+)(?:\s|$)', text)
        if matches:
            if len(matches) != 1 or int(matches[0][0]) != child_pid or int(matches[0][1]) != 0:
                raise RuntimeError('Host save did not prove its original child exited successfully')
            return {'pid': child_pid, 'exit_code': 0}
        if process.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError('Host save/quit acknowledgement timed out or owner exited')
        time.sleep(0.1)
