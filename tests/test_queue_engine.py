"""Engine evidence must prove exact native effects, receipts, and an independent tail."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

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

    def peer_fixture(self):
        self.selection.update(suite='engine-peers', kind='mp', clients=2, languages=['EN', 'RU'], cases=['peer-cancel'])
        tokens = ['00000000-0000-0000-0000-00000000000' + str(i) for i in range(1, 4)]
        server = '[STARTUP_TEST] SERVER_READY\n'
        for actor, condition, scraps, receipts, owner, token in [
                ('client1', 94, 2, 1, 1, tokens[0]), ('client2', 100, 0, 2, 2, tokens[1])]:
            server += f'[ENGINE_TEST] PREPARED case=peer-cancel condition=94 scraps=2 electricity=0 nativeGenerator=true actor={actor}\n'
            server += f'[ENGINE_TEST] TARGET case=peer-cancel x={10+owner} y=20 z=0 index=1 actor={actor}\n'
            server += f'[ENGINE_TEST] AUTHORITY case=peer-cancel condition={condition} scraps={scraps} tailRead=true actor={actor}\n'
            client = '[QUEUE_TEST] NATIVE_CONNECTED\n[QUEUE_TEST] PREFLIGHT_COMPLETE mods=3 mode=toolkit\n'
            client += '[ENGINE_TEST] ENQUEUED case=peer-cancel repairDuration=150 tailPages=1 nativeDurations=true\n'
            client += f'[ENGINE_TEST] CAPTURE case=peer-cancel kind=ISFixGenerator token={token} transaction=7 player={owner}\n'
            if actor == 'client1':
                client += '[ENGINE_TEST] CANCEL_REQUEST case=peer-cancel progress=true\n'
            else:
                client += f'[ENGINE_TEST] CAPTURE case=peer-cancel kind=ISFixGenerator token={tokens[2]} transaction=8 player={owner}\n'
            client += f'[ENGINE_TEST] PASS case=peer-cancel condition={condition} scraps={scraps} tailRead=true boundary=true progress=true receipts={receipts}\n'
            client += '[ENGINE_TEST] COMPLETE cases=1\n'
            (self.root / (actor + '-launch.log')).write_text(client)
        correlation = f'transaction=7 firstPlayer=1 secondPlayer=2 firstToken={tokens[0]} secondToken={tokens[1]}'
        server += f'[ENGINE_TEST] COLLISION case=peer-cancel {correlation}\n'
        server += f'[ENGINE_TEST] CANCEL_OVERLAP {correlation} otherPending=true\n[ENGINE_TEST] PROBE active=true\n'
        (self.root / 'server-launch.log').write_text(server)

    def test_peers_require_both_real_owners_and_exact_independent_outcomes(self):
        self.peer_fixture()
        engine.validate(self.selection)
        result = engine.verify(self.root, self.selection, {})
        self.assertFalse(result['issues'])
        self.assertEqual([row['actor'] for row in result['outcomes']], ['client1', 'client2'])
        self.assertTrue(engine.complete(self.selection, 'client2', (self.root / 'client2-launch.log').read_text()))
        (self.root / 'client2-launch.log').unlink()
        result = engine.verify(self.root, self.selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual([row['status'] for row in result['outcomes']], ['failed', 'failed'])

    def test_peer_collision_cannot_pass_with_foreign_identity_or_unverified_effects(self):
        changes = [
            ('client2', 'transaction=7', 'transaction=8'),
            ('client2', 'player=2', 'player=1'),
            ('client2', 'condition=100 scraps=0', 'condition=94 scraps=2'),
            ('client2', '000000000002', '000000000001'),
            ('server', 'firstToken=', 'wrongToken='),
            ('server', 'actor=client2', 'actor=client1'),
            ('server', 'condition=100 scraps=0', 'condition=98 scraps=1'),
            ('server', 'CANCEL_OVERLAP', 'HISTORICAL_STARTED'),
            ('server', 'CANCEL_OVERLAP transaction=7', 'CANCEL_OVERLAP transaction=8'),
            ('server', 'otherPending=true', 'otherPending=false'),
            ('server', 'PROBE active=true', 'PROBE active=false'),
            ('server', 'x=12 y=20', 'x=11 y=20'),
        ]
        for role, original, replacement in changes:
            with self.subTest(role=role, original=original):
                self.peer_fixture()
                path = self.root / (role + '-launch.log')
                path.write_text(path.read_text().replace(original, replacement))
                self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])

    def test_peer_stage_keeps_shared_sources_identical_and_rejects_single_client(self):
        self.peer_fixture()
        runtime = {'roles': {role: {'cache': str(self.root / role)} for role in ['server', 'client1', 'client2']}}
        probe = self.root / 'probe.jar'
        probe.write_bytes(b'read-only test probe')
        with patch.object(engine, '_peer_probe', return_value=probe):
            engine.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        for side, name in [('shared', 'QueueEngineAuthority.lua'), ('client', 'ZZEngine.lua'), ('server', 'ZZEngineServer.lua')]:
            values = [(self.root / role / 'mods/ActionQueueTest/42/media/lua' / side / name).read_bytes() for role in runtime['roles']]
            self.assertEqual(values, [values[0]] * 3)
        self.assertEqual(runtime['fixture']['mods'], ['EnginePeerProbe'])
        for role in runtime['roles']:
            layer = self.root / role / 'mods/EnginePeerProbe/42'
            self.assertEqual((layer / 'media/java/EnginePeerProbe.jar').read_bytes(), probe.read_bytes())
            self.assertIn('javaPkgName=net.alexredby.queueengineprobe', (layer / 'mod.info').read_text())
        self.assertIn(ROOT / 'tests/native_queue/engine/java/Main.java', engine.sources(ROOT, self.selection))
        for key, value in [('clients', 1), ('kind', 'sp'), ('languages', ['EN']), ('cases', ['repair', 'cancel'])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                engine.validate(dict(self.selection, **{key: value}))


if __name__ == '__main__':
    unittest.main()
