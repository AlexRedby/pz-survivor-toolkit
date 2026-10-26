"""CXRemote HTTP and output fixtures; no CapFrameX, game or Windows input needed."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tests/optimizer_trial/TrialCapFrameX.ps1'
PWSH = shutil.which('pwsh')


@contextmanager
def api_fixture(responses=None):
    calls = []
    responses = responses or {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def handle_request(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length).decode() if length else None
            calls.append((self.command, self.path, json.loads(raw) if raw else None))
            defaults = {
                ('GET', '/api/version'): (200, {'Version': '1.9.1.5'}),
                ('GET', '/api/processes'): (200, ['java']),
                ('POST', '/api/capture'): (200, {'Message': 'Capture started'}),
            }
            answer = responses.get((self.command, self.path), defaults.get((self.command, self.path), (404, {})))
            if callable(answer):
                answer = answer()
            status, body = answer
            self.send_response(status)
            if status == 302:
                self.send_header('Location', '/should-not-follow')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            try:
                self.wfile.write(json.dumps(body).encode())
            except (BrokenPipeError, ConnectionResetError):
                pass  # Expected for the bounded HTTP timeout fixture.

        do_GET = handle_request
        do_POST = handle_request
        do_DELETE = handle_request

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1], calls
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


@unittest.skipUnless(PWSH, 'PowerShell unavailable')
class TrialCapFrameXTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz-cxremote-')
        self.root = Path(self.temp.name).resolve()
        self.executable = self.root / 'CapFrameX.exe'
        self.executable.write_bytes(b'fixture executable, never run')
        self.directory = self.root / 'capture'

    def tearDown(self):
        self.temp.cleanup()

    def config(self, properties, path=None):
        path = path or self.root / 'CapFrameX/Configuration/AppSettings.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(properties))
        return path

    def invoke(self, body, port=0, timeout=10):
        harness = self.root / 'fixture.ps1'
        harness.write_text("""
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. $env:PZ_CX_SCRIPT
$process=[pscustomobject]@{Id=4242}
$expectedStart=[DateTime]::Parse('2026-10-26T00:00:00Z').ToUniversalTime()
$script:javaProcesses=@($process)
$script:cxProcesses=@([pscustomobject]@{Id=1212;Path=$env:PZ_CX_EXE})
$script:identityChecks=0
function Get-Process { param($Name,$ErrorAction)
 if ($Name -eq 'java') {return $script:javaProcesses}
 if ($Name -eq 'CapFrameX') {return $script:cxProcesses}
 throw 'unexpected process query'
}
function Assert-JfrTargetProcess { param($Process,$ExpectedExecutablePath,$ExpectedStartUtc)
 if ($Process.Id -ne 4242 -or $ExpectedExecutablePath -ne '/owned/java' -or $ExpectedStartUtc -ne $expectedStart) {
  throw 'identity arguments changed'
 }
 $script:identityChecks++
 return [pscustomobject]@{Pid=4242}
}
$client=[pscustomobject]@{BaseUri=('http://localhost:'+$env:PZ_CX_PORT);Version='1.9.1.5'}
""" + body)
        env = dict(os.environ, PZ_CX_SCRIPT=str(SCRIPT), PZ_CX_PORT=str(port),
                   PZ_CX_EXE=str(self.executable), PZ_CX_DIR=str(self.directory), APPDATA=str(self.root))
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness)],
                                text=True, capture_output=True, timeout=timeout, env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def capture(self, prefix=''):
        return self.invoke(prefix + """
