"""Offline real-pipe tests. The fake GameServer never uses the game's classpath."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SUPPORT = ROOT / 'tests/native_queue/support'


def clean_environment():
    return {key: value for key, value in os.environ.items()
            if key not in ('JDK_JAVA_OPTIONS', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS')}


def jdk25():
    configured = os.environ.get('PZ_JDK')
    candidates = []
    for value in (configured, os.environ.get('JAVA_HOME')):
        if value:
            binary = Path(value) / 'bin'
            candidates.append((binary / 'javac', binary / 'java'))
    if not configured:
        javac, java = shutil.which('javac'), shutil.which('java')
        if javac and java:
            candidates.append((Path(javac), Path(java)))
        if sys.platform == 'darwin' and Path('/usr/libexec/java_home').is_file():
            result = subprocess.run(['/usr/libexec/java_home', '-v', '25'], capture_output=True, text=True,
                                    timeout=10, env=clean_environment())
            if result.returncode == 0:
                binary = Path(result.stdout.strip()) / 'bin'
                candidates.append((binary / 'javac', binary / 'java'))
    for javac, java in candidates:
        try:
            result = subprocess.run([str(javac), '-version'], capture_output=True, text=True,
                                    timeout=10, env=clean_environment())
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and re.search(r'\bjavac 25(?:\D|$)', result.stdout + result.stderr) and java.is_file():
            return javac, java
    if configured:
        raise RuntimeError('PZ_JDK must identify an available JDK 25 compiler and runtime')
    raise unittest.SkipTest('JDK 25 unavailable; set PZ_JDK to run the offline Host child diagnostics checks')


class HostChildDiagnosticsTests(unittest.TestCase):
    def test_owned_pipe_capture_and_incomplete_observation_receipts(self):
        javac, java = jdk25()
        sources = [SUPPORT / 'ToolkitHostChildDiagnostics.java', SUPPORT / 'ToolkitHostChildDiagnosticsChecks.java',
                   SUPPORT / 'host-diagnostics/zombie/network/GameServer.java']
        with tempfile.TemporaryDirectory(prefix='pz-host-child-diagnostics-') as temporary:
            root = Path(temporary); classes = root / 'classes'; classes.mkdir(); evidence = root / 'evidence'; evidence.mkdir()
            compiled = subprocess.run([str(javac), '--release', '25', '-d', str(classes), *map(str, sources)],
                                      capture_output=True, text=True, timeout=30, env=clean_environment())
            self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
            checked = subprocess.run([str(java), '-cp', str(classes), 'ToolkitHostChildDiagnosticsChecks', str(evidence)],
                                     capture_output=True, text=True, timeout=45, env=clean_environment())
            self.assertEqual(0, checked.returncode, checked.stdout + checked.stderr)
            self.assertIn('PASS ToolkitHostChildDiagnosticsChecks', checked.stdout)


if __name__ == '__main__':
    unittest.main()
