"""Portable PowerShell storage-report protocol checks; no Windows hardware claim."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tests/optimizer_trial/TrialStorage.ps1'
PWSH = shutil.which('pwsh')


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class TrialStorageTests(unittest.TestCase):
    def invoke(self, body):
        with tempfile.TemporaryDirectory(prefix='pz-storage-') as directory:
            harness = Path(directory) / 'fixture.ps1'
            harness.write_text("""
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. $env:PZ_STORAGE_SCRIPT
$env:USERPROFILE='C:\\Users\\private-test-profile'
""" + body + '\n$result | ConvertTo-Json -Depth 20 -Compress\n')
            run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness)],
                                 env=dict(os.environ, PZ_STORAGE_SCRIPT=str(SCRIPT), PZ_STORAGE_FIXTURE_ROOT=directory,
                                          TMPDIR=directory, TEMP=directory, TMP=directory),
                                 capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            return json.loads(run.stdout)

    def providers(self):
        return r"""
function Initialize-TrialStorageNative {return $null}
$script:diskCalls=@{}
function Read-TrialStorageDisk([uint32]$Number) {
    $key=[string]$Number
    if (-not $script:diskCalls.ContainsKey($key)) {$script:diskCalls[$key]=0}
    $script:diskCalls[$key]++
    return [pscustomobject]@{Status='Available';Model=('model-'+$Number);FriendlyName=('disk-'+$Number);BusType='NVMe';Reason=$null;SerialNumber='PRIVATE_SERIAL';UniqueId='PRIVATE_UNIQUE';PSComputerName='PRIVATE_HOST';MediaType='HDD'}
}
function Read-TrialStoragePath([string]$Path) {
    $number=0; $final=$Path
    if ($Path -eq 'C:\selected\mod') {$number=2;$final='D:\mod'}
    if ($Path -eq 'C:\workshop') {$number=5;$final='E:\workshop'}
    return [pscustomobject]@{FinalPath=$final;ResolutionStatus='Available';MappingStatus='Available';DiskNumbers=@($number);Reason=$null;VolumeGuid='PRIVATE_VOLUME'}
}
"""

    def test_selected_and_runtime_paths_stay_distinct_and_follow_provider_mapping(self):
        result = self.invoke(self.providers() + r"""
$result=Get-TrialStorageReportInline -Paths @(
    @{Role='Game';Id='game';Path='C:\game'},
    @{Role='Workshop';Id='workshop';Path='C:\workshop'},
    @{Role='SelectedSource';Id='example';Path='C:\selected\mod'},
    @{Role='RuntimeSource';Id='example';Path='C:\cache\mods\example'})
""")
        self.assertEqual(result['Format'], 1)
        rows = result['Paths']
        self.assertEqual([r['Role'] for r in rows], ['Game', 'Workshop', 'SelectedSource', 'RuntimeSource'])
        self.assertEqual([r['Disks'][0]['Number'] for r in rows], [0, 5, 2, 0])
        self.assertEqual(rows[1]['FinalPath'], r'E:\workshop')
        self.assertEqual(rows[2]['Id'], rows[3]['Id'])
        self.assertNotEqual(rows[2]['FinalPath'], rows[3]['FinalPath'])
        self.assertEqual(set(rows[2]['Disks'][0]), {'Number', 'Status', 'Model', 'FriendlyName', 'BusType', 'MediaType', 'MediaTypeReason', 'Reason'})
        encoded = json.dumps(result)
        for private in ('PRIVATE_SERIAL', 'PRIVATE_UNIQUE', 'PRIVATE_HOST', 'PRIVATE_VOLUME'):
            self.assertNotIn(private, encoded)
        for row in rows:
            self.assertEqual(row['Disks'][0]['MediaType'], 'Unknown')
            self.assertEqual(row['Disks'][0]['MediaTypeReason'], 'NoProvenPhysicalMediaAssociation')

    def test_multi_disk_volume_is_not_collapsed_and_metadata_is_reused(self):
        result = self.invoke(self.providers() + r"""
function Read-TrialStoragePath([string]$Path) {
    return @{FinalPath=$Path;ResolutionStatus='Available';MappingStatus='Available';DiskNumbers=@(4,2,4);Reason=$null}
}
$report=Get-TrialStorageReportInline -Paths @(@{Role='Game';Path='C:\game'},@{Role='RuntimeSource';Path='C:\mods'})
$result=@{report=$report;calls=$script:diskCalls}
""")
        self.assertEqual(result['calls'], {'2': 1, '4': 1})
        for row in result['report']['Paths']:
            self.assertEqual([d['Number'] for d in row['Disks']], [2, 4])

    def test_failures_are_per_path_and_do_not_serialize_exception_messages(self):
        result = self.invoke(self.providers() + r"""
