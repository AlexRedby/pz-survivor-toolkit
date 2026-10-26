"""Bounded sampling policy and interop layouts; no Windows hardware claim."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
PWSH=shutil.which('pwsh')
SCRIPT=ROOT/'tests/optimizer_trial/TrialTelemetry.ps1'
def ps(s):return "'"+str(s).replace("'","''")+"'"

@unittest.skipUnless(PWSH,'PowerShell required')
class Telemetry(unittest.TestCase):
    def run_ps(self,body):
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/'test.ps1'
            f.write_text("$ErrorActionPreference='Stop'\nSet-StrictMode -Version 2\n. "+ps(SCRIPT)+"\n"+body)
            r=subprocess.run([PWSH,'-NoProfile','-File',str(f)],capture_output=True,text=True,timeout=20)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            return r.stdout
    def fixture(self):
        return """
$p=Get-Process -Id $PID
$s=@{PreviousTick=0L;PreviousCpu=0.0;Unavailable=@{};NvidiaTool='fixture'}
function Get-CimInstance {throw 'CIM must never run during capture'}
function Read-TrialCim {throw 'CIM helper must never run during capture'}
$script:nativeCalls=0;$script:nvCalls=0
function Read-TrialNativeCounter {param($Kind,$Process);$script:nativeCalls++;return [pscustomobject]@{status='Available';source='fixture';data=@{kind=$Kind;total=0};error=$null}}
function Read-TrialNvidiaSample {$script:nvCalls++;return [pscustomobject]@{status='Available';elapsedMs=4;unavailableReason=$null}}
"""
    def test_no_cim_and_cpu_delta_with_native_zero_preserved(self):
        out=self.run_ps(self.fixture()+"""
$a=Get-TrialTelemetry $p $s $true
Start-Sleep -Milliseconds 20
$b=Get-TrialTelemetry $p $s $true
if ($script:nativeCalls -ne 6 -or $script:nvCalls -ne 1) {throw 'wrong sample policy'}
if ($null -ne $a.process.cpuCoresUsed -or $null -eq $b.process.cpuCoresUsed) {throw 'bad CPU baseline'}
if ($b.counters.io.data.total -ne 0) {throw 'zero missing'}
$b|ConvertTo-Json -Depth 8 -Compress
""")
        sample=json.loads(out);self.assertEqual(sample['format'],2);self.assertGreaterEqual(sample['sampleCostMs'],0)
    def test_unavailable_counters_disabled_without_fake_zero(self):
        self.run_ps(self.fixture()+"""
function Read-TrialNativeCounter {$script:nativeCalls++;return [pscustomobject]@{status='Unavailable';data=$null;error='AccessDenied'}}
function Read-TrialNvidiaSample {$script:nvCalls++;return [pscustomobject]@{status='Unavailable';elapsedMs=2;unavailableReason='ToolMissing'}}
$a=Get-TrialTelemetry $p $s $true
$b=Get-TrialTelemetry $p $s $true
if ($script:nativeCalls -ne 3 -or $script:nvCalls -ne 1 -or $s.Unavailable.io -ne 'AccessDenied') {throw 'failure retried'}
if ($null -ne $a.counters.io.data -or $b.counters.Count -ne 0) {throw 'fabricated data'}
""")
    def test_slow_optional_provider_not_repeated(self):
        self.run_ps(self.fixture()+"""
function Read-TrialNativeCounter {$script:nativeCalls++;Start-Sleep -Milliseconds 270;return [pscustomobject]@{status='Available';data=@{value=5};error=$null}}
function Read-TrialNvidiaSample {$script:nvCalls++;return [pscustomobject]@{status='Available';elapsedMs=400;unavailableReason=$null}}
$a=Get-TrialTelemetry $p $s $true
$s.NextNvidiaUtc=[DateTime]::MinValue
$b=Get-TrialTelemetry $p $s $true
if ($script:nativeCalls -ne 3 -or $script:nvCalls -ne 1) {throw 'slow provider retried'}
if ($s.Unavailable.io -ne 'DisabledAfterSlowSample' -or $s.Unavailable.nvidia -ne 'DisabledAfterSlowSample') {throw 'missing cost reason'}
if ($a.counters.io.data.value -ne 5) {throw 'last valid sample lost'}
""")
    def test_nvidia_interval_is_elapsed_time_not_sample_count(self):
        self.run_ps(self.fixture()+"""
$a=Get-TrialTelemetry $p $s $true
$b=Get-TrialTelemetry $p $s $false
$c=Get-TrialTelemetry $p $s $true
if ($script:nvCalls -ne 1) {throw 'too frequent NVIDIA'}
$s.NextNvidiaUtc=[DateTime]::MinValue
$d=Get-TrialTelemetry $p $s $true
if ($script:nvCalls -ne 2) {throw 'NVIDIA never sampled again'}
""")
    def test_interop_compiles_and_layouts_match_win64(self):
        source=SCRIPT.read_text().split("@'\n",1)[1].split("\n'@",1)[0]
        self.run_ps("Add-Type -TypeDefinition @'\n"+source+"\n'@\n"+"""
if ([Runtime.InteropServices.Marshal]::SizeOf([type][PZTrialTelemetry.Memory]) -ne 64) {throw 'bad MEMORYSTATUSEX layout'}
if ([Runtime.InteropServices.Marshal]::SizeOf([type][PZTrialTelemetry.Io]) -ne 48) {throw 'bad IO_COUNTERS layout'}
$expected=8+9*[IntPtr]::Size
if ([Runtime.InteropServices.Marshal]::SizeOf([type][PZTrialTelemetry.ProcessMemory]) -ne $expected) {throw 'bad PROCESS_MEMORY_COUNTERS_EX layout'}
""")

if __name__=='__main__':unittest.main()
