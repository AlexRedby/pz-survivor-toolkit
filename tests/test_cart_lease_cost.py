"""Strict receipt/byte accounting regressions; synthetic logs, not wire measurements."""
import copy
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from tests.test_cart_equipment_lifetimes import fixture,ROLES

ROOT=Path(__file__).resolve().parents[1]
API=runpy.run_path(str(ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-lease-cost.py'))

class LeaseCostEvidenceTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.root=Path(temp.name)
        self.populate()
    def populate(self,menu=False):
        self.selection,logs,rows=fixture(menu=menu);self.rows={}
        for role in ROLES:
            counter=0;out=[]
            lines=logs[role]+[marker+json.dumps(row) for marker,row in rows[role]]
            for line in lines:
                matched=False
                for marker,module in API['MARKERS'].items():
                    if marker not in line:continue
                    row=json.loads(line.split(marker,1)[1]);command=API['INBOUND'][module]['server' if role=='server' else 'client'].get(row['event'])
                    if command:
                        counter+=1;receipt=role+':receipt:'+str(counter);row['receipt']=receipt
                        epoch=202 if role=='server' and row['requester']=='client2' else 201
                        native=dict(process='native-'+role,connectionEpoch=epoch,ingressGeneration=counter,receipt=receipt,
                          direction='client-to-server' if role=='server' else 'server-to-client',module=module,command=command,
                          payloadBytes=100+counter,engineBytes=103+counter,monoNs=counter*1000000)
                        out.append((API['NATIVE'],native))
                    out.append((marker,row));matched=True;break
                if not matched:out.append(('',line))
            self.rows[role]=out
    def analyze(self):
        (self.root/'selection.json').write_text(json.dumps(self.selection))
        for role,rows in self.rows.items():
            (self.root/(role+'-launch.log')).write_text('\n'.join(marker+json.dumps(row) if marker else row for marker,row in rows)+'\n')
        return API['analyze'](self.root)
    def natives(self,role):return [r for m,r in self.rows[role] if m==API['NATIVE']]
    def test_exact_delivered_counts_engine_header_and_bursts(self):
        result=self.analyze();self.assertTrue(result['evidenceComplete'])
        self.assertEqual(result['totals']['messages'],66)
        self.assertEqual(result['totals']['engineBytes']-result['totals']['payloadBytes'],3*66)
        self.assertEqual(sum(r['messages'] for r in result['commands']),66)
        self.assertEqual(result['perProcessOneSecondBursts']['server']['maximumMessages'],34)
        self.assertIn('excludes RakNet/IP/UDP',result['scope'])
        self.assertNotIn('wireBytes',result)
    def test_menu_commands_keep_exact_callback_receipts_and_counts(self):
        self.populate(menu=True)
        result=self.analyze()
        self.assertEqual(result['totals']['messages'],74)
        commands={row['command']:row['messages'] for row in result['commands'] if row['command'] in ('MenuAbsent','MenuResume')}
        self.assertEqual(commands,dict(MenuAbsent=4,MenuResume=4))
        original=copy.deepcopy(self.rows)
        for command in ('MenuAbsent','MenuResume'):
            self.rows=copy.deepcopy(original)
            for role in ROLES:
                matches=[r for r in self.natives(role) if r['command']==command]
                if matches:matches[0]['receipt']='wrong-receipt';break
            with self.subTest(command=command),self.assertRaises(ValueError):self.analyze()

    def test_native_shape_direction_process_header_and_size_are_strict(self):
        original=copy.deepcopy(self.rows)
        for key,value in [('process','other'),('direction','server-to-client'),('module','foreign'),('command','Receipt'),('payloadBytes',0),('engineBytes',999),('connectionEpoch',0),('ingressGeneration',0),('monoNs',float('nan'))]:
            self.rows=copy.deepcopy(original);self.natives('server')[0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):self.analyze()
    def test_each_native_command_requires_one_exact_callback_receipt(self):
        original=copy.deepcopy(self.rows)
        for mode in ('missing','duplicate','wrong-command','wrong-receipt'):
            self.rows=copy.deepcopy(original);rows=self.rows['client1']
            n=next(i for i,(m,r) in enumerate(rows) if m==API['NATIVE'])
            if mode=='missing':rows.pop(n)
            elif mode=='duplicate':rows.insert(n,copy.deepcopy(rows[n]))
            elif mode=='wrong-command':rows[n][1]['command']='Receipt'
            else:rows[n+1][1]['receipt']='unrelated'
            with self.subTest(mode=mode),self.assertRaises(ValueError):self.analyze()
    def test_generation_and_native_clock_cannot_rewind(self):
        for field in ('ingressGeneration','monoNs'):
            original=copy.deepcopy(self.rows);self.natives('server')[1][field]=0
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
            self.rows=original
    def test_extra_native_receipt_cannot_hide_in_totals(self):
        row=copy.deepcopy(self.natives('client1')[-1]);row.update(receipt='extra',ingressGeneration=999,monoNs=999000000)
        self.rows['client1'].append((API['NATIVE'],row))
        with self.assertRaisesRegex(ValueError,'Unmatched extra'):self.analyze()
    def test_stale_native_connections_are_not_interchangeable(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            self.rows=copy.deepcopy(original);self.natives(role)[1]['connectionEpoch']=999
            with self.subTest(role=role),self.assertRaises(ValueError):self.analyze()
    def test_bursts_never_combine_process_clocks(self):
        for role in ROLES:
            for n,row in enumerate(self.natives(role)):row['monoNs']=n*1000000000
        result=self.analyze()
        self.assertEqual({r['maximumMessages'] for r in result['perProcessOneSecondBursts'].values()},{1})
    def test_existing_chain_failure_is_not_bypassed_by_byte_logs(self):
        for marker,row in self.rows['client1']:
            if marker=='[CART_LEASE_LIFETIME] ' and row['event']=='complete':row['lifetime']='unknown';break
        with self.assertRaises(ValueError):self.analyze()

if __name__=='__main__':unittest.main()
