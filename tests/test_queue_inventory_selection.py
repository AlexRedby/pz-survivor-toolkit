"""Diagnostic acceptance must reject missing attribution and changed identity."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from queue_checks.adapters import auxiliary
HERE=ROOT/'tests/native_queue/contributions/storage-profile'
V=auxiliary._load(HERE/'selection_verify.py')
S=auxiliary._load(HERE/'stage_selection_probe.py')


COHORTS = {
    'Base.Nails': ('nonfluid', 'none', 0, {'fuel': False, 'disinfectant': False}),
    'Base.PetrolCan': ('fluid', 'Petrol', 10, {'fuel': True, 'disinfectant': False, 'beverage': False, 'alcoholic': False, 'empty': False}),
    'Base.Whiskey': ('fluid', 'Whiskey', 1, {'fuel': False, 'disinfectant': True, 'beverage': True, 'alcoholic': True, 'empty': False}),
}


def selection(item=None):
    return dict(suite='storage-profile',mode='toolkit',kind='sp',cases=['inventory-selection'],languages=['EN'],
        mods=['ZombieBuddy',*auxiliary.INVENTORY_MODS],resources={'exclusive':True},
        options={} if item is None else {'inventory_selection_item':item})


def workload(item):
    branch, fluid, amount, usage = COHORTS[item]
    return dict(itemType=item,branch=branch,isFluid=branch=='fluid',isDrainable=False,
        fluidType=fluid,fluidAmount=amount,fluidCapacity=amount,verifiedItems=4800,stateVerified=True,
        fillPolicy='setup-full-capacity' if branch=='fluid' else 'native-nonfluid',usageWitness=copy.deepcopy(usage))


def records(item='Base.Nails'):
    result=[('SETUP',dict(workload(item),count=4800))]
    for mode in ('clean','vanilla'):
        for state in ('collapsed','expanded'):
            for i in range(1,8):
                metric={'calls':1,'inclusiveMs':2,'exclusiveMs':1,'maxMs':2,'errors':0,'samplesMs':[2],'droppedSamples':0}
                result.append(('SAMPLE',{'phase':mode+'-'+state,'index':i,'count':4800,'emptySelection':True,
                    'identityVerified':True,'observerOverheadIncluded':True,'outerMs':3,
                    **workload(item),
                    'workload':dict(workload(item),renderer=mode,mode='details',classMatches=True,probeItems=4800,groups=1,expanded=state=='expanded'),
                    'mapperLabels':['mapper.'+mode],
                    'metrics':{'mapper.'+mode:copy.deepcopy(metric),'presentation.refresh':copy.deepcopy(metric)}}))
    result.append(('RESTORED',dict(workload(item),ownedRemoved=4800,identityVerified=True,originals=4,remaining=4)))
    return result


def text(rows):
    return '\n'.join('[STORAGE_PROFILE] SELECTION_'+k+' '+json.dumps(v) for k,v in rows)


class SelectionProfileTests(unittest.TestCase):
    def test_timing_requires_exclusive_fresh_sp(self):
        s=selection()
        auxiliary.validate(s)
        with self.assertRaises(ValueError): auxiliary.validate(dict(s,resources={'exclusive':False}))
        with self.assertRaises(ValueError): auxiliary.validate(dict(s,options={'world_template':'/unused'}))

    def test_only_supported_cohorts_can_be_selected_in_standalone_timing(self):
        for item in COHORTS:
            auxiliary.validate(selection(item))
        for item in ('Base.WaterBottle', '', None, 1, False, ['Base.Nails']):
            s=selection();s['options']['inventory_selection_item']=item
            with self.subTest(item=item),self.assertRaises(ValueError): auxiliary.validate(s)
        for change in ({'cases':['inventory-work']}, {'suite':'inventory-presentation','cases':['scenes']},
                       {'kind':'mp'}, {'clients':2}, {'clients':True}, {'resources':{'exclusive':False}}):
            with self.subTest(change=change),self.assertRaises(ValueError):
                auxiliary.validate(dict(selection('Base.Whiskey'),**change))
        for option in ('seed_run','world_template','startup_connection','mp_host'):
            s=selection('Base.PetrolCan');s['options'][option]=True
            with self.subTest(option=option),self.assertRaises(ValueError): auxiliary.validate(s)

    def test_staging_writes_validated_config_for_default_and_each_cohort(self):
        load=auxiliary._load
        def fixtures(path):
            if path.name in ('stage_inventory_probe.py','stage_selection_probe.py'):
                return SimpleNamespace(stage=lambda *args,**kwargs:None)
            return load(path)
        for item in (None,*COHORTS):
            with self.subTest(item=item),tempfile.TemporaryDirectory() as directory:
                output=Path(directory);cache=output/'client1';cache.mkdir()
                runtime={'roles':{'client1':{'cache':str(cache)}}}
                with patch.object(auxiliary,'_load',side_effect=fixtures):
                    auxiliary.stage(ROOT,output,output/'game',output/'jdk',selection(item),
                                    {'PZSurvivorToolkit':ROOT/'PZSurvivorToolkit'},runtime)
                config=cache/'mods/StorageProfileNative/42/media/lua/shared/InventorySelectionConfig.lua'
                self.assertEqual(config.read_text(),'return {itemType='+json.dumps(item or 'Base.Nails')+'}\n')

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

    def test_each_cohort_requires_matching_type_branch_and_immutable_state(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            (p/'selection-observer-inputs.json').write_text(json.dumps({'test_only':True,'sources':[{}]*9}))
            for item in COHORTS:
                rows=records(item)
                accepted=V.verify(p,text(rows),selection(item))
                self.assertEqual(accepted['selection_workload'],workload(item))
                self.assertEqual(len(accepted['selection_samples']),28)
                for where in ('setup','sample','workload','restored'):
                    for field,value in (('itemType','Base.WaterBottle'),('branch','unknown'),
                            ('isFluid',item=='Base.Nails'),('isDrainable',True),
                            ('stateVerified',False),('verifiedItems',4799),('fluidType','Water'),
                            ('fluidAmount',None),('fluidCapacity',float('nan')),('usageWitness',{}),
                            ('fillPolicy','reader-fill')):
                        candidate=copy.deepcopy(rows)
                        row={'setup':candidate[0][1],'sample':candidate[1][1],
                             'workload':candidate[1][1]['workload'],'restored':candidate[-1][1]}[where]
                        row[field]=value
                        with self.subTest(item=item,where=where,field=field),self.assertRaises(ValueError):
                            V.verify(p,text(candidate),selection(item))
                other='Base.PetrolCan' if item!='Base.PetrolCan' else 'Base.Whiskey'
                with self.subTest(item=item,mismatch=other),self.assertRaises(ValueError):
                    V.verify(p,text(rows),selection(other))
                candidate=copy.deepcopy(rows);candidate[1][1]['workload']=None
                with self.subTest(item=item,mutation='missing workload'),self.assertRaises(ValueError):
                    V.verify(p,text(candidate),selection(item))
                # A coherent but changed amount/capacity still violates the
                # baseline, even if a sample and its view receipt agree.
                if item!='Base.Nails':
                    candidate=copy.deepcopy(rows)
                    for row in (candidate[1][1],candidate[1][1]['workload']):
                        row['fluidAmount']=row['fluidCapacity']=0.5
                    with self.subTest(item=item,mutation='amount'),self.assertRaises(ValueError):
                        V.verify(p,text(candidate),selection(item))


if __name__=='__main__':unittest.main()
