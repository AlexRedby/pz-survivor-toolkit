"""Live loopback admission protocol checks with a JDK only; no game or patch build."""
from contextlib import contextmanager
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).parent / 'net/alexredby/pztoolkitjavapatches/TimingAdmission.java'
BANK = 'checks.TimingBank'
TOKEN = 'a' * 64
REGISTRATION = 'b' * 32


@unittest.skipUnless(shutil.which('javac') and shutil.which('java'), 'requires a local JDK')
class JvmTimingGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='pz-timing-guard-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.classes = Path(cls.temporary.name)
        harness = cls.classes / 'TimingGuardProbe.java'
        harness.write_text('''import net.alexredby.pztoolkitjavapatches.TimingAdmission;
public class TimingGuardProbe {
    public static void main(String[] args) {
        if (args.length > 0 && args[0].equals("optional")) {
            System.out.println("REQUESTED=" + TimingAdmission.requested(
                java.util.Arrays.copyOfRange(args, 1, args.length), "checks.TimingBank"));
        } else {
            System.out.println("REGISTRATION=" + TimingAdmission.require("checks.TimingBank"));
            if (args.length > 0 && args[0].equals("twice")) {
                TimingAdmission.require("checks.TimingBank");
            }
        }
    }
}
''')
        subprocess.run([shutil.which('javac'), '-d', str(cls.classes), str(SOURCE), str(harness)],
                       check=True, capture_output=True, text=True)

    def command(self, *, port=None, properties=None, args=()):
        values = {'pz.timing.port': str(port or 1), 'pz.timing.token': TOKEN,
                  'pz.timing.bank': BANK, 'pz.timing.owner': str(os.getpid())}
        if properties is not None:
            values.update(properties)
        return [shutil.which('java'), *(f'-D{key}={value}' for key, value in values.items() if value is not None),
                '-cp', str(self.classes), 'TimingGuardProbe', *args]

    def run_probe(self, **kwargs):
        return subprocess.run(self.command(**kwargs), capture_output=True, text=True, timeout=8)

    @contextmanager
    def service(self, response=None, count=1):
        requests, failures = [], []
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(5)
        port = listener.getsockname()[1]

        def serve():
            try:
                for index in range(count):
                    connection, _ = listener.accept()
                    with connection:
                        connection.settimeout(3)
                        line = bytearray()
                        while not line.endswith(b'\n'):
                            chunk = connection.recv(1)
                            if not chunk:
                                raise AssertionError('JVM closed before request newline')
                            line.extend(chunk)
                            if len(line) > 512:
                                raise AssertionError('Admission request exceeded protocol bound')
                        fields = line.decode('ascii').rstrip('\n').split('\t')
                        requests.append(fields)
                        reply = (f'PZ_TIMING_OK\t{REGISTRATION}\t{BANK}\t{fields[3]}\n'
                                 if response is None else response(fields, index))
                        connection.sendall(reply.encode('ascii'))
            except Exception as error:
                failures.append(error)
            finally:
                listener.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        try:
            yield port, requests
        finally:
            thread.join(6)
            self.assertFalse(thread.is_alive(), 'Admission test service did not finish')
            if failures:
                raise failures[0]

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('IllegalStateException: JVM timing admission rejected:', result.stderr)
        self.assertNotIn('TIMING_ADMISSION ', result.stdout)
        self.assertNotIn('REGISTRATION=', result.stdout)
        self.assertNotIn(TOKEN, result.stderr)

    def test_untimed_functional_request_needs_no_properties_or_service(self):
        empty = {key: None for key in ('pz.timing.port', 'pz.timing.token', 'pz.timing.bank', 'pz.timing.owner')}
        result = self.run_probe(properties=empty, args=('optional',))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'REQUESTED=false')

    def test_direct_and_explicit_measurement_require_live_admission(self):
        for args in ((), ('optional', '--measure')):
            with self.subTest(args=args), self.service() as (port, requests):
                result = self.run_probe(port=port, args=args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(requests), 1)
            self.assertEqual(requests[0][:3], ['PZ_TIMING_V1', TOKEN, BANK])
            self.assertGreater(int(requests[0][3]), 0)
            self.assertIn(f'TIMING_ADMISSION {REGISTRATION} {BANK} pid={requests[0][3]}', result.stdout)

    def test_missing_invalid_or_wrong_bank_properties_reject_before_connecting(self):
        cases = [{'pz.timing.bank': None}, {'pz.timing.bank': 'checks.OtherBank'},
                 {'pz.timing.token': None}, {'pz.timing.token': TOKEN.upper()},
                 {'pz.timing.port': None}, {'pz.timing.port': '0'}, {'pz.timing.port': '65536'},
                 {'pz.timing.owner': None}, {'pz.timing.owner': '0'}, {'pz.timing.owner': '999999999999'}]
        for properties in cases:
            with self.subTest(properties=properties):
                self.assert_rejected(self.run_probe(properties=properties))

    def test_closed_service_rejects_stale_admission(self):
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
        listener.close()
        self.assert_rejected(self.run_probe(port=port))

    def test_unresponsive_live_service_times_out(self):
        def silence(fields, index):
            threading.Event().wait(2.2)
            return ''
        with self.service(silence) as (port, _):
            result = self.run_probe(port=port)
        self.assert_rejected(result)
        self.assertIn('SocketTimeoutException', result.stderr)

    def test_refused_malformed_truncated_and_wrong_process_responses_reject(self):
        responses = [lambda f, i: 'PZ_TIMING_DENIED\n',
                     lambda f, i: f'PZ_TIMING_OK\t{"B" * 32}\t{BANK}\t{f[3]}\n',
                     lambda f, i: f'PZ_TIMING_OK\t{REGISTRATION}\tchecks.OtherBank\t{f[3]}\n',
                     lambda f, i: f'PZ_TIMING_OK\t{REGISTRATION}\t{BANK}\t{int(f[3]) + 1}\n',
                     lambda f, i: 'incomplete', lambda f, i: 'x' * 513 + '\n']
        for response in responses:
            with self.subTest(response=response), self.service(response) as (port, _):
                self.assert_rejected(self.run_probe(port=port))

    def test_registration_is_checked_again_on_each_require(self):
        def response(fields, index):
            return (f'PZ_TIMING_OK\t{REGISTRATION}\t{BANK}\t{fields[3]}\n'
                    if index == 0 else 'PZ_TIMING_DENIED\n')
        with self.service(response, count=2) as (port, requests):
            result = self.run_probe(port=port, args=('twice',))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(requests), 2)
        self.assertEqual(result.stdout.count('TIMING_ADMISSION '), 1)

    def test_owner_can_be_ancestor_through_worker_process(self):
        with self.service() as (port, _):
            result = subprocess.run([sys.executable, '-c',
                                     'import subprocess,sys;sys.exit(subprocess.call(sys.argv[1:]))',
                                     *self.command(port=port)], capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_real_admission_service_attests_a_real_jvm_without_game_inputs(self):
        from tools.queue_checks import admission, timing, preparation_process
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            snapshot = dict(total_memory=16 * 1024**3, available_memory=12 * 1024**3,
                            cpu_count=8, processes=[])
            with patch.object(admission, 'STATE', directory / 'state'), \
                    patch.object(admission, 'LEGACY_LOCK', directory / 'legacy.lock'), \
                    patch.object(admission, 'WINDOWS_HOST_MUTEX', 'PZToolkitTimingTest-' + directory.name), \
                    patch.object(admission.host, 'sample', return_value=snapshot):
                with timing.acquire(directory / 'bank', BANK, wait=0, heap_mib=64, native_mib=64) as registration:
                    result = preparation_process.run([shutil.which('java'), *registration.java_options,
                        '-cp', str(self.classes), 'TimingGuardProbe'], capture_output=True, text=True, timeout=8)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    evidence = registration.validate(result.stdout)
                    self.assertTrue(evidence['attested'])
                    self.assertEqual(evidence['admission']['phase'], 'timing')
                    self.assertTrue(evidence['admission']['exclusive'])
                self.assertEqual(admission.status()['timing'], [])


if __name__ == '__main__':
    unittest.main()