$receipt=Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'
$receipt | ConvertTo-Json -Compress
""", port=self.port)

    def outputs(self, token='fixture-token', process='java.exe', frames=None, pids=None, application='java.exe'):
        self.directory.mkdir(exist_ok=True)
        frames = [1000] * 10 if frames is None else frames
        session = {'Info': {'ProcessName': process, 'Comment': token},
                   'Runs': [{'CaptureData': {'MsBetweenPresents': frames,
                                             'TimeInSeconds': list(range(len(frames)))}}]}
        json_path = self.directory / 'CapFrameX-java.exe-fixture.json'
        json_path.write_text(json.dumps(session))
        pids = [4242] * 10 if pids is None else pids
        # Raw CSV is intentionally timestamped separately from JSON, as CX does.
        csv_path = self.directory / 'CapFrameX-java.exe-other-timestamp.json.csv'
        csv_path.write_text('//Ignore=true\nApplication,ProcessID,FrameTime,CPUStartQPCTimeInMs\n' +
                            ''.join(f'"{application}",{pid},1000,{index * 1000}\n' for index, pid in enumerate(pids)))
        return json_path, csv_path

    def complete(self, expression='Complete-TrialFrameCapture $receipt'):
        return self.invoke("""
$receipt=[pscustomobject]@{directory=$env:PZ_CX_DIR;token='fixture-token';targetPid=4242;processName='java';seconds=10}
""" + '$result=' + expression + '\nConvertTo-Json -InputObject $result -Depth 8 -Compress\n')

    def failure(self, body, pattern, port=0):
        result = self.invoke("$failure=''; try {" + body +
                             "} catch {$failure=$_.Exception.Message}; @{failure=$failure} | ConvertTo-Json -Compress", port)
        self.assertRegex(result['failure'], pattern)
        return result['failure']

    def test_unavailable_process_path_uses_limited_image_query_for_portable(self):
        with api_fixture() as (port, calls):
            (self.root / 'portable.json').write_text(json.dumps({'portable': True}))
            config=self.config({'WebservicePort': str(port)}, self.root/'Portable/Config/AppSettings.json')
            for getter in ("$script:cxProcesses[0].Path=$null", "$script:cxProcesses[0] | Add-Member ScriptProperty Path { throw 'module access denied' } -Force"):
                with self.subTest(getter=getter):
                    result=self.invoke(getter + """
$script:imageCalls=0
function Get-TrialLimitedProcessImage { param($ProcessId); if ($ProcessId -ne 1212) {throw 'wrong PID'}; $script:imageCalls++; return $env:PZ_CX_EXE }
$r=Get-TrialCapFrameX
if ($script:imageCalls -ne 1) {throw 'limited image query not used'}
$r | ConvertTo-Json -Compress
""")
                    self.assertEqual(Path(result['ConfigPath']), config)
                    self.assertEqual(result['BaseUri'], f'http://localhost:{port}')
            self.assertEqual(len(calls),2)

    def test_no_image_path_uses_only_verified_default_api_not_stale_config(self):
        self.config({'WebservicePort':'1','UseAggregation':True,'SaveAggregationOnly':True})
        result=self.invoke("""
$script:cxProcesses[0].Path=$null
function Get-TrialLimitedProcessImage { return $null }
function Invoke-TrialFrameRequest { param($Client,$Method,$Route)
 if ($Client.BaseUri -ne 'http://localhost:1337' -or $Method -ne 'GET' -or $Route -ne '/api/version') {throw 'unexpected discovery request'}
 return [pscustomobject]@{Version='1.9.1.5'}
}
Get-TrialCapFrameX | ConvertTo-Json -Compress
""")
        self.assertIsNone(result['ConfigPath'])
        self.assertEqual(result['Version'],'1.9.1.5')
        self.failure("""
$script:cxProcesses[0].Path=$null
function Get-TrialLimitedProcessImage { return $null }
function Invoke-TrialFrameRequest { throw 'connection refused' }
Get-TrialCapFrameX
""",'is running.*EXE path is unavailable.*CapFrameXDir')

    def test_no_image_path_accepts_explicit_port_or_portable_directory(self):
        with api_fixture() as (port, calls):
            prefix="""