function Read-TrialStoragePath([string]$Path) {
    if ($Path -eq 'C:\bad') {throw 'PRIVATE_HOST PRIVATE_SERIAL C:\Users\private-test-profile'}
    return @{FinalPath=$Path;ResolutionStatus='Available';MappingStatus='Available';DiskNumbers=@(7);Reason=$null}
}
function Read-TrialStorageDisk([uint32]$Number) {throw 'PRIVATE_UNIQUE'}
$result=Get-TrialStorageReportInline -Paths @(@{Role='Game';Path='C:\bad'},@{Role='Workshop';Path='C:\valid'})
""")
        self.assertEqual([r['Reason'] for r in result['Paths']], ['StorageProbeUnavailable', 'StorageProbeUnavailable'])
        self.assertNotIn('PRIVATE_', json.dumps(result))
        self.assertNotIn('private-test-profile', json.dumps(result))

    def test_disk_metadata_failure_keeps_proven_volume_mapping(self):
        result = self.invoke(self.providers() + r"""
function Get-Disk {throw 'PRIVATE_SERIAL'}
# Exercise the production disk-provider failure projection, rather than a throwing replacement.
. $env:PZ_STORAGE_SCRIPT
function Initialize-TrialStorageNative {return $null}
function Read-TrialStoragePath([string]$Path) {return @{FinalPath=$Path;ResolutionStatus='Available';MappingStatus='Available';DiskNumbers=@(7);Reason=$null}}
$result=Get-TrialStorageReportInline -Paths @(@{Role='Game';Path='C:\game'})
""")
        row = result['Paths'][0]
        self.assertEqual(row['MappingStatus'], 'Available')
        self.assertEqual(row['Disks'][0]['Number'], 7)
        self.assertEqual(row['Disks'][0]['Status'], 'Unavailable')
        self.assertIsNone(row['Disks'][0]['Model'])
        self.assertEqual(row['Disks'][0]['Reason'], 'DiskMetadataUnavailable')
        self.assertNotIn('PRIVATE_', json.dumps(result))

    def test_home_network_and_volume_identity_redaction(self):
        result = self.invoke(self.providers() + r"""
$script:pathCalls=0
function Read-TrialStoragePath([string]$Path) {
    $script:pathCalls++
    $final=$Path
    if ($Path -eq 'C:\junction') {$final='\\private-host\private-share\game'}
    return @{FinalPath=$final;ResolutionStatus='Available';MappingStatus='Available';DiskNumbers=@(0);Reason=$null}
}
$report=Get-TrialStorageReportInline -Paths @(
    @{Role='Cache';Path='C:\Users\private-test-profile\cache'},
    @{Role='SelectedSource';Path='\\?\C:\Users\private-test-profile\mod'},
    @{Role='Network';Path='\\private-host\private-share\game'},
    @{Role='Network';Path='\\?\UNC\private-host\private-share\game'},
    @{Role='Volume';Path='\\?\Volume{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}\game'},
    @{Role='Game';Path='C:\junction'})
$result=@{report=$report;calls=$script:pathCalls}
""")
        rows = result['report']['Paths']
        self.assertEqual(rows[0]['Path'], r'%USERPROFILE%\cache')
        self.assertEqual(rows[1]['Path'], r'%USERPROFILE%\mod')
        self.assertEqual([rows[i]['Path'] for i in (2, 3)], ['<network-path>', '<network-path>'])
        self.assertEqual(rows[4]['Path'], '<volume-path>')
        self.assertEqual(rows[5]['FinalPath'], '<network-path>')
        self.assertEqual(rows[5]['MappingStatus'], 'Unavailable')
        encoded = json.dumps(result)
        for forbidden in ('private-host', 'private-share', 'private-test-profile', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'):
            self.assertNotIn(forbidden, encoded)
        self.assertEqual(result['calls'], 4)

    def test_mixed_separators_and_extended_paths_cannot_leak_home_or_network(self):
        result = self.invoke(self.providers() + r"""
$result=Get-TrialStorageReportInline -Paths @(
    @{Role='Cache';Path='C:/Users/private-test-profile/game'},
    @{Role='Cache';Path='C:\Users/private-test-profile\game'},
    @{Role='Cache';Path='\\?\C:/Users\private-test-profile/game'},
    @{Role='Network';Path='//private-host/private-share/game'},
    @{Role='Network';Path='//?/UNC/private-host\private-share/game'},
    @{Role='Volume';Path='//?/Volume{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}/game'})
""")
        self.assertTrue(all(row['Path'].startswith('%USERPROFILE%') for row in result['Paths'][:3]))
        self.assertEqual([row['Path'] for row in result['Paths'][3:]], ['<network-path>', '<network-path>', '<volume-path>'])
        encoded = json.dumps(result)
        for private in ('private-test-profile', 'private-host', 'private-share', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'):
            self.assertNotIn(private, encoded)

    def test_uncertain_termination_and_deletion_have_explicit_neutral_status(self):
        result = self.invoke(r"""
