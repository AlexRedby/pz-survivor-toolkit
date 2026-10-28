"""Exercise binary asynchronous trial logs with controlled streams and a real child.

No Java/game process, installed profile or native desktop is used.
"""
import base64
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROCESS = ROOT / "tests/optimizer_trial/TrialProcess.ps1"
PWSH = shutil.which("pwsh")


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


STREAMS = r"""
namespace TrialPipeChecks {
    using System;
    using System.IO;
    using System.Threading;
    public sealed class GateOutput : MemoryStream {
        public readonly ManualResetEventSlim Entered = new ManualResetEventSlim(false);
        public readonly ManualResetEventSlim Release = new ManualResetEventSlim(false);
        public override void Write(byte[] bytes, int offset, int count) {
            Entered.Set();
            if (!Release.Wait(15000)) throw new IOException("test output gate timed out");
            base.Write(bytes, offset, count);
        }
    }
    public sealed class OpenInput : MemoryStream {
        public readonly ManualResetEventSlim Finish = new ManualResetEventSlim(false);
        public OpenInput() : base(new byte[] {1, 2, 3, 4, 5}) {}
        public override int Read(byte[] bytes, int offset, int count) {
            int read = base.Read(bytes, offset, count);
            if (read != 0) return read;
            if (!Finish.Wait(15000)) throw new IOException("test input gate timed out");
            return 0;
        }
    }
    public sealed class FlushOutput : MemoryStream {
        public readonly ManualResetEventSlim Flushed = new ManualResetEventSlim(false);
        public override void Flush() {
            base.Flush();
            if (Length > 0) Flushed.Set();
        }
    }
    public sealed class BrokenOutput : MemoryStream {
        public override void Write(byte[] bytes, int offset, int count) {
            throw new IOException("injected output failure");
        }
    }
    public sealed class BrokenInput : MemoryStream {
        private bool first = true;
        public BrokenInput() : base(new byte[] {0, 255, 128, 9, 42}) {}
        public override int Read(byte[] bytes, int offset, int count) {
            if (!first) throw new IOException("injected input failure");
            first = false;
            return base.Read(bytes, offset, count);
        }
    }
    public static class WaitFor {
        public static bool InputClosed(PZTrial.BufferedLogPipe pipe) {
            return SpinWait.SpinUntil(() => pipe.Snapshot().InputClosed, 5000);
        }
    }
}
"""