$script:cxProcesses[0].Path=$null
function Get-TrialLimitedProcessImage { return $null }
"""
            r=self.invoke(prefix+'Get-TrialCapFrameX -Port ([int]$env:PZ_CX_PORT) | ConvertTo-Json -Compress',port)
            self.assertEqual(r['BaseUri'],f'http://localhost:{port}')
            (self.root/'portable.json').write_text(json.dumps({'portable':True,'paths':{'config':'./custom-settings'}}))
            config=self.config({'WebservicePort':str(port)},self.root/'custom-settings/AppSettings.json')
            r=self.invoke(prefix+"Get-TrialCapFrameX -Directory ([IO.Path]::GetDirectoryName($env:PZ_CX_EXE)) | ConvertTo-Json -Compress")
            self.assertEqual(Path(r['ConfigPath']),config)

    def test_explicit_portable_folder_cannot_override_known_running_folder(self):
        self.directory.mkdir()
        with api_fixture() as (port,calls):
            self.failure('Get-TrialCapFrameX -Directory $env:PZ_CX_DIR -Port ([int]$env:PZ_CX_PORT)', 'differs from the running',port)
            self.assertEqual(calls,[])

    def test_limited_image_interop_compiles_without_native_calls(self):
        r=self.invoke("""
Add-Type -TypeDefinition (Get-TrialProcessImageSource) -ErrorAction Stop
if (-not ('PZTrialProcessImage.Reader' -as [type])) {throw 'interop did not compile'}
if ([Environment]::OSVersion.Platform -ne 'Win32NT' -and $null -ne (Get-TrialLimitedProcessImage 1212)) {throw 'non-Windows attempted native path lookup'}
@{compiled=$true} | ConvertTo-Json -Compress
""")
        self.assertTrue(r['compiled'])

    def test_preflight_discovers_port_and_version_without_mutating_settings(self):
        with api_fixture() as (port, calls):
            config = self.config({'WebservicePort': str(port), 'CaptureDelay': 30})
            before = config.read_bytes()
            result = self.invoke('Get-TrialCapFrameX | ConvertTo-Json -Compress')
            self.assertEqual(result['Version'], '1.9.1.5')
            self.assertEqual(result['BaseUri'], f'http://localhost:{port}')
            self.assertEqual(Path(result['ConfigPath']), config)
            self.assertEqual(config.read_bytes(), before)
            self.assertEqual(calls, [('GET', '/api/version', None)])

    def test_portable_config_takes_precedence_and_override_is_supported(self):
        with api_fixture() as (port, calls):
            self.config({'WebservicePort': '1'})
            (self.root / 'portable.json').write_text(json.dumps({'portable': True, 'paths': {'config': './portable-config'}}))
            portable_config = self.config({'WebservicePort': str(port)}, self.root / 'portable-config/AppSettings.json')
            result = self.invoke('Get-TrialCapFrameX | ConvertTo-Json -Compress')
            self.assertEqual(Path(result['ConfigPath']), portable_config)
            result = self.invoke('Get-TrialCapFrameX -Port ([int]$env:PZ_CX_PORT) | ConvertTo-Json -Compress', port)
            self.assertEqual(result['Version'], '1.9.1.5')
            self.assertEqual(len(calls), 2)

    def test_preflight_rejects_missing_instance_aggregation_and_fake_endpoint(self):
        self.failure('$script:cxProcesses=@(); Get-TrialCapFrameX', 'exactly one CapFrameX')
        self.config({'UseAggregation': True, 'SaveAggregationOnly': True})
        with api_fixture() as (port, calls):
            self.failure('Get-TrialCapFrameX -Port ([int]$env:PZ_CX_PORT)', 'SaveAggregationOnly', port)
            self.assertEqual(calls, [])
        self.config({})
        with api_fixture({('GET', '/api/version'): (200, {'Message': 'Error'})}) as (port, calls):
            self.failure('Get-TrialCapFrameX -Port ([int]$env:PZ_CX_PORT)', 'not a supported', port)

    def test_start_posts_one_explicit_zero_delay_capture_and_records_ack(self):
        with api_fixture() as (self.port, calls):
            result = self.capture()
            self.assertEqual(result['targetPid'], 4242)
            self.assertEqual(result['token'], 'fixture-token')
            self.assertEqual(result['directory'], str(self.directory))
            self.assertEqual(result['seconds'], 10)
            self.assertLessEqual(result['requestedUtc'], result['acknowledgedUtc'])
            self.assertEqual(calls, [('GET', '/api/processes', None), ('POST', '/api/capture', {
                'ProcessName': 'java', 'CaptureTime': 10, 'CaptureFileMode': 'JsonCsv',
                'RecordDirectory': str(self.directory), 'Comment': 'fixture-token'})])
            self.assertTrue(self.directory.is_dir())
            self.assertEqual(list(self.directory.iterdir()), [])

    def test_ambiguous_ineligible_or_changed_identity_never_posts(self):
        with api_fixture() as (port, calls):
            self.failure("$script:javaProcesses+=,[pscustomobject]@{Id=5151}; Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'",
                         'exactly one java', port)
            self.assertEqual(calls, [])
            self.failure("function Assert-JfrTargetProcess { $script:identityChecks++; if ($script:identityChecks -gt 1) {throw 'stale owned PID'} }; Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'",
                         'stale owned PID', port)
            self.assertEqual([x[0] for x in calls], ['GET'])
        with api_fixture({('GET', '/api/processes'): (200, ['other'])}) as (port, calls):
            self.failure("Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'",
                         'not capture-eligible', port)
            self.assertFalse(any(x[0] == 'POST' for x in calls))
        self.assertFalse(self.directory.exists())

    def test_existing_directory_is_preserved_even_when_empty(self):
        self.directory.mkdir()
        with api_fixture() as (port, calls):
            self.failure("Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'",
                         'must be new', port)
            self.assertEqual(calls, [])
        self.assertTrue(self.directory.exists())

    def test_busy_or_unacknowledged_start_never_retries_or_stops(self):
        for status, answer in [(500, {'Message': 'Capture already running.'}), (200, {'Message': 'Error'})]:
            with self.subTest(status=status), api_fixture({('POST', '/api/capture'): (status, answer)}) as (port, calls):
                self.failure("Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'",
                             'HTTP 500|did not acknowledge', port)
                self.assertEqual([x[0] for x in calls], ['GET', 'POST'])
                self.assertTrue(self.directory.exists())
                self.directory.rmdir()

    def test_timeout_is_bounded_and_does_not_retry_unknown_start(self):
        def delayed():
            time.sleep(4)
            return 200, {'Message': 'Capture started'}

        with api_fixture({('POST', '/api/capture'): delayed}) as (port, calls):
            start = time.monotonic()
            self.failure("Start-TrialFrameCapture $client $process '/owned/java' $expectedStart $env:PZ_CX_DIR 10 'fixture-token'",
                         'outcome may be unknown', port)
            self.assertLess(time.monotonic() - start, 6)
            self.assertEqual([x[0] for x in calls], ['GET', 'POST'])

    def test_redirects_and_nonlocal_endpoints_are_rejected(self):
        with api_fixture({('GET', '/api/version'): (302, {})}) as (port, calls):
            self.failure('Get-TrialCapFrameX -Port ([int]$env:PZ_CX_PORT)', 'HTTP 302', port)
            self.assertEqual(calls, [('GET', '/api/version', None)])
        self.failure("$client.BaseUri='http://example.test:1337'; Invoke-TrialFrameRequest $client 'GET' '/api/version'",
                     'localhost HTTP endpoint')

    def test_completion_uses_frametime_sum_checks_every_csv_pid_and_keeps_files(self):
        json_path, csv_path = self.outputs()
        before = {p: p.read_bytes() for p in (json_path, csv_path)}
        result = self.complete()
        self.assertEqual(Path(result['Json']), json_path)
        self.assertEqual(Path(result['Csv']), csv_path)
        self.assertEqual(result['DurationSeconds'], 10)
        self.assertEqual(result['FrameCount'], 10)
        self.assertEqual(result['CsvFrameCount'], 10)
        self.assertEqual(result['JsonSha256'], hashlib.sha256(before[json_path]).hexdigest())
        self.assertEqual(result['CsvSha256'], hashlib.sha256(before[csv_path]).hexdigest())
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content)

    def test_completion_is_nonblocking_until_complete_valid_outputs(self):
        self.assertIsNone(self.complete())
        json_path, csv_path = self.outputs()
        csv_path.unlink()
        self.assertIsNone(self.complete())
        self.outputs()
        json_path.write_text('{"Info":')
        self.assertIsNone(self.complete())
        self.outputs(frames=[])
        self.assertIsNone(self.complete())
        self.outputs(frames=[1000] * 8)
        self.assertIsNone(self.complete())
        # A plausible last timestamp cannot disguise a short frametime sum.
        data = json.loads(json_path.read_text())
        data['Runs'][0]['CaptureData']['TimeInSeconds'][-1] = 10
        json_path.write_text(json.dumps(data))
        self.assertIsNone(self.complete())

    def test_partial_csv_is_not_complete_and_additional_valid_raw_frames_are_allowed(self):
        self.outputs(pids=[4242])
        self.assertIsNone(self.complete())
        self.outputs(pids=[4242] * 11)
        self.assertEqual(self.complete()['CsvFrameCount'], 11)

    def test_completion_refuses_open_writers_and_keeps_both_read_handles_through_hashing(self):
        json_path, csv_path = self.outputs()
        for path in (json_path, csv_path):
            with self.subTest(path=path.name):
                body = """
