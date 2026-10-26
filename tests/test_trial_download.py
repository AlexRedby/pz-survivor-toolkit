"""Streaming download fixtures; local HTTP only, no GitHub or game launches."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest

PWSH = shutil.which('pwsh')
SCRIPT = Path(__file__).resolve().parent / 'optimizer_trial' / 'TrialDownload.ps1'
PAYLOAD = b'bounded streaming fixture\n' * 4096


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


class DownloadFixture(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def handle(self):
        try:
            super().handle()
        except ConnectionResetError:
            # Cancellation deliberately closes a keep-alive connection.
            pass

    def do_GET(self):
        try:
            if self.path == '/headers-stall':
                time.sleep(4)
                return
            if self.path == '/redirect':
                self.send_response(302)
                self.send_header('Location', '/chunked')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if self.path == '/unsafe-redirect':
                self.send_response(302)
                self.send_header('Location', 'http://example.com/private?secret=hidden')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            self.send_response(200)
            if self.path == '/oversize':
                self.send_header('Content-Length', str(256 * 1024 * 1024 + 1))
            elif self.path in ('/chunked', '/drip', '/heartbeat'):
                self.send_header('Transfer-Encoding', 'chunked')
            elif self.path == '/truncated':
                self.send_header('Content-Length', str(len(PAYLOAD) + 100))
                self.send_header('Connection', 'close')
            elif self.path == '/body-stall':
                self.send_header('Content-Length', '100')
            else:
                self.send_header('Content-Length', str(len(PAYLOAD)))
            self.end_headers()
            if self.path == '/oversize':
                return
            if self.path == '/body-stall':
                self.wfile.write(b'1234567')
                self.wfile.flush()
                time.sleep(4)
                return
            if self.path in ('/chunked', '/drip', '/heartbeat'):
                chunks = [PAYLOAD] if self.path == '/chunked' else [b'x'] * 25
                for chunk in chunks:
                    self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                    self.wfile.flush()
                    if self.path in ('/drip', '/heartbeat'):
                        time.sleep(.25)
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
            else:
                self.wfile.write(PAYLOAD)
                self.wfile.flush()
                if self.path == '/truncated':
                    self.close_connection = True
        except (BrokenPipeError, ConnectionResetError):
            pass


@unittest.skipUnless(PWSH, 'PowerShell 7 is required for portable download fixtures')
class TrialDownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), DownloadFixture)
        cls.server.daemon_threads = True
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.destination = Path(self.temp.name).resolve() / 'asset.partial'

    def download(self, route='/normal', expected=0, idle=2, total=15, uri=None):
        source = uri or self.base_url + route
        body = f"""