$script:kills=0; $script:waits=0; $script:disposes=0
$worker=[pscustomobject]@{HasExited=$false}
$worker | Add-Member ScriptMethod Kill {$script:kills++}
$worker | Add-Member ScriptMethod WaitForExit {param($Milliseconds); if ($Milliseconds -ne 1000) {throw 'Unbounded wait'}; $script:waits++; return $false}
$worker | Add-Member ScriptMethod Dispose {$script:disposes++}
function Remove-TrialStorageTemporaryDirectory {throw 'PRIVATE_HOST PRIVATE_VOLUME'}
$cleanup=Complete-TrialStorageWorker $worker $true 'neutral-fixture'
$result=@{cleanup=$cleanup;kills=$script:kills;waits=$script:waits;disposes=$script:disposes}
""")
        self.assertEqual(result['cleanup'], {'WorkerCleanup': 'Unconfirmed', 'TemporaryFilesCleanup': 'Unconfirmed'})
        self.assertEqual([result[key] for key in ('kills', 'waits', 'disposes')], [1, 1, 1])
        self.assertNotIn('PRIVATE_', json.dumps(result))

    def test_initialization_unavailable_and_invalid_records_fail_soft(self):
        result = self.invoke(r"""
function Initialize-TrialStorageNative {return 'NotWindows'}
function Read-TrialStoragePath {throw 'must not probe'}
$result=Get-TrialStorageReportInline -Paths @(@{Role='Game';Path='C:\game'},@{Role='Invalid';Path=42},@{Role='Empty';Path=''})
""")
        self.assertEqual([r['Reason'] for r in result['Paths']], ['NotWindows', 'InvalidPathRecord', 'InvalidPathRecord'])
        self.assertTrue(all(not r['Disks'] for r in result['Paths']))
        self.assertTrue(all(r['FinalPath'] is None for r in result['Paths']))

    def test_owned_worker_reprojects_and_redacts_its_response(self):
        result = self.invoke(r"""
$copy=Join-Path $env:PZ_STORAGE_FIXTURE_ROOT 'worker-helper.ps1'
$override=@'
function Get-TrialStorageReportInline([object[]]$Paths) {
    $rows=@()
    foreach ($path in $Paths) {
        $rows+=,@{Role='PRIVATE_HOST';Id='PRIVATE_SERIAL';Path='PRIVATE_VOLUME';FinalPath='C:\Users\private-test-profile\mods';ResolutionStatus='Available';MappingStatus='Available';Reason=$null;Disks=@(@{Number=3;Status='Available';Model='model';FriendlyName='disk';BusType='NVMe';MediaType='SSD';SerialNumber='PRIVATE_SERIAL';UniqueId='PRIVATE_UNIQUE'})}
    }
    return @{Format=1;Status='Collected';Paths=@($rows);Private='PRIVATE_HOST'}
}
'@
[IO.File]::WriteAllText($copy,([IO.File]::ReadAllText($env:PZ_STORAGE_SCRIPT)+"`n"+$override))
. $copy
$result=Get-TrialStorageReport -Paths @(@{Role='RuntimeSource';Id='example';Path='C:\Users\private-test-profile\cache'})
if (@(Get-ChildItem -LiteralPath $env:PZ_STORAGE_FIXTURE_ROOT -Filter 'pz-trial-storage-*').Count) {throw 'Worker temp directory leaked'}
""")
        self.assertEqual(result['Status'], 'Collected')
        row = result['Paths'][0]
        self.assertEqual(row['Role'], 'RuntimeSource')
        self.assertEqual(row['Id'], 'example')
        self.assertEqual(row['Path'], r'%USERPROFILE%\cache')
        self.assertEqual(row['FinalPath'], r'%USERPROFILE%\mods')
        self.assertEqual(row['Disks'][0]['MediaType'], 'Unknown')
        self.assertNotIn('PRIVATE_', json.dumps(result))
        self.assertNotIn('private-test-profile', json.dumps(result))
        self.assertGreaterEqual(result['ElapsedMs'], 0)
        self.assertEqual(result['WorkerCleanup'], 'Exited')
        self.assertEqual(result['TemporaryFilesCleanup'], 'Removed')

    def test_owned_worker_timeout_stops_only_that_worker_and_removes_temp_files(self):
        result = self.invoke(r"""
