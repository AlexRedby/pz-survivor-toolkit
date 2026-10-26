"""Portable benchmark packaging and profile isolation without a Windows game."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import prepare_driving_benchmark as package


class DrivingPackage(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / "tests/driving_benchmark"
        self.source.mkdir(parents=True)
        for name in package.LAUNCHER_FILES:
            shutil.copy2(ROOT / "tests/driving_benchmark" / name, self.source / name)
        self.mod = self.source / "mods/PZDrivingBench/42"
        self.mod.mkdir(parents=True)
        (self.mod / "mod.info").write_text("id=PZDrivingBench\n")
        (self.mod / "fixture.lua").write_text("-- test source\n")
        (self.mod.parent / "common").mkdir()

    def test_archive_has_only_distributable_sources_and_host_gate(self):
        (self.source / "Profiles/CurrentMods/Saves").mkdir(parents=True)
        (self.source / "Profiles/CurrentMods/Saves/private.txt").write_text("never package")
        (self.root / "projectzomboid.jar").write_text("never package")
        output, archive = package.prepare(self.root)
        with zipfile.ZipFile(archive) as bundle:
            self.assertEqual({(Path("PZDrivingBench") / path.relative_to(output)).as_posix()
                              + ("/" if path.is_dir() else "") for path in output.rglob("*")},
                             set(bundle.namelist()))
            self.assertIn("PZDrivingBench/mods/PZDrivingBench/common/", bundle.namelist())
            self.assertFalse(any("Profiles" in path or path.endswith(".jar") for path in bundle.namelist()))
            ini = bundle.read("PZDrivingBench/Server/PZDrivingBench.ini").decode()
            self.assertIn("SpawnPoint=10818,10118,0\n", ini)
            self.assertIn("Mods=PZDrivingBench\n", ini)

    def test_owned_unused_output_can_be_rebuilt(self):
        output, archive = package.prepare(self.root)
        (output / "stale.txt").write_text("old")
        (self.mod / "fixture.lua").write_text("-- new source\n")
        package.prepare(self.root)
        self.assertFalse((output / "stale.txt").exists())
        self.assertEqual("-- new source\n", (output / "mods/PZDrivingBench/42/fixture.lua").read_text())
        self.assertTrue(archive.is_file())

    def test_used_profiles_and_existing_archive_are_preserved(self):
        output, archive = package.prepare(self.root)
        sentinel = output / "Profiles/CurrentMods/console.txt"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text("keep logs")
        before = archive.read_bytes()
        with self.assertRaisesRegex(ValueError, "Keep existing benchmark profiles"):
            package.prepare(self.root)
        self.assertEqual("keep logs", sentinel.read_text())
        self.assertEqual(before, archive.read_bytes())

    def test_recordings_and_existing_archive_are_preserved(self):
        output, archive = package.prepare(self.root)
        sentinel = output / "JFR/earlier/drive.jfr"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_bytes(b"keep recording")
        before = archive.read_bytes()
        with self.assertRaisesRegex(ValueError, "Keep existing benchmark"):
            package.prepare(self.root)
        self.assertEqual(b"keep recording", sentinel.read_bytes())
        self.assertEqual(before, archive.read_bytes())

    def test_foreign_output_and_linked_source_are_rejected(self):
        output = self.root / "dist/PZDrivingBench"
        output.mkdir(parents=True)
        sentinel = output / "foreign.txt"
        sentinel.write_text("keep")
        with self.assertRaisesRegex(ValueError, "foreign output"):
            package.prepare(self.root)
        self.assertEqual("keep", sentinel.read_text())
        shutil.rmtree(output)
        (self.mod / "linked.lua").symlink_to(self.mod / "fixture.lua")
        with self.assertRaisesRegex(ValueError, "Non-regular"):
            package.prepare(self.root)
        self.assertFalse(output.exists())

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is not installed")
    def test_powershell_parser_and_safe_profile_snapshot(self):
        source = self.root / "source cache"
        source.mkdir()
        (source / "options.ini").write_text("width=1920\n")
        (source / "keys.ini").write_text("Forward=17\n")
        (source / "accounts.db").write_text("must not copy")
        (source / "Saves").mkdir()
        (source / "mods/LocalMod/42").mkdir(parents=True)
        (source / "mods/LocalMod/42/mod.info").write_text("id=LocalMod\n")
        (source / "mods/default.txt").write_text(
            "VERSION = 1,\nmods\n{\n mod = LocalMod,\n mod = WorkshopOnly,\n}\nmaps\n{\n}\n")
        output, _ = package.prepare(self.root)
        script = self.root / "check.ps1"
        script.write_text(r'''
param([string]$Package, [string]$Source)
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$launcher = Join-Path $Package 'Launch.ps1'
$null = [System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
. $launcher -SourceProfile $Source
function Check($Value, $Message) { if (-not $Value) { throw $Message } }
$cache = Join-Path $Package 'Profiles/CurrentMods'
$lock = Get-ProfileLock $cache
try {
    Initialize-Profile $cache $Source 'CurrentMods' $Package
    Check ((Get-Content -LiteralPath (Join-Path $cache 'options.ini') -Raw) -eq "width=1920`n") 'graphics not copied'
    Check (-not (Test-Path -LiteralPath (Join-Path $cache 'accounts.db'))) 'account copied'
    Check (-not (Test-Path -LiteralPath (Join-Path $cache 'Saves'))) 'save copied'
    Check (Test-Path -LiteralPath (Join-Path $cache 'mods/LocalMod/42/mod.info')) 'local mod missing'
    $selection = [IO.File]::ReadAllText((Join-Path $cache 'mods/default.txt'))
    Check ($selection -match 'mod = WorkshopOnly,') 'workshop selection lost'
    Check ($selection -match 'mod = PZDrivingBench,') 'fixture not enabled'
    # The real B42.21 boot erases default.txt if this native release marker is absent.
    Check (Test-Path -LiteralPath (Join-Path $cache 'mods/reset-mods-42_00.txt')) 'first boot will erase selection'
    $secondLockFailed = $false
    try { $second = Get-ProfileLock $cache; $second.Dispose() } catch { $secondLockFailed = $true }
    Check $secondLockFailed 'profile lock not exclusive'
    [IO.File]::WriteAllText((Join-Path $Source 'options.ini'), 'changed source')
    [IO.File]::WriteAllText((Join-Path $Source 'keys.ini'), 'changed source keys')
    [IO.File]::WriteAllText((Join-Path $cache 'Server/PZDrivingBench.ini'), 'user host settings')
    Initialize-Profile $cache $Source 'CurrentMods' $Package
    Check (([IO.File]::ReadAllText((Join-Path $cache 'options.ini'))) -eq "width=1920`n") 'settings recopied'
    Check (([regex]::Matches([IO.File]::ReadAllText((Join-Path $cache 'mods/default.txt')), 'mod = PZDrivingBench,')).Count -eq 1) 'duplicate fixture'
    Check (([IO.File]::ReadAllText((Join-Path $cache 'Server/PZDrivingBench.ini'))) -eq 'user host settings') 'host preset overwritten'
    # An old package's first boot erased the imported list; its second added only the starter.
    $selectionPath = Join-Path $cache 'mods/default.txt'
    [IO.File]::WriteAllText($selectionPath, "VERSION = 1,`nmods`n{`n mod = PZDrivingBench,`n}`nmaps`n{`n}`n")
    $save = Join-Path $cache 'Saves/Sandbox/existing/map.bin'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($save)) | Out-Null
    [IO.File]::WriteAllText($save, 'keep test save')
    Initialize-Profile $cache $Source 'CurrentMods' $Package
    Check (([IO.File]::ReadAllText($selectionPath)) -notmatch 'WorkshopOnly') 'selection implicitly recopied'
    Initialize-Profile $cache $Source 'CurrentMods' $Package -RefreshMods
    $selection = [IO.File]::ReadAllText($selectionPath)
    Check ($selection -match 'mod = LocalMod,' -and $selection -match 'mod = WorkshopOnly,') 'refresh did not restore source selection'
    Check (([regex]::Matches($selection, 'mod = PZDrivingBench,')).Count -eq 1) 'refresh duplicated starter'
    Check (([IO.File]::ReadAllText((Join-Path $cache 'options.ini'))) -eq "width=1920`n") 'refresh replaced graphics'
    Check (([IO.File]::ReadAllText((Join-Path $cache 'keys.ini'))) -eq "Forward=17`n") 'refresh replaced keys'
    Check (([IO.File]::ReadAllText($save)) -eq 'keep test save') 'refresh replaced test save'
    Check (([IO.File]::ReadAllText((Join-Path $cache 'Server/PZDrivingBench.ini'))) -eq 'user host settings') 'refresh replaced host settings'
    Remove-Item -LiteralPath (Join-Path $Source 'mods/default.txt')
    $failed = $false
    try { Initialize-Profile $cache $Source 'CurrentMods' $Package -RefreshMods } catch { $failed = $true }
    Check $failed 'refresh accepted missing source selection'
    Check (([IO.File]::ReadAllText($selectionPath)) -eq $selection) 'failed refresh damaged selection'
} finally { $lock.Dispose() }
$vanilla = Join-Path $Package 'Profiles/Vanilla'
$lock = Get-ProfileLock $vanilla
try {
    Initialize-Profile $vanilla $Source 'Vanilla' $Package
    $selection = [IO.File]::ReadAllText((Join-Path $vanilla 'mods/default.txt'))
    Check ($selection -match 'mod = PZDrivingBench,') 'vanilla fixture missing'
    Check ($selection -notmatch 'LocalMod|WorkshopOnly') 'vanilla includes source mods'
    Check (Test-Path -LiteralPath (Join-Path $vanilla 'mods/reset-mods-42_00.txt')) 'vanilla first boot will erase starter'
    $failed = $false
    try { Initialize-Profile $vanilla $Source 'Vanilla' $Package -RefreshMods } catch { $failed = $true }
    Check $failed 'vanilla accepted source refresh'
} finally { $lock.Dispose() }
$foreign = Join-Path $Package 'Profiles/Foreign'
[IO.Directory]::CreateDirectory($foreign) | Out-Null
$failed = $false
try { $unexpected = Get-ProfileLock $foreign; $unexpected.Dispose() } catch { $failed = $true }
Check $failed 'foreign profile accepted'
$failed = $false
try { Assert-SeparatePaths $Source (Join-Path $Source 'child') } catch { $failed = $true }
Check $failed 'source overlap accepted'
Write-Host 'Profile snapshot and guards passed.'
''', encoding="utf-8")
        result = subprocess.run([shutil.which("pwsh"), "-NoProfile", "-File", str(script),
                                 "-Package", str(output), "-Source", str(source)], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
