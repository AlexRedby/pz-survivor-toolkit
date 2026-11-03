"""Bounded read-only thread evidence for a stalled, runner-owned setup client."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


TIMEOUT_SECONDS = 5
MAX_OUTPUT_BYTES = 256 * 1024


def capture(root, runtime, processes, execution):
    finding = execution.get('setup_failure', {})
    if not isinstance(finding, dict):
        return
    evidence = finding.get('evidence', {})
    if not isinstance(evidence, dict) or finding.get('kind') != 'fixture-setup' or evidence.get('deadline_exceeded') is not True:
        return
    required = execution.get('preflight', {}).get('required_roles', [])
    roles = evidence.get('pending_roles') or [finding.get('role')]
    results = execution.setdefault('setup_diagnostics', {})
    for role in dict.fromkeys(roles):
        if role not in required or role not in ('client1', 'client2'):
            continue
        start = evidence.get('setup_started', {}).get(role)
        item = results[role] = dict(pause_at_setup_start=start, status='unavailable')
        try:
            process = processes.get(role)
            expected = execution.get('processes', {}).get(role, {}).get('pid')
            if (process is None or type(expected) is not int or expected <= 0
                    or process.pid != expected or process.poll() is not None):
                item['reason'] = 'Runner-owned client is no longer live'
                continue
            item['pid'] = expected
            jdk = runtime.get('jdk')
            if not isinstance(jdk, str) or not Path(jdk).is_absolute():
                item['reason'] = 'Prepared diagnostic JDK is unavailable'
                continue
            tool = Path(jdk) / 'bin' / ('jcmd.exe' if os.name == 'nt' else 'jcmd')
            if not tool.is_file():
                item['reason'] = 'Prepared JDK has no jcmd'
                continue
            target = Path(root) / (role + '-setup-threads.log')
            with tempfile.TemporaryFile() as stream:
                try:
                    result = subprocess.run([str(tool), str(expected), 'Thread.print', '-l'],
                        stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                        timeout=TIMEOUT_SECONDS, check=False)
                    item.update(status='captured' if result.returncode == 0 else 'failed', exit_code=result.returncode)
                except subprocess.TimeoutExpired:
                    item.update(status='timed-out', timeout_seconds=TIMEOUT_SECONDS)
                stream.seek(0)
                data = stream.read(MAX_OUTPUT_BYTES + 1)
            item['truncated'] = len(data) > MAX_OUTPUT_BYTES
            data = data[:MAX_OUTPUT_BYTES]
            with target.open('xb') as output:
                output.write(data)
            item.update(file=target.name, sha256=hashlib.sha256(data).hexdigest())
        except Exception as error:
            # Diagnostic failure never replaces the original setup failure.
            item.update(status='error', reason=type(error).__name__ + ': ' + str(error))
