"""Joint capture checks; actual disposable Java, no game or Windows hardware claims."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
JDK = Path(os.environ.get('PZ_TEST_JDK', '/nonexistent-jdk'))


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


FRAME_FIXTURES = r"""
$frameClient=[pscustomobject]@{BaseUri='http://localhost:1337';Version='fixture'}
function Assert-TrialCapFrameXTarget {}
function Wait-TrialCaptureHotkey { return [pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o');foregroundPid=$process.Id} }
function Start-TrialFrameCapture {
 param($Client,$Process,$Executable,$Started,$Directory,$Seconds,$Token)
 return [pscustomobject]@{directory=$Directory;token=$Token;targetPid=$Process.Id;processName='java';seconds=$Seconds;requestedUtc=[DateTime]::UtcNow.ToString('o');acknowledgedUtc=[DateTime]::UtcNow.ToString('o')}
}
function Complete-TrialFrameCapture { return [pscustomobject]@{Json='fixture.json';Csv='fixture.csv'} }
"""


@unittest.skipUnless(PWSH, 'PowerShell required')
class TrialDiagnostics(unittest.TestCase):
    def invoke(self, root, body, timeout=50):
        file = root / 'test.ps1'
        file.write_text("$env:USERPROFILE="+ps(root)+"\n. "+ps(ROOT/'tests/optimizer_trial/Launch-Trial.ps1')+
                        " -SourceProfile "+ps(root/'source')+"\n"+FRAME_FIXTURES+body)
        r=subprocess.run([PWSH,'-NoProfile','-NonInteractive','-File',str(file)],text=True,capture_output=True,timeout=timeout)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        return r

    def fixture(self, root):
        (root/'cache').mkdir(); (root/'run').mkdir()
        (root/'cache/options.ini').write_text('width=2560\nheight=1440\n')
        return ("$plan=[pscustomobject]@{Mode='Control';Java='/fake/java';Cache="+ps(root/'cache')+
                ";ProcessStartUtc='2026-10-26T00:00:00Z';Logs=[pscustomobject]@{Directory="+ps(root/'run')+"}}\n"
                "$process=[pscustomobject]@{Id=987654}\n$tools=[pscustomobject]@{Jcmd='jcmd';Jfr='jfr'}\n"
                "function Assert-JfrTargetProcess { param($Process,$Path,$Start); return @{} }\n"
                "function Get-TrialHardware { return @{fixture=$true} }\n"
                "function Save-TrialJvmSnapshot {}\nfunction Get-TrialNvidiaTool { return $null }\nfunction Read-Host { return '' }\n")

    def test_empty_recording_and_failed_attach_never_complete(self):
        for kind in ('empty','attach'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as t:
                root=Path(t).resolve();body=self.fixture(root)
                if kind=='attach':
                    body+="function Start-JfrDrivingCapture { throw 'attach failure' }\n"
                else:
                    body+="""
function Start-JfrDrivingCapture {
 param($Jcmd,$Id,$Directory,$Name,$Seconds,$Delay,$TargetProcess,$ExpectedExecutablePath,$ExpectedStartUtc)
 [IO.Directory]::CreateDirectory($Directory)|Out-Null
 $p=Join-Path $Directory 'drive.jfr';[IO.File]::WriteAllText($p,'')
 return [pscustomobject]@{File=$p;ExpectedEnd=[DateTime]::UtcNow.AddSeconds(-1);EarliestEnd=[DateTime]::UtcNow.AddSeconds(120)}
}
function Invoke-JfrTool { return [pscustomobject]@{Code=0;Output='misleading success'} }
function Start-Sleep {}
"""
                body+="$r=Invoke-TrialDiagnostics $process $plan $tools 2 0 -FrameClient $frameClient -FrameSeconds 1; if ($r.status -ne 'Incomplete') {throw 'false complete'}\n"
                self.invoke(root,body)
                status=json.loads((root/'run/diagnostics.json').read_text())
                self.assertEqual(status['status'],'Incomplete')
                self.assertTrue(status['error'])
                self.assertTrue((root/'run/hardware.json').is_file())

    def test_target_revalidated_after_last_sample(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t).resolve();body=self.fixture(root)+"""
$script:gone=$false
function Assert-JfrTargetProcess { if ($script:gone) {throw 'client exited after final sample'} }
function Start-JfrDrivingCapture {
 param($Jcmd,$Id,$Directory,$Name,$Seconds,$Delay,$TargetProcess,$ExpectedExecutablePath,$ExpectedStartUtc)
 [IO.Directory]::CreateDirectory($Directory)|Out-Null
 $p=Join-Path $Directory 'drive.jfr';[IO.File]::WriteAllText($p,'short dump-on-exit file')
 return [pscustomobject]@{File=$p;ExpectedEnd=[DateTime]::UtcNow.AddMilliseconds(750);EarliestEnd=[DateTime]::UtcNow.AddSeconds(120)}
}
function Start-Sleep { param($Seconds,$Milliseconds); if ($Milliseconds) { [Threading.Thread]::Sleep($Milliseconds) } }
function Get-TrialTelemetry { $script:gone=$true; return @{sample=1} }
function Invoke-JfrTool { throw 'must reject exited identity before JFR summary' }
$r=Invoke-TrialDiagnostics $process $plan $tools 15 1 -FrameClient $frameClient -FrameSeconds 1
if ($r.status -ne 'Incomplete' -or $r.error -notmatch 'client exited') {throw 'early exit accepted'}
"""
            self.invoke(root,body)
            self.assertTrue((root/'run/JFR/drive.jfr').exists())

    def test_jfr_window_must_cover_frames_and_failed_post_is_not_retried(self):
        for fault in ('window','post','late'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as t:
                root=Path(t).resolve();body=self.fixture(root)+r"""
$script:frameStarts=0
function Start-Sleep {}
function Start-JfrDrivingCapture {
 param($Jcmd,$Id,$Directory,$Name,$Seconds,$Delay,$TargetProcess,$ExpectedExecutablePath,$ExpectedStartUtc)
 [IO.Directory]::CreateDirectory($Directory)|Out-Null
 $p=Join-Path $Directory 'drive.jfr';[IO.File]::WriteAllText($p,'preserved JFR')
 return [pscustomobject]@{File=$p;ExpectedEnd=[DateTime]::UtcNow.AddSeconds(-1);EarliestEnd=[DateTime]::UtcNow.AddSeconds($script:remaining)}
}
function Start-TrialFrameCapture { $script:frameStarts++; throw 'unknown POST outcome' }
"""
                body+="$script:remaining="+('1' if fault=='window' else '120')+"\n"
                if fault=='late':
                    body+="function Start-TrialFrameCapture { $script:frameStarts++; return [pscustomobject]@{acknowledgedUtc=[DateTime]::UtcNow.AddSeconds(200).ToString('o')} }\n"
                body+="$r=Invoke-TrialDiagnostics $process $plan $tools 15 1 -FrameClient $frameClient -FrameSeconds 1\n"
                body+="if ($r.status -ne 'Incomplete' -or $script:frameStarts -ne "+('0' if fault=='window' else '1')+") {throw 'unsafe frame start/retry'}\n"
                self.invoke(root,body)
                self.assertEqual((root/'run/JFR/drive.jfr').read_text(),'preserved JFR')
                frame=json.loads((root/'run/frame-capture.json').read_text())
                self.assertEqual(frame['status'],'Incomplete')

    def test_wpr_order_and_cleanup_on_success_or_frame_start_failure(self):
        for fail in (False, True):
            with self.subTest(fail=fail), tempfile.TemporaryDirectory() as t:
                root=Path(t).resolve();body=self.fixture(root)+r"""
$script:steps=[Collections.Generic.List[string]]::new()
function Initialize-TrialWprCapture {
 $script:steps.Add('prepare')
 return [pscustomobject]@{Directory=$null;Status=[pscustomobject]@{status='Ready'}}
}
function Wait-TrialCaptureHotkey {
 $script:steps.Add('hotkey')
 return [pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o')}
}
function Start-TrialWprCapture {param($c);$script:steps.Add('wpr-start');$c.Status.status='Recording'}
function Complete-TrialWprCapture {param($c);$script:steps.Add('wpr-complete');$c.Status.status='Complete'}
function Stop-TrialWprCapture {param($c);$script:steps.Add('wpr-cleanup');$c.Status.status='Complete'}
function Start-Sleep {}
function Start-JfrDrivingCapture {
 param($Jcmd,$Id,$Directory,$Name,$Seconds,$Delay,$TargetProcess,$ExpectedExecutablePath,$ExpectedStartUtc)
 $script:steps.Add('jfr-start')
 [IO.Directory]::CreateDirectory($Directory)|Out-Null
 $p=Join-Path $Directory 'drive.jfr';[IO.File]::WriteAllText($p,'fixture recording')
 return [pscustomobject]@{File=$p;ExpectedEnd=[DateTime]::UtcNow.AddSeconds(-1);EarliestEnd=[DateTime]::UtcNow.AddSeconds(120)}
}
function Invoke-JfrTool {return [pscustomobject]@{Code=0;Output='fixture summary'}}
$originalStart=${function:Start-TrialFrameCapture}
function Start-TrialFrameCapture {
 $script:steps.Add('frames-start')
 if ($script:failFrames) {throw 'unknown frame POST outcome'}
 return & $originalStart @args
}
"""
                body+="$script:failFrames="+('$true' if fail else '$false')+"\n"
                body+="$r=Invoke-TrialDiagnostics $process $plan $tools 15 1 -FrameClient $frameClient -FrameSeconds 1\n"
                body+="[IO.File]::WriteAllText("+ps(root/'steps.json')+",($script:steps | ConvertTo-Json))\n"
                self.invoke(root,body)
                steps=json.loads((root/'steps.json').read_text())
                self.assertEqual(steps[:5],['prepare','hotkey','wpr-start','jfr-start','frames-start'])
                self.assertEqual(steps[-1],'wpr-cleanup')
                self.assertEqual('wpr-complete' in steps,not fail)
                state=json.loads((root/'run/diagnostics.json').read_text())
                self.assertEqual(state['status'],'Incomplete' if fail else 'Complete')
                self.assertTrue((root/'run/wpr-capture.json').is_file())
                self.assertTrue((root/'run/capture-readiness.json').is_file())
                if not fail:
                    self.assertEqual(state['extendedStatus'],'Complete')
                    self.assertTrue((root/'run/sensor-coverage.json').is_file())


    def test_optional_wpr_exceptions_preserve_baseline_and_cleanup_owned_helper(self):
        for fault in ('Prepare', 'Start', 'Complete', 'Stop', 'Receipt', 'LateReceipt'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as t:
                root=Path(t).resolve();body=self.fixture(root)+r"""
$script:jfrStarts=0; $script:frameStarts=0; $script:stopSignals=0; $script:receiptWrites=0
$script:worker=[pscustomobject]@{Id=456;HasExited=$false}
function Initialize-TrialWprCapture {
 if ($script:fault -eq 'Prepare') {throw 'optional preparation fixture'}
 return [pscustomobject]@{Directory=$null;Worker=$script:worker;Status=[pscustomobject]@{status='Ready';reason=$null;targetPid=$process.Id;startedUtc=$null;stoppedUtc=$null}}
}
function Start-TrialWprCapture {
 param($c)
 if ($script:fault -eq 'Start') {throw 'optional start fixture'}
 $c.Status.status='Recording'; $c.Status.startedUtc=[DateTime]::UtcNow.ToString('o')
}
function Complete-TrialWprCapture {
 param($c)
 if ($script:fault -eq 'Complete') {throw 'optional completion fixture'}
 if ($c.Status.status -eq 'Recording') { $c.Status.status='Complete'; $c.Status.stoppedUtc=[DateTime]::UtcNow.ToString('o') }
}
function Stop-TrialWprCapture {
 param($c)
 if ($script:fault -eq 'Stop') {throw 'optional stop fixture'}
 if ($c.Status.status -eq 'Recording') { $c.Status.status='Complete'; $c.Status.stoppedUtc=[DateTime]::UtcNow.ToString('o') }
}
function Send-TrialWprRequest {param($c,$action); if ($action -ne 'stop') {throw 'unexpected cleanup command'}; $script:stopSignals++}
function Get-TrialWprStatus {param($c);return $c.Status}
$script:saveReceipt=${function:Save-TrialWprReceipt}
function Save-TrialWprReceipt {
 param($c,$directory)
 $script:receiptWrites++
 if ($script:fault -eq 'Receipt' -or ($script:fault -eq 'LateReceipt' -and $script:receiptWrites -eq 4)) {throw 'optional receipt fixture'}
 & $script:saveReceipt $c $directory
}
function Start-Sleep {param($Seconds,$Milliseconds); if ($Milliseconds) {$script:worker.HasExited=$true}}
function Start-JfrDrivingCapture {
 param($Jcmd,$Id,$Directory,$Name,$Seconds,$Delay,$TargetProcess,$ExpectedExecutablePath,$ExpectedStartUtc)
 $script:jfrStarts++
 [IO.Directory]::CreateDirectory($Directory)|Out-Null
 $p=Join-Path $Directory 'drive.jfr';[IO.File]::WriteAllText($p,'preserved baseline JFR')
 return [pscustomobject]@{File=$p;ExpectedEnd=[DateTime]::UtcNow.AddSeconds(-1);EarliestEnd=[DateTime]::UtcNow.AddSeconds(120)}
}
function Invoke-JfrTool {return [pscustomobject]@{Code=0;Output='fixture summary'}}
$script:startFrames=${function:Start-TrialFrameCapture}
function Start-TrialFrameCapture { $script:frameStarts++; return & $script:startFrames @args }
"""
                body+="$script:fault="+ps(fault)+"\n"
                body+="$r=Invoke-TrialDiagnostics $process $plan $tools 15 1 -FrameClient $frameClient -FrameSeconds 1\n"
                body+="[IO.File]::WriteAllText("+ps(root/'observed.json')+",(@{result=$r;jfrStarts=$script:jfrStarts;frameStarts=$script:frameStarts;stopSignals=$script:stopSignals}|ConvertTo-Json -Depth 12))\n"
                self.invoke(root,body)
                observed=json.loads((root/'observed.json').read_text())
                state=json.loads((root/'run/diagnostics.json').read_text())
                self.assertEqual(state['status'],'Complete')
                self.assertEqual(observed['result']['status'],'Complete')
                self.assertEqual(observed['result']['extendedStatus'],'Partial')
                self.assertEqual(state['extendedStatus'],'Partial')
                self.assertIn(state['wprStatus'],('Unavailable','Incomplete'))
                self.assertIn('Receipt' if fault=='LateReceipt' else fault,state['wprIntegrationFailures'])
                self.assertIsNone(state['error'])
                self.assertEqual(observed['jfrStarts'],1)
                self.assertEqual(observed['frameStarts'],1)
                self.assertEqual(observed['stopSignals'],0 if fault=='Prepare' else 1)
                self.assertEqual((root/'run/JFR/drive.jfr').read_text(),'preserved baseline JFR')
                self.assertTrue((root/'run/JFR/summary.txt').is_file())
                self.assertEqual(json.loads((root/'run/frame-capture.json').read_text())['status'],'Complete')
                if fault!='Receipt':
                    wrapper=json.loads((root/'run/wpr-capture.json').read_text())
                    # Late receipt failure is still reported in diagnostics.json;
                    # earlier helper/receipt evidence remains unchanged.
                    if fault!='LateReceipt':
                        self.assertNotEqual(wrapper['receipt']['status'],'Complete')


    def test_failed_helper_metadata_retains_context_and_signals_owned_stop(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t).resolve();body=self.fixture(root)+r"""
function Get-TrialWprToolSelection { [pscustomobject]@{Selected=[pscustomobject]@{Path=(Join-Path $plan.Cache 'fake-wpr');Source='System';Sha256=('a'*64);Version='10.0.26100.1'};Candidates=@();Reason=$null} }
function Get-TrialWprSystemDirectory { $plan.Cache }
function Start-Process {
 $child=[pscustomobject]@{Id=456;HasExited=$false}
 $child | Add-Member -MemberType ScriptProperty -Name StartTime -Value {throw 'fixture denied helper metadata'}
 return $child
}
$c=Initialize-TrialWprCapture (Join-Path $plan.Logs.Directory 'WPR') $process $plan
"""
            body+="[IO.File]::WriteAllText("+ps(root/'observed.json')+",(@{status=$c.Status.status;reason=$c.Status.reason;retained=($null -ne $c.Worker);stopSent=$c.StopSent;stopExists=(Test-Path (Join-Path $c.Directory 'stop.request.json'))}|ConvertTo-Json))\n"
            self.invoke(root,body)
            observed=json.loads((root/'observed.json').read_text())
            self.assertEqual(observed,{'status':'Unavailable','reason':'HelperInitializationFailed','retained':True,'stopSent':True,'stopExists':True})

    @unittest.skipUnless((JDK/'bin/java').is_file() and (JDK/'bin/jcmd').is_file(),'PZ_TEST_JDK required')
    def test_real_combined_capture_and_duplicate_protection(self):
        with tempfile.TemporaryDirectory(prefix="pz joint O'Brien ") as t:
            root=Path(t).resolve();(root/'cache').mkdir();(root/'run').mkdir()
            (root/'cache/options.ini').write_text('width=2560\nheight=1440\n')
            java=root/'Target.java';java.write_text('class Target {public static void main(String[] a)throws Exception {System.out.println("READY");System.out.flush();for(int i=0;i<600;i++){byte[] b=new byte[100000];b[0]=1;Thread.sleep(100);}}}')
            target=subprocess.Popen([str(JDK/'bin/java'),'-Xmx128m',str(java)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                self.assertEqual(target.stdout.readline().strip(),'READY')
                body=("$process=Get-Process -Id "+str(target.pid)+"\n$plan=[pscustomobject]@{Mode='Control';Java="+ps(JDK/'bin/java')+
                      ";Cache="+ps(root/'cache')+";ProcessStartUtc=$process.StartTime.ToUniversalTime().ToString('o');Logs=[pscustomobject]@{Directory="+ps(root/'run')+"}}\n"+
                      "$tools=[pscustomobject]@{Jcmd="+ps(JDK/'bin/jcmd')+";Jfr="+ps(JDK/'bin/jfr')+"}\n"+"""
function Get-TrialHardware { return @{testPlatform='macOS';hardwareCounters='mocked'} }
function Get-TrialNvidiaTool { return $null }
function Read-TrialCim { return [pscustomobject]@{status='Unavailable';data=@();error='not Windows'} }
function Read-Host { return '' }
$r=Invoke-TrialDiagnostics $process $plan $tools 15 1 -FrameClient $frameClient -FrameSeconds 1
if ($r.status -ne 'Complete') {throw ('capture failed: '+$r.error)}
$failed=$false
try { Invoke-TrialDiagnostics $process $plan $tools 15 1 -FrameClient $frameClient -FrameSeconds 1 } catch { $failed=$true }
if (-not $failed) {throw 'existing capture overwritten'}
""")
                self.invoke(root,body)
                s=json.loads((root/'run/diagnostics.json').read_text());self.assertGreater(s['samples'],0)
                self.assertEqual(s['targetPid'],target.pid)
                frames=json.loads((root/'run/frame-capture.json').read_text())
                self.assertEqual(frames['status'],'Complete')
                jfr=json.loads((root/'run/JFR/capture.json').read_text())
                self.assertLess(jfr['acknowledgedUtc'],frames['request']['requestedUtc'])
                self.assertLess(frames['triggeredUtc'],jfr['requestedUtc'])
                self.assertEqual((root/'run/JFR/drive.jfr').read_bytes()[:4],b'FLR\x00')
                self.assertTrue((root/'run/JVM/VM-flags.txt').is_file())
                self.assertEqual((root/'run/game-options.ini').read_text(),'width=2560\nheight=1440\n')
                telemetry=[json.loads(x) for x in (root/'run/telemetry.jsonl').read_text().splitlines()]
                self.assertTrue(all(x['targetPid']==target.pid for x in telemetry))
                self.assertIn('process',telemetry[0]);self.assertIn('io',s['unavailableCounters'])
                self.assertEqual(s['unavailableCounters']['nvidia'],'ToolMissing')
            finally:
                target.terminate();target.communicate(timeout=10)


if __name__=='__main__':unittest.main()