$copy=Join-Path $env:PZ_STORAGE_FIXTURE_ROOT 'slow-worker-helper.ps1'
$override=@'
function Get-TrialStorageReportInline([object[]]$Paths) {
    [IO.File]::WriteAllText((Join-Path $env:PZ_STORAGE_FIXTURE_ROOT 'worker.pid'),[string]$PID)
    Start-Sleep -Seconds 30
}
'@
[IO.File]::WriteAllText($copy,([IO.File]::ReadAllText($env:PZ_STORAGE_SCRIPT)+"`n"+$override))
. $copy
$parentProcessId=$PID
$watch=[Diagnostics.Stopwatch]::StartNew()
$report=Get-TrialStorageReport -Paths @(@{Role='Game';Path='C:\game'}) -TimeoutSeconds 2
$watch.Stop()
$pidFile=Join-Path $env:PZ_STORAGE_FIXTURE_ROOT 'worker.pid'
$ownedAlive=$false; $workerStarted=[IO.File]::Exists($pidFile)
if ($workerStarted) {
    $ownedProcessId=[int][IO.File]::ReadAllText($pidFile)
    $ownedAlive=$null -ne (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)
}
$result=@{report=$report;elapsed=$watch.Elapsed.TotalSeconds;workerStarted=$workerStarted;ownedAlive=$ownedAlive;parentAlive=($null -ne (Get-Process -Id $parentProcessId));tempDirectories=@(Get-ChildItem -LiteralPath $env:PZ_STORAGE_FIXTURE_ROOT -Filter 'pz-trial-storage-*').Count}
""")
        self.assertEqual(result['report']['Status'], 'Timeout')
        self.assertEqual(result['report']['WorkerCleanup'], 'Stopped')
        self.assertEqual(result['report']['TemporaryFilesCleanup'], 'Removed')
        self.assertEqual(result['report']['Paths'][0]['Reason'], 'StorageProbeTimeout')
        self.assertTrue(result['workerStarted'])
        self.assertFalse(result['ownedAlive'])
        self.assertTrue(result['parentAlive'])
        self.assertEqual(result['tempDirectories'], 0)
        self.assertLess(result['elapsed'], 6)

    def test_owned_worker_failure_is_neutral_and_fail_soft(self):
        result = self.invoke(r"""
$copy=Join-Path $env:PZ_STORAGE_FIXTURE_ROOT 'failed-worker-helper.ps1'
$override=@'
function Get-TrialStorageReportInline([object[]]$Paths) {throw 'PRIVATE_HOST PRIVATE_SERIAL'}
'@
[IO.File]::WriteAllText($copy,([IO.File]::ReadAllText($env:PZ_STORAGE_SCRIPT)+"`n"+$override))
. $copy
$result=Get-TrialStorageReport -Paths @(@{Role='Game';Path='C:\game'})
""")
        self.assertEqual(result['Status'], 'Unavailable')
        self.assertEqual(result['Paths'][0]['Reason'], 'StorageWorkerUnavailable')
        self.assertNotIn('PRIVATE_', json.dumps(result))

    def test_native_interop_layout_and_bounded_extent_parser_without_windows_calls(self):
        source = SCRIPT.read_text().split("@'\n", 1)[1].split("\n'@", 1)[0]
        result = self.invoke("Add-Type -TypeDefinition @'\n" + source + "\n'@\n" + r"""
$offset=[Runtime.InteropServices.Marshal]::OffsetOf([type][PZTrialStorage.VolumeExtents],'First').ToInt32()
$size=[Runtime.InteropServices.Marshal]::SizeOf([type][PZTrialStorage.DiskExtent])
if ($offset -ne 8 -or $size -ne 24) {throw 'Unexpected Win32 DISK_EXTENT layout'}
$data=New-Object byte[] 80
[BitConverter]::GetBytes([uint32]3).CopyTo($data,0)
[BitConverter]::GetBytes([uint32]7).CopyTo($data,8)
[BitConverter]::GetBytes([uint32]2).CopyTo($data,32)
[BitConverter]::GetBytes([uint32]7).CopyTo($data,56)
$numbers=[PZTrialStorage.Native]::ParseDiskExtents($data,80)
$rejected=0
foreach ($length in @(0,4,8,32,79,81)) {
    try {$null=[PZTrialStorage.Native]::ParseDiskExtents($data,$length)} catch {$rejected++}
}
[BitConverter]::GetBytes([uint32]1025).CopyTo($data,0)
try {$null=[PZTrialStorage.Native]::ParseDiskExtents($data,80)} catch {$rejected++}
$network=[PZTrialStorage.Native]::Read('\\private-host\share\file')
$result=@{offset=$offset;size=$size;numbers=@($numbers);rejected=$rejected;networkReason=$network.Reason;networkPath=$network.FinalPath}
""")
        self.assertEqual(result['numbers'], [2, 7])
        self.assertEqual(result['rejected'], 7)
        self.assertEqual(result['networkReason'], 'NetworkStorageUnavailable')
        self.assertEqual(result['networkPath'], '<network-path>')


if __name__ == '__main__':
    unittest.main()
