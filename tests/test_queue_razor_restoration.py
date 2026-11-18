"""Fail-closed selection and absent/invalid live razor evidence checks."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import razor_restoration as a
from queue_checks.adapters import razor_restoration_verifier as v


def selection(kind='mp'):
    return dict(suite='razor-restoration', cases=list(a.CASES), kind=kind, mode='toolkit',
                languages=['EN'], clients=1, mods=list(a.MODS), options={'mp_host': True} if kind == 'mp' else {})


class RazorRestorationTests(unittest.TestCase):
    def test_runner_declares_ordered_real_producer_bank(self):
        self.assertEqual(adapters.get('razor-restoration'), a)
        self.assertEqual([row['id'] for row in a.definitions()['razor-restoration']['cases']], list(a.CASES))
        for kind in ('sp', 'mp'):
            a.validate(selection(kind))

    def test_selection_refuses_wrong_provider_and_dedicated_host(self):
        mutations = [lambda s: s.update(mode='native'), lambda s: s['mods'].append('P4TidyUpMeister'),
                     lambda s: s['options'].pop('mp_host'), lambda s: s.update(cases=list(reversed(a.CASES))),
                     lambda s: s.update(clients=2), lambda s: s['options'].update(world_template='old-save')]
        for mutate in mutations:
            value = copy.deepcopy(selection()); mutate(value)
            with self.assertRaises(ValueError):
                a.validate(value)

    def test_approach_admission_requires_exact_container_array_and_token(self):
        # This tests a receipt sub-schema, never a successful native case/run.
        names = ('approach', 'pickup', 'preparationEquip', 'trim', 'command')
        roles = {name: [dict(actionRef=name, operationRef='episode', allocated=True)] for name in names}
        roles['pickup'][0]['sourceRef'] = 'canonical-source'
        ids = {'bag': {'id': 42}}
        ev = dict(producerQueue=list(names), producerEntries=[dict(position=index, actionRef=name, role=name,
                  operationRef='episode', sameToken=True, actorSame=True, queueEntrySame=True)
                  for index, name in enumerate(names, 1)],
                  approach=dict(actionRef='approach', position=1, type='ISQueueActionsAction', bagId=42,
                                containerRef='canonical-source', operationRef='episode', sourceBound=True,
                                pickupSourceSame=True, canonicalBag=True, actorSame=True, sameToken=True,
                                queueSame=True, listSame=True, queueEntrySame=True))
        self.assertEqual(v.producer_errors(ev, roles, ids), [])
        for field, value in [('sourceBound', False), ('bagId', 99), ('position', 2), ('containerRef', 'foreign'),
                             ('operationRef', 'foreign'), ('queueEntrySame', False), ('listSame', False), ('actorSame', False)]:
            changed = copy.deepcopy(ev); changed['approach'][field] = value
            self.assertTrue(v.producer_errors(changed, roles, ids), field)
        changed = copy.deepcopy(ev); changed['producerEntries'][1]['position'] = 1
        self.assertTrue(v.producer_errors(changed, roles, ids))
        changed = copy.deepcopy(ev); changed['producerQueue'] = list(reversed(names))
        self.assertTrue(v.producer_errors(changed, roles, ids))
        changed = copy.deepcopy(roles); changed['pickup'][0]['operationRef'] = 'foreign'
        self.assertTrue(v.producer_errors(ev, changed, ids))

    def test_host_transfer_uses_inventory_transaction_and_canonical_identity(self):
        # Sub-schema observations only; these are not native run/pass receipts.
        ids = dict(case='restore-success', bag=dict(id=42), items={'razor': dict(id=73, type='Base.Razor')})
        physical = dict(case=ids['case'], role='pickup', at=10, authority=False, itemId=73, itemType='Base.Razor',
                        source=42, destination='root', sourceCount=0, destinationCount=1, canonical=True, bagCanonical=True)
        sample = dict(at=10, boundary='begin-perform', transaction=7, done=True, rejected=False, duration=30,
                      physical=physical, itemState='canonical-replica', itemExact=True, itemCanonical=True,
                      nativeRef='native', operationRef='episode', nativeSame=True, actorSame=True, operationSame=True,
                      sourceSame=True, destinationSame=True, queueSame=True, rootSame=True)
        action = dict(role='pickup', nativeRef='native', operationRef='episode', ack=[], transfers=[sample])
        self.assertEqual(v.transfer_errors(action, ids, 'mp'), [])
        cleared = copy.deepcopy(sample); cleared.update(boundary='finish-perform', transaction=0, done=False, itemState='nil', itemCanonical=False)
        action['transfers'].append(cleared)
        self.assertEqual(v.transfer_errors(action, ids, 'mp'), [])
        for mutate in (lambda a: a['transfers'][0].update(sourceSame=False),
                       lambda a: a['transfers'][0].update(itemExact=False),
                       lambda a: a['transfers'][0].update(rejected=True),
                       lambda a: a.update(ack=[dict(state='completed', token='invented')]),
                       lambda a: a['transfers'][0]['physical'].update(itemId=99),
                       lambda a: a['transfers'].reverse()):
            changed = copy.deepcopy(action); mutate(changed)
            self.assertTrue(v.transfer_errors(changed, ids, 'mp'))
        authority = copy.deepcopy(physical); authority['authority'] = True
        receipt = dict(transfers=[authority])
        intent_ids = copy.deepcopy(ids); intent_ids['case'] = 'new-primary-intent'; authority['case'] = intent_ids['case']
        self.assertEqual(v.authority_transfer_errors(receipt, intent_ids), [])
        authority['destinationCount'] = 0; authority['sourceCount'] = 1
        self.assertTrue(v.authority_transfer_errors(receipt, intent_ids))

    def test_missing_live_logs_never_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            result = v.verify(Path(directory), selection(), {})
        self.assertTrue(result['issues'])
        self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))

    def test_empty_case_evidence_never_passes(self):
        for kind in ('sp', 'mp'):
            self.assertTrue(v.check_case({}, selection(kind), {}, {}))

    def test_sources_exist_and_exclude_legacy_synthetic_producer(self):
        sources = a.sources(PROJECT, selection())
        self.assertTrue(all(path.is_file() for path in sources))
        self.assertFalse(any('claimed-return/client' in str(path) for path in sources))


if __name__ == '__main__':
    unittest.main()
