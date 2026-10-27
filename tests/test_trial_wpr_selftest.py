"""Recorder-only orchestration regressions; no Windows ETW success claim."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

SCRIPTS = Path(__file__).resolve().parent / 'optimizer_trial'
PWSH = shutil.which('pwsh')

@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class WprSelfTestTests(unittest.TestCase):
    def run_probe(self, directory, mode):
        env=dict(os.environ, PZ_SCRIPTS=str(SCRIPTS), PZ_OUT=str(directory), PZ_MODE=mode)
        code=r'''
$ErrorActionPreference='Stop'
. (Join-Path $env:PZ_SCRIPTS 'Test-WPR.ps1')
$global:completed=0; $global:signals=@(); $global:ownTarget=$false; $global:slept=0
function Assert-JfrTargetProcess { throw 'Self-test must not select Java.' }
function Start-TrialWprCapture { throw 'Self-test must not use game entrypoint.' }
function Initialize-TrialWprOwnedCapture {
 param($Directory,$Process,$Plan)
 $global:ownTarget=($Process.Id -eq $PID -and $Plan.Java -eq (Get-Process -Id $PID).Path -and $Plan.WprDurationSeconds -eq 30)
 $d=Join-Path $Directory ('a'*32); [IO.Directory]::CreateDirectory($d)|Out-Null
 $s=[pscustomobject]@{status='Ready';reason=$null;tool=[pscustomobject]@{Source='ADK';Version='10.0.26100.1';Path='installed-wpr'};headerValidated=$false;cleanupState='Unknown';traceBytes=$null;traceSha256=$null}
 if($env:PZ_MODE -eq 'unavailable'){$s.status='Unavailable';$s.reason='WprUpgradeRequired'}
 return [pscustomobject]@{Directory=$d;Status=$s;StartSent=$false}
}
function Get-TrialWprStatus {param($Context);return $Context.Status}
function Send-TrialWprRequest {param($Context,$Action);$global:signals+=@($Action)}
function Wait-TrialWprState {param($Context,$States,$Seconds);if($env:PZ_MODE -ne 'start-timeout'){$Context.Status.status='Recording'};return $Context.Status}
function Start-Sleep {param($Seconds);$global:slept=$Seconds}
function Complete-TrialWprCapture {
 param($Context);$global:completed++
 if($Context.Status.status -eq 'Unavailable'){return $Context.Status}
 $s=$Context.Status;$s.status='Complete';$s.headerValidated=$true;$s.cleanupState='Absent'
 $p=Join-Path $Context.Directory 'drive.etl';[IO.File]::WriteAllBytes($p,[byte[]]::new(1024));$s.traceBytes=1024;$s.traceSha256=(Get-FileHash $p).Hash
 if($env:PZ_MODE -eq 'save-failed'){$s.status='Incomplete';$s.reason='OwnedSessionSaveFailed'}
 if($env:PZ_MODE -eq 'corrupt'){$s.traceSha256='b'*64}
 if($env:PZ_MODE -eq 'cleanup-unknown'){$s.cleanupState='Unknown'}
 Write-TrialWprJson (Join-Path $Context.Directory 'wpr-status.json') $s
 return $s
}
$r=Invoke-TrialWprSelfTest $env:PZ_OUT
@{result=$r;completed=$global:completed;signals=$global:signals;ownTarget=$global:ownTarget;slept=$global:slept}|ConvertTo-Json -Depth 10 -Compress|Write-Output
'''
        run=subprocess.run([PWSH,'-NoProfile','-NonInteractive','-Command',code],env=env,text=True,capture_output=True,timeout=20)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        return json.loads(run.stdout.splitlines()[-1])

    def test_success_checks_only_controller_and_preserves_small_report_and_etl(self):
        with tempfile.TemporaryDirectory() as tmp:
            data=self.run_probe(Path(tmp).resolve(),'success');r=data['result']
            self.assertEqual(r['status'],'Passed');self.assertTrue(r['traceVerified'])
            self.assertTrue(data['ownTarget']);self.assertEqual(data['slept'],10)
            self.assertEqual(data['completed'],1);self.assertEqual(data['signals'],['start'])
            folder=Path(r['directory'])
            with zipfile.ZipFile(folder/'WPR-check-result.zip') as z:
                self.assertEqual(set(z.namelist()),{'result.json','wpr-status.json'})
                self.assertEqual(json.loads(z.read('result.json'))['status'],'Passed')
            self.assertEqual(len(list(folder.rglob('*.etl'))),1)

    def test_failed_start_save_integrity_or_cleanup_never_claims_pass_and_finalizes(self):
        for mode in ('unavailable','start-timeout','save-failed','corrupt','cleanup-unknown'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                data=self.run_probe(Path(tmp).resolve(),mode);r=data['result']
                self.assertEqual(r['status'],'Failed');self.assertFalse(r['traceVerified'])
                self.assertEqual(data['completed'],1)
                self.assertTrue((Path(r['directory'])/'WPR-check-result.zip').is_file())
                if mode=='unavailable':
                    self.assertEqual(r['reason'],'WprUpgradeRequired');self.assertEqual(data['signals'],[])

if __name__=='__main__':unittest.main()
