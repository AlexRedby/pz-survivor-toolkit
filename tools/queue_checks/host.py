"""Host admission estimates; ps CPU values are averages, not fresh interval samples."""
import math
import os
from pathlib import Path
import re
import subprocess
import sys


GAME_ARGUMENT = re.compile(
    r'(?:^|\s)(?:ToolkitSmokeLauncher|ToolkitVideoLauncher|zombie\.network\.GameServer|zombie\.gameStates\.MainScreenState)(?=$|\s)'
    r'|(?:^|[/\s:\"\'])projectzomboid\.jar(?=$|[\s:\"\'])'
)


def parse_vm_stat(text):
    """Estimate reclaimable bytes without counting overlapping purgeable pages twice."""
    page = re.search(r'page size of (\d+) bytes', text)
    if not page or int(page[1]) <= 0:
        raise ValueError('vm_stat has no valid page size')
    counts = []
    for name in ('free', 'inactive', 'speculative'):
        match = re.search(r'^Pages ' + name + r':\s+(\d+)\.\s*$', text, re.M)
        if not match:
            raise ValueError('vm_stat has no valid Pages ' + name)
        counts.append(int(match[1]))
    return int(page[1]) * sum(counts)


def parse_processes(stats, commands):
    """Join ps args/stats to executable names, avoiding shell-text game matches."""
    executables = {}
    for line in commands.splitlines():
        if not line.strip():
            continue
        fields = line.split(None, 1)
        if len(fields) != 2 or not fields[0].isdigit() or int(fields[0]) <= 0:
            raise ValueError('Invalid ps executable inventory: ' + line)
        pid = int(fields[0])
        if pid in executables:
            raise ValueError('Duplicate ps executable PID: ' + str(pid))
        executables[pid] = fields[1]
    if not executables:
        raise ValueError('ps returned no executable inventory')
    processes, seen = [], set()
    for line in stats.splitlines():
        if not line.strip():
            continue
        fields = line.split(None, 3)
        if len(fields) < 3:
            raise ValueError('Invalid ps process statistics: ' + line)
        try:
            pid, rss, cpu = int(fields[0]), int(fields[1]), float(fields[2]) / 100
        except ValueError as error:
            raise ValueError('Invalid ps process statistics: ' + line) from error
        if pid <= 0 or rss < 0 or not math.isfinite(cpu) or cpu < 0 or pid in seen:
            raise ValueError('Invalid ps process statistics: ' + line)
        seen.add(pid)
        command = fields[3] if len(fields) == 4 else ''
        executable = executables.get(pid, '')
        name = Path(executable).name
        game = name in ('java', 'javaw', 'launchctl') and bool(GAME_ARGUMENT.search(command))
        game = game or name == 'JavaAppLauncher' and 'Project Zomboid.app/' in executable
        processes.append({'pid': pid, 'rss': rss * 1024, 'cpu': cpu, 'command': command, 'game': game})
    if not processes:
        raise ValueError('ps returned no process statistics')
    return processes


def _output(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.PIPE,
                                   env=dict(os.environ, LC_ALL='C'), timeout=10)


def sample():
    """Return current memory and process estimates, or fail closed with a diagnostic."""
    try:
        if sys.platform == 'darwin':
            values = _output(['/usr/sbin/sysctl', '-n', 'hw.memsize', 'hw.logicalcpu']).split()
            if len(values) != 2:
                raise ValueError('sysctl must return physical memory and logical CPU count')
            total, cpus = map(int, values)
            available = parse_vm_stat(_output(['/usr/bin/vm_stat']))
        elif sys.platform.startswith('linux'):
            memory = Path('/proc/meminfo').read_text()
            values = {}
            for name in ('MemTotal', 'MemAvailable'):
                match = re.search(r'^' + name + r':\s+(\d+) kB\s*$', memory, re.M)
                if not match:
                    raise ValueError('/proc/meminfo has no valid ' + name)
                values[name] = int(match[1]) * 1024
            total, available = values['MemTotal'], values['MemAvailable']
            cpus = len(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else os.cpu_count()
        else:
            raise ValueError('unsupported platform: ' + sys.platform)
        if total <= 0 or cpus is None or cpus <= 0 or available < 0:
            raise ValueError('invalid host memory or CPU capacity')
        stats = _output(['/bin/ps', '-axo', 'pid=,rss=,pcpu=,args='])
        commands = _output(['/bin/ps', '-axo', 'pid=,comm='])
        return {'total_memory': total, 'available_memory': min(total, available),
                'cpu_count': cpus, 'processes': parse_processes(stats, commands)}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise RuntimeError('Cannot sample host resources: ' + str(error)) from error
