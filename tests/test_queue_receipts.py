"""Shared JSON receipt boundaries, independent of each native fixture's domain."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import receipts
from queue_checks.adapters import container_configuration, quartermaster_distribution
from queue_checks.adapters import warehouse_legacy, warehouse_manifest, warehouse_persistence


INVALID_OBJECTS = (
    '', '{', '{"value": 1} trailing', '{"value":}',
    '[]', 'null', 'true', '42', '"text"',
    '{"value": 1, "value": 2}',
    '{"nested": {"value": 1, "value": 2}}',
    '{"nested": [{"value": 1, "value": 2}]}',
    '{"value": NaN}', '{"value": Infinity}', '{"value": -Infinity}',
    '{"nested": [1e400]}', '{"nested": {"value": -1e400}}',
)


class ReceiptDecoderTests(unittest.TestCase):
    def test_preserves_json_types_and_nested_unicode_values(self):
        expected = dict(integer=123456789012345678901234567890, number=1.25,
                        yes=True, no=False, nothing=None, text='Кладовая 食料 😀',
                        nested=[{}, [1, -2.5, False, None], {'key': 'value'}])
        decoded = receipts.decode_object(json.dumps(expected, ensure_ascii=False))
        self.assertEqual(decoded, expected)
        for key in ('integer', 'number', 'yes', 'no', 'nothing', 'text', 'nested'):
            with self.subTest(key=key):
                self.assertIs(type(decoded[key]), type(expected[key]))

    def test_rejects_malformed_nonobject_duplicate_and_nonfinite_json(self):
        for payload in INVALID_OBJECTS:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                receipts.decode_object(payload)


class ReceiptRecordsTests(unittest.TestCase):
    def test_filters_exact_marker_and_event_before_decoding(self):
        text = '\r\n'.join([
            'native startup message',
            '[OTHER] STATE invalid JSON',
            '[X] OTHER invalid JSON',
            '[X] STATE_EXTRA invalid JSON',
            '[X] STATE\tinvalid JSON',
            '[X] STATE',
            '[X]STATE invalid JSON',
            'LOG : Lua , 123> [X] STATE {"index": 1}',
            '[X] STATE {"index": 2}',
            'LOG : Lua > [X] STATE {"index": 1}',
            '',
        ])
        self.assertEqual(receipts.records(text, '[X] ', 'STATE'),
                         [{'index': 1}, {'index': 2}, {'index': 1}])

    def test_selected_invalid_record_fails_instead_of_disappearing(self):
        for payload in INVALID_OBJECTS:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                receipts.records('native> [X] STATE ' + payload, '[X] ', 'STATE')

    def test_marker_text_inside_string_values_is_preserved(self):
        value = {'label': '[X] STATE payload text', 'nested': {'label': '[X] OTHER '}}
        text = 'native> [X] STATE ' + json.dumps(value)
        self.assertEqual(receipts.records(text, '[X] ', 'STATE'), [value])


class AdapterReceiptTests(unittest.TestCase):
    def test_event_wrappers_preserve_their_own_marker_in_json_values(self):
        for adapter in (warehouse_manifest, container_configuration,
                        warehouse_legacy, warehouse_persistence):
            value = {'label': adapter.MARKER + 'STATE literal',
                     'nested': [adapter.MARKER, {'text': adapter.MARKER + 'OTHER '}]}
            text = 'LOG : Lua > ' + adapter.MARKER + 'STATE ' + json.dumps(value)
            with self.subTest(adapter=adapter.__name__):
                self.assertEqual(adapter._records(text, 'STATE'), [value])
                self.assertEqual(adapter._records(adapter.MARKER + 'OTHER bad JSON', 'STATE'), [])

    def test_event_wrappers_share_strict_decoder(self):
        for adapter in (warehouse_manifest, container_configuration,
                        warehouse_legacy, warehouse_persistence):
            for payload in INVALID_OBJECTS:
                text = adapter.MARKER + 'STATE ' + payload
                with self.subTest(adapter=adapter.__name__, payload=payload), self.assertRaises(ValueError):
                    adapter._records(text, 'STATE')

    def test_deposit_wrapper_preserves_event_order_repeats_and_prefix_selection(self):
        text = '\r\n'.join([
            '[OTHER] PREPARED invalid JSON',
            'LOG : Lua > [QM_DEPOSIT] PREPARED {"label": "[QM_DEPOSIT] LOCAL "}',
            '[QM_DEPOSIT] LOCAL {"index": 1}',
            '[QM_DEPOSIT] LOCAL {"index": 1}',
            '[QM_DEPOSIT] COMPLETE {}',
        ])
        self.assertEqual(quartermaster_distribution._deposit_records(text), [
            ('PREPARED', {'label': '[QM_DEPOSIT] LOCAL '}),
            ('LOCAL', {'index': 1}), ('LOCAL', {'index': 1}), ('COMPLETE', {}),
        ])
        self.assertEqual(quartermaster_distribution._deposit_records(
            '[QM_DEPOSIT] LOCAL bad JSON\n[QM_PLAN] STATE {"index": 2}', 'QM_PLAN'),
            [('STATE', {'index': 2})])

    def test_deposit_wrapper_shares_strict_decoder(self):
        for payload in INVALID_OBJECTS:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                quartermaster_distribution._deposit_records('[QM_DEPOSIT] LOCAL ' + payload)


if __name__ == '__main__':
    unittest.main()
