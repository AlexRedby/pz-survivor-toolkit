"""Diagnostic acceptance must reject missing attribution and changed identity."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from queue_checks.adapters import auxiliary
HERE=ROOT/'tests/native_queue/contributions/storage-profile'
V=auxiliary._load(HERE/'selection_verify.py')
S=auxiliary._load(HERE/'stage_selection_probe.py')


def records():
    result=[('SETUP',{'count':4800})]
    for mode in ('clean','vanilla'):
        for state in ('collapsed','expanded'):
            for i in range(1,8):
                metric={'calls':1,'inclusiveMs':2,'exclusiveMs':1,'maxMs':2,'errors':0,'samplesMs':[2],'droppedSamples':0}
                result.append(('SAMPLE',{'phase':mode+'-'+state,'index':i,'count':4800,'emptySelection':True,
                    'identityVerified':True,'observerOverheadIncluded':True,'outerMs':3,
                    'workload':{'renderer':mode,'mode':'details','classMatches':True,'probeItems':4800,'groups':1,'expanded':state=='expanded'},
                    'mapperLabels':['mapper.'+mode],
                    'metrics':{'mapper.'+mode:copy.deepcopy(metric),'presentation.refresh':copy.deepcopy(metric)}}))
    result.append(('RESTORED',{'ownedRemoved':4800,'identityVerified':True,'originals':4,'remaining':4}))
    return result


def text(rows):
    return '\n'.join('[STORAGE_PROFILE] SELECTION_'+k+' '+json.dumps(v) for k,v in rows)


class SelectionProfileTests(unittest.TestCase):
    def test_timing_requires_exclusive_fresh_sp(self):
        s=dict(suite='storage-profile',mode='toolkit',kind='sp',cases=['inventory-selection'],languages=['EN'],
            mods=['ZombieBuddy',*auxiliary.INVENTORY_MODS],resources={'exclusive':True})
        auxiliary.validate(s)
        with self.assertRaises(ValueError): auxiliary.validate(dict(s,resources={'exclusive':False}))
        with self.assertRaises(ValueError): auxiliary.validate(dict(s,options={'world_template':'/unused'}))

    def test_unsupported_mapper_is_rejected_before_launch(self):
        with self.assertRaises(ValueError): S.transform('ISUI/ISInventoryPane.lua','function ISInventoryPane:restoreSelection(saved)\nend\n')
        with self.assertRaises(ValueError): S.replace_once('same same','same','replacement')

    def test_observations_need_attribution_samples_and_exact_population(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            (p/'selection-observer-inputs.json').write_text(json.dumps({'test_only':True,'sources':[{}]*9}))
            rows=records();self.assertEqual(len(V.verify(p,text(rows),{})['selection_samples']),28)
            for change in ('mapper','identity','negative','cleanup','missing','error'):
                candidate=copy.deepcopy(rows)
                if change=='mapper': candidate[1][1]['metrics'].pop('mapper.clean')
                elif change=='identity': candidate[1][1]['identityVerified']=False
                elif change=='negative': candidate[1][1]['metrics']['mapper.clean']['exclusiveMs']=-1
                elif change=='cleanup': candidate[-1][1]['ownedRemoved']=4799
                elif change=='missing': candidate.pop(1)
                else: candidate[1][1]['metrics']['mapper.clean']['errors']=1
                with self.subTest(change=change),self.assertRaises(ValueError): V.verify(p,text(candidate),{})


if __name__=='__main__':unittest.main()
