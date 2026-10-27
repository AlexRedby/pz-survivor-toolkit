"""A charge investigation must prove real crafts and exact input identities."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import plastic_battery as adapter


def rows():
    result = []
    for provider in ('base', 'damn'):
        for operation in ('insert', 'remove'):
            for charge in (0, 0.37, 1):
                index = len(result) + 1
                available = operation == 'insert' or charge > 0
                result.append(dict(index=index, provider=provider, operation=operation,
                    requestedCharge=charge, available=available, queueDrained=True,
                    before=[], after=[], gunID=index * 10, batteryID=index * 10 + 1,
                    inputIDs=[index * 10, index * 10 + 1] if operation == 'insert' else [index * 10],
                    actionObserved=available, nativeDuration=available, performCalls=int(available)))
    return result


def verify(values):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        text = '\n'.join(adapter.MARKER + 'PHASE ' + json.dumps(row) for row in values)
        text += '\n' + adapter.MARKER + 'COMPLETE ' + json.dumps(dict(phases=12, restored=True))
        (root / 'client1-launch.log').write_text(text)
        return adapter.verify(root, {}, {})


class PlasticBatteryCaptureTests(unittest.TestCase):
    def test_complete_matrix_is_capture_not_a_conservation_pass(self):
        result = verify(rows())
        self.assertEqual(result['issues'], [])
        self.assertEqual(result['outcomes'][0]['status'], 'captured')

    def test_all_unavailable_cannot_pass_without_standard_positive_controls(self):
        values = rows()
        for row in values:
            row.update(available=False, actionObserved=False, nativeDuration=False, performCalls=0)
        self.assertTrue(verify(values)['issues'])

    def test_canceled_duplicate_or_wrong_input_craft_is_rejected(self):
        for field, value in [('performCalls', 0), ('performCalls', 2), ('inputIDs', [999]),
                             ('actionObserved', False), ('nativeDuration', False)]:
            values = rows(); values[0][field] = value
            with self.subTest(field=field, value=value):
                self.assertTrue(verify(values)['issues'])

    def test_missing_or_duplicate_phase_is_rejected(self):
        values = rows()
        self.assertTrue(verify(values[:-1])['issues'])
        duplicate = copy.deepcopy(values); duplicate[-1] = duplicate[0]
        self.assertTrue(verify(duplicate)['issues'])


if __name__ == '__main__':
    unittest.main()