$receipt=[pscustomobject]@{directory=$env:PZ_CX_DIR;token='fixture-token';targetPid=4242;processName='java';seconds=10}
$writer=[IO.FileStream]::new('""" + str(path).replace("'", "''") + """',[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $result=Complete-TrialFrameCapture $receipt; ConvertTo-Json -InputObject $result -Compress }
finally { $writer.Dispose() }
"""
                self.assertIsNone(self.invoke(body))
        self.assertEqual(self.complete()['FrameCount'], 10)

    def test_decimal_frametimes_are_invariant_under_russian_culture(self):
        self.outputs(frames=[1000.25] * 10)
        result = self.invoke("""
[Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('ru-RU')
$receipt=[pscustomobject]@{directory=$env:PZ_CX_DIR;token='fixture-token';targetPid=4242;processName='java';seconds=10}
Complete-TrialFrameCapture $receipt | ConvertTo-Json -Compress
""")
        self.assertAlmostEqual(result['DurationSeconds'], 10.0025)

    @unittest.skipIf(os.name == 'nt', 'Symlink fixture requires Unix; Windows junction guard uses the same reparse flag')
    def test_linked_output_or_parent_path_is_rejected(self):
        json_path, _ = self.outputs()
        outside = self.root / 'outside.json'
        json_path.rename(outside)
        json_path.symlink_to(outside)
        self.failure("$r=[pscustomobject]@{directory=$env:PZ_CX_DIR}; Complete-TrialFrameCapture $r", 'symbolic links or junctions')
        linked = self.root / 'linked'
        linked.symlink_to(self.directory, target_is_directory=True)
        self.failure("$r=[pscustomobject]@{directory=(Join-Path $env:APPDATA 'linked')}; Complete-TrialFrameCapture $r", 'symbolic links or junctions')

    def test_wrong_token_name_pid_duration_and_duplicate_outputs_fail_closed(self):
        fixtures = [({'token': 'foreign'}, 'token'), ({'process': 'foreign.exe'}, 'process name'),
                    ({'pids': [4242] * 9 + [9999]}, 'wrong PID'), ({'application': 'foreign.exe'}, 'process name'),
                    ({'frames': [1000] * 16}, 'duration exceeds')]
        for changes, pattern in fixtures:
            with self.subTest(changes=changes):
                self.outputs(**changes)
                self.failure("$r=[pscustomobject]@{directory=$env:PZ_CX_DIR;token='fixture-token';targetPid=4242;processName='java';seconds=10}; Complete-TrialFrameCapture $r", pattern)
        self.outputs()
        (self.directory / 'foreign.json').write_text('{}')
        self.failure("$r=[pscustomobject]@{directory=$env:PZ_CX_DIR}; Complete-TrialFrameCapture $r", 'Multiple')

    def test_import_is_inert(self):
        self.invoke("if (Test-Path -LiteralPath $env:PZ_CX_DIR) {throw 'import created capture directory'}")


if __name__ == '__main__':
    unittest.main()
