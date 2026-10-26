"""Hotkey control flow with a fake native adapter; no Windows input or focus changes."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(PWSH, 'PowerShell required')
class TrialHotkey(unittest.TestCase):
    def invoke(self, body):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'test.ps1'
            script.write_text("$ErrorActionPreference='Stop'\n. " +
                              ps(ROOT / 'tests/optimizer_trial/TrialHotkey.ps1') + '\n' + body)
            result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(script)],
                                    text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result

    def fixture(self):
        return """
$script:checks=0; $script:polls=0; $script:sleeps=0; $script:cleanup=0
$script:registration=$true
$process=[pscustomobject]@{Id=12345}
$identityStart=[DateTime]::Parse('2026-10-26T00:00:00Z')
function Assert-JfrTargetProcess {
 param($Process,$Path,$Start)
 if ($Process.Id -ne 12345 -or $Path -ne '/owned/java' -or $Start -ne $identityStart) {throw 'identity arguments lost'}
 $script:checks++
}
function Start-Sleep {
 param($Milliseconds)
 if ($Milliseconds -ne 100) {throw 'wrong polling interval'}
 $script:sleeps++
}
function New-TrialHotkeyNativeAdapter {
 $adapter=[pscustomobject]@{LastError=1409}
 $adapter | Add-Member ScriptMethod Register { return $script:registration }
 $adapter | Add-Member ScriptMethod Poll { $script:polls++; return $script:polls -ge 2 }
 $adapter | Add-Member ScriptMethod ForegroundPid { if ($script:polls -eq 2) {return 99999}; return 12345 }
 $adapter | Add-Member ScriptMethod Unregister { $script:cleanup++ }
 return $adapter
}
"""

    def test_waits_for_owned_foreground_hotkey_and_releases_registration(self):
        self.invoke(self.fixture() + """
$result=Wait-TrialCaptureHotkey $process '/owned/java' $identityStart
if ($result.foregroundPid -ne 12345 -or -not $result.Utc.EndsWith('Z')) {throw 'wrong capture event'}
if ($script:polls -ne 3 -or $script:sleeps -ne 2) {throw 'captured without hotkey or in foreign foreground'}
if ($script:checks -ne 5 -or $script:cleanup -ne 1) {throw 'identity validation or cleanup missing'}
""")

    def test_stale_identity_during_wait_releases_registration(self):
        self.invoke(self.fixture() + """
function Assert-JfrTargetProcess {
 $script:checks++
 if ($script:checks -eq 3) {throw 'owned process identity changed'}
}
$failure=''
try { Wait-TrialCaptureHotkey $process '/owned/java' $identityStart } catch {$failure=$_.Exception.Message}
if ($failure -notmatch 'owned process identity changed') {throw 'identity failure suppressed'}
if ($script:cleanup -ne 1 -or $script:polls -ne 1) {throw 'stale process polled or registration leaked'}
""")

    def test_identity_checked_again_before_accepting_hotkey(self):
        self.invoke(self.fixture() + """
function Assert-JfrTargetProcess {
 $script:checks++
 if ($script:checks -eq 5) {throw 'process exited at hotkey'}
}
$failure=''
try { Wait-TrialCaptureHotkey $process '/owned/java' $identityStart } catch {$failure=$_.Exception.Message}
if ($failure -notmatch 'process exited at hotkey' -or $script:cleanup -ne 1) {throw 'late identity failure accepted'}
""")

    def test_registration_collision_explains_failure_without_polling(self):
        self.invoke(self.fixture() + """
$script:registration=$false
$failure=''
try { Wait-TrialCaptureHotkey $process '/owned/java' $identityStart } catch {$failure=$_.Exception.Message}
if ($failure -notmatch 'Ctrl[+]Shift[+]F8' -or $failure -notmatch '1409' -or $failure -notmatch 'already use') {throw 'collision explanation missing'}
if ($script:polls -ne 0 -or $script:cleanup -ne 0) {throw 'unowned registration accessed'}
""")

    def test_native_poll_failure_releases_registration(self):
        self.invoke(self.fixture() + """
$factory=${function:New-TrialHotkeyNativeAdapter}
function New-TrialHotkeyNativeAdapter {
 $adapter=& $factory
 $adapter | Add-Member -Force ScriptMethod Poll {throw 'native poll failed'}
 return $adapter
}
$failure=''
try { Wait-TrialCaptureHotkey $process '/owned/java' $identityStart } catch {$failure=$_.Exception.Message}
if ($failure -notmatch 'native poll failed' -or $script:cleanup -ne 1) {throw 'poll failure leaked registration'}
""")

    def test_import_is_inert_and_csharp_compiles_without_native_calls(self):
        self.invoke("""
if ('PZTrialHotkey.NativeAdapter' -as [type]) {throw 'import initialized native helper'}
Add-Type -TypeDefinition (Get-TrialHotkeyNativeSource) -ErrorAction Stop
if (-not ('PZTrialHotkey.NativeAdapter' -as [type])) {throw 'native helper did not compile'}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
 $failure=''
 try { New-TrialHotkeyNativeAdapter } catch {$failure=$_.Exception.Message}
 if ($failure -notmatch 'requires Windows') {throw 'platform gate missing'}
}
""")


if __name__ == '__main__':
    unittest.main()
