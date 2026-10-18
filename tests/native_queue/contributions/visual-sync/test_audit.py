import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('visual_audit', Path(__file__).with_name('audit.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


def event(kind, actor='client1', ids=(1, 2), line=1, **extra):
    player = {'username': 'client1', 'local': actor == 'client1', 'worn': [
        {'item': {'id': i, 'type': 'Base.Trace'}, 'visual': {'object': i}} for i in ids]}
    return dict(kind=kind, actor=actor, line=line, timeMs=100, player=player,
                packetVisuals=[{'object': i} for i in ids], wire={'sha256': 'bytes'}, **extra)


class AuditTests(unittest.TestCase):
    def packets(self, sent=(1, 2), received=(1, 2)):
        return [event('visual.write', 'server', sent), event('visual.parse.enter', count=len(sent)),
                event('visual.parse.exit', ids=received, remaining=0)]

    def test_matching_wire_and_order(self):
        result = module.audit(self.packets()); self.assertEqual(result['issues'], [])
        self.assertFalse(result['mismatches']); self.assertFalse(result['identityMismatches'])
        self.assertTrue(result['packets'][0]['wireMatched'])
        self.assertTrue(result['identitiesVerified'])

    def test_count_and_equal_count_reorder_detected(self):
        self.assertEqual(len(module.audit(self.packets(received=(1,)))['mismatches']), 1)
        result = module.audit(self.packets(received=(2, 1)))
        self.assertEqual(len(result['identityMismatches']), 1); self.assertFalse(result['mismatches'])

    def test_identical_bytes_do_not_prove_unique_identities(self):
        rows = self.packets(); rows.insert(0, event('visual.write', 'server', (3, 4)))
        result = module.audit(rows)
        self.assertTrue(result['packets'][0]['identityAmbiguous']); self.assertFalse(result['identityMismatches'])
        self.assertFalse(result['identitiesVerified'])

    def test_unmatched_or_unknown_ids_cannot_certify_identity(self):
        rows = self.packets(); rows.pop(0)
        self.assertFalse(module.audit(rows)['identitiesVerified'])
        rows = self.packets(); rows[-1]['packetVisuals'][0] = {'object': 999}
        self.assertFalse(module.audit(rows)['identitiesVerified'])

    def test_remote_visuals_map_to_worn_object_ids(self):
        rows = self.packets(); rows[-1]['packetVisuals'] = [{'object': 1, 'item': None}, {'item': {'id': 0}}]
        self.assertEqual(module.visual_ids(rows[-1]), [1, 0])

    def test_local_removed_ids_returned_by_clothing(self):
        rows = self.packets()
        removed = event('bandage.remove', ids=(2,), line=10); removed['before'] = event('before')['player']
        rows += [removed, event('clothing.process.exit', line=11)]
        result = module.audit(rows)
        self.assertEqual(result['reintroducedRemovedIDs'][0]['id'], 1)
        self.assertEqual(result['reintroducedRemovedIDs'][0]['removedLine'], 10)

    def test_remote_cleanup_is_not_local_removal(self):
        row = event('bandage.remove', actor='client2', ids=()); row['before'] = event('before')['player']
        result = module.audit(self.packets() + [row]); self.assertFalse(result['localRemovals'])

    def test_final_convergence_requires_both_local_and_server_clear(self):
        removed = event('bandage.remove', ids=(2,), line=10); removed['before'] = event('before')['player']
        rows = self.packets() + [removed, event('clothing.process.exit', 'server', (2,), line=11)]
        self.assertTrue(module.audit(rows)['allRemovedConverged'])
        rows[-1] = event('visual.write', 'server', (1, 2), line=11)
        self.assertFalse(module.audit(rows)['allRemovedConverged'])
        self.assertFalse(module.audit(self.packets())['allRemovedConverged'])

    def test_missing_capture_and_capped_trace_are_issues(self):
        self.assertTrue(module.audit([])['issues'])
        self.assertTrue(module.audit(self.packets() + [event('lineCap')])['issues'])

    def test_unclosed_and_failed_parse_are_issues(self):
        self.assertTrue(module.audit([event('visual.parse.exit')])['issues'])
        self.assertTrue(module.audit([event('visual.parse.enter')])['issues'])
        rows = self.packets(); rows[-1]['error'] = 'native failure'
        self.assertTrue(module.audit(rows)['issues'])


if __name__ == '__main__':
    unittest.main()
