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

    def placement_evidence(self,kind):
        target=dict(x=10,y=20,z=0)
        def proof(mode):
            actual=dict(x=10.5 if mode=='local'else 10,y=20.5 if mode=='local'else 20,z=0,
                        square=dict(target),currentSquare=dict(target))
            if mode=='local':actual.update(queued=0,timed=False,moving=False,hasPath=False,deferredX=0,deferredY=0)
            return dict(mode=mode,target=dict(target),actual=actual,teleports=int(mode=='local'),stableMs=500,
                        quietMs=500 if mode=='local'else 0,elapsedMs=1000 if mode=='local'else 500)
        client=proof('local');authority=proof('replica'if kind=='mp'else'local')
        prepared=[dict(case=case,placement=dict(target),placementProof=copy.deepcopy(authority),
                       origin=dict(x=10+i,y=20,z=0))for i,case in enumerate(animal.CASES)]
        return client,authority,prepared

    def placement_logs(self,kind,client,authority):
        def raw(name,value):return animal.PREFIX+name+' '+json.dumps(value)+'\n'
        return raw('CLIENT_PLACEMENT'if kind=='mp'else'PLACEMENT',client),raw('PLACEMENT',authority)

    def test_placement_accepts_distinct_role_proofs_and_historical_initial_origin(self):
        for kind in ('sp','mp'):
            client,authority,prepared=self.placement_evidence(kind)
            text,server=self.placement_logs(kind,client,authority)
            animal.check_placements(text,server,prepared,kind)
            if kind=='mp':self.assertNotEqual(client,authority)
            self.assertNotEqual(prepared[0]['origin'],prepared[-1]['origin'])

    def test_placement_rejects_missing_mismatched_stale_or_remote_teleport_receipts(self):
        mutations=('missing-client','duplicate-client','missing-authority','duplicate-authority','missing-prepared',
                   'client-target','client-stale-square','authority-target','authority-stale-square',
                   'authority-teleport','prepared-target','prepared-proof-missing','historical-proof-replaced')
        for kind in ('sp','mp'):
            for mutation in mutations:
                with self.subTest(kind=kind,mutation=mutation):
                    client,authority,prepared=self.placement_evidence(kind)
                    if mutation=='client-target':client['target']['x']+=1
                    elif mutation=='client-stale-square':client['actual']['currentSquare']['x']-=1
                    elif mutation=='authority-target':authority['target']['x']+=1
                    elif mutation=='authority-stale-square':authority['actual']['square']['x']-=1
                    elif mutation=='authority-teleport':authority['teleports']=int(kind=='mp')
                    elif mutation=='prepared-target':prepared[-1]['placement']['x']+=1
                    elif mutation=='prepared-proof-missing':prepared[-1].pop('placementProof')
                    elif mutation=='historical-proof-replaced':
                        prepared[-1]['placementProof']['stableMs']=600;prepared[-1]['placementProof']['elapsedMs']+=100
                    text,server=self.placement_logs(kind,client,authority)
                    if mutation=='missing-client':text=''
                    elif mutation=='duplicate-client':text+=text
                    elif mutation=='missing-authority':server=''
                    elif mutation=='duplicate-authority':server+=server
                    elif mutation=='missing-prepared':prepared=[]
                    with self.assertRaises((AssertionError,KeyError,ValueError)):
                        animal.check_placements(text,server,prepared,kind)

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