$ErrorActionPreference='Stop'
. {ps(SCRIPT)}
try {{
  $result=Save-TrialDownload -Uri {ps(source)} -Destination {ps(self.destination)} -ExpectedBytes {expected} -IdleTimeoutSeconds {idle} -TotalTimeoutSeconds {total}
  Write-Output ('RESULT:' + (@{{Ok=$true;Bytes=$result.Bytes;Elapsed=$result.ElapsedSeconds}} | ConvertTo-Json -Compress))
}} catch {{
  # Verify disposal allows another exclusive managed open immediately after failure.
  $closed=$true
  if ([IO.File]::Exists({ps(self.destination)})) {{
    try {{ $probe=[IO.File]::Open({ps(self.destination)},'Open','ReadWrite','None'); $probe.Dispose() }} catch {{ $closed=$false }}
  }}
  Write-Output ('RESULT:' + (@{{Ok=$false;Error=$_.Exception.Message;Closed=$closed}} | ConvertTo-Json -Compress))
}}
"""
        started = time.monotonic()
        process = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', body], capture_output=True, text=True, timeout=25)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        lines = [line for line in process.stdout.splitlines() if line.startswith('RESULT:')]
        self.assertEqual(len(lines), 1, process.stdout + process.stderr)
        return json.loads(lines[0][7:]), process.stdout, time.monotonic() - started

    def test_known_length_and_expected_size(self):
        result, output, _ = self.download(expected=len(PAYLOAD))
        self.assertTrue(result['Ok'], output)
        self.assertEqual(result['Bytes'], len(PAYLOAD))
        self.assertEqual(self.destination.read_bytes(), PAYLOAD)
        self.assertIn('Download complete:', output)
        self.assertIn(' bytes (', output)
        self.assertIn('/', output)
        self.assertIn('%', output)

    def test_chunked_and_relative_redirect(self):
        for route in ('/chunked', '/redirect'):
            with self.subTest(route=route):
                result, output, _ = self.download(route, expected=len(PAYLOAD))
                self.assertTrue(result['Ok'], output)
                self.assertEqual(self.destination.read_bytes(), PAYLOAD)
                self.destination.unlink()

    def test_stalled_headers_and_body_are_bounded_and_closed(self):
        for route, partial in (('/headers-stall', b''), ('/body-stall', b'1234567')):
            with self.subTest(route=route):
                result, output, elapsed = self.download(route, idle=1)
                self.assertFalse(result['Ok'], output)
                self.assertIn('inactivity timeout', result['Error'])
                self.assertIn(f'{len(partial)} bytes', result['Error'])
                self.assertTrue(result['Closed'])
                self.assertLess(elapsed, 3.8)
                self.assertEqual(self.destination.read_bytes(), partial)
                self.destination.unlink()

    def test_total_deadline_is_bounded_despite_continuous_data(self):
        result, output, elapsed = self.download('/drip', idle=2, total=2)
        self.assertFalse(result['Ok'], output)
        self.assertIn('total timeout', result['Error'])
        self.assertTrue(result['Closed'])
        self.assertLess(elapsed, 4.5)
        self.assertGreater(self.destination.stat().st_size, 0)

    def test_live_heartbeat_reports_bytes_and_wait_time(self):
        result, output, _ = self.download('/heartbeat', idle=2)
        self.assertTrue(result['Ok'], output)
        progress = [line for line in output.splitlines() if line.startswith('Download:')]
        self.assertGreaterEqual(len(progress), 2, output)
        self.assertIn('bytes', progress[-1])
        self.assertIn('waiting', progress[-1])
        self.assertLessEqual(len(progress), 3, output)

    def test_expected_header_mismatch_and_truncated_body_fail(self):
        for route, expected in (('/normal', 1), ('/truncated', 0), ('/chunked', len(PAYLOAD) + 1)):
            with self.subTest(route=route):
                result, output, _ = self.download(route, expected=expected)
                self.assertFalse(result['Ok'], output)
                self.assertTrue(result['Closed'])
                self.destination.unlink()

    def test_content_length_cap_is_enforced_before_writing(self):
        result, output, _ = self.download('/oversize')
        self.assertFalse(result['Ok'], output)
        self.assertIn('256 MiB', result['Error'])
        self.assertEqual(self.destination.stat().st_size, 0)

    def test_existing_file_is_never_overwritten(self):
        self.destination.write_bytes(b'keep me')
        result, output, _ = self.download()
        self.assertFalse(result['Ok'], output)
        self.assertEqual(self.destination.read_bytes(), b'keep me')

    def test_unapproved_url_and_redirect_are_rejected_without_leaking_query(self):
        for uri, route in (('http://example.com/file?secret=hidden', '/normal'), (None, '/unsafe-redirect'), ('https://example.com/file', '/normal')):
            with self.subTest(uri=uri, route=route):
                result, output, _ = self.download(route, uri=uri)
                self.assertFalse(result['Ok'], output)
                self.assertNotIn('secret', result['Error'])
                if self.destination.exists():
                    self.destination.unlink()

    def test_relative_destination_is_rejected(self):
        self.destination = Path('relative.partial')
        result, output, _ = self.download()
        self.assertFalse(result['Ok'], output)
        self.assertIn('absolute path', result['Error'])

    def test_missing_parent_and_link_parent_are_rejected(self):
        self.destination = Path(self.temp.name).resolve() / 'missing' / 'file'
        result, output, _ = self.download()
        self.assertFalse(result['Ok'], output)
        self.destination.parent.symlink_to(Path(self.temp.name).resolve(), target_is_directory=True)
        result, output, _ = self.download()
        self.assertFalse(result['Ok'], output)
        self.assertIn('link or junction', result['Error'])


if __name__ == '__main__':
    unittest.main()
