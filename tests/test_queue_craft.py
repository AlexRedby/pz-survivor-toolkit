"""Craft evidence must prove exact tools, native effects and completion ownership."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft


class CraftAdapterTests(unittest.TestCase):
    AUTHORITY = '[CRAFT_QUEUE_TEST] AUTHORITY consumed=1 outputs=1 toolsReturned=2 tailRead=true'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='craft', cases=['borrowed-tools'], kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(craft.MODS), clients=1, options={})

    def records(self):
        enabled = self.selection['mode'] == 'toolkit'
        rows = [dict(event='setup', cases=['borrowed-tools'], expected=1,
                     queueEnabled=enabled, nativeDurations=True),
                dict(event='case', id='borrowed-tools', status='passed', consumed=1, outputs=1,
                     toolsReturned=2, tailRead=True, returnsBeforeRead=enabled,
                     sharedPerform=enabled, sharedComplete=enabled and self.selection['kind'] == 'sp',
                     localDeferrals=0, nativeDuration=150, authorityVerified=True,
                     toolIds=[101, 202], returnOrder=[101, 202]),
                dict(event='complete', cases=['borrowed-tools'], expected=1, performed=1, failed=0, skipped=0)]
        return [dict(row, suite='craft', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1')
                for row in rows]

    def verify(self, rows=None, authority=None, extra=''):
        if rows is None:
            rows = self.records()
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + extra
        authority = self.AUTHORITY if authority is None else authority
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority)
        else:
            text += '\n' + authority
        (self.root / 'client1-launch.log').write_text(text)
        return craft.verify(self.root, self.selection, {})

    def test_sp_mp_native_and_toolkit_success(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                with self.subTest(kind=kind, mode=mode):
                    self.selection.update(kind=kind, mode=mode)
                    craft.validate(self.selection)
                    result = self.verify()
                    self.assertEqual(result['issues'], [])
                    self.assertEqual(result['outcomes'], [dict(actor='client1', case='borrowed-tools',
                        status='passed', reason='', outcome=dict(consumed=1, outputs=1, toolsReturned=2,
                        tailRead=True, returnsBeforeRead=mode == 'toolkit', localDeferrals=0,
                        nativeDuration=150, authorityVerified=True))])

    def test_invalid_selections_are_rejected(self):
        for change in ({'cases': []}, {'cases': ['other']}, {'cases': ['borrowed-tools'] * 2},
                       {'kind': 'coop'}, {'mode': 'other'}, {'languages': ['RU']},
                       {'languages': ['EN', 'EN']}, {'clients': True}, {'clients': 2},
                       {'mods': craft.MODS[:-1]}, {'options': {'world_template': '/old/save'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                craft.validate(dict(self.selection, **change))

    def test_exact_tool_identity_and_return_order_are_required(self):
        for ids, order in ((None, [101, 202]), ([], []), ([101], [101]), ([101, 101], [101, 101]),
                           ([101, '202'], [101, '202']), ([True, 202], [True, 202]),
                           ([1, 202], [True, 202]), ([101, 202], [101.0, 202.0]),
                           ([101, 202], None), ([101, 202], [202, 101]),
                           ([101, 202], [101, 303]), ([101, 202], [101, 202, 303])):
            rows = self.records()
            rows[1].update(toolIds=ids, returnOrder=order)
            with self.subTest(ids=ids, order=order):
                self.assertTrue(self.verify(rows)['issues'])

    def test_missing_duplicate_reordered_or_error_events_fail(self):
        rows = self.records()
        for changed in ([], rows[1:], rows[:-1], rows + [rows[-1]], rows + [rows[1]],
                        [rows[1], rows[0], rows[2]], [rows[0], dict(rows[1], event='error'), rows[2]]):
            with self.subTest(events=[row['event'] for row in changed]):
                result = self.verify(changed)
                self.assertTrue(result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_malformed_event_envelopes_are_rejected(self):
        for event in ('not json', '[]', '{}', '{"event": "unknown"}'):
            with self.subTest(event=event), self.assertRaises(ValueError):
                self.verify(extra='[QUEUE_CHECK] ' + event)

    def test_wrong_context_fails(self):
        for key, value in (('suite', 'equipment'), ('kind', 'mp'), ('mode', 'native'), ('actor', 'client2')):
            rows = self.records()
            rows[1][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify(rows)['issues'])

    def test_native_effects_counts_and_strict_types_are_required(self):
        for index, key, value in ((0, 'expected', True), (0, 'queueEnabled', 1), (0, 'nativeDurations', False),
                                  (1, 'consumed', 0), (1, 'outputs', 2), (1, 'toolsReturned', 1),
                                  (1, 'tailRead', False), (1, 'nativeDuration', 1),
                                  (1, 'authorityVerified', False), (1, 'status', 'skipped'),
                                  (2, 'performed', True), (2, 'failed', 1), (2, 'skipped', 1)):
            rows = self.records()
            rows[index][key] = value
            with self.subTest(index=index, key=key):
                self.assertTrue(self.verify(rows)['issues'])
        for index, key in ((0, 'nativeDurations'), (1, 'toolIds'), (1, 'outputs'), (2, 'performed')):
            rows = self.records()
            del rows[index][key]
            with self.subTest(missing=key):
                self.assertTrue(self.verify(rows)['issues'])

    def test_completion_phase_and_local_deferral_must_match_selected_mode(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for key in ('returnsBeforeRead', 'sharedPerform', 'sharedComplete'):
                    rows = self.records()
                    rows[1][key] = not rows[1][key]
                    with self.subTest(kind=kind, mode=mode, key=key):
                        self.assertTrue(self.verify(rows)['issues'])
                for value in (1, True, None):
                    rows = self.records()
                    rows[1]['localDeferrals'] = value
                    with self.subTest(kind=kind, mode=mode, localDeferrals=value):
                        self.assertTrue(self.verify(rows)['issues'])

    def test_authoritative_receipt_must_be_unique_and_exact(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for receipt in ('', self.AUTHORITY + '\n' + self.AUTHORITY,
                            self.AUTHORITY.replace('consumed=1', 'consumed=0'),
                            self.AUTHORITY.replace('outputs=1', 'outputs=2'),
                            self.AUTHORITY.replace('toolsReturned=2', 'toolsReturned=1'),
                            self.AUTHORITY.replace('tailRead=true', 'tailRead=false')):
                with self.subTest(kind=kind, authority=receipt):
                    self.assertTrue(self.verify(authority=receipt)['issues'])
            self.assertTrue(self.verify(extra='[QUEUE_TEST] FAIL fixture')['issues'])
        self.assertTrue(self.verify(authority=self.AUTHORITY + '\n[QUEUE_TEST] FAIL server')['issues'])

    def test_completion_marker_requires_exactly_one_client_completion(self):
        for text in ('', '[CRAFT_QUEUE_TEST] COMPLETE_PENDING',
                     '[CRAFT_QUEUE_TEST] COMPLETE\n[CRAFT_QUEUE_TEST] COMPLETE'):
            self.assertFalse(craft.complete(self.selection, 'client1', text))
        self.assertTrue(craft.complete(self.selection, 'client1', '[CRAFT_QUEUE_TEST] COMPLETE\n'))
        self.assertFalse(craft.complete(self.selection, 'server', '[CRAFT_QUEUE_TEST] COMPLETE\n'))

    def test_stage_copies_scripts_startup_and_event_writer_to_all_roles(self):
        for kind, roles in (('sp', ['client1']), ('mp', ['server', 'client1'])):
            self.selection['kind'] = kind
            runtime = {'roles': {role: {'cache': str(self.root / kind / role)} for role in roles}}
            craft.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
            for role in roles:
                media = self.root / kind / role / 'mods/ActionQueueTest/42/media'
                scripts = ROOT / 'tests/native_queue/craft/scripts'
                for script in scripts.rglob('*'):
                    if script.is_file():
                        self.assertEqual((media / 'scripts' / script.relative_to(scripts)).read_bytes(),
                                         script.read_bytes())
                for side, name, suite in (('client', 'ZZStartup.lua', 'startup'),
                                          ('server', 'ZZStartupServer.lua', 'startup'),
                                          ('shared', 'QueueHealthEvents.lua', 'health')):
                    self.assertEqual((media / 'lua' / side / name).read_bytes(),
                                     (ROOT / 'tests/native_queue' / suite / side / name).read_bytes())
            self.assertEqual(runtime['fixture']['server_ready'], '[STARTUP_TEST] SERVER_READY')
            self.assertEqual(runtime['fixture']['sandbox'], {'Zombies': 6, 'MinutesPerPage': 2.0})
        sources = craft.sources(ROOT, self.selection)
        self.assertIn(ROOT / 'tests/native_queue/craft/scripts/queue_craft.txt', sources)
        for side, name in (('client', 'ZZCraftQueue.lua'), ('server', 'ZZCraftServer.lua'),
                           ('shared', 'QueueCraftFixture.lua')):
            self.assertIn(ROOT / 'tests/native_queue/craft' / side / name, sources)
        self.assertIn(ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua', sources)
        for side, name in (('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')):
            self.assertIn(ROOT / 'tests/native_queue/startup' / side / name, sources)


if __name__ == '__main__':
    unittest.main()
