"""Focused negative contracts, synthetic receipts only; never real initialized-game timing proof."""
import copy
import csv
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tests import test_loot_resolved_native as N
A=N.A
F=N.F
spec=importlib.util.spec_from_file_location('_test_operations_receipts',F/'operations_compare.py')
O=importlib.util.module_from_spec(spec);spec.loader.exec_module(O)


class OperationsBoundary(unittest.TestCase):
 def setUp(self):
  self.fixture=N.LootResolvedNative(methodName='runTest');self.fixture.setUp();self.addCleanup(self.fixture.doCleanups)
  self.root=self.fixture.root;self.cache=self.fixture.cache
  self.selection=self.fixture.selection;self.selection['cases']=['operations'];self.selection['options']['loot_runtime_mode']='candidate'
  self.fixture.receipt.update(mode='candidate',bank='operations',scripts={},entry_point='lootResolvedRuntimeRunFor',operations_contract=copy.deepcopy(O.CONTRACT))
  self.fixture.mod(self.cache)
  (self.cache/'mods'/A.MOD/'42/media/lua/shared/ZZLootResolvedRuntime.lua').write_text((F/'operations-bridge.lua').read_text())

 def test_explicit_paired_artifact_and_ordinary_sandbox(self):
  A.validate(self.selection);self.assertEqual(A.bundle(self.cache,self.selection)[1]['operations_contract'],O.CONTRACT)
  self.assertEqual(A.sandbox(self.selection),A.SANDBOX)
  self.assertEqual(A.bank(self.selection),('operations','operations',2))
  bad=copy.deepcopy(self.selection);bad['options']['loot_runtime_mode']='control'
  with self.assertRaisesRegex(ValueError,'candidate artifact'):A.validate(bad)
  source=self.cache/'mods'/A.MOD/'42/media/lua/shared/ZZLootResolvedRuntime.lua';source.write_text((F/'ZZLootResolvedRuntime.lua').read_text())
  with self.assertRaisesRegex(ValueError,'Lua differs'):A.bundle(self.cache,self.selection)
  source.write_text((F/'operations-bridge.lua').read_text())
  for key,value in [('warmup_pairs',63),('storage_limit',0),('semantic_accept_observer',True),('headless_operations_checks',False)]:
   saved=copy.deepcopy(self.fixture.receipt);self.fixture.receipt['operations_contract'][key]=value;self.fixture.mod(self.cache)
   source.write_text((F/'operations-bridge.lua').read_text())
   with self.subTest(key=key),self.assertRaisesRegex(ValueError,'paired window'):A.bundle(self.cache,self.selection)
   self.fixture.receipt=saved

 def write(self,name,fields,rows):
  with (self.cache/name).open('w',newline='') as out:
   writer=csv.DictWriter(out,fieldnames=fields,delimiter='\t',lineterminator='\n');writer.writeheader();writer.writerows(rows)

 def receipts(self):
  rows=[];markers=[];warm=set()
  for phase,count in [('warmup',64),('measure',24)]:
   for pair in range(count):
    for position in range(2):
     index=(position+pair)%2;group=list(O.GROUPS)[index];first=bool((pair+index)&1);order='BA' if first else 'AB'
     for candidate in (first,not first):
      i=len(rows);variant='resolved' if candidate else 'native';batch=O.GROUPS[group]['batch']
      row=dict(phase=phase,group=group,pair=str(pair),order=order,variant=variant,batch=str(batch),window_id=str(i),wall_start=str(i*1000),wall_end=str(i*1000+100),
               cpu_start=str(i*1000),cpu_end=str(i*1000+(20 if candidate else 40)),allocated='100',selections='32',created='2',increments='2',null_returns='0',digest=hashlib.sha256((phase+group+str(pair)).encode()).hexdigest(),next_rng='42',created_types='Base.Nails',cold_types='-',cleanup='verified')
      rows.append(row)
      markers.append(dict(kind='pz.loot.RollWindow',start_ns=str(1_000_000+i*1000),end_ns=str(1_000_000+i*1000+110),thread_id='123',method='none',level='0',compile_id='0',window_id=str(i),detail='group='+group+',variant='+variant+',phase='+phase+',pair='+str(pair)+',batch='+str(batch)))
  sentinel=dict(kind='pz.loot.RollWindow',start_ns='0',end_ns='1',thread_id='1',method='none',level='0',compile_id='0',window_id='-2',detail='group=none,variant=none,phase=admission,pair=-1,batch=0')
  comp=[]
  for i,name in enumerate(('zombie.inventory.ItemPickerJava.doRollItemInternal(','zombie.inventory.ItemPickerJava.rollContainerItemInternal(','toolkit.lootresolved.runtime.OperationsMain.half(')):
   comp.append(dict(kind='jdk.Compilation',start_ns=str(10+i*10),end_ns=str(15+i*10),thread_id='2',method=name+')V',level='4',compile_id=str(i+1),window_id='-1',detail='success=true,osr=false'))
  events=[sentinel,*comp,*markers]
  self.write('loot-operations.tsv',O.FIELDS,rows);self.write('loot-operations-events.tsv',O.EVENT_FIELDS,events)
  inputs=dict(owner_thread_id='123',callback_admission=O.CONTRACT['callback_admission'],callback_binding='native:ItemCodeOnCreate.onCreateGasMask(Clothing)',ordinary_options='{medicalLootNew=1.0,mementoLootNew=1.0,rollsMultiplier=1.0}',empty1000_cpu_ns='100',empty1000_wall_ns='50',container_identity='detached-no-native-world-object-id',native_identity_logger='unchanged-diagnostics-included-if-emitted',direct_public_calls='352',bag_public_calls='704')
  inputs['ordinary_options_sha256']=hashlib.sha256(inputs['ordinary_options'].encode()).hexdigest()
  for group in O.GROUPS:
   inputs[group+'.graph']='rolls:40800000;Nails:3f800000;';inputs[group+'.sha256']=hashlib.sha256(inputs[group+'.graph'].encode()).hexdigest()
  (self.cache/'loot-operations-inputs.properties').write_text(''.join(k+'='+v+'\n' for k,v in inputs.items()))
  return rows,events

 def test_authority_adapter_uses_operations_analyzer_and_preserves_identity_diagnostics(self):
  self.fixture.base_bank(100);self.receipts()
  activation=self.cache/'loot-resolved-runtime-activation-100.txt'
  text=activation.read_text().replace('mode=control','mode=candidate').replace('bank=base','bank=operations')
  h=self.fixture.receipt['native_hashes']['zombie/inventory/ItemPickerJava.class']
  activation.write_text(text.replace('output='+h,'output='+'1'*64)+'operations_factory_definitions=1\noperations_spawner_definitions=1\n')
  status=self.cache/'loot-resolved-runtime-status.txt'
  status.write_text(status.read_text().replace('mode=control','mode=candidate').replace('bank=base','bank=operations').replace('cases=8','cases=2')+'operations_scope='+O.CONTRACT['scope']+'\nwindows=352\n')
  self.fixture.write(self.root/'runtime.json',__import__('json').dumps({'project':str(N.ROOT),'roles':{'client1':{'cache':str(self.cache)}}}))
  self.fixture.write(self.root/'execution.json',__import__('json').dumps({'processes':{'client1':{'pid':100}}}))
  auth=dict(role='client1',case='operations',runtimeMode='candidate',status='complete',cases=2,source='sp-main-tick')
  final=dict(role='client1',case='operations',runtimeMode='candidate',status='complete',authority=True)
  self.fixture.write(self.root/'client1-launch.log','[ItemPickInfo] cannot get ID for container: crate\n[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=2 reason=\n'+self.fixture.event('AUTHORITY',auth)+self.fixture.event('COMPLETE',final))
  result=A.verify(self.root,self.selection,{})
  self.assertEqual(result['issues'],[],result)
  self.assertEqual(result['evidence']['native_identity_diagnostics_total_in_authority_log'],1)
  self.assertTrue(result['evidence']['semantic_proofs']['timing_qualified'])
  activation.write_text(activation.read_text().replace('operations_factory_definitions=1','operations_factory_definitions=0'))
  self.assertTrue(A.verify(self.root,self.selection,{})['issues'])

 def test_balanced_complete_same_jvm_raw_pairs_and_literal_compilation(self):
  self.receipts();result=O.report(self.cache)
  self.assertTrue(result['timing_qualified']);self.assertEqual(len(result['windows']),352)
  for group in O.GROUPS:self.assertEqual(result['summary'][group]['positive_pairs'],24)
  self.assertIn('not universal C2',result['events']['note'])

 def test_window_identity_omission_contents_rng_and_disposal_fail(self):
  original,_=self.receipts()
  for key,value in [('window_id','1'),('phase','measure'),('variant','resolved'),('batch','999'),('digest','0'*64),('next_rng','43'),('cleanup','skipped'),('selections','0'),('created','5000'),('null_returns','1')]:
   rows=copy.deepcopy(original);rows[0][key]=value;self.write('loot-operations.tsv',O.FIELDS,rows)
   with self.subTest(key=key),self.assertRaises(ValueError):O.report(self.cache)
  for rows in (original[:-1],original+[original[-1]]):
   self.write('loot-operations.tsv',O.FIELDS,rows)
   with self.assertRaises(ValueError):O.report(self.cache)

 def test_jfr_history_owner_and_marker_cardinality_are_required(self):
  _,original=self.receipts()
  for events in (original[1:],original[:-1],original+[original[-1]]):
   self.write('loot-operations-events.tsv',O.EVENT_FIELDS,events)
   with self.assertRaises(ValueError):O.report(self.cache)
  for key,value in [('thread_id','999'),('detail','group=foreign'),('start_ns','999999999999')]:
   events=copy.deepcopy(original);events[-1][key]=value;self.write('loot-operations-events.tsv',O.EVENT_FIELDS,events)
   with self.subTest(key=key),self.assertRaises(ValueError):O.report(self.cache)

 def test_compile_deopt_data_loss_osr_and_cold_type_never_hidden(self):
  rows,original=self.receipts();start=next(e for e in original if e['window_id']=='256')['start_ns']
  for kind,method,detail in [('jdk.Compilation','test.M()V','success=true,osr=false'),('jdk.Deoptimization','test.M()V','reason=unstable,action=reinterpret'),('jdk.DataLoss','none','amount=1')]:
   event=dict(kind=kind,start_ns=start,end_ns=start,thread_id='2',method=method,level='4',compile_id='10',window_id='-1',detail=detail)
   self.write('loot-operations-events.tsv',O.EVENT_FIELDS,original+[event]);result=O.report(self.cache)
   self.assertFalse(result['timing_qualified']);self.assertEqual(len(result['windows']),352)
  events=copy.deepcopy(original)
  for e in events:
   if e['kind']=='jdk.Compilation':e['detail']='success=true,osr=true'
  self.write('loot-operations-events.tsv',O.EVENT_FIELDS,events)
  self.assertFalse(O.report(self.cache)['timing_qualified'])
  self.write('loot-operations-events.tsv',O.EVENT_FIELDS,original)
  for row in rows:
   if row['phase']=='measure':row['created_types']='Base.Nails,Base.NewCold';row['cold_types']='Base.NewCold'
  self.write('loot-operations.tsv',O.FIELDS,rows)
  result=O.report(self.cache);self.assertFalse(result['timing_qualified']);self.assertEqual(len(result['cold_created_type_windows']),96)

 def test_input_graph_callback_and_identity_diagnostic_scope_cannot_disappear(self):
  self.receipts();path=self.cache/'loot-operations-inputs.properties';original=path.read_text()
  for old,new in [('callback_binding=native:','callback_binding=foreign:'),('container_identity=detached','container_identity=real'),('direct_public_calls=352','direct_public_calls=351'),('ordinary_options_sha256=','ordinary_options_sha256=0')]:
   path.write_text(original.replace(old,new))
   with self.subTest(old=old),self.assertRaises(ValueError):O.report(self.cache)


if __name__=='__main__':unittest.main()
