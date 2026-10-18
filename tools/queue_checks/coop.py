"""The real CoopServer shares its owner's cache; keep its evidence separate."""
from pathlib import Path
import re
import shutil


def enabled(selection):
    options = selection.get('options', {})
    if not isinstance(options, dict):
        raise ValueError('Suite options must be an object')
    value = options.get('mp_host', False)
    if type(value) is not bool or value and selection.get('kind') != 'mp':
        raise ValueError('mp_host must be boolean and requires MP')
    if value and any(selection.get('options', {}).get(key) for key in ('world_template', 'seed_run', 'startup_connection')):
        raise ValueError('Host requires a fresh world and the fixture client identities')
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
