"""Read-only NVIDIA sampler fixtures: fake executables, no GPU/driver required."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parent / 'optimizer_trial' / 'TrialNvidia.ps1'
PWSH = shutil.which('pwsh')
FIELDS = ('timestamp,index,name,driver_version,pstate,temperature.gpu,utilization.gpu [%],'
          'utilization.memory [%],memory.used [MiB],memory.total [MiB],'
          'clocks.current.graphics [MHz],clocks.current.memory [MHz],power.draw [W]')
CSV = FIELDS + '\n2026/10/26 10:00:00.000,0,Fixture GPU,555,P2,65,90 %,25 %,1000 MiB,8000 MiB,1500 MHz,7000 MHz,100 W\n'


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class NvidiaSamplerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz-nvidia-')
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def tool(self, body):
        path = self.root / 'fake-nvidia-smi'
        path.write_text('#!' + sys.executable + '\n' + body + '\n')
        path.chmod(0o700)
        return path

    def invoke(self, tool=None, command=None):
        env = dict(os.environ, PZ_NVIDIA_SCRIPT=str(SCRIPT), PZ_NVIDIA_TOOL=str(tool or ''), PZ_NVIDIA_PIDFILE=str(self.root / 'pid'))
        body = command or '$r = Read-TrialNvidiaSample $env:PZ_NVIDIA_TOOL; $r | ConvertTo-Json -Depth 6 -Compress'
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-Command', '. $env:PZ_NVIDIA_SCRIPT; ' + body],
                                env=env, text=True, capture_output=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def test_success_keeps_raw_headers_units_and_uses_only_query_flags(self):
        tool = self.tool('import sys\nassert len(sys.argv) == 3\nassert sys.argv[1].startswith("--query-gpu=timestamp,index,name,")\nassert sys.argv[2] == "--format=csv"\nassert not any(x in sys.argv[1] for x in ("serial", "uuid", "hostname"))\nprint(' + repr(CSV) + ', end="")')
        sample = self.invoke(tool)
        self.assertEqual(sample['status'], 'Available')
        self.assertEqual(sample['csv'], CSV)
        self.assertEqual(sample['unavailableFields'], [])
        self.assertEqual(sample['exitCode'], 0)

    def test_device_unsupported_values_remain_unavailable_in_raw_csv(self):
        csv = CSV.replace('100 W', 'N/A').replace('7000 MHz', '[Not Supported]')
        sample = self.invoke(self.tool('print(' + repr(csv) + ', end="")'))
        self.assertEqual(sample['status'], 'Available')
        self.assertEqual(sample['csv'], csv)
        self.assertEqual(set(sample['unavailableFields']), {'clocks.current.memory [MHz]', 'power.draw [W]'})

    def test_absent_tool_and_query_error_are_optional_unavailable(self):
        sample = self.invoke()
        self.assertEqual(sample['status'], 'Unavailable')
        self.assertEqual(sample['unavailableReason'], 'ToolMissing')
        tool = self.tool('import sys\nprint("unsupported field", file=sys.stderr)\nsys.exit(2)')
        sample = self.invoke(tool)
        self.assertEqual(sample['status'], 'Unavailable')
        self.assertEqual(sample['unavailableReason'], 'QueryFailed')
        self.assertEqual(sample['exitCode'], 2)
        self.assertIsNone(sample['csv'])

    def test_full_stderr_is_drained_without_deadlock(self):
        tool = self.tool('import sys\nsys.stderr.write("x" * 300000)\nprint(' + repr(CSV) + ', end="")')
        self.assertEqual(self.invoke(tool)['status'], 'Available')

    def test_timeout_is_bounded_and_kills_only_owned_tool(self):
        tool = self.tool('import os,time\nfrom pathlib import Path\nPath(os.environ["PZ_NVIDIA_PIDFILE"]).write_text(str(os.getpid()))\ntime.sleep(20)')
        sample = self.invoke(tool)
        self.assertEqual(sample['status'], 'Unavailable')
        self.assertEqual(sample['unavailableReason'], 'Timeout')
        self.assertLess(sample['elapsedMs'], 2200)
        self.assertGreaterEqual(sample['elapsedMs'], 1500)
        pid = int((self.root / 'pid').read_text())
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(.05)
        else:
            self.fail('Owned timed-out sampler process survived')

    def test_empty_invalid_and_unstartable_tool_do_not_raise(self):
        for body, reason in (('pass', 'EmptyOutput'), ('print("not csv")', 'InvalidOutput')):
            self.assertEqual(self.invoke(self.tool(body))['unavailableReason'], reason)
        path = self.root / 'not-executable'
        path.write_text('fixture')
        self.assertEqual(self.invoke(path)['status'], 'Unavailable')

    def test_discovery_prefers_command_and_import_has_no_side_effects(self):
        tool = self.tool('raise RuntimeError("must not execute during discovery")')
        command = 'function Get-Command { [pscustomobject]@{Source=$env:PZ_NVIDIA_TOOL} }; @{tool=(Get-TrialNvidiaTool)} | ConvertTo-Json -Compress'
        self.assertEqual(self.invoke(tool, command)['tool'], str(tool))
        command = 'function Get-Command { }; $env:SystemRoot=""; $env:WINDIR=""; $env:ProgramW6432=""; $env:ProgramFiles=""; @{tool=(Get-TrialNvidiaTool)} | ConvertTo-Json -Compress'
        self.assertIsNone(self.invoke(command=command)['tool'])


if __name__ == '__main__':
    unittest.main()
