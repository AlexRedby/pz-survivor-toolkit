"""WPR protocol fixtures on PowerShell/macOS; no Windows ETW/UAC claims."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent / 'optimizer_trial'
PWSH = shutil.which('pwsh')

# Verbatim stdout/stderr captured from both Windows 10.0.19041 CoreSystem
# -help advanced attempts (exit -983562750). No machine paths or identities.
WPR_19041_GENERAL_HELP = (
    '\r\nMicrosoft Windows Performance Recorder Version 10.0.19041 (CoreSystem)\r\n'
    'Copyright (c) 2019 Microsoft Corporation. All rights reserved.\r\n\r\n'
    '\tUsage: wpr options ...\r\n\r\n'
    '\t-help\t\t\t - Provide command line help information\r\n'
    '\t-profiles\t\t - Enumerates the profile names and descriptions from a profile file\r\n'
    '\t-purgecache\t\t - Purges the dynamic symbols cache\r\n'
    '\t-start\t\t\t - Starts one or more profiles\r\n'
    '\t-marker\t\t\t - Fires an event marker\r\n'
    '\t-markerflush\t\t - Fires an event marker and flushes the working set\r\n'
    '\t-status\t\t\t - Displays status on active recording (if any)\r\n'
    '\t-profiledetails\t\t - Displays the detailed information about a set of profiles\r\n'
    '\t-providers\t\t - Displays detailed information about providers\r\n'
    '\t-cancel\t\t\t - Cancels recording initiated via WPR (if any)\r\n'
    '\t-stop\t\t\t - Stops recording initiated via WPR (if any) and saves\r\n'
    '\t-flush\t\t\t - Flushes logging sessions initiated through WPR (if any)\r\n'
    '\t-log\t\t\t - Configure debug logging to the event log\r\n'
    '\t-disablepagingexecutive\t - Change the Disable Paging Executive settings\r\n'
    '\t-heaptracingconfig\t - Change heap tracing settings for a process\r\n'
    '\t-snapshotconfig\t\t - Change snapshot settings for a process\r\n'
    '\t-capturestateondemand\t - Capture states for the configured providers in the current recording\r\n'
    '\t-pmcsources\t\t - Query the list of hardware counters available on the system\r\n'
    '\t-setprofint\t\t - Set sampled profile interval\r\n'
    '\t-profint\t\t - Query the current profile interval\r\n'
    '\t-resetprofint\t\t - Restores the default profile interval values\r\n'
    '\t-boottrace\t\t - Configures the registry entries for autologger/globallogger sessions\r\n'
    '\t-enableperiodicsnapshot\t - Enable Periodic Snapshot for the specified interval and given process id\r\n'
    '\t-disableperiodicsnapshot - Disable Periodic Snapshot for all process\r\n'
    '\t-singlesnapshot\t\t - On demand Snapshot for the specified process\r\n'
    '\t-instancename\t\t - Specifies a name to uniquely identify the tracing instance. \r\n'
    '\t\t\t\t   Useful when managing multiple concurrent wpr sessions. Must be last parameter.\r\n\n'
)


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class WprProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz-wpr-')
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def run_ps(self, body, timeout=12):
        env = dict(os.environ, PZ_WPR_SCRIPTS=str(SCRIPTS), PZ_WPR_ROOT=str(self.root),
                   PZ_WPR_19041_HELP=WPR_19041_GENERAL_HELP)
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-Command', "$ErrorActionPreference='Stop'; " + body],
                                env=env, capture_output=True, text=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def worker(self, setup='', mode='success'):
        # Test only via fixed public protocol. No fake executable is used in production.
        return self.run_ps(r'''
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$global:mode=''' + "'" + mode + "'" + r'''
$run=Join-Path $env:PZ_WPR_ROOT ('a'*32); if (Test-Path $run) { Remove-Item $run -Recurse -Force }; [IO.Directory]::CreateDirectory($run) | Out-Null
$id='a'*32
$c=[ordered]@{format=1;captureId=$id;targetPid=123;processStartUtc='2026-10-26T12:00:00.0000000Z';expectedExecutable='java.exe';parentPid=456;parentStartUtc='2026-10-26T12:00:00.0000000Z';parentExecutable='powershell.exe';captureSeconds=30;prepareSeconds=900;maximumTempBytes=2147483648}
Write-TrialWprJson (Join-Path $run 'control.json') $c
$hash=(Get-FileHash (Join-Path $run 'control.json')).Hash
$s=[ordered]@{format=1;captureId=$id;instanceName=('PZTrial_'+$id);targetPid=123;processStartUtc=$c.processStartUtc;status='Requested';reason=$null;requestedUtc=[DateTime]::UtcNow.ToString('o');startRequestedUtc=$null;startedUtc=$null;stopRequestedUtc=$null;stoppedUtc=$null;helperPid=$null;helperStartUtc=$null;profiles=@('GeneralProfile','GPU');loggingMode='File';traceFile='drive.etl';traceBytes=$null;traceSha256=$null;headerValidated=$false}
Write-TrialWprJson (Join-Path $run 'wpr-status.json') $s
Write-TrialWprJson (Join-Path $run 'start.request.json') @{captureId=$id;action='start';targetPid=123;requestedUtc=[DateTime]::UtcNow.ToString('o')}
$global:commands=@()
function Get-TrialWprTool { 'fake-wpr' }
function Test-TrialWprElevated { $global:mode -ne 'not-elevated' }
function Test-TrialWprIdentity { param($ProcessId,$Executable,$StartUtc); return ($global:mode -ne 'parent-exit' -or $global:commands.Count -lt 3) }
function Get-TrialWprTempBytes { param($Root); if ($global:mode -eq 'size') { return 2147483648 }; return 0 }
function Test-TrialWprTrace { param($Path); $global:mode -ne 'invalid-trace' }
function Invoke-TrialWprCommand {
 param($Tool,$Arguments,$TimeoutSeconds)
 $global:commands+=,@($Arguments)
 $code=0; $output='ok'; $timed=$false
 switch ($Arguments[0]) {
  '-help' {
   $output='-instancename <text>'
   if ($global:mode -eq 'unsupported') { $output='old help' }
   if ($global:mode -eq 'localized-help') { $output="`t-instancename`t - Nom de l'instance de trace" }
   if ($global:mode -like 'help-*') {
    $output=$env:PZ_WPR_19041_HELP
    if ($Arguments.Count -gt 1) {
     $code=-983562750
     if ($global:mode -eq 'help-advanced-missing') { $code=0; $output='old advanced help' }
    } else {
     if ($global:mode -eq 'help-general-failure') { $code=1 }
     if ($global:mode -eq 'help-timeout') { $code=$null; $timed=$true }
     if ($global:mode -eq 'help-command-failure') { $code=$null; $output='CommandFailed' }
     if ($global:mode -eq 'help-mentioned') { $output='Error: -instancename is not supported' }
     if ($global:mode -eq 'help-option-prefix') { $output='-instancename-extra - unrelated option' }
    }
   }
  }
  '-profiledetails' {
   $output='CSwitch ReadyThread SampledProfile DPC Interrupt DiskIO HardFaults'
   if ($global:mode -eq 'coverage') { $output='SampledProfile' }
   if ($global:mode -eq 'coverage-substring') { $output='NoCSwitch ReadyThread SampledProfile DPC Interrupt DiskIO HardFaults' }
   if ($global:mode -eq 'profile-failure') { $code=1 }
   if ($global:mode -eq 'profile-timeout') { $timed=$true }
  }
  '-start' {
   if ($global:mode -eq 'start-failure') { $code=1 }
   if ($global:mode -eq 'start-timeout') { $code=$null; $timed=$true }
   if ($global:mode -notin @('parent-exit','tamper','size')) { Write-TrialWprJson (Join-Path $run 'stop.request.json') @{captureId=$id;action='stop';targetPid=123;requestedUtc=[DateTime]::UtcNow.ToString('o')} }
   if ($global:mode -eq 'tamper') { [IO.File]::AppendAllText((Join-Path $run 'control.json'),' ') }
  }
  '-status' { $output='Events Lost : 7' }
  '-stop' { [IO.File]::WriteAllBytes((Join-Path $run 'drive.etl'),[byte[]]::new(1024)); if ($global:mode -eq 'stop-failure') { $code=1 } }
 }
 [pscustomobject]@{exitCode=$code;timedOut=$timed;output=$output;elapsedMs=1}
}
''' + setup + r'''
$null=Invoke-TrialWprWorker $run $hash
@{receipt=(Read-TrialWprJson (Join-Path $run 'wpr-status.json'));commands=$global:commands} | ConvertTo-Json -Depth 14 -Compress
''')

    def test_success_records_only_owned_named_instance_and_verifiable_receipt(self):
        result = self.worker()
        receipt = result['receipt']
        self.assertEqual(receipt['status'], 'Complete')
        self.assertEqual(receipt['traceBytes'], 1024)
        self.assertEqual(len(receipt['traceSha256']), 64)
        self.assertTrue(receipt['headerValidated'])
        for field in ('requestedUtc', 'startRequestedUtc', 'startedUtc', 'stopRequestedUtc', 'stoppedUtc'):
            self.assertIsNotNone(receipt[field])
        self.assertEqual(receipt['profiles'], ['GeneralProfile', 'GPU'])
        for command in result['commands']:
            if command[0] in ('-start', '-status', '-stop', '-cancel'):
                self.assertEqual(command[-2:], ['-instancename', receipt['instanceName']])
        self.assertIn('-filemode', result['commands'][2])
        self.assertIsNone(receipt['lostEvents'])
        self.assertEqual(receipt['evidence'][-2]['result']['output'], 'Events Lost : 7')

    def test_unsupported_instance_or_coverage_never_starts_or_controls_session(self):
        for mode, reason in (('unsupported', 'NamedInstancesUnsupported'), ('coverage', 'RequiredProfileCoverageUnavailable'),
                             ('coverage-substring', 'RequiredProfileCoverageUnavailable'), ('profile-failure', 'ProfilesUnavailable'),
                             ('profile-timeout', 'ProfilesUnavailable'), ('not-elevated', 'HelperNotElevated')):
            result = self.worker(mode=mode)
            self.assertEqual(result['receipt']['status'], 'Unavailable')
            self.assertEqual(result['receipt']['reason'], reason)
            self.assertFalse(any(c[0] in ('-start', '-status', '-stop', '-cancel') for c in result['commands']))

    def test_captured_19041_help_error_falls_back_to_read_only_general_help(self):
        # The fallback response is a fixture for the documented plain -help
        # form, not a claim that Windows capture succeeded on this machine.
        result = self.worker(mode='help-19041')
        self.assertEqual(result['receipt']['status'], 'Complete')
        self.assertEqual(result['commands'][:3], [
            ['-help', 'advanced'], ['-help'], ['-profiledetails', 'GeneralProfile+GPU', '-filemode']])
        first, fallback = result['receipt']['evidence'][:2]
        self.assertEqual(first['result']['exitCode'], -983562750)
        self.assertEqual(first['result']['output'], WPR_19041_GENERAL_HELP)
        self.assertEqual(fallback['stage'], 'NamedInstanceSupportGeneralHelp')
        self.assertEqual(fallback['result']['exitCode'], 0)
        for command in result['commands'][3:]:
            self.assertEqual(command[-2:], ['-instancename', result['receipt']['instanceName']])

    def test_help_fallback_also_handles_missing_advanced_option(self):
        result = self.worker(mode='help-advanced-missing')
        self.assertEqual(result['receipt']['status'], 'Complete')
        self.assertEqual(result['commands'][1], ['-help'])

    def test_failed_timed_out_or_non_declaration_help_never_controls_sessions(self):
        for mode in ('help-general-failure', 'help-timeout', 'help-command-failure',
                     'help-mentioned', 'help-option-prefix'):
            with self.subTest(mode=mode):
                result = self.worker(mode=mode)
                self.assertEqual(result['receipt']['reason'], 'NamedInstancesUnsupported')
                self.assertEqual(result['receipt']['status'], 'Unavailable')
                self.assertEqual(result['commands'], [['-help', 'advanced'], ['-help']])

    def test_localized_help_option_description_needs_no_english_words(self):
        result = self.worker(mode='localized-help')
        self.assertEqual(result['receipt']['status'], 'Complete')
        self.assertEqual(result['commands'][:2], [
            ['-help', 'advanced'], ['-profiledetails', 'GeneralProfile+GPU', '-filemode']])

    def test_failed_or_timed_out_start_attempt_still_saves_only_owned_instance(self):
        for mode in ('start-failure', 'start-timeout'):
            result = self.worker(mode=mode)
            self.assertEqual(result['receipt']['status'], 'Incomplete')
            self.assertIsNone(result['receipt']['startedUtc'])
            self.assertTrue(any(c[0] == '-stop' for c in result['commands']))

    def test_stop_failure_never_claims_trace_identity(self):
        receipt = self.worker(mode='stop-failure')['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertIsNone(receipt['stoppedUtc'])
        self.assertIsNone(receipt['traceBytes'])
        self.assertIsNone(receipt['traceSha256'])
        self.assertFalse(receipt['headerValidated'])
        cleanup = self.worker(mode='stop-failure')['commands'][-1]
        self.assertEqual(cleanup, ['-cancel', '-instancename', receipt['instanceName']])

    def test_invalid_trace_never_claims_hash_or_complete(self):
        receipt = self.worker(mode='invalid-trace')['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertEqual(receipt['reason'], 'TraceHeaderInvalid')
        self.assertIsNotNone(receipt['stoppedUtc'])
        self.assertIsNone(receipt['traceSha256'])

    def test_parent_exit_saves_partial_trace(self):
        receipt = self.worker(mode='parent-exit')['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertEqual(receipt['stopCause'], 'ParentExited')
        self.assertTrue(receipt['headerValidated'])

    def test_modified_control_stops_owned_session_and_preserves_partial_trace(self):
        receipt = self.worker(mode='tamper')['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertEqual(receipt['stopCause'], 'ValidationFailure')
        self.assertTrue(receipt['headerValidated'])

    def test_invalid_signal_rejected_before_start(self):
        result = self.worker("Write-TrialWprJson (Join-Path $run 'start.request.json') @{captureId=('b'*32);action='start';targetPid=123;requestedUtc=[DateTime]::UtcNow.ToString('o')}")
        self.assertEqual(result['receipt']['status'], 'Unavailable')
        self.assertFalse(any(c[0] == '-start' for c in result['commands']))

    def test_large_bounded_receipt_remains_readable_and_control_limit_stays_small(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
$path=Join-Path $env:PZ_WPR_ROOT 'wpr-status.json'
Write-TrialWprJson $path @{status='Complete';evidence=('x'*180000)}
$s=Read-TrialWprJson $path
@{status=$s.status;length=$s.evidence.Length}|ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'status': 'Complete', 'length': 180000})

    def test_launcher_timeout_reports_partial_without_rewriting_helper_receipt(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
$path=Join-Path $env:PZ_WPR_ROOT 'wpr-status.json'
$s=[pscustomobject]@{status='Recording';reason=$null}
Write-TrialWprJson $path $s
$c=[pscustomobject]@{Status=$s;Worker=(Get-Process -Id $PID);StopSent=$false;LocalFailure=$null;StatusPath=$path}
function Get-TrialWprStatus { param($Context); return $Context.Status }
function Send-TrialWprRequest { }
function Wait-TrialWprState { param($Context,$States,$Seconds); return $Context.Status }
$r=Complete-TrialWprCapture $c
@{status=$r.status;reason=$r.reason;onDisk=(Read-TrialWprJson $path).status}|ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'status': 'Incomplete', 'reason': 'HelperCompletionTimeout', 'onDisk': 'Recording'})

    def test_reparse_and_oversized_control_rejected(self):
        target = self.root / 'target'; target.mkdir()
        (self.root / 'link').symlink_to(target, target_is_directory=True)
        result = self.run_ps(r'''
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
$reparse=$false; $large=$false
try { Assert-TrialWprPath (Join-Path $env:PZ_WPR_ROOT 'link/file') } catch { $reparse=$true }
$p=Join-Path $env:PZ_WPR_ROOT 'large.json'; [IO.File]::WriteAllText($p,('x'*131073))
try { Read-TrialWprJson $p } catch { $large=$true }
@{reparse=$reparse;large=$large}|ConvertTo-Json -Compress
''')
        self.assertEqual(result, {'reparse': True, 'large': True})

    def test_import_is_inert_and_optional_unavailable_preserves_target_gate(self):
        result = self.run_ps(r'''
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
function Assert-JfrTargetProcess { param($Process,$Path,$Utc); $global:gated=$true }
function Get-TrialWprTool { return $null }
$p=[pscustomobject]@{Id=123}; $plan=[pscustomobject]@{Java='java.exe';ProcessStartUtc='2026-10-26T12:00:00Z'}
$c=Initialize-TrialWprCapture $env:PZ_WPR_ROOT $p $plan
$a=Start-TrialWprCapture $c; $b=Complete-TrialWprCapture $c; $d=Stop-TrialWprCapture $c
@{gated=$global:gated;status=$d.status;reason=$d.reason;files=@(Get-ChildItem $c.Directory | ForEach-Object Name)}|ConvertTo-Json -Compress
''')
        self.assertTrue(result['gated'])
        self.assertEqual(result['status'], 'Unavailable')
        self.assertEqual(result['reason'], 'WprUnavailable')
        self.assertEqual(result['files'], ['wpr-status.json'])

    def test_command_timeout_kills_only_owned_command(self):
        executable = self.root / 'fake-wpr'
        executable.write_text('#!/bin/sh\nsleep 20\n')
        executable.chmod(0o700)
        result = self.run_ps(r'''
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
Invoke-TrialWprCommand (Join-Path $env:PZ_WPR_ROOT 'fake-wpr') @('-help','advanced') 1 | ConvertTo-Json -Compress
''')
        self.assertTrue(result['timedOut'])
        self.assertLess(result['elapsedMs'], 2500)


    def test_size_watchdog_saves_trace_but_reports_partial(self):
        receipt = self.worker(mode='size')['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertEqual(receipt['stopCause'], 'SizeWatchdog')
        self.assertTrue(receipt['headerValidated'])

    def test_live_process_identity_rejects_wrong_path_and_reused_pid_time(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$p=Get-Process -Id $PID
@{actual=(Test-TrialWprIdentity $PID $p.Path ($p.StartTime.ToUniversalTime()));wrongPath=(Test-TrialWprIdentity $PID ($p.Path+'.other') $p.StartTime);wrongTime=(Test-TrialWprIdentity $PID $p.Path ($p.StartTime.AddSeconds(-1)))} | ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'actual': True, 'wrongPath': False, 'wrongTime': False})

    def test_uac_decline_is_optional_and_has_no_capture_requests(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
function Get-TrialWprSystemDirectory { $env:PZ_WPR_ROOT }
function Assert-JfrTargetProcess { }
function Get-TrialWprTool { 'fake-wpr' }
function Start-Process { throw 'UAC declined fixture' }
$p=[pscustomobject]@{Id=123}; $plan=[pscustomobject]@{Java=(Join-Path $env:PZ_WPR_ROOT 'java.exe');ProcessStartUtc=[DateTime]::UtcNow.ToString('o')}
$c=Initialize-TrialWprCapture $env:PZ_WPR_ROOT $p $plan
@{status=$c.Status.status;reason=$c.Status.reason;files=@(Get-ChildItem $c.Directory | ForEach-Object Name)} | ConvertTo-Json -Compress
""")
        self.assertEqual(result['status'], 'Unavailable')
        self.assertEqual(result['reason'], 'HelperStartFailedOrUacDeclined')
        self.assertEqual(result['files'], ['control.json', 'wpr-status.json'])

    def test_helper_receipts_and_start_stop_are_idempotent_and_target_gated(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
function Get-TrialWprSystemDirectory { $env:PZ_WPR_ROOT }; $global:gates=0; $global:verb=$null
function Assert-JfrTargetProcess { $global:gates++ }
function Get-TrialWprTool { 'fake-wpr' }
function Start-Process {
 param($FilePath,$ArgumentList,$Verb,$WindowStyle,[switch]$PassThru,$ErrorAction)
 $global:verb=$Verb
 $w=Get-Process -Id $PID
 $s=Read-TrialWprJson $context.StatusPath
 $s.helperPid=$PID; $s.helperStartUtc=$w.StartTime.ToUniversalTime().ToString('o'); $s.status='Ready'
 Write-TrialWprJson $context.StatusPath $s
 return $w
}
function Wait-TrialWprState {
 param($Context,$States,$Seconds)
 $s=Read-TrialWprJson $Context.StatusPath
 if (Test-Path (Join-Path $Context.Directory 'start.request.json')) { $s.status='Recording' }
 if (Test-Path (Join-Path $Context.Directory 'stop.request.json')) { $s.status='Complete' }
 Write-TrialWprJson $Context.StatusPath $s
 return (Get-TrialWprStatus $Context)
}
$p=[pscustomobject]@{Id=123}; $plan=[pscustomobject]@{Java=(Join-Path $env:PZ_WPR_ROOT 'java.exe');ProcessStartUtc='2026-10-26T12:00:00Z';WprDurationSeconds=999}
$c=Initialize-TrialWprCapture $env:PZ_WPR_ROOT $p $plan
$ready=$c.Status.status
$null=Start-TrialWprCapture $c; $start=(Get-Item (Join-Path $c.Directory 'start.request.json')).LastWriteTimeUtc.Ticks
$null=Start-TrialWprCapture $c; $null=Complete-TrialWprCapture $c
$stop=(Get-Item (Join-Path $c.Directory 'stop.request.json')).LastWriteTimeUtc.Ticks
$null=Complete-TrialWprCapture $c; $null=Stop-TrialWprCapture $c
$s=Read-TrialWprJson $c.StatusPath; $s.status='Forged'; $s.helperPid=999999; Write-TrialWprJson $c.StatusPath $s
$final=Get-TrialWprStatus $c
@{ready=$ready;final=$final.status;gates=$global:gates;verb=$global:verb;startUnchanged=($start -eq (Get-Item (Join-Path $c.Directory 'start.request.json')).LastWriteTimeUtc.Ticks);stopUnchanged=($stop -eq (Get-Item (Join-Path $c.Directory 'stop.request.json')).LastWriteTimeUtc.Ticks);bound=(Read-TrialWprJson (Join-Path $c.Directory 'control.json')).captureSeconds} | ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'ready': 'Ready', 'final': 'Complete', 'gates': 2, 'verb': 'RunAs', 'startUnchanged': True, 'stopUnchanged': True, 'bound': 240})

    def test_trace_header_rejects_absent_empty_or_short_files_before_native_call(self):
        result = self.run_ps(r'''
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$p=Join-Path $env:PZ_WPR_ROOT 'short.etl'
$a=Test-TrialWprTrace $p; [IO.File]::WriteAllBytes($p,[byte[]]::new(512)); $b=Test-TrialWprTrace $p
@{absent=$a;short=$b}|ConvertTo-Json -Compress
''')
        self.assertEqual(result, {'absent': False, 'short': False})


if __name__ == '__main__':
    unittest.main()
