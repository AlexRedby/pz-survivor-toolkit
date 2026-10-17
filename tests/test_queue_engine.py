"""Engine evidence must prove exact native effects, receipts, and an independent tail."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import engine


class EngineAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='engine', cases=['repair', 'cancel'], kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(engine.MODS), clients=1, options={})

    def fixture(self, mp=False):
        self.selection['kind'] = 'mp' if mp else 'sp'
        client = ('[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if mp else 'TRUE_SP') + '\n'
                  '[QUEUE_TEST] PREFLIGHT_COMPLETE mods=3 mode=toolkit\n')
        authority = '[STARTUP_TEST] SERVER_READY\n' if mp else ''
        for case, condition, scraps, receipts in [('repair', 100, 0, 2), ('cancel', 94, 2, 1)]:
            authority += f'[ENGINE_TEST] PREPARED case={case} condition=94 scraps=2 electricity=0 nativeGenerator=true\n'
            authority += f'[ENGINE_TEST] AUTHORITY case={case} condition={condition} scraps={scraps} tailRead=true\n'
            client += f'[ENGINE_TEST] ENQUEUED case={case} repairDuration=150 tailPages=1 nativeDurations=true\n'
            if mp:
                for index in range(receipts):
                    client += f'[ENGINE_TEST] CAPTURE case={case} kind=ISFixGenerator token=00000000-0000-0000-0000-00000000000{index}\n'
            if case == 'cancel':
                client += '[ENGINE_TEST] CANCEL_REQUEST case=cancel progress=true\n'
            client += (f'[ENGINE_TEST] PASS case={case} condition={condition} scraps={scraps}'
                       f' tailRead=true boundary=true progress=true receipts={receipts if mp else 0}\n')
        client += '[ENGINE_TEST] COMPLETE cases=2\n'
        (self.root / 'client1-launch.log').write_text(client + ('' if mp else authority))
        if mp:
            (self.root / 'server-launch.log').write_text(authority)

    def test_sp_and_mp_require_exact_native_effects_and_captured_receipts(self):
        for mp in [False, True]:
            with self.subTest(mp=mp):
                self.fixture(mp)
                self.assertFalse(engine.verify(self.root, self.selection, {})['issues'])
                path = self.root / ('server-launch.log' if mp else 'client1-launch.log')
                path.write_text(path.read_text().replace('AUTHORITY case=repair condition=100 scraps=0',
                                                        'AUTHORITY case=repair condition=98 scraps=1'))
                self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])

    def test_duplicate_or_missing_capture_cannot_pass(self):
        self.fixture(True)
        path = self.root / 'client1-launch.log'
        text = path.read_text()
        capture = next(line for line in text.splitlines() if 'CAPTURE case=repair' in line)
        path.write_text(text + capture + '\n')
        self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])
        path.write_text(text.replace(capture + '\n', ''))
        self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])

    def test_stage_reuses_existing_native_startup_and_preserves_shared_checksum(self):
        runtime = {'roles': {role: {'cache': str(self.root / role)} for role in ['server', 'client1']}}
        self.selection['kind'] = 'mp'
        engine.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        for role in ['server', 'client1']:
            target = self.root / role / 'mods/ActionQueueTest/42/media/lua'
            for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
                self.assertEqual((target / side / name).read_bytes(),
                                 (ROOT / 'tests/native_queue/startup' / side / name).read_bytes())
        self.assertEqual(runtime['fixture']['server_ready'], '[STARTUP_TEST] SERVER_READY')
        self.assertEqual(runtime['fixture']['sandbox']['MinutesPerPage'], 2.0)
        self.assertIn(ROOT / 'tests/native_queue/engine/shared/QueueEngineAuthority.lua', engine.sources(ROOT, self.selection))

    def test_rejects_unsupported_kind_mods_world_or_partial_case_list(self):
        engine.validate(self.selection)
        for key, value in [('cases', ['repair']), ('mode', 'native'), ('clients', True),
                           ('mods', ['PZSurvivorToolkit']), ('options', {'world_template': '/tmp/old'})]:
            with self.subTest(key=key):
                selection = dict(self.selection, **{key: value})
                with self.assertRaises(ValueError):
                    engine.validate(selection)


if __name__ == '__main__':
    unittest.main()
