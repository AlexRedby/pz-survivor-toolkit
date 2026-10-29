"""WPR protocol fixtures on PowerShell/macOS; no Windows ETW/UAC claims."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

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


# Verbatim advanced-help stdout from Windows ADK WPR 10.0.26100.
# Successful exit 0, without machine paths or identities.
WPR_26100_ADVANCED_HELP = (
    '\r\n'
    '  wpr -purgecache \tPurges the dynamic symbols cache.\r\n'
    '\tUsage:\twpr -purgecache\r\n'
    '\r\n'
    '  wpr -log \tConfigure debug logging to the event log.\r\n'
    '\tUsage:\twpr -log {enabled|disabled|remove}\r\n'
    '\r\n'
    '  wpr -disablepagingexecutive ...\tTurns Disable Paging Executive settings On or Off.\r\n'
    '\tUsage:\twpr -disablepagingexecutive {on/off}\r\n'
    '\r\n'
    '  wpr [command] -instancename ...\tRun command with user specified instance name.\r\n'
    '\tUsage:\twpr <command> -instancename <instance name>\r\n'
    '\tCan be applied to any commands that manipulates the logging session.\r\n'
    '\tUser can control multiple sessions by specifying unique instance name.\r\n'
    '\tIf the logging session was started with this option, all the subsequent\r\n'
    '\tcommands should use the same instance name option. Must be the last parameter.\r\n'
    '\r\n'
    '  wpr [command] -container ...\tRun command in container\r\n'
    '\tUsage:\twpr <command> -container [<ID>...[up to 64 IDs] [-host]]\r\n'
    '\t-host\tThe command is applied to the host as well as the container\r\n'
    '\tSupported Container Commands:\r\n'
    '\t\t-Start\tStart Trace Collection  (see wpr -help start)\r\n'
    '\t\t-Stop\tStop Trace Collection   (see wpr -help stop)\r\n'
    '\t\t-Cancel\tCancel Trace Collection (see wpr -help cancel)\r\n'
    '\t\t-Status\tQuery Status Trace Collection (see wpr -help status)\r\n'
    '\t\t-Flush\tFlush Trace Collection (see wpr -help flush)\r\n'
    '\n'
)


class WprProfileTests(unittest.TestCase):
    def test_profile_retains_scheduler_edges_with_only_sampled_cpu_stacks(self):
        root = ET.parse(SCRIPTS / 'PZTrial.wprp').getroot()
        keywords = {node.attrib['Value'] for node in root.findall('./Profiles/SystemProvider/Keywords/Keyword')}
        self.assertTrue({'CSwitch', 'ReadyThread', 'SampledProfile', 'DPC', 'Interrupt',
                         'DiskIO', 'HardFaults', 'ProcessThread', 'Loader'} <= keywords)
        self.assertEqual({node.attrib['Value'] for node in root.findall('./Profiles/SystemProvider/Stacks/Stack')},
                         {'SampledProfile'})
        providers = root.findall('./Profiles/EventProvider')
        self.assertEqual(len(providers), 3)
        self.assertTrue(all(node.attrib['Stack'] == 'false' for node in providers))
        self.assertEqual({node.attrib['LoggingMode'] for node in root.findall('./Profiles/Profile')}, {'File', 'Memory'})
        self.assertEqual(sum(int(node.find('BufferSize').attrib['Value']) * int(node.find('Buffers').attrib['Value'])
                             for node in root.findall('./Profiles/SystemCollector') + root.findall('./Profiles/EventCollector')), 32768)


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class WprProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz-wpr-')
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def run_ps(self, body, timeout=12):
        env = dict(os.environ, PZ_WPR_SCRIPTS=str(SCRIPTS), PZ_WPR_ROOT=str(self.root),
                   PZ_WPR_19041_HELP=WPR_19041_GENERAL_HELP,
                   PZ_WPR_26100_HELP=WPR_26100_ADVANCED_HELP)
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
$c=[ordered]@{toolPath=(Join-Path $env:PZ_WPR_ROOT 'fake-wpr');toolSource='System';toolSha256=('a'*64);profileSha256=(Get-TrialWprProfile).Sha256;format=1;captureId=$id;targetPid=123;processStartUtc='2026-10-26T12:00:00.0000000Z';expectedExecutable='java.exe';parentPid=456;parentStartUtc='2026-10-26T12:00:00.0000000Z';parentExecutable='powershell.exe';captureSeconds=30;prepareSeconds=900;maximumTempBytes=2147483648}
Write-TrialWprJson (Join-Path $run 'control.json') $c
$hash=(Get-FileHash (Join-Path $run 'control.json')).Hash
$s=[ordered]@{format=1;captureId=$id;instanceName=('PZTrial_'+$id);targetPid=123;processStartUtc=$c.processStartUtc;status='Requested';reason=$null;requestedUtc=[DateTime]::UtcNow.ToString('o');startRequestedUtc=$null;startedUtc=$null;stopRequestedUtc=$null;stoppedUtc=$null;helperPid=$null;helperStartUtc=$null;profiles=@('PZTrial.light');loggingMode='File';traceFile='drive.etl';traceBytes=$null;traceSha256=$null;headerValidated=$false}
Write-TrialWprJson (Join-Path $run 'wpr-status.json') $s
Write-TrialWprJson (Join-Path $run 'start.request.json') @{captureId=$id;action='start';targetPid=123;requestedUtc=[DateTime]::UtcNow.ToString('o')}
$global:commands=@(); $global:collectorQueries=@()
function Get-TrialWprToolSelection { [pscustomobject]@{Selected=[pscustomobject]@{Path=(Join-Path $env:PZ_WPR_ROOT 'fake-wpr');Source='System';Sha256=('a'*64);Version='10.0.26100.1'};Candidates=@();Reason=$null} }
function Get-TrialWprToolMetadata { param($Path,$Source); [pscustomobject]@{Path=$Path;Source=$Source;Sha256=('a'*64);Eligible=$true} }
function Test-TrialWprElevated { $global:mode -ne 'not-elevated' }
function Test-TrialWprIdentity { param($ProcessId,$Executable,$StartUtc); return ($global:mode -ne 'parent-exit' -or $global:commands.Count -lt 3) }
function Get-TrialWprTempBytes { param($Root); if ($global:mode -eq 'size') { return 2147483648 }; return 0 }
function Get-TrialWprCollectorQueryCode {
 param($Name)
 $global:collectorQueries+=@($Name)
 if ($global:mode -eq 'cleanup-active' -and $Name.EndsWith('Graphics')) { return 0 }
 if ($global:mode -eq 'cleanup-unknown') { return 5 }
 return 4201
}
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
   if ($global:mode -like 'adk-help*') {
    $output=$env:PZ_WPR_26100_HELP
    if ($global:mode -eq 'adk-help-failure') { $code=1 }
    if ($global:mode -eq 'adk-help-timeout') { $timed=$true }
    if ($global:mode -eq 'adk-help-mentioned') { $output='Error: wpr [command] -instancename is not supported' }
    if ($global:mode -eq 'adk-help-command-token') { $output=$output.Replace('[command]', '[profile]').Replace('<command>', '<profile>') }
    if ($global:mode -eq 'adk-help-command-prefix') { $output=$output.Replace('wpr ', 'otherwpr ') }
    if ($global:mode -eq 'adk-help-option-suffix') { $output=$output.Replace('-instancename', '-instancename-extra') }
   }
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
   $output='CSwitch ReadyThread SampledProfile DPC Interrupt DiskIO HardFaults Microsoft-Windows-DxgKrnl Microsoft-Windows-DXGI 9e9bba3c-2e38-40cb-99f4-9e8281425164'
   if ($global:mode -eq 'coverage') { $output='SampledProfile' }
   if ($global:mode -eq 'coverage-substring') { $output='NoCSwitch ReadyThread SampledProfile DPC Interrupt DiskIO HardFaults' }
   if ($global:mode -eq 'graphics-guids') { $output='CSwitch ReadyThread SampledProfile DPC Interrupt DiskIO HardFaults {802EC45A-1E99-4B83-9920-87C98277BA9D} {CA11C036-0102-4A2D-A6AD-F03CFED5D3C9} Microsoft-Windows-Dwm-Core' }
   if ($global:mode -eq 'graphics-coverage') { $output='CSwitch ReadyThread SampledProfile DPC Interrupt DiskIO HardFaults' }
   if ($global:mode -eq 'profile-command-failure') { $code=$null }
   if ($global:mode -eq 'profile-failure') { $code=1 }
   if ($global:mode -eq 'profile-timeout') { $timed=$true }
  }
  '-start' {
   if ($global:mode -eq 'start-failure') { $code=1 }
   if ($global:mode -in @('start-timeout','start-timeout-cleanup')) { $code=$null; $timed=$true }
   if ($global:mode -notin @('parent-exit','tamper','size')) { Write-TrialWprJson (Join-Path $run 'stop.request.json') @{captureId=$id;action='stop';targetPid=123;requestedUtc=[DateTime]::UtcNow.ToString('o')} }
   if ($global:mode -eq 'tamper') { [IO.File]::AppendAllText((Join-Path $run 'control.json'),' ') }
  }
  '-status' {
   $output="Nom collecteur : WPR_initiated_PZTrial_$($id)_System`nNom collecteur : WPR_initiated_PZTrial_$($id)_Graphics`nEvents Lost : 7"
   if ($global:mode -eq 'no-collector-names') { $output='Events Lost : 7' }
   if ($global:mode -eq 'status-failure') { $code=1 }
   if ($global:mode -eq 'status-timeout') { $code=$null; $timed=$true }
   if ($global:mode -eq 'status-command-failure') { $code=$null; $output='CommandFailed' }
   if ($global:mode -in @('profile-absent','observed-error') -and @($global:commands | Where-Object { $_[0] -eq '-cancel' }).Count -gt 0) { $code=-984076288; $output='Aucun profil actif' }
  }
  '-cancel' {
   if ($global:mode -in @('observed-error','profile-absent','no-collector-names','status-failure','status-timeout','status-command-failure','start-timeout-cleanup')) { $code=-984076288; $output='There are no trace profiles running.' }
   if ($global:mode -eq 'unrelated-cancel-error') { $code=5; $output='There are no trace profiles running.' }
  }
  '-stop' { [IO.File]::WriteAllBytes((Join-Path $run 'drive.etl'),[byte[]]::new(1024)); if ($global:mode -in @('stop-failure','observed-error','profile-absent','cleanup-active','cleanup-unknown','no-collector-names','status-failure','status-timeout','status-command-failure','unrelated-cancel-error','start-timeout-cleanup')) { $code=-2147417850; $output='Cannot change thread mode after it is set. Error code: 0x80010106' } }
 }
 [pscustomobject]@{exitCode=$code;timedOut=$timed;output=$output;elapsedMs=1}
}
''' + setup + r'''
$null=Invoke-TrialWprWorker $run $hash
@{receipt=(Read-TrialWprJson (Join-Path $run 'wpr-status.json'));commands=$global:commands;collectorQueries=$global:collectorQueries} | ConvertTo-Json -Depth 14 -Compress
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
        self.assertEqual(receipt['profiles'], ['PZTrial.light'])
        for command in result['commands']:
            if command[0] in ('-start', '-status', '-stop', '-cancel'):
                self.assertEqual(command[-2:], ['-instancename', receipt['instanceName']])
        self.assertIn('-filemode', result['commands'][2])
        self.assertIsNone(receipt['lostEvents'])
        self.assertIn('Events Lost : 7', next(e['result']['output'] for e in receipt['evidence'] if e['stage']=='CollectorsBeforeStop'))
        self.assertEqual(receipt['cleanupState'], 'Absent')

    def test_unsupported_instance_or_coverage_never_starts_or_controls_session(self):
        for mode, reason in (('unsupported', 'NamedInstancesUnsupported'), ('coverage', 'RequiredProfileCoverageUnavailable'),
                             ('coverage-substring', 'RequiredProfileCoverageUnavailable'), ('profile-failure', 'ProfilesUnavailable'),
                             ('profile-timeout', 'ProfilesUnavailable'), ('profile-command-failure', 'ProfilesUnavailable'),
                             ('graphics-coverage', 'RequiredGraphicsCoverageUnavailable'), ('not-elevated', 'HelperNotElevated')):
            result = self.worker(mode=mode)
            self.assertEqual(result['receipt']['status'], 'Unavailable')
            self.assertEqual(result['receipt']['reason'], reason)
            self.assertFalse(any(c[0] in ('-start', '-status', '-stop', '-cancel') for c in result['commands']))

    def test_captured_26100_advanced_help_starts_and_saves_without_general_help(self):
        result = self.worker(mode='adk-help')
        receipt = result['receipt']
        self.assertEqual(receipt['status'], 'Complete')
        self.assertEqual(receipt['traceBytes'], 1024)
        self.assertTrue(receipt['headerValidated'])
        self.assertEqual(result['commands'][:2], [
            ['-help', 'advanced'], ['-profiledetails', str(SCRIPTS / 'PZTrial.wprp') + '!PZTrial.light', '-filemode']])
        self.assertNotIn(['-help'], result['commands'])
        self.assertEqual(receipt['evidence'][0]['stage'], 'NamedInstanceSupport')
        self.assertEqual(receipt['evidence'][0]['result']['output'], WPR_26100_ADVANCED_HELP)
        self.assertEqual(receipt['evidence'][0]['result']['exitCode'], 0)
        self.assertNotIn('NamedInstanceSupportGeneralHelp', [entry['stage'] for entry in receipt['evidence']])
        self.assertTrue(any(command[0] == '-start' for command in result['commands']))
        self.assertTrue(any(command[0] == '-stop' for command in result['commands']))
        for command in result['commands']:
            if command[0] in ('-start', '-status', '-stop', '-cancel'):
                self.assertEqual(command[-2:], ['-instancename', receipt['instanceName']])

    def test_failed_or_non_declaration_adk_help_never_controls_sessions(self):
        for mode in ('adk-help-failure', 'adk-help-timeout', 'adk-help-mentioned',
                     'adk-help-command-token', 'adk-help-command-prefix', 'adk-help-option-suffix'):
            with self.subTest(mode=mode):
                result = self.worker(mode=mode)
                self.assertEqual(result['receipt']['reason'], 'NamedInstancesUnsupported')
                self.assertEqual(result['receipt']['status'], 'Unavailable')
                self.assertEqual(result['commands'], [['-help', 'advanced'], ['-help']])
                self.assertFalse(result['collectorQueries'])

    def test_captured_19041_help_error_falls_back_to_read_only_general_help(self):
        # The fallback response is a fixture for the documented plain -help
        # form, not a claim that Windows capture succeeded on this machine.
        result = self.worker(mode='help-19041')
        self.assertEqual(result['receipt']['status'], 'Complete')
        self.assertEqual(result['commands'][:3], [
            ['-help', 'advanced'], ['-help'], ['-profiledetails', str(SCRIPTS / 'PZTrial.wprp') + '!PZTrial.light', '-filemode']])
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

    def test_profile_graphics_coverage_accepts_guids_or_resolved_friendly_names(self):
        self.assertEqual(self.worker(mode='graphics-guids')['receipt']['status'], 'Complete')

    def test_truncated_status_never_supplies_owned_collector_identities(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$id='PZTrial_'+('a'*32)
$r=@{exitCode=0;timedOut=$false;outputTruncated=$true;output=('Collecteur : WPR_initiated_'+$id+'_System')}
@{names=@(Get-TrialWprOwnedCollectors $r $id)}|ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'names': []})

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
            ['-help', 'advanced'], ['-profiledetails', str(SCRIPTS / 'PZTrial.wprp') + '!PZTrial.light', '-filemode']])

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
        cleanup = next(c for c in self.worker(mode='stop-failure')['commands'] if c[0] == '-cancel')
        self.assertEqual(cleanup, ['-cancel', '-instancename', receipt['instanceName']])

    def test_observed_com_save_error_is_preserved_when_owned_collectors_are_absent(self):
        result = self.worker(mode='observed-error')
        receipt = result['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertEqual(receipt['reason'], 'OwnedSessionSaveFailed')
        self.assertEqual(receipt['saveFailure'], 'OwnedSessionSaveFailed')
        self.assertEqual(receipt['cleanupState'], 'Absent')
        self.assertEqual(receipt['profileState'], 'Absent')
        evidence = {entry['stage']: entry['result'] for entry in receipt['evidence']}
        self.assertEqual(evidence['Stop']['exitCode'], -2147417850)
        self.assertEqual(evidence['OwnedSessionCleanup']['exitCode'], -984076288)
        self.assertTrue(result['collectorQueries'])
        self.assertTrue(all(name.startswith('WPR_initiated_' + receipt['instanceName'] + '_')
                            for name in result['collectorQueries']))
        self.assertIn(['-status', 'collectors', '-details', '-instancename', receipt['instanceName']], result['commands'])
        self.assertFalse(receipt['headerValidated'])

    def test_profile_absence_and_cleanup_state_are_separate_from_save_failure(self):
        for mode, cleanup in (('profile-absent', 'Absent'), ('cleanup-active', 'Active'),
                              ('cleanup-unknown', 'Unknown'), ('no-collector-names', 'Unknown'),
                              ('status-failure', 'Unknown'), ('status-timeout', 'Unknown'),
                              ('status-command-failure', 'Unknown')):
            with self.subTest(mode=mode):
                result = self.worker(mode=mode)
                self.assertEqual(result['receipt']['reason'], 'OwnedSessionSaveFailed')
                self.assertEqual(result['receipt']['cleanupState'], cleanup)
                if mode == 'profile-absent':
                    self.assertEqual(result['receipt']['profileState'], 'Absent')
                if mode in ('no-collector-names', 'status-failure', 'status-timeout', 'status-command-failure'):
                    self.assertFalse(result['collectorQueries'])

    def test_start_timeout_with_failed_save_still_cleans_only_verified_owned_collectors(self):
        result = self.worker(mode='start-timeout-cleanup')
        receipt = result['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertIsNone(receipt['startedUtc'])
        self.assertFalse(receipt['headerValidated'])
        self.assertEqual(receipt['cleanupState'], 'Absent')
        self.assertTrue(result['collectorQueries'])
        for command in result['commands']:
            if command[0] in ('-start', '-stop', '-cancel', '-status'):
                self.assertEqual(command[-2:], ['-instancename', receipt['instanceName']])

    def test_changed_profile_hash_prevents_start(self):
        for setup in (
            "$c.profileSha256='b'*64; Write-TrialWprJson (Join-Path $run 'control.json') $c; $hash=(Get-FileHash (Join-Path $run 'control.json')).Hash",
            r"""$global:profileReads=0; $global:realProfile=Get-TrialWprProfile
