"""Receipt retries and reconnects must preserve exactly the same item evidence."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('native_tags', Path(__file__).parent / 'native_tags/run.py')
native_tags = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native_tags)


class ReceiptChecks(unittest.TestCase):
    def setUp(self):
        self.receipt = dict(actor='client1', phase='enabled', exact=True,
                            originalInventoryUnchanged=True, ids={'42': {'source': 0, 'destination': 1}})

    def test_retry_and_reconnect_reuse_identical_ids(self):
        native_tags.validate_receipts([self.receipt, copy.deepcopy(self.receipt)], 'client1', ['enabled'])

    def test_missing_or_changed_authority_evidence_is_rejected(self):
        changed = copy.deepcopy(self.receipt)
        changed['ids']['42']['destination'] = 0
        for receipts in ([], [changed, self.receipt], [dict(self.receipt, exact=False)],
                         [dict(self.receipt, originalInventoryUnchanged=False)]):
            with self.subTest(receipts=receipts), self.assertRaises(AssertionError):
                native_tags.validate_receipts(receipts, 'client1', ['enabled'])

    def test_reconnect_requires_both_authority_epochs(self):
        before = dict(self.receipt, reconnected=False)
        after = dict(self.receipt, reconnected=True)
        native_tags.validate_reconnect_receipts([before, after], 'client1', 'enabled')
        for invalid in ([before], [after], [self.receipt, before], [dict(before, actor='client2'), after]):
            with self.subTest(receipts=invalid), self.assertRaises(AssertionError):
                native_tags.validate_reconnect_receipts(invalid, 'client1', 'enabled')


class PlacementChecks(unittest.TestCase):
    def test_both_load_acknowledgements_precede_native_creation(self):
        import json
        ready = lambda actor, signature='same': '[TAG_PLACEMENT_READY] ' + json.dumps(dict(actor=actor, signature=signature))
        created = lambda actor: '[TAG_PLACEMENT] ' + json.dumps(dict(actor=actor))
        valid = [ready('client1'), ready('client2'), created('client1'), created('client2')]
        native_tags.validate_placement_order('\n'.join(valid))
        for invalid in ([ready('client1'), created('client1'), ready('client2'), created('client2')],
                        [ready('client1'), ready('client2', 'other'), *valid[2:]],
                        valid + [created('client1')], valid[:-1]):
            with self.subTest(log=invalid), self.assertRaises(AssertionError):
                native_tags.validate_placement_order('\n'.join(invalid))


if __name__ == '__main__':
    unittest.main()
