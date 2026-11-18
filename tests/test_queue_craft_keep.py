"""Keep evidence must preserve its exact independent native return and craft."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft


class CraftKeepAdapterTests(unittest.TestCase):
    def selection(self, kind='sp'):
        return dict(suite='craft', cases=[craft.KEEP_CASE], kind=kind, mode='toolkit',
                    languages=['EN'], mods=list(craft.MODS), clients=1, options={})

    def evidence(self, kind='sp'):
        ki = int(kind == 'mp'); ri = 1 - ki
        prep = dict(case=craft.KEEP_CASE, tools=[101, 102], bags=[103, 104], material=105, book=106,
                    outputs=1, materialCondition=10, materialUses=0, outputBaseline=[800],
                    sparePlanks=[dict(id=700, condition=8, uses=0)], keptIndex=ki+1,
                    playerId=42 if kind == 'mp' else -1,
                    toolMeta=[dict(id=id, kind=tool, condition=10, uses=0)
                              for id, tool in zip([101, 102], ('Base.Saw', 'Base.HandDrill'))])
        receipt = dict(case=craft.KEEP_CASE, materialId=105, bookId=106, materialPresent=False,
                       materialCondition=10, materialUses=0, consumed=1, outputs=1, outputIds=[900],
                       outputPlankCounts=[1], accountedPlanks=1, sparePlanks=copy.deepcopy(prep['sparePlanks']),
                       toolsReturned=1, toolsKept=1, tailRead=True,
                       resources=[dict(meta, sourceId=prep['bags'][i], sourceCount=int(i != ki), rootCount=int(i == ki))
                                  for i, meta in enumerate(prep['toolMeta'])])
        trace = []
        if kind == 'mp':
            identity = dict(protocol=1, player=42, transaction=3, kind='ISHandcraftAction',
                            token='12345678-1234-1234-1234-123456789abc')
            trace = [dict(identity, state=state) for state in ('started', 'completed')]
        row = dict({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'},
                   event='case', id=craft.KEEP_CASE, status='passed', reason=None, toolIds=prep['tools'],
                   pickupIds=sorted(prep['tools']), returnIds=[prep['tools'][ri]],
                   keptId=prep['tools'][ki], keptSourceId=prep['bags'][ki], siblingId=prep['tools'][ri],
                   siblingSourceId=prep['bags'][ri], keepSucceeded=True, keptRowRemoved=True,
                   siblingPreserved=True, craftProgress=True, craftProgressAfterKeep=True, keepProgress=.1,
                   tailProgress=True, returnsBeforeRead=True, tokenCancelled=False,
                   producer='CraftChainRecipes.enqueue', nativeDuration=150, authorityVerified=True,
                   playerId=prep['playerId'], outcomeTrace=trace)
        return row, prep, receipt

    def verify(self, kind='sp', evidence=None, raw_trace=None):
        row, prep, receipt = evidence or self.evidence(kind)
        selection = self.selection(kind)
        rows = [dict(event='setup', cases=selection['cases'], expected=1, queueEnabled=True, nativeDurations=True),
                row, dict(event='complete', cases=selection['cases'], expected=1, performed=1, failed=0, skipped=0)]
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(dict(value, suite='craft', kind=kind,
                         mode='toolkit', actor='client1')) for value in rows)
        text += '\n' + '\n'.join('[CRAFT_QUEUE_TEST] OUTCOME ' + json.dumps(value)
                                  for value in (row['outcomeTrace'] if raw_trace is None else raw_trace))
        authority = '\n'.join('[CRAFT_QUEUE_TEST] ' + marker + ' ' + json.dumps(value)
                              for marker, value in [('PREPARED', prep), ('KEEP_AUTHORITY', receipt)])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'client1-launch.log').write_text(text + ('\n' + authority if kind == 'sp' else ''))
            if kind == 'mp':
                (root / 'server-launch.log').write_text(authority)
            return craft.verify(root, selection, {})

    def test_sp_host_keep_opposite_rows_with_exact_authority(self):
        for kind in ('sp', 'mp'):
            craft.validate(self.selection(kind))
            result = self.verify(kind)
            self.assertEqual([], result['issues'])
            self.assertEqual('passed', result['outcomes'][0]['status'])

    def test_isolated_toolkit_without_foreign_provider_required(self):
        for change in ({'mode': 'native'}, {'cases': ['borrowed-tools', craft.KEEP_CASE]},
                       {'mods': craft.MODS + ['P4TidyUpMeister']}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                craft.validate(dict(self.selection(), **change))

    def test_current_craft_sibling_and_effect_evidence_are_mandatory(self):
        for key, value in [('keptId', 102), ('keptSourceId', 104), ('siblingId', 101), ('siblingSourceId', 103),
                           ('keepSucceeded', False), ('keptRowRemoved', False), ('siblingPreserved', False),
                           ('craftProgressAfterKeep', False), ('returnIds', [101, 102]), ('pickupIds', [101]),
                           ('outputs', 2), ('outputIds', [800]), ('consumed', True), ('tokenCancelled', True),
                           ('tailRead', False), ('producer', 'fixture'), ('keepProgress', .3), ('keepProgress', 0)]:
            evidence = self.evidence(); evidence[0][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence=evidence)['issues'])

    def test_authoritative_endpoints_conservation_and_spares_are_mandatory(self):
        for change in ('swapped-origin', 'root-sibling', 'changed-condition', 'duplicate-output', 'missing-spare', 'authority-only'):
            row, prep, receipt = self.evidence()
            if change == 'swapped-origin':
                receipt['resources'][1]['sourceId'] = prep['bags'][0]
            elif change == 'root-sibling':
                receipt['resources'][1].update(sourceCount=0, rootCount=1)
            elif change == 'changed-condition':
                receipt['resources'][0]['condition'] = 9
            elif change == 'duplicate-output':
                receipt['outputIds'] = [prep['material']]
            elif change == 'missing-spare':
                receipt['sparePlanks'] = []
            else:
                receipt['toolsReturned'] = 2
            if change != 'authority-only':
                row.update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            with self.subTest(change=change):
                self.assertTrue(self.verify(evidence=(row, prep, receipt))['issues'])

    def test_real_host_started_completed_state_and_raw_receipt_are_required(self):
        for change in ('missing', 'rejected', 'transaction', 'token', 'raw'):
            row, prep, receipt = self.evidence('mp')
            raw = None
            if change == 'missing':
                row['outcomeTrace'] = row['outcomeTrace'][:1]
            elif change == 'rejected':
                row['outcomeTrace'][1]['state'] = 'rejected'
            elif change == 'transaction':
                row['outcomeTrace'][1]['transaction'] += 1
            elif change == 'token':
                row['outcomeTrace'][1]['token'] = '12345678-1234-1234-1234-123456789abd'
            else:
                raw = []
            with self.subTest(change=change):
                self.assertTrue(self.verify('mp', (row, prep, receipt), raw)['issues'])


if __name__ == '__main__':
    unittest.main()
