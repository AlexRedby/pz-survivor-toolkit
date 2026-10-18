"""A client completion claim cannot replace the forge's authoritative effects."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import forge


class ForgeEvidence(unittest.TestCase):
    def test_pass_requires_matching_server_receipts_and_idle_native_actions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows, receipts = [], []
            for case in forge.CASES:
                authority = dict(case=case, exactEffects=True)
                rows.append(dict(event='case', id=case, status='passed', authorityVerified=True,
                                 authority=authority, queueDrained=True, ownerIdle=True,
                                 nativeDuration=1150 if case == 'handcraft' else 1000))
                receipts.append(authority)
            def verify():
                (root / 'client1-launch.log').write_text('\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows)
                                                       + '\n[FORGE_TEST] COMPLETE\n')
                (root / 'server-launch.log').write_text('\n'.join('[FORGE_TEST] Verified ' + json.dumps(row) for row in receipts))
                return forge.verify(root, {}, {})['outcomes']
            self.assertTrue(all(row['status'] == 'passed' for row in verify()))
            receipts[1] = dict(case='forge', exactEffects=False)
            self.assertEqual(verify()[1]['status'], 'failed')
            receipts[1] = rows[1]['authority']
            rows[1]['queueDrained'] = False
            self.assertEqual(verify()[1]['status'], 'failed')
            rows[1]['queueDrained'] = True
            rows[1]['nativeDuration'] = 1
            self.assertEqual(verify()[1]['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
