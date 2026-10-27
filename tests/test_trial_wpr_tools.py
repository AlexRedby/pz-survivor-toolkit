"""Bounded WPR discovery fixtures; macOS mocks do not verify Windows ETW or trust APIs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent / 'optimizer_trial'
PWSH = shutil.which('pwsh')


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class WprToolSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz-wpr-tools-')
        self.root = Path(self.temp.name).resolve()
        self.program_x86 = self.root / 'Program Files (x86)'
        self.program = self.root / 'Program Files'
        self.system = self.root / 'System32'
        self.adk = self.program_x86 / 'Windows Kits/10/Windows Performance Toolkit/wpr.exe'
        self.adk_native = self.program / 'Windows Kits/10/Windows Performance Toolkit/wpr.exe'
        self.system_wpr = self.system / 'wpr.exe'
        self.records = []

    def tearDown(self):
        self.temp.cleanup()

    def tool(self, path, version='10.0.26100.1', publisher='Microsoft Corporation', status='Valid'):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(('fixture-' + version if version else 'unknown-version').encode())
        self.records.append(dict(Path=str(path), Version=version,
                                 Subject=f'CN=Windows, O={publisher}, C=US', Status=status))
        return path

    def run_ps(self, body='Get-TrialWprToolSelection | ConvertTo-Json -Depth 10 -Compress', windows=True):
        env = dict(os.environ, PZ_WPR_SCRIPTS=str(SCRIPTS), PZ_TOOLS_ROOT=str(self.root),
                   PZ_TOOLS_RECORDS=json.dumps(self.records), PZ_TOOLS_WINDOWS=str(windows))
        fixture = r'''
$ErrorActionPreference='Stop'
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWpr.ps1')
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprTools.ps1')
function Test-TrialWprWindows { return ($env:PZ_TOOLS_WINDOWS -eq 'True') }
function Get-TrialWprProgramFilesDirectories {
    (Join-Path $env:PZ_TOOLS_ROOT 'Program Files (x86)')
    (Join-Path $env:PZ_TOOLS_ROOT 'Program Files')
}
function Get-TrialWprSystemDirectory { Join-Path $env:PZ_TOOLS_ROOT 'System32' }
$global:records=@($env:PZ_TOOLS_RECORDS | ConvertFrom-Json)
function Get-FixtureRecord([string]$Path) {
    return ($global:records | Where-Object { $_.Path -eq $Path } | Select-Object -First 1)
}
function Get-TrialWprFileVersionInfo([string]$Path) {
    $record=Get-FixtureRecord $Path
    if (-not $record.Version) { return [pscustomobject]@{FileVersion='not numeric';ProductVersion='unknown';FileMajorPart=0;FileMinorPart=0;FileBuildPart=0;FilePrivatePart=0} }
    $parts=$record.Version.Split('.')
    return [pscustomobject]@{FileVersion=($record.Version+' (fixture)');ProductVersion=$record.Version;
        FileMajorPart=$parts[0];FileMinorPart=$parts[1];FileBuildPart=$parts[2];FilePrivatePart=$parts[3]}
}
function Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    $record=Get-FixtureRecord $LiteralPath
    return [pscustomobject]@{Status=$record.Status;SignerCertificate=[pscustomobject]@{Subject=$record.Subject}}
}
function Start-Process { throw 'Discovery must not execute any candidate.' }
'''
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-Command', fixture + body],
                                env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def test_new_installed_adk_preferred_to_captured_old_system(self):
        self.tool(self.system_wpr, '10.0.19041.1')
        self.tool(self.adk)
        result = self.run_ps()
        self.assertEqual(result['Selected']['Path'], str(self.adk))
        self.assertEqual(result['Selected']['Source'], 'ADK')
        self.assertEqual(result['Selected']['Version'], '10.0.26100.1')
        old = next(candidate for candidate in result['Candidates'] if candidate['Source'] == 'System')
        self.assertFalse(old['Eligible'])
        self.assertEqual(old['Reason'], 'WprUpgradeRequired')
        self.assertIsNone(result['Reason'])

    def test_supported_system_used_when_adk_missing_or_rejected(self):
        self.tool(self.system_wpr, '10.0.19650.0')
        self.tool(self.adk, publisher='Other Corporation')
        result = self.run_ps()
        self.assertEqual(result['Selected']['Path'], str(self.system_wpr))
        self.assertEqual(result['Selected']['Source'], 'System')
        self.assertEqual(result['Candidates'][0]['Reason'], 'UntrustedPublisher')
        self.assertEqual(result['Candidates'][1]['Reason'], 'ToolMissing')

    def test_old_system_without_adk_requires_upgrade(self):
        self.tool(self.system_wpr, '10.0.19041.1')
        result = self.run_ps()
        self.assertIsNone(result['Selected'])
        self.assertEqual(result['Reason'], 'WprUpgradeRequired')
        self.assertEqual([candidate['Reason'] for candidate in result['Candidates']],
                         ['ToolMissing', 'ToolMissing', 'WprUpgradeRequired'])

    def test_unknown_version_and_invalid_signature_are_rejected(self):
        self.tool(self.adk, version=None)
        self.tool(self.adk_native, status='NotTrusted')
        result = self.run_ps()
        self.assertIsNone(result['Selected'])
        self.assertEqual(result['Candidates'][0]['Reason'], 'UnknownVersion')
        self.assertEqual(result['Candidates'][1]['Reason'], 'UntrustedPublisher')
        self.assertEqual(result['Reason'], 'WprUnavailable')

    def test_reparse_candidate_is_rejected_before_identity_reads(self):
        real = self.tool(self.root / 'other/wpr.exe')
        self.adk.parent.mkdir(parents=True)
        self.adk.symlink_to(real)
        result = self.run_ps()
        self.assertIsNone(result['Selected'])
        self.assertEqual(result['Candidates'][0]['Reason'], 'ToolValidationFailed')
        self.assertIsNone(result['Candidates'][0]['Sha256'])

    def test_non_windows_has_no_candidates(self):
        self.tool(self.adk)
        result = self.run_ps(windows=False)
        self.assertIsNone(result['Selected'])
        self.assertEqual(result['Candidates'], [])
        self.assertEqual(result['Reason'], 'WprUnavailable')

    def test_exact_identity_and_paired_dll_evidence_retained(self):
        self.tool(self.adk)
        dll = self.tool(self.adk.with_name('wprcontrol.dll'), '10.0.26100.2')
        result = self.run_ps(r'''
$selection=Get-TrialWprToolSelection
$again=Get-TrialWprToolMetadata $selection.Selected.Path $selection.Selected.Source
@{Selection=$selection;Again=$again;LegacyPath=(Get-TrialWprTool)} | ConvertTo-Json -Depth 12 -Compress
''')
        selected = result['Selection']['Selected']
        self.assertEqual(result['LegacyPath'], str(self.adk))
        self.assertEqual(selected, result['Again'])
        self.assertEqual(selected['Sha256'], hashlib.sha256(self.adk.read_bytes()).hexdigest())
        self.assertEqual(selected['SignatureStatus'], 'Valid')
        self.assertIn('O=Microsoft Corporation', selected['Publisher'])
        self.assertEqual(selected['WprControl']['Path'], str(dll))
        self.assertEqual(selected['WprControl']['Sha256'], hashlib.sha256(dll.read_bytes()).hexdigest())

    def test_arbitrary_signed_path_and_mismatched_source_are_rejected(self):
        self.tool(self.adk)
        self.tool(self.root / 'wpr.exe')
        result = self.run_ps(r'''
@{Arbitrary=(Get-TrialWprToolMetadata (Join-Path $env:PZ_TOOLS_ROOT 'wpr.exe') 'ADK');
  WrongSource=(Get-TrialWprToolMetadata (Get-TrialWprTool) 'System')} | ConvertTo-Json -Depth 10 -Compress
''')
        for candidate in result.values():
            self.assertFalse(candidate['Eligible'])
            self.assertEqual(candidate['Reason'], 'UntrustedToolPath')
            self.assertIsNone(candidate['Sha256'])

    def test_import_is_inert(self):
        result = self.run_ps(r'''
function Test-TrialWprWindows { throw 'Import probed the platform.' }
function Get-TrialWprToolCandidates { throw 'Import discovered tools.' }
function Get-TrialWprFileVersionInfo { throw 'Import read file identity.' }
. (Join-Path $env:PZ_WPR_SCRIPTS 'TrialWprTools.ps1')
@{Imported=$true} | ConvertTo-Json -Compress
''')
        self.assertTrue(result['Imported'])


if __name__ == '__main__':
    unittest.main()
