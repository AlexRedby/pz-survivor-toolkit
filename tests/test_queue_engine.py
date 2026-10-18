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

    def fixture(self, mp=False, mode='toolkit'):
        self.selection.update(kind='mp' if mp else 'sp', mode=mode)
        enabled = mode == 'toolkit'
        client = ('[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if mp else 'TRUE_SP') + '\n'
                  f'[QUEUE_TEST] PREFLIGHT_COMPLETE mods=3 mode={mode}\n')
        authority = '[STARTUP_TEST] SERVER_READY\n' if mp else ''
        for case, condition, scraps, receipts in [('repair', 98 if not enabled and not mp else 100,
                                                 1 if not enabled and not mp else 0, 2), ('cancel', 94, 2, 1)]:
            read = str(enabled or case == 'repair').lower()
            authority += f'[ENGINE_TEST] PREPARED case={case} condition=94 scraps=2 electricity=0 nativeGenerator=true\n'
            authority += f'[ENGINE_TEST] AUTHORITY case={case} condition={condition} scraps={scraps} tailRead={read}\n'
            client += f'[ENGINE_TEST] ENQUEUED case={case} repairDuration=150 tailPages=1 nativeDurations=true\n'
            if mp and enabled:
                for index in range(receipts):
                    client += f'[ENGINE_TEST] CAPTURE case={case} kind=ISFixGenerator token=00000000-0000-0000-0000-00000000000{index}\n'
            if case == 'cancel':
                client += '[ENGINE_TEST] CANCEL_REQUEST case=cancel progress=true\n'
            count = 2 if enabled and case == 'repair' else 0
            client += f'[ENGINE_TEST] PHASES case={case} perform={count} complete={count if not mp else 0} flush={count}\n'
            client += (f'[ENGINE_TEST] PASS case={case} condition={condition} scraps={scraps}'
                       f' tailRead={read} boundary={str(enabled).lower()} progress=true receipts={receipts if mp and enabled else 0}\n')
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

    def test_completion_phases_preserve_calibrated_host_and_zero_native_boundaries(self):
        for mp in (False, True):
            for mode in ('native', 'toolkit'):
                with self.subTest(mp=mp, mode=mode):
                    self.fixture(mp, mode)
                    result = engine.verify(self.root, self.selection, {})
                    self.assertEqual(result['issues'], [])
                    count = 2 if mode == 'toolkit' else 0
                    self.assertEqual(result['outcomes'][0]['outcome']['nativeCompletion'],
                                     dict(perform=count, complete=count if not mp else 0, flush=count))
        self.fixture(True)
        path = self.root / 'client1-launch.log'
        path.write_text(path.read_text().replace('perform=2 complete=0 flush=2', 'perform=1 complete=0 flush=1'))
        self.assertEqual(engine.verify(self.root, self.selection, {})['issues'], [])

    def test_completion_phases_reject_missing_duplicate_malformed_and_unsettled_evidence(self):
        for mp in (False, True):
            original = f'[ENGINE_TEST] PHASES case=repair perform=2 complete={0 if mp else 2} flush=2'
            mutations = ['', original + '\n' + original, original.replace('perform=2', 'perform=true'),
                         original.replace('perform=2', 'perform=2.0'), original.replace('perform=2', 'perform=-1'),
                         original.replace('perform=2', 'perform=3'), original.replace(' flush=2', ''),
                         original.replace('flush=2', 'flush=1'), original.replace('complete=0', 'complete=2') if mp
                         else original.replace('complete=2', 'complete=0')]
            for replacement in mutations:
                with self.subTest(mp=mp, replacement=replacement):
                    self.fixture(mp)
                    path = self.root / 'client1-launch.log'
                    path.write_text(path.read_text().replace(original, replacement))
                    self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])
        for mode in ('native', 'toolkit'):
            self.fixture(True, mode)
            path = self.root / 'client1-launch.log'
            path.write_text(path.read_text().replace('case=cancel perform=0 complete=0 flush=0',
                                                    'case=cancel perform=1 complete=0 flush=1'))
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

    def test_accepts_selected_cases_and_rejects_unsupported_inputs(self):
        engine.validate(self.selection)
        for mode in ('native', 'toolkit'):
            for cases in (['repair'], ['missing-target', 'late-continuation']):
                engine.validate(dict(self.selection, mode=mode, cases=cases))
        for key, value in [('cases', []), ('cases', ['repair', 'repair']), ('cases', ['unknown']), ('mode', 'unknown'), ('clients', True),
                           ('mods', ['PZSurvivorToolkit']), ('options', {'world_template': '/tmp/old'})]:
            with self.subTest(key=key):
                selection = dict(self.selection, **{key: value})
                with self.assertRaises(ValueError):
                    engine.validate(selection)

    def target_fixture(self, mode='toolkit', mp=False):
        self.selection.update(cases=['missing-target', 'late-continuation'], mode=mode, kind='mp' if mp else 'sp')
        enabled = mode == 'toolkit'
        read = str(enabled).lower()
        client = ('[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if mp else 'TRUE_SP') + '\n'
                  f'[QUEUE_TEST] PREFLIGHT_COMPLETE mods=3 mode={mode}\n')
        authority = '[STARTUP_TEST] SERVER_READY\n' if mp else ''
        for case in self.selection['cases']:
            authority += f'[ENGINE_TEST] PREPARED case={case} condition=94 scraps=2 electricity=0 nativeGenerator=true\n'
            authority += f'[ENGINE_TEST] AUTHORITY case={case} condition=94 scraps=2 tailRead={read}\n'
            client += f'[ENGINE_TEST] ENQUEUED case={case} repairDuration=150 tailPages=1 nativeDurations=true\n'
            receipts = 1 if enabled and mp and case == 'late-continuation' else 0
            if receipts:
                client += f'[ENGINE_TEST] CAPTURE case={case} kind=ISFixGenerator token=00000000-0000-0000-0000-000000000001\n'
            if case == 'missing-target':
                authority += f'[ENGINE_TEST] TARGET_REMOVED case={case} beforeRepair=true\n'
                client += f'[ENGINE_TEST] MISSING_TARGET case={case} beforeStart=true blockerProgress=true\n'
            else:
                client += f'[ENGINE_TEST] CANCEL_REQUEST case={case} progress=true\n'
                client += f'[ENGINE_TEST] LATE_CALLBACK case={case} parentRetired=true repeats=2 unchanged=true\n'
            client += f'[ENGINE_TEST] PHASES case={case} perform=0 complete=0 flush=0\n'
            client += f'[ENGINE_TEST] PASS case={case} condition=94 scraps=2 tailRead={read} boundary={read} progress=true receipts={receipts}\n'
        client += '[ENGINE_TEST] COMPLETE cases=2\n'
        (self.root / 'client1-launch.log').write_text(client + ('' if mp else authority))
        if mp:
            (self.root / 'server-launch.log').write_text(authority)

    def test_target_and_late_callback_controls_require_independent_authority_proofs(self):
        for mode in ('native', 'toolkit'):
            for mp in (False, True):
                with self.subTest(mode=mode, mp=mp):
                    self.target_fixture(mode, mp)
                    result = engine.verify(self.root, self.selection, {})
                    self.assertFalse(result['issues'], result)
                    self.assertEqual([row['outcome']['tailRead'] for row in result['outcomes']], [mode == 'toolkit'] * 2)
        for original, replacement in [('beforeRepair=true', 'beforeRepair=false'),
                                       ('beforeStart=true', 'beforeStart=false'),
                                       ('parentRetired=true', 'parentRetired=false'),
                                       ('repeats=2', 'repeats=1'), ('unchanged=true', 'unchanged=false'),
                                       ('condition=94 scraps=2', 'condition=98 scraps=1'),
                                       ('tailRead=true', 'tailRead=false')]:
            with self.subTest(original=original):
                self.target_fixture()
                path = self.root / 'client1-launch.log'
                path.write_text(path.read_text().replace(original, replacement))
                self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])
        self.target_fixture()
        path = self.root / 'client1-launch.log'
        proof = next(line for line in path.read_text().splitlines() if 'LATE_CALLBACK' in line)
        path.write_text(path.read_text() + proof + '\n')
        self.assertTrue(engine.verify(self.root, self.selection, {})['issues'])

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
            count = 2 if actor == 'client2' else 0
            client += f'[ENGINE_TEST] PHASES case=peer-cancel perform={count} complete=0 flush={count}\n'
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
