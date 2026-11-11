"""Bounded native main/Cocoa stack evidence for one owned client, without raw reports."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

TIMEOUT_SECONDS = 4
MAX_REPORT_BYTES = 2 * 1024 * 1024
MAX_THREADS = 8
MAX_FRAMES = 256
_SYMBOL = re.compile(r'[A-Za-z_?~+\-][A-Za-z0-9_?~:$<>.,+\-*\[\] ()=&|]{0,255}\Z')
_IMAGE = re.compile(r'[A-Za-z0-9_.+\-]{1,128}\Z')
_FRAME = re.compile(r'^(\s*[+!:| ]*)\s*(\d+)\s+(.+?)\s+\(in ([^)]+)\)(?:\s.*)?$')


def _empty(pid, status, reason):
    return {'pid': pid, 'status': status, 'reason': reason, 'threads': []}


def _valid_pid(pid):
    return type(pid) is int and 0 < pid <= 2147483647


def parse(text, pid):
    """Discard process headers, arguments, thread names, images and source paths."""
    identity = re.search(r'^Process:.*\[(\d+)\]\s*$', text, re.MULTILINE)
    if not identity or int(identity[1]) != pid or '\nCall graph:\n' not in text:
        return _empty(pid, 'error', 'invalid-report-identity')
    blocks, current = [], None
    graph = text.split('\nCall graph:\n', 1)[1]
    for line in graph.splitlines():
        if line.startswith(('Total number in stack', 'Binary Images:')):
            break
        if re.match(r'^\s+\d+\s+Thread_\d+\b', line):
            current = {'kind': 'main' if 'com.apple.main-thread' in line else 'other',
                       'frames': [], 'limited': False}
            blocks.append(current)
            continue
        match = _FRAME.match(line)
        if not current or not match:
            continue
        symbol, image = match[3], match[4]
        if not _SYMBOL.fullmatch(symbol) or not _IMAGE.fullmatch(image):
            continue
        if current['kind'] == 'other' and symbol.startswith((
                '-[NSApplication ', 'NSApplicationMain', '_DPSNextEvent', '__CFRunLoopRun')):
            current['kind'] = 'cocoa'
        if len(current['frames']) >= MAX_FRAMES:
            current['limited'] = True
            continue
        current['frames'].append({'samples': min(int(match[2]), 10**9),
                                  'depth': min(len(match[1]), 8192),
                                  'symbol': symbol, 'image': image})
    threads = [block for block in blocks if block['kind'] != 'other' and block['frames']]
    if not threads:
        return _empty(pid, 'unavailable', 'window-thread-not-found')
    return {'pid': pid, 'status': 'limited' if len(threads) > MAX_THREADS else 'returned',
            'reason': 'sampled', 'threads': threads[:MAX_THREADS]}


def capture(pid):
    """Sample a numeric owned PID; diagnostic failure never affects client cleanup."""
    if not _valid_pid(pid):
        return _empty(None, 'error', 'invalid-pid')
    if sys.platform != 'darwin':
        return _empty(pid, 'unavailable', 'not-macos')
    try:
        with tempfile.TemporaryDirectory(prefix='pz-owned-stack-') as directory:
            output = Path(directory) / 'sample.txt'
            completed = subprocess.run(
                [sys.executable, '-I', str(Path(__file__).resolve()), '--worker', str(pid), str(output)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=TIMEOUT_SECONDS, check=False)
            if completed.returncode:
                return _empty(pid, 'unavailable', 'sampler-exited')
            with output.open('rb') as stream:
                raw = stream.read(MAX_REPORT_BYTES + 1)
            if len(raw) > MAX_REPORT_BYTES:
                return _empty(pid, 'error', 'report-limit')
            return parse(raw.decode('utf-8', errors='replace'), pid)
    except subprocess.TimeoutExpired:
        return _empty(pid, 'timeout', 'sampler-timeout')
    except (OSError, subprocess.SubprocessError):
        return _empty(pid, 'unavailable', 'sampler-unavailable')
    except (ValueError, TypeError, OverflowError):
        return _empty(pid, 'error', 'invalid-report')


def _main():
    if len(sys.argv) != 4 or sys.argv[1] != '--worker':
        return 2
    try:
        import resource
        pid = int(sys.argv[2])
        if not _valid_pid(pid) or sys.platform != 'darwin':
            return 2
        resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_REPORT_BYTES, MAX_REPORT_BYTES))
        # exec keeps the sampler inside the parent's timeout; it cannot orphan a helper.
        os.execv('/usr/bin/sample', ['sample', str(pid), '1', '10', '-mayDie', '-file', sys.argv[3]])
    except (OSError, ValueError):
        return 2


if __name__ == '__main__':
    raise SystemExit(_main())
