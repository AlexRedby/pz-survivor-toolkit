"""Reading evidence requires exact effects, not just an empty action queue."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))
from queue_checks.adapters import bulk_reading


class BulkReadingReportTests(unittest.TestCase):
    def test_exact_authority_and_client_effects_are_required(self):
        selection = {'kind': 'mp'}
        ids = list(range(101, 116))
        receipt = {'count': 15, 'items': [{'id': value, 'read': True, 'returned': True} for value in ids]}
        profile = {'frames': {'idle': {'samples': 100}, 'running': {'samples': 200}},
                   'enqueue': [{'count': value} for value in range(5, 16)]}

        def event(name, value):
            return bulk_reading.MARKER + name + ' ' + json.dumps(value) + '\n'

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = event('LOCAL', receipt) + event('PROFILE', profile) + bulk_reading.MARKER + 'COMPLETE\n'
            (root / 'client1-launch.log').write_text(client)
            server = root / 'server-launch.log'
            prepared = event('PREPARED', {'ids': ids})
            server.write_text(prepared + event('AUTHORITY', receipt))
            self.assertFalse(bulk_reading.verify(root, selection, {})['issues'])
            for change in ('unread', 'not-returned', 'wrong-id', 'missing-authority', 'duplicate-authority'):
                with self.subTest(change=change):
                    broken = copy.deepcopy(receipt)
                    if change == 'unread': broken['items'][0]['read'] = False
                    if change == 'not-returned': broken['items'][0]['returned'] = False
                    if change == 'wrong-id': broken['items'][0]['id'] = 999
                    records = 0 if change == 'missing-authority' else 2 if change == 'duplicate-authority' else 1
                    server.write_text(prepared + event('AUTHORITY', broken) * records)
                    self.assertTrue(bulk_reading.verify(root, selection, {})['issues'])
            server.write_text(prepared + event('AUTHORITY', receipt))
            (root / 'client1-launch.log').write_text(client.replace(bulk_reading.MARKER + 'COMPLETE\n', ''))
            self.assertTrue(bulk_reading.verify(root, selection, {})['issues'])
