"""Focused qualification gates: loaded modifiers, authoritative persistence, bounded actual transitions."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import lot_streaming as A


class LotStreamingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite=A.SUITE, cases=['fresh'], kind='sp', mode='toolkit', clients=1,
            languages=['EN'], mods=A.MODS, resources={'exclusive': True}, options={'lot_locks_expect': 'patched'})

    def runtime(self, patched=True, server=False, client=False):
        return dict(format=1, ok=True, server=server, client=client, seedString=A.SEED,
            getMethods=[dict(overload=o, synchronized=not patched, modifiers=9 if patched else 41) for o in ('primitive', 'boxed')],
            bootstrap=dict(available=True, active=patched, state='active' if patched else 'not-installed',
                transformations=int(patched), lotInputHash=A.LOT_HASH, poolInputHash=A.POOL_HASH),
            mapFiles=[dict(index=0, indexMatchesPriority=True)])

    def snapshot(self, generated=True):
        return dict(ok=True, runtime=self.runtime(), cells=[dict(x=x, y=y, loaded=True,
            generated=generated or i == 0, animalZones=2, geometrySha256='a' * 64,
            generatedBitRoundtrip=dict(savedBytes=1, consumedBytes=1, matches=True, restored=generated or i == 0))
            for i, (x, y) in enumerate(A.CELLS)])

    def line(self, event, value):
        return A.MARKER + event + ' ' + json.dumps(value) + '\n'

    def log(self, reload=False):
        text = ''
        if reload: text += self.line('BASELINE', dict(role='client1', phase='saved', probe=self.snapshot()))
        for phase in A.PHASES:
            text += self.line('SNAPSHOT', dict(role='client1', phase=phase, probe=self.snapshot(reload or phase != 'before')))
            text += self.line('TREES', dict(role='client1', phase=phase, probe=dict(ok=True, runtime=self.runtime(),
                chunks=[dict(trees=0, authoredLayers=[dict(payloadSha256='b' * 64)]) for _ in range(2)])))
        for phase in ('away', 'returned'):
            text += self.line('TRANSITION', dict(role='client1', phase=phase, steps=23, maxStep=12, distance=272))
        text += self.line('SAVE_READY', dict(case='reload' if reload else 'fresh', role='client1', nativeSave=True))
        text += self.line('COMPLETE', dict(case='reload' if reload else 'fresh', role='client1'))
        return text

    def verify(self, text):
        (self.root / 'client1-launch.log').write_text(text)
        return A.verify(self.root, self.selection, {})

    def test_selection_requires_real_host_exclusive_and_template(self):
        A.validate(self.selection)
        for update in ({'clients': True}, {'resources': {}}, {'options': {}}, {'kind': 'mp'}, {'cases': ['reload']}):
            with self.subTest(update=update), self.assertRaises(ValueError): A.validate(dict(self.selection, **update))
        mp = dict(self.selection, kind='mp', clients=2, languages=['EN', 'RU'], options=dict(lot_locks_expect='control', mp_host=True))
        A.validate(mp)
        A.validate(dict(self.selection, cases=['reload'], options=dict(lot_locks_expect='patched', world_template='/sealed/world')))

    def test_loaded_flags_and_transformation_count_are_required(self):
        A._runtime(self.runtime(), 'patched', False, False)
        for change in ('flags', 'count', 'hash'):
            value = self.runtime()
            if change == 'flags': value['getMethods'][0]['modifiers'] = 41
            elif change == 'count': value['bootstrap']['transformations'] = 2
            else: value['bootstrap']['lotInputHash'] = 'changed'
            with self.subTest(change=change), self.assertRaises(ValueError): A._runtime(value, 'patched', False, False)
        control = self.runtime(False); A._runtime(control, 'control', False, False)
        control['bootstrap']['transformations'] = 1
        with self.assertRaises(ValueError): A._runtime(control, 'control', False, False)

    def test_fresh_requires_natural_generation_and_actual_transition(self):
        self.assertEqual(self.verify(self.log())['issues'], [])
        text = self.log().replace('"distance": 272', '"distance": 0')
        self.assertTrue(self.verify(text)['issues'])
        text = self.log().replace('"generated": false', '"generated": true')
        self.assertTrue(self.verify(text)['issues'])

    def test_reload_compares_saved_geometry_and_generated_bits(self):
        self.selection['cases'] = ['reload']
        self.selection['options']['world_template'] = '/sealed/world'
        text = self.log(True); self.assertEqual(self.verify(text)['issues'], [])
        text = text.replace('a' * 64, 'c' * 64, 1)
        self.assertTrue(self.verify(text)['issues'])

    def test_bad_probe_and_duplicate_records_do_not_hide_beside_good_rows(self):
        text = self.log()
        self.assertTrue(self.verify(text + self.line('COMPLETE', dict(case='fresh', role='client1')))['issues'])
        self.assertTrue(self.verify(text.replace('"ok": true', '"ok": false', 1))['issues'])

    def test_lua_sources_are_bounded_and_do_not_force_generation(self):
        base = ROOT / 'tests/native_queue/lot-streaming'
        text = '\n'.join(p.read_text() for p in base.rglob('*.lua'))
        self.assertIn('steps<=40', text)
        self.assertIn('step<=16', text)
        self.assertNotIn('genAnimalsPath', text)
        self.assertNotIn('checkAnimalZonesGenerated', text)
        self.assertNotIn('setSeedString', text)

    def test_staged_fresh_reload_and_host_keep_common_bootstrap_and_owned_helpers(self):
        for kind, case in (('sp', 'fresh'), ('sp', 'reload'), ('mp', 'fresh'), ('mp', 'reload')):
            with self.subTest(kind=kind, case=case):
                root = self.root / (kind + '-' + case); root.mkdir()
                selection = dict(self.selection, kind=kind, cases=[case], clients=2 if kind == 'mp' else 1,
                    languages=['EN', 'RU'] if kind == 'mp' else ['EN'], options=dict(lot_locks_expect='patched'))
                if case == 'reload': selection['options']['world_template'] = '/sealed/world'
                if kind == 'mp': selection['options']['mp_host'] = True
                roles = ['server', 'client1', 'client2'] if kind == 'mp' else ['client1']
                runtime = dict(roles={role: {'cache': str(root / role)} for role in roles}, fixture={})
                for role in roles:
                    for side in ('client', 'shared', 'server'):
                        (root / role / 'mods/ActionQueueTest/42/media/lua' / side).mkdir(parents=True)
                if kind == 'mp':
                    (root / 'server/Server').mkdir(); (root / 'server/Server/queue-smoke.ini').write_text('Map=Muldraugh, KY\n')
                with patch.object(A.subprocess, 'run'), patch.object(A.optimizer_profile, 'stage'):
                    A.stage(ROOT, root, root / 'game', root / 'jdk', selection, {}, runtime)
                starter = root / 'client1/mods/ActionQueueTest/42/media/lua/client/ZZStartup.lua'
                text = starter.read_text()
                self.assertIn('HOST_REQUEST', text)
                self.assertIn('OnConnectFailed', text)
                if kind == 'sp' and case == 'reload': self.assertIn("continueLatestSave('Sandbox','" + A.WORLD + "')", text)
                if kind == 'sp' and case == 'fresh': self.assertIn("setSeedString('" + A.SEED + "')", text)
                if kind == 'mp': self.assertIn('Seed=' + A.SEED, (root / 'server/Server/queue-smoke.ini').read_text())
                if kind == 'mp':
                    self.assertEqual(runtime['roles']['client1']['env']['PZ_LOT_QUAL_SERVER_CACHE'], str(root / 'server'))
                self.assertEqual(runtime['fixture']['mods'], ['LotStreamingProbe'])


if __name__ == '__main__': unittest.main()
