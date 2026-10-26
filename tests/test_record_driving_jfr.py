"""Focused attach helper checks; a disposable Java process, never the game."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tests/driving_benchmark/Record-JFR.ps1"
POWERSHELL = shutil.which("pwsh")
JDK = Path(os.environ.get("PZ_TEST_JDK") or os.environ.get("JAVA_HOME") or "/nonexistent-jdk25")

@unittest.skipUnless(POWERSHELL, "PowerShell is not installed")
class DrivingJfr(unittest.TestCase):
    def run_ps(self, source, *arguments):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "check.ps1"
            path.write_text(source, encoding="utf-8")
            result = subprocess.run([POWERSHELL, "-NoProfile", "-File", str(path),
                                     "-Script", str(SCRIPT), *arguments],
                                    capture_output=True, text=True, timeout=45)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result

    def test_parser_and_false_success_guard(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            self.run_ps(r'''
param([string]$Script,[string]$Root)
$tokens=$null; $errors=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($Script,[ref]$tokens,[ref]$errors)
if ($errors.Count) {throw ($errors | Out-String)}
. $Script
function Invoke-JfrTool([string]$Tool,[string[]]$ToolArguments) {
    if ($ToolArguments -contains 'VM.version') {
        return [pscustomobject]@{Code=0;Output='OpenJDK 64-Bit Server VM version 25.0.1'}
    }
    if ($ToolArguments -contains 'JFR.check') {
        return [pscustomobject]@{Code=0;Output='No available recordings.'}
    }
    return [pscustomobject]@{Code=0;Output='Could not start recording'}
}
$failed=$false
try {Start-JfrDrivingCapture 'fake' 123 (Join-Path $Root 'failed') 'PZDrive_test' 2 1} catch {
    $failed=$_.Exception.Message -match 'not acknowledged'
}
if (-not $failed) {throw 'Exit-code-zero JFR error was treated as success'}
$sentinel=Join-Path $Root 'failed/start-command.txt'
$before=[IO.File]::ReadAllText($sentinel)
$failed=$false
try {Start-JfrDrivingCapture 'fake' 123 (Join-Path $Root 'failed') 'PZDrive_test' 2 1} catch {$failed=$true}
if (-not $failed -or [IO.File]::ReadAllText($sentinel) -ne $before) {throw 'Existing output overwritten'}
$failed=$false
try {Start-JfrDrivingCapture 'fake' 123 (Join-Path $Root 'injected') 'bad name' 2 1} catch {$failed=$true}
if (-not $failed -or (Test-Path (Join-Path $Root 'injected'))) {throw 'Invalid name accepted'}
# JFR may preallocate an empty destination; completion must wait from acknowledgement.
function Invoke-JfrTool([string]$Tool,[string[]]$ToolArguments) {
    if ($ToolArguments -contains 'VM.version') {
        return [pscustomobject]@{Code=0;Output='OpenJDK 64-Bit Server VM version 25.0.1'}
    }
    if ($ToolArguments -contains 'JFR.check') {
        Start-Sleep -Seconds 3
        $script:ackLowerBound=[DateTime]::UtcNow
        return [pscustomobject]@{Code=0;Output='Recording 1: name=PZDrive_delayed (delayed)'}
    }
    return [pscustomobject]@{Code=0;Output='Started recording'}
}
$capture=Start-JfrDrivingCapture 'fake' 123 (Join-Path $Root 'delayed') 'PZDrive_delayed' 2 1
if ($capture.ExpectedEnd -lt $script:ackLowerBound.AddSeconds(5)) {
    throw 'Deadline used request time instead of successful acknowledgement'
}

''', "-Root", str(root))

    def test_exact_launch_identity_rejects_wrong_stale_and_reused_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            self.run_ps(r'''
param([string]$Script,[string]$Root)
. $Script
function New-FakeProcess([int]$Number,[string]$Path,[DateTime]$Started,[bool]$Exited=$false) {
    $item=[pscustomobject]@{Id=$Number;Path=$Path;StartTime=$Started;HasExited=$Exited}
    $item | Add-Member ScriptMethod Refresh {}
    $item | Add-Member ScriptMethod Dispose {}
    return $item
}
$started=[DateTime]::UtcNow.AddMinutes(-1)
$executable=Join-Path $Root 'client/java.exe'
$owned=New-FakeProcess 123 $executable $started
$script:current=New-FakeProcess 123 $executable $started
function Get-Process([int]$Id,[string]$ErrorAction) {
    if (-not $script:current) {throw 'No process with that PID'}
    return $script:current
}
$identity=Assert-JfrTargetProcess $owned $executable $started
if ($identity.Pid -ne 123 -or $identity.StartUtc.Kind -ne [DateTimeKind]::Utc) {throw 'Identity was not normalized'}
function Require-IdentityFailure([string]$ExpectedMessage) {
    $failed=$false
    try {$null=Assert-JfrTargetProcess $owned $executable $started} catch {
        $failed=$_.Exception.Message -match $ExpectedMessage
    }
    if (-not $failed) {throw ('Unsafe process identity accepted: '+$ExpectedMessage)}
}
$script:current=New-FakeProcess 123 (Join-Path $Root 'unrelated-server/java.exe') $started
Require-IdentityFailure 'Executable does not match'
$script:current=New-FakeProcess 123 $executable $started.AddSeconds(1)
Require-IdentityFailure 'stale or reused PID'
$script:current=$null
Require-IdentityFailure 'No process'
$script:current=New-FakeProcess 123 $executable $started $true
Require-IdentityFailure 'exited'
$script:current=New-FakeProcess 123 $executable $started
$failed=$false
try {$null=Assert-JfrTargetProcess $owned $executable ([DateTime]::SpecifyKind($started,[DateTimeKind]::Unspecified))} catch {$failed=$true}
if (-not $failed) {throw 'Non-UTC launch time accepted'}
# Even valid identity must match the PID sent to jcmd, before any output is made.
$failed=$false
try {
    Start-JfrDrivingCapture 'fake' 456 (Join-Path $Root 'wrong-pid') 'PZDrive_wrong' 2 1 `
        -TargetProcess $owned -ExpectedExecutablePath $executable -ExpectedStartUtc $started
} catch {$failed=$_.Exception.Message -match 'Recording PID'}
if (-not $failed -or (Test-Path (Join-Path $Root 'wrong-pid'))) {throw 'Unrelated PID was attached'}
# A PID replaced between VM.version and JFR.start must never receive JFR.start.
function Invoke-JfrTool([string]$Tool,[string[]]$ToolArguments) {
    if ($ToolArguments -contains 'VM.version') {
        $script:current=New-FakeProcess 123 $executable $started.AddSeconds(1)
        return [pscustomobject]@{Code=0;Output='OpenJDK 64-Bit Server VM version 25.0.1'}
    }
    throw 'JFR.start reached an unrelated process'
}
$failed=$false
try {
    Start-JfrDrivingCapture 'fake' 123 (Join-Path $Root 'reused-pid') 'PZDrive_reused' 2 1 `
        -TargetProcess $owned -ExpectedExecutablePath $executable -ExpectedStartUtc $started
} catch {$failed=$_.Exception.Message -match 'stale or reused PID'}
if (-not $failed) {throw 'PID reuse during attachment was not rejected'}
''', "-Root", str(Path(temporary).resolve()))

    @unittest.skipUnless((JDK / "bin/java").is_file() and (JDK / "bin/jcmd").is_file(),
                         "Set PZ_TEST_JDK to a JDK25 for the disposable JVM test")
    def test_real_java_capture_spaces_apostrophe_and_argument_roundtrip(self):
        with tempfile.TemporaryDirectory(prefix="pz-jfr-check-") as temporary:
            root = Path(temporary).resolve()
            source = root / "JfrCaptureTarget.java"
            source.write_text("""
