import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import animal_terminal as animal


class AnimalTerminalEvidenceTests(unittest.TestCase):
    def test_completion_marker_does_not_establish_effects(self):
        selection = dict(cases=list(animal.CASES), kind='sp', mode='toolkit')
        text = animal.PREFIX + 'COMPLETE ' + json.dumps({'cases': animal.CASES})
        self.assertTrue(animal.complete(selection, 'client1', text))
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'client1-launch.log').write_text(text)
            result = animal.verify(directory, selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual(result['outcomes'], [])

    def evidence(self):
        ids = dict(case='pet-success', animal=dict(id=7, online=3),
                   book=dict(id=2, type='Base.BookFirstAid1', total=220),
                   baseline=dict(husbandryXP=10))
        event = dict(sequence=1, at=2000, amount=2, before=10, after=12,
                     petTimer=15000, acceptance=43.125, level=0)
        value = dict(case='pet-success', animal=7, online=3, animalType='hen',
                     acceptance=43.15625, petTimer=14900, cooldownReady=False,
                     ghost=False, held=False, husbandryXP=12, husbandryLevel=0,
                     xpLedger=[event], petting=False, idleAction='', distance=1,
                     rootIds=[2], book=dict(id=2, type='Base.BookFirstAid1', root=True,
                                           pages=220, itemPages=220, total=220))
        return ids, value

    def test_passive_acceptance_drift_is_not_a_paid_effect_oracle(self):
        ids, value = self.evidence()
        animal.snapshot(value, ids, final=True, authority=True)
        for mutate in (
            lambda v: v.update(xpLedger=[]),
            lambda v: v['xpLedger'].append(copy.deepcopy(v['xpLedger'][0])),
            lambda v: v['xpLedger'][0].update(petTimer=0),
            lambda v: v['xpLedger'][0].update(after=13),
            lambda v: v.update(husbandryXP=13),
        ):
            invalid = copy.deepcopy(value)
            mutate(invalid)
            with self.assertRaises(AssertionError):
                animal.snapshot(invalid, ids, final=True, authority=True)

    def test_cancel_requires_no_paid_effect(self):
        ids, value = self.evidence()
        ids['case'] = value['case'] = 'pet-cancel'
        value.update(petTimer=0, cooldownReady=True, xpLedger=[], husbandryXP=10)
        animal.snapshot(value, ids, final=True, authority=True)
        value['husbandryXP'] = 12
        with self.assertRaises(AssertionError):
            animal.snapshot(value, ids, final=True, authority=True)


if __name__ == '__main__':
    unittest.main()
