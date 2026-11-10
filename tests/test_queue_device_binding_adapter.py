"""Evidence gate for the same-square wrong-device regression."""
import copy
import unittest
from tests import test_queue_tv_controls_adapter as tv_fixture
from queue_checks.adapters import device_binding as adapter


class DeviceBindingTests(unittest.TestCase):
    def evidence(self, case='eject-idle', kind='mp', mode='toolkit'):
        row, ids, baseline, final, acks = tv_fixture.TVControlsTests().evidence(case, kind, mode)
        wrong = dict(ids['tv'], index=0)
        ids['wrong'] = wrong
        row['ids'] = copy.deepcopy(ids)
        row['suite'] = 'device-binding'
        for snapshot in [row[k] for k in ('input', 'baseline', 'authorityBaseline', 'client', 'server')] + [baseline, final]:
            snapshot['wrong'] = dict(identity=copy.deepcopy(wrong), on=True, power=1, powerable=True,
                                     volume=.5, channel=90000, hasMedia=False, mediaIndex=-1, playing=False)
        selection = dict(suite='device-binding', cases=list(adapter.CASES), kind=kind, mode=mode,
                         clients=1, languages=['EN'], mods=list(adapter.MODS),
                         options={'mp_host': True} if kind == 'mp' else {})
        return row, ids, baseline, final, acks, selection

    def check(self, evidence):
        row, ids, baseline, final, acks, selection = evidence
        return adapter.check_case(row, row['id'], selection, ids, baseline, final, acks)

    def test_selected_second_device_and_native_controls(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in adapter.CASES:
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual([], self.check(self.evidence(case, kind, mode)))

    def test_wrong_device_effect_and_identity_are_rejected(self):
        evidence = self.evidence()
        evidence[0]['client']['wrong']['hasMedia'] = True
        self.assertTrue(self.check(evidence))
        evidence = self.evidence()
        evidence[1]['wrong']['x'] += 1
        evidence[0]['ids'] = copy.deepcopy(evidence[1])
        self.assertTrue(self.check(evidence))
        evidence = self.evidence()
        evidence[0]['server']['wrong']['volume'] = .25
        self.assertTrue(self.check(evidence))


if __name__ == '__main__':
    unittest.main()