function Get-TrialWprProfile { $global:profileReads++; $p=$global:realProfile | Select-Object *; if ($global:profileReads -gt 1) { $p.Sha256='b'*64 }; return $p }""",
        ):
            result = self.worker(setup)
            self.assertEqual(result['receipt']['reason'], 'ProfileIdentityChanged')
            self.assertEqual(result['receipt']['status'], 'Unavailable')
            self.assertFalse(any(c[0] in ('-start', '-stop', '-cancel', '-status') for c in result['commands']))

    def test_native_owned_collector_query_interop_compiles_without_invoking_etw(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$definition=(Get-Command Get-TrialWprCollectorQueryCode).ScriptBlock.ToString()
$source=[regex]::Match($definition,"(?s)@'(.*?)'@").Groups[1].Value
Add-Type -TypeDefinition $source -ErrorAction Stop
@{compiled=($null -ne ('PZTrialEtw.Collector' -as [type]));query=($null -ne [PZTrialEtw.Collector].GetMethod('Query'))}|ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'compiled': True, 'query': True})

    def test_no_profile_hresult_does_not_parse_localized_or_unrelated_error_prose(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
@{localized=(Test-TrialWprNoProfiles @{exitCode=-984076288;timedOut=$false;output='Aucun profil'});
 unrelated=(Test-TrialWprNoProfiles @{exitCode=5;timedOut=$false;output='There are no trace profiles running.'});
 unknown=(Test-TrialWprNoProfiles @{exitCode=$null;timedOut=$false;output='There are no trace profiles running.'});
 timeout=(Test-TrialWprNoProfiles @{exitCode=-984076288;timedOut=$true;output=''})} | ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'localized': True, 'unrelated': False, 'unknown': False, 'timeout': False})

    def test_collector_identity_parser_rejects_other_instances_and_malformed_names(self):
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$id='PZTrial_'+('a'*32)
$text="Collecteur : WPR_initiated_$($id)_System`nCollecteur : WPR_initiated_PZTrial_$('b'*32)_Graphics`nError : prefix WPR_initiated_$($id)_Other`nCollecteur : WPR_initiated_$($id)_Bad:Name`nCollecteur : WPR_initiated_$($id)_$('X'*129)"
$r=@{exitCode=0;timedOut=$false;output=$text}
$names=@(Get-TrialWprOwnedCollectors $r $id)
$r.exitCode=5; $failed=@(Get-TrialWprOwnedCollectors $r $id)
$global:queries=0
function Get-TrialWprCollectorQueryCode { $global:queries++; return 4201 }
$invalid=Get-TrialWprCollectorState @('unrelated logger') $id
@{names=$names;failed=$failed;invalid=$invalid.state;queries=$global:queries}|ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'names': ['WPR_initiated_PZTrial_' + 'a'*32 + '_System'],
                                  'failed': [], 'invalid': 'Unknown', 'queries': 0})

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
function Get-TrialWprToolSelection { [pscustomobject]@{Selected=$null;Candidates=@();Reason='WprUnavailable'} }
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


    def test_command_output_cap_marks_truncation_instead_of_trusting_partial_names(self):
        executable = self.root / 'fake-wpr'
        executable.write_text('#!/bin/sh\n/usr/bin/yes x | /usr/bin/head -c 20000\n')
        executable.chmod(0o700)
        result = self.run_ps(r"""
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprWorker.ps1')
$r=Invoke-TrialWprCommand (Join-Path $env:PZ_WPR_ROOT 'fake-wpr') @('-status')
@{length=$r.output.Length;truncated=$r.outputTruncated;code=$r.exitCode}|ConvertTo-Json -Compress
""")
        self.assertEqual(result, {'length': 8192, 'truncated': True, 'code': 0})

    def test_size_watchdog_saves_trace_but_reports_partial(self):
        receipt = self.worker(mode='size')['receipt']
        self.assertEqual(receipt['status'], 'Incomplete')
        self.assertEqual(receipt['stopCause'], 'SizeWatchdog')
        self.assertEqual(receipt['observedTempBytes'], 2147483648)
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
function Get-TrialWprToolSelection { [pscustomobject]@{Selected=[pscustomobject]@{Path=(Join-Path $env:PZ_WPR_ROOT 'fake-wpr');Source='System';Sha256=('a'*64);Version='10.0.26100.1'};Candidates=@();Reason=$null} }
function Get-TrialWprToolMetadata { param($Path,$Source); [pscustomobject]@{Path=$Path;Source=$Source;Sha256=('a'*64);Eligible=$true} }
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
function Get-TrialWprToolSelection { [pscustomobject]@{Selected=[pscustomobject]@{Path=(Join-Path $env:PZ_WPR_ROOT 'fake-wpr');Source='System';Sha256=('a'*64);Version='10.0.26100.1'};Candidates=@();Reason=$null} }
function Get-TrialWprToolMetadata { param($Path,$Source); [pscustomobject]@{Path=$Path;Source=$Source;Sha256=('a'*64);Eligible=$true} }
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

    def test_header_validation_exception_after_stop_still_cleans_owned_instance(self):
        result = self.worker("function Test-TrialWprTrace { param($Path); throw 'fixture header API failure' }")
        self.assertEqual(result['receipt']['status'], 'Incomplete')
        self.assertEqual(result['receipt']['reason'], 'OwnedSessionSaveOrValidationFailed')
        self.assertEqual(result['receipt']['cleanupState'], 'Absent')
        self.assertTrue(any(c[0]=='-cancel' for c in result['commands']))

    def test_successful_stop_with_active_or_unknown_collector_still_cleans_owned_instance(self):
        for code, expected in ((0, 'Active'), (5, 'Unknown')):
            result = self.worker("function Get-TrialWprCollectorQueryCode { param($Name); return " + str(code) + " }")
            self.assertEqual(result['receipt']['status'], 'Incomplete')
            self.assertEqual(result['receipt']['reason'], 'OwnedCollectorAbsenceUnverified')
            self.assertEqual(result['receipt']['cleanupState'], expected)
            cancel = [c for c in result['commands'] if c[0]=='-cancel']
            self.assertEqual(cancel, [['-cancel','-instancename',result['receipt']['instanceName']]])

    def test_replaced_or_ineligible_tool_never_executes_session_commands(self):
        for expression in ("$false", "$true"):
            setup = "function Get-TrialWprToolMetadata { param($Path,$Source); [pscustomobject]@{Path=$Path;Source=$Source;Sha256=('b'*64);Eligible=" + expression + "} }"
            result = self.worker(setup)
            self.assertEqual(result['receipt']['reason'], 'WprToolIdentityChanged')
            self.assertEqual(result['commands'], [])

    def test_tool_replaced_while_waiting_for_start_never_starts(self):
        result = self.worker("$global:checks=0; function Get-TrialWprToolMetadata { param($Path,$Source); $global:checks++; [pscustomobject]@{Path=$Path;Source=$Source;Sha256=$(if($global:checks -eq 1){'a'*64}else{'b'*64});Eligible=$true} }")
        self.assertEqual(result['receipt']['reason'], 'WprToolIdentityChanged')
        self.assertFalse(any(c[0] in ('-start','-stop','-cancel') for c in result['commands']))

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