@unittest.skipUnless(PWSH, "PowerShell is needed for trial process tests")
class TrialProcessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pz trial process ")
        self.base = Path(self.directory.name).resolve()
        self.addCleanup(self.directory.cleanup)

    def powershell(self, script, *, streams=False):
        source = self.base / "check.ps1"
        helper = ""
        if streams:
            # Compile together so the stream helper's strongly typed predicate
            # works even when Add-Type does not reference its earlier assembly.
            main = ROOT / "tests/optimizer_trial/TrialProcess.cs"
            helper = ("$helper=" + ps(STREAMS) + "\n"
                      "Add-Type -TypeDefinition ((Get-Content -Raw -LiteralPath "
                      + ps(main) + ") + [Environment]::NewLine + $helper)\n")
        source.write_text(
            "$ErrorActionPreference='Stop'\n" + helper
            + ". " + ps(PROCESS) + "\nInitialize-TrialProcess\n" + script,
            encoding="utf-8",
        )
        result = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-File", str(source)],
            text=True, capture_output=True, timeout=35,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout.strip())

    def test_blocked_output_does_not_block_input_drain(self):
        result = self.powershell(r"""
$payload=[byte[]]::new(40001)
for ($i=0; $i -lt $payload.Length; $i++) { $payload[$i]=[byte]($i % 256) }
$input=[IO.MemoryStream]::new($payload)
$output=[TrialPipeChecks.GateOutput]::new()
$pipe=[PZTrial.BufferedLogPipe]::new($input,$output,65536)
try {
    $entered=$output.Entered.Wait(5000)
    $drained=[TrialPipeChecks.WaitFor]::InputClosed($pipe)
    $before=$pipe.Snapshot()
} finally { $output.Release.Set() }
$done=$pipe.Wait(5000)
@{Entered=$entered;Drained=$drained;Before=$before;Done=$done;
  Final=$pipe.Snapshot();Bytes=[Convert]::ToBase64String($output.ToArray())} | ConvertTo-Json -Depth 6
""", streams=True)
        self.assertTrue(result["Entered"])
        self.assertTrue(result["Drained"], "Reader waited on the blocked output stream")
        self.assertEqual(result["Before"]["BytesRead"], 40001)
        self.assertEqual(result["Before"]["DroppedBytes"], 0)
        self.assertTrue(result["Done"])
        self.assertEqual(base64.b64decode(result["Bytes"]), bytes(i % 256 for i in range(40001)))
        self.assertEqual(result["Final"]["BytesWritten"], 40001)
        self.assertEqual(result["Final"]["PendingBytes"], 0)
        self.assertFalse(result["Final"]["Error"])

    def test_idle_output_is_flushed_before_child_pipe_closes(self):
        result = self.powershell(r"""
$input=[TrialPipeChecks.OpenInput]::new()
$output=[TrialPipeChecks.FlushOutput]::new()
$pipe=[PZTrial.BufferedLogPipe]::new($input,$output,65536)
try {
    $flushed=$output.Flushed.Wait(5000)
    $before=$pipe.Snapshot()
} finally { $input.Finish.Set() }
@{Flushed=$flushed;Before=$before;Done=$pipe.Wait(5000);Final=$pipe.Snapshot()} | ConvertTo-Json -Depth 6
""", streams=True)
        self.assertTrue(result["Flushed"], "Readiness logs must be visible before game exit")
        self.assertFalse(result["Before"]["InputClosed"])
        self.assertEqual(result["Before"]["BytesWritten"], 5)
        self.assertTrue(result["Done"])
        self.assertFalse(result["Final"]["Error"])

    def test_binary_utf8_and_final_unterminated_tail_are_exact(self):
        payload = b"\x00\xff\x80\r\n" + "Русский текст 😀".encode() * 1500 + b"final tail without newline"
        encoded = base64.b64encode(payload).decode()
        result = self.powershell(f"""
$input=[IO.MemoryStream]::new([Convert]::FromBase64String({ps(encoded)}))
$output=[IO.MemoryStream]::new()
$pipe=[PZTrial.BufferedLogPipe]::new($input,$output,1048576)
$done=$pipe.Wait(5000)
@{{Done=$done;Final=$pipe.Snapshot();Bytes=[Convert]::ToBase64String($output.ToArray())}} | ConvertTo-Json -Depth 6
""")
        self.assertTrue(result["Done"])
        self.assertEqual(base64.b64decode(result["Bytes"]), payload)
        status = result["Final"]
        self.assertEqual(status["BytesRead"], len(payload))
        self.assertEqual(status["BytesWritten"], len(payload))
        self.assertEqual(status["DroppedBytes"], 0)
        self.assertEqual(status["PendingBytes"], 0)
        self.assertTrue(status["InputClosed"])
        self.assertTrue(status["WriterClosed"])
        self.assertFalse(status["Error"])

    def test_overflow_is_bounded_and_accounted_without_stopping_drain(self):
        result = self.powershell(r"""
$payload=[byte[]]::new(2097152)
$input=[IO.MemoryStream]::new($payload)
$output=[TrialPipeChecks.GateOutput]::new()
$pipe=[PZTrial.BufferedLogPipe]::new($input,$output,16384)
try {
    $drained=[TrialPipeChecks.WaitFor]::InputClosed($pipe)
    $blocked=$pipe.Snapshot()
} finally { $output.Release.Set() }
$done=$pipe.Wait(5000)
@{Drained=$drained;Blocked=$blocked;Done=$done;Final=$pipe.Snapshot()} | ConvertTo-Json -Depth 6
""", streams=True)
        self.assertTrue(result["Drained"])
        self.assertTrue(result["Done"])
        self.assertLessEqual(result["Blocked"]["PendingBytes"], 16384)
        final = result["Final"]
        self.assertEqual(final["BytesRead"], 2097152)
        self.assertGreater(final["DroppedBytes"], 0)
        self.assertEqual(final["BytesWritten"] + final["DroppedBytes"], final["BytesRead"])
        self.assertEqual(final["PendingBytes"], 0)
        self.assertTrue(final["Error"], "Overflow must remain visible as an incomplete capture")

    def test_input_and_output_exceptions_terminate_without_deadlock(self):
        result = self.powershell(r"""
$a=[PZTrial.BufferedLogPipe]::new([TrialPipeChecks.BrokenInput]::new(),[IO.MemoryStream]::new(),65536)
$b=[PZTrial.BufferedLogPipe]::new([IO.MemoryStream]::new([byte[]]::new(1048576)),[TrialPipeChecks.BrokenOutput]::new(),1048576)
@{InputDone=$a.Wait(5000);OutputDone=$b.Wait(5000);Input=$a.Snapshot();Output=$b.Snapshot()} | ConvertTo-Json -Depth 6
""", streams=True)
        self.assertTrue(result["InputDone"])
        self.assertTrue(result["OutputDone"])
        self.assertIn("injected input failure", result["Input"]["Error"])
        self.assertIn("injected output failure", result["Output"]["Error"])
        for name in ("Input", "Output"):
            self.assertTrue(result[name]["InputClosed"])
            self.assertTrue(result[name]["WriterClosed"])
        self.assertEqual(result["Output"]["BytesRead"], 1048576)

    def child(self):
        child = self.base / "child with spaces.py"
        child.write_text(
            "import os, sys\n"
            "sys.stdout.buffer.write(('PID:%s\\n' % os.getpid()).encode())\n"
            "sys.stdout.buffer.write(bytes(range(256)) * 1024 + b'out-tail')\n"
            "sys.stderr.buffer.write('Ошибка 😀'.encode() * 20000 + b'err-tail')\n"
            "sys.stdout.buffer.flush()\nsys.stderr.buffer.flush()\n"
            "raise SystemExit(7)\n", encoding="utf-8",
        )
        return child

    def test_wrapper_preserves_both_streams_nonzero_exit_and_real_child_pid(self):
        child = self.child()
        stdout, stderr = self.base / "stdout.bin", self.base / "stderr.bin"
        arguments = '"' + str(child) + '"'
        result = self.powershell(f"""
$plan=[pscustomobject]@{{Java={ps(sys.executable)};WorkingDirectory={ps(self.base)};CommandLine={ps(arguments)}}}
$logs=[pscustomobject]@{{Stdout={ps(stdout)};Stderr={ps(stderr)}}}
$capture=Start-TrialProcess $plan $logs
$childId=$capture.Process.Id
try {{
    if (-not $capture.Process.WaitForExit(10000)) {{ throw "Child did not exit" }}
    $status=Complete-TrialProcess $capture
}} finally {{
    if (-not $capture.Process.HasExited) {{ $capture.Process.Kill() }}
}}
@{{Pid=$childId;ExitCode=$capture.Process.ExitCode;Status=$status}} | ConvertTo-Json -Depth 8
""")
        self.assertEqual(result["ExitCode"], 7)
        self.assertEqual(stdout.read_bytes(), f"PID:{result['Pid']}\n".encode() + bytes(range(256)) * 1024 + b"out-tail")
        self.assertEqual(stderr.read_bytes(), "Ошибка 😀".encode() * 20000 + b"err-tail")
        status = result["Status"]
        self.assertEqual(status["Status"], "Complete")
        self.assertEqual(status["Policy"], "AsyncPipeQueueV1")
        for name, path in (("Stdout", stdout), ("Stderr", stderr)):
            self.assertEqual(status[name]["BytesWritten"], path.stat().st_size)
            self.assertEqual(status[name]["DroppedBytes"], 0)
            self.assertTrue(status[name]["InputClosed"])
            self.assertTrue(status[name]["WriterClosed"])

    def test_completion_timeout_is_bounded_and_remains_incomplete_after_drain(self):
        child = self.base / "inherited pipes.py"
        release = self.base / "release-descendant"
        # A descendant keeps the original child's inherited stdout/stderr open.
        # EOF is intentionally withheld after the actual captured PID has exited.
        code = (
            "import pathlib, time\n"
            f"release=pathlib.Path({str(release)!r})\n"
            "deadline=time.monotonic()+12\n"
            "while not release.exists() and time.monotonic()<deadline: time.sleep(.01)\n"
        )
        child.write_text(
            "import subprocess, sys\n"
            f"subprocess.Popen([sys.executable, '-c', {code!r}])\n",
            encoding="utf-8",
        )
        arguments = '"' + str(child) + '"'
        result = self.powershell(f"""
$capture=[PZTrial.TrialProcessCapture]::Start({ps(sys.executable)},{ps(self.base)}, {ps(arguments)},{ps(self.base / 'timeout-out')},{ps(self.base / 'timeout-err')},65536)
try {{
    if (-not $capture.Process.WaitForExit(5000)) {{ throw "Captured parent did not exit" }}
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $initial=$capture.Complete(30)
    $elapsed=$timer.ElapsedMilliseconds
}} finally {{
    [IO.File]::WriteAllText({ps(release)},'release')
    if (-not $capture.Process.HasExited) {{ $capture.Process.Kill() }}
}}
$final=$capture.Complete(5000)
@{{Initial=$initial;Elapsed=$elapsed;Final=$final}} | ConvertTo-Json -Depth 8
""")
        self.assertEqual(result["Initial"]["Status"], "Incomplete")
        self.assertTrue(result["Initial"]["CompletionTimedOut"])
        self.assertLess(result["Elapsed"], 1500)
        self.assertEqual(result["Final"]["Status"], "Incomplete")
        for name in ("Stdout", "Stderr"):
            self.assertTrue(result["Final"][name]["InputClosed"])
            self.assertTrue(result["Final"][name]["WriterClosed"])

    def test_actual_launcher_failure_handlers_drain_without_initial_plan_pid(self):
        child = self.base / "post-start failure child.py"
        release = self.base / "release-after-catch"
        child.write_text(
            "import pathlib, sys, time\n"
            f"release=pathlib.Path({str(release)!r})\n"
            "deadline=time.monotonic()+8\n"
            "while not release.exists() and time.monotonic()<deadline: time.sleep(.01)\n"
            "if not release.exists(): raise SystemExit(88)\n"
            "sys.stdout.buffer.write(b'A' * 262144 + b'post-error stdout tail')\n"
            "sys.stderr.buffer.write(b'B' * 262144 + b'post-error stderr tail')\n"
            "sys.stdout.buffer.flush()\nsys.stderr.buffer.flush()\n"
            "raise SystemExit(7)\n", encoding="utf-8",
        )
        stdout, stderr = self.base / "failure-out", self.base / "failure-err"
        receipt = self.base / "failure-receipt.json"
        script = r"""
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(__LAUNCHER__,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Launcher source did not parse' }
$matches=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
    @($node.CatchClauses | Where-Object { $_.Extent.Text.Contains('$launchFailure = $_') }).Count -eq 1
},$true))
if ($matches.Count -ne 1) { throw 'Expected exactly one actual post-start catch/finally' }
$handler=$matches[0]
# Only the triggering operation is synthetic. Execute the launcher's live,
# unmodified catch and finally, rather than copying their implementation.
$failureScript="try { throw 'injected post-start failure' } " + $handler.CatchClauses[0].Extent.Text + ' finally ' + $handler.Finally.Extent.Text
$previousPath=$env:PATH; $previousApp=$env:SteamAppId; $previousGame=$env:SteamGameId
$sessionLogs=[pscustomobject]@{Directory=__BASE__;Console=__MISSING_CONSOLE__;Receipt=__RECEIPT__}
$plan=[pscustomobject]@{Pid=$null;Activation='Pending';LogCapture=$null;FinishedUtc=$null;JavaExitCode=$null}
$log=__RECEIPT__; $logsFinalized=$false; $warningSawLiveChild=$false
function Save-TrialPlan($Plan,[string]$Path) {
    [IO.File]::WriteAllText($Path,($Plan | ConvertTo-Json -Depth 10))
}
# Release the child at the catch's first warning so both output tails are
# produced after the injected failure, while the actual wait/drain executes.
function Write-Warning($Message) {
    if (-not (Test-Path -LiteralPath __RELEASE__)) {
        $script:warningSawLiveChild=-not $capture.Process.HasExited
        [IO.File]::WriteAllText(__RELEASE__,'release')
    }
}
$capture=[PZTrial.TrialProcessCapture]::Start(__PYTHON__,__BASE__,__ARGUMENTS__,__STDOUT__,__STDERR__,1048576)
$actualChildId=$capture.Process.Id
$initialPidWasNull=$null -eq $plan.Pid
try {
    try { . ([scriptblock]::Create($failureScript)) }
    catch { $observedError=$_.Exception.Message }
} finally {
    [IO.File]::WriteAllText(__RELEASE__,'release')
    if (-not $capture.Process.WaitForExit(5000)) { $capture.Process.Kill() }
}
@{InitialPidWasNull=$initialPidWasNull;WarningSawLiveChild=$warningSawLiveChild;Error=$observedError;
  ActualPid=$actualChildId;LogsFinalized=$logsFinalized;Exited=$capture.Process.HasExited;
  Plan=$plan;Status=$capture.Snapshot()} | ConvertTo-Json -Depth 10
"""
        values = {
            "__LAUNCHER__": ROOT / "tests/optimizer_trial/Launch-Trial.ps1",
            "__BASE__": self.base,
            "__MISSING_CONSOLE__": self.base / "absent-console.txt",
            "__RECEIPT__": receipt,
            "__RELEASE__": release,
            "__PYTHON__": sys.executable,
            "__ARGUMENTS__": '"' + str(child) + '"',
            "__STDOUT__": stdout,
            "__STDERR__": stderr,
        }
        for marker, value in values.items():
            script = script.replace(marker, ps(value))
        result = self.powershell(script)
        self.assertTrue(result["InitialPidWasNull"])
        self.assertTrue(result["WarningSawLiveChild"])
        self.assertEqual(result["Error"], "injected post-start failure")
        self.assertTrue(result["Exited"])
        self.assertTrue(result["LogsFinalized"])
        self.assertEqual(result["Status"]["Status"], "Complete")
        self.assertEqual(stdout.read_bytes(), b"A" * 262144 + b"post-error stdout tail")
        self.assertEqual(stderr.read_bytes(), b"B" * 262144 + b"post-error stderr tail")
        saved = json.loads(receipt.read_text())
        self.assertEqual(saved["Pid"], result["ActualPid"])
        self.assertEqual(saved["JavaExitCode"], 7)
        self.assertEqual(saved["Activation"], "Incomplete")
        self.assertEqual(saved["LogCapture"]["Status"], "Complete")
        self.assertTrue(saved["FinishedUtc"])

    def test_startup_failures_are_reported(self):
        child = self.child()
        result = self.powershell(f"""
$missingExecutable=$false
try {{ [PZTrial.TrialProcessCapture]::Start({ps(self.base / 'missing-executable')},{ps(self.base)},'',{ps(self.base / 'out1')},{ps(self.base / 'err1')},65536) | Out-Null }} catch {{ $missingExecutable=$true }}
$missingDirectory=$false
try {{ [PZTrial.TrialProcessCapture]::Start({ps(sys.executable)},{ps(self.base)}, {ps('"' + str(child) + '"')},{ps(self.base / 'absent' / 'out2')},{ps(self.base / 'err2')},65536) | Out-Null }} catch {{ $missingDirectory=$true }}
@{{MissingExecutable=$missingExecutable;MissingDirectory=$missingDirectory}} | ConvertTo-Json
""")
        self.assertEqual(result, {"MissingExecutable": True, "MissingDirectory": True})


if __name__ == "__main__":
    unittest.main()