public class JfrCaptureTarget {
 public static void main(String[] args) throws Exception {
  System.out.println("READY"); System.out.flush();
  for (int i=0; i<6000; i++) {
   byte[] b=new byte[100000]; b[0]=(byte)i;
   Thread.sleep(10);
  }
 }
}
""", encoding="utf-8")
            target = subprocess.Popen([str(JDK / "bin/java"), "-Xmx128m", str(source)],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertEqual("READY", target.stdout.readline().strip())
                output = root / "O'Brien запись with spaces"
                self.run_ps(r'''
param([string]$Script,[string]$Jdk,[int]$TargetId,[string]$Output)
. $Script
# The native-argument wrapper must retain spaces, quotes, empty arguments and trailing backslashes.
$probe=Join-Path ([IO.Path]::GetDirectoryName($Output)) 'Args.java'
[IO.File]::WriteAllText($probe, 'class Args {public static void main(String[] a) { for(String s:a) System.out.println(s.length()+":"+s); }}')
$arguments=@('', 'space value', 'quote"value', 'C:\trailing\')
$result=Invoke-JfrTool (Join-Path $Jdk 'bin/java') (@($probe)+$arguments)
Require-JfrToolSuccess $result 'argument probe'
$expected=(@($arguments | ForEach-Object { ([string]$_.Length)+':'+$_ }) -join [Environment]::NewLine)
if ($result.Output.Trim() -ne $expected.Trim()) {throw ('Native argument quoting changed values: '+$result.Output)}
$owned=Get-Process -Id $TargetId -ErrorAction Stop
$started=$owned.StartTime.ToUniversalTime()
$executable=Join-Path $Jdk 'bin/java'
$null=Assert-JfrTargetProcess $owned $executable $started
$failed=$false
try {$null=Assert-JfrTargetProcess $owned $executable $started.AddTicks(-1)} catch {$failed=$true}
if (-not $failed) {throw 'A real Java process accepted stale launch identity'}
$failed=$false
try {$null=Assert-JfrTargetProcess $owned (Join-Path $Jdk 'bin/jcmd') $started} catch {$failed=$true}
if (-not $failed) {throw 'A real Java process accepted an unrelated executable identity'}
$capture=Start-JfrDrivingCapture (Join-Path $Jdk 'bin/jcmd') $TargetId $Output 'PZDrive_probe' 2 1 `
    -TargetProcess $owned -ExpectedExecutablePath $executable -ExpectedStartUtc $started
Start-Sleep -Seconds 4
$summary=Invoke-JfrTool (Join-Path $Jdk 'bin/jfr') @('summary',$capture.File)
Require-JfrToolSuccess $summary 'real JFR summary'
if ((Get-Item -LiteralPath $capture.File).Length -lt 1000) {throw 'Empty recording'}
$meta=Get-Content -LiteralPath (Join-Path $Output 'capture.json') -Raw | ConvertFrom-Json
if ($meta.targetPid -ne $TargetId -or $meta.durationSeconds -ne 2 -or $meta.delaySeconds -ne 1) {throw 'Wrong target metadata'}
if ($meta.targetExecutable -ne $executable -or (([DateTime]$meta.targetStartUtc).ToUniversalTime().Ticks -ne $started.Ticks)) {
    throw 'Launch identity missing from recording metadata'
}
Write-Host 'Actual JDK25 attach, delayed capture, quoted paths, native arguments and readable recording passed.'
''', "-Jdk", str(JDK), "-TargetId", str(target.pid), "-Output", str(output))
                self.assertEqual(b"FLR\x00", (output / "drive.jfr").read_bytes()[:4])
                metadata = json.loads((output / "capture.json").read_text(encoding="utf-8-sig"))
                self.assertEqual(target.pid, metadata["targetPid"])
            finally:
                target.terminate()
                target.communicate(timeout=10)

if __name__ == "__main__":
    unittest.main()
