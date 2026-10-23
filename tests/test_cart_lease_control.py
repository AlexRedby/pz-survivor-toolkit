"""Malformed-evidence regressions for real held-cart control log shapes; no game."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-lease.py'
API = runpy.run_path(str(SOURCE))
EPOCH = 100000
MARKER = '[CART_LEASE] '


def fixture():
    selection = dict(suite='wooden_cart_multiplayer', kind='mp', mode='toolkit',
        cases=['owner_observer_motion'], options=dict(mp_host=True, cart_fast_motion=True, cart_lease_control=True))
    logs = {role: [f'LOG : General > [CART_MP] START epoch={EPOCH}'] for role in ('server', 'client1', 'client2')}
    for elapsed in (0, 8000, 16000, 26000):
        logs['client1'].append('[CART_MP_STATE] '+json.dumps(dict(user='client1',id=7,
            wall=EPOCH+elapsed,primary=42,secondary=42)))
    logs['server'].append('[CART_MP] CART_SPEC '+json.dumps(dict(id=42,cartType='SaucedWheelbarrow.WheelbarrowWood')))
    rows = {role: [] for role in logs}
    for round_ in range(1, 4):
        for role, offset in (('client1', 3), ('client2', 8)):
            elapsed = (round_-1)*8000+offset
            nonce = 'fresh-native-seed:'+role+':'+str(round_)
            base = dict(nonce=nonce, owner=7)
            binding = dict(session='exact-server-session', grant=1, lease=1, cart=42, guarded=True)
            rows[role].append(dict(base,actor=role,event='request',round=round_,elapsed=elapsed,wall=EPOCH+elapsed+1))
            rows['server'].append(dict(base,**binding,actor='server',event='bind',requester=role,wall=EPOCH+elapsed+2))
            rows[role].append(dict(base,**binding,actor=role,event='bound',wall=EPOCH+elapsed+3))
            rows['server'].append(dict(base,**binding,actor='server',event='echo',requester=role,
                                       seq=round_,accepted=role=='client1',wall=EPOCH+elapsed+4))
            rows[role].append(dict(base,**binding,actor=role,event='receipt',seq=round_,
                                   accepted=role=='client1',wall=EPOCH+elapsed+5))
    return selection, logs, rows


class LeaseControlEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.profile = Path(self.temp.name)
        self.selection, self.logs, self.rows = fixture()

    def write(self):
        (self.profile/'selection.json').write_text(json.dumps(self.selection))
        for role, rows in self.rows.items():
            lines = self.logs[role]+['LOG : General > '+MARKER+json.dumps(row) for row in rows]
            (self.profile/(role+'-launch.log')).write_text('\n'.join(lines)+'\n')

    def analyze(self):
        self.write()
        return API['analyze'](self.profile)

    def records(self, role, event):
        return [row for row in self.rows[role] if row['event'] == event]

    def test_six_exact_guarded_chains_and_logical_message_scope(self):
        result = self.analyze()
        self.assertTrue(result['evidenceComplete'])
        self.assertTrue(result['diagnosticOnly'])
        self.assertEqual(result['completeChains'], 6)
        self.assertEqual(result['logicalCommandMessages'], dict(total=24,clientToServer=12,serverToClient=12))
        self.assertEqual([row['accepted'] for row in result['chains']], [True]*3+[False]*3)
        self.assertEqual({row['sampleToLogDelayMs'] for row in result['chains']}, {1})
        self.assertIn('not wire bytes', result['qualification'])
        self.assertIn('No action, release, reconnect', result['qualification'])
        self.assertIn('runtime PASS', result['qualification'])
        self.assertNotIn('runtimePass', result)

    def test_only_frozen_explicit_canonical_selection_is_accepted(self):
        original = copy.deepcopy(self.selection)
        for changes in (dict(suite='cart_motion_mp'),dict(mode='baseline'),dict(kind='sp'),dict(cases=[])):
            self.selection = dict(original, **changes)
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError,'Frozen selection'):
                self.analyze()
        for value in (False, 1, 'true', None):
            self.selection = copy.deepcopy(original)
            self.selection['options']['cart_lease_control'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.analyze()

    def test_rejects_non_host_short_action_inventory_and_wall_banks(self):
        original = copy.deepcopy(self.selection)
        for key, value in (('mp_host',False),('cart_fast_motion',False),('cart_actions',True),
                           ('cart_inventory_equip',True),('cart_wall_exit','left')):
            self.selection = copy.deepcopy(original); self.selection['options'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.analyze()

    def test_missing_duplicate_and_extra_chains_cannot_pass(self):
        original = copy.deepcopy(self.rows)
        for role, event in (('client1','request'),('client1','bound'),('client2','receipt'),('server','bind'),('server','echo')):
            for action in ('remove','duplicate'):
                self.rows = copy.deepcopy(original)
                row = self.records(role,event)[0]
                if action == 'remove':
                    self.rows[role].remove(row)
                else:
                    self.rows[role].insert(self.rows[role].index(row),copy.deepcopy(row))
                with self.subTest(role=role,event=event,action=action), self.assertRaises(ValueError):
                    self.analyze()

    def test_reused_and_foreign_nonce_never_greedily_pair(self):
        original = copy.deepcopy(self.rows)
        for role, event in (('server','bind'),('server','echo'),('client1','bound'),('client2','receipt')):
            self.rows = copy.deepcopy(original); self.records(role,event)[0]['nonce'] += '-foreign'
            with self.subTest(role=role,event=event), self.assertRaises(ValueError):
                self.analyze()
        self.rows = copy.deepcopy(original)
        self.records('client1','request')[1]['nonce'] = self.records('client1','request')[0]['nonce']
        with self.assertRaises(ValueError):
            self.analyze()

    def test_foreign_role_requester_and_protocol_error_are_rejected(self):
        original = copy.deepcopy(self.rows)
        for role, event, changes in (
                ('client1','request',dict(actor='client2')),('server','bind',dict(actor='client1')),
                ('server','echo',dict(requester='spectator')),('client2','receipt',dict(event='echo'))):
            self.rows = copy.deepcopy(original); self.records(role,event)[0].update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.analyze()
        self.rows = copy.deepcopy(original)
        self.rows['client2'].append(dict(actor='client2',event='error',reason='native ingress missing',wall=EPOCH+17000))
        with self.assertRaisesRegex(ValueError,'lease probe error'):
            self.analyze()

    def test_every_response_requires_actual_boolean_guard(self):
        original = copy.deepcopy(self.rows)
        for role, event in (('server','bind'),('server','echo'),('client1','bound'),('client2','receipt')):
            for value in (False,1,'true',None):
                self.rows = copy.deepcopy(original); self.records(role,event)[0]['guarded'] = value
                with self.subTest(role=role,event=event,value=value), self.assertRaisesRegex(ValueError,'guard'):
                    self.analyze()

    def test_owner_success_and_observer_denial_are_both_required(self):
        original = copy.deepcopy(self.rows)
        for role, event, index in (('client1','receipt',0),('client2','receipt',0),('server','echo',0),('server','echo',1)):
            expected = [row for row in original[role] if row['event']==event][index]['accepted']
            for value in (not expected,1,'false',None):
                self.rows = copy.deepcopy(original)
                target = self.records(role,event)[index]
                target['accepted'] = value
                with self.subTest(role=role,event=event,value=value), self.assertRaises(ValueError):
                    self.analyze()
        self.rows = copy.deepcopy(original)
        for row in self.records('client2','receipt'):
            row['accepted'] = True
        for row in self.records('server','echo'):
            if row['requester']=='client2': row['accepted'] = True
        with self.assertRaisesRegex(ValueError,'authority result'):
            self.analyze()

    def test_exact_session_grant_lease_cart_and_round_must_survive_all_callbacks(self):
        original = copy.deepcopy(self.rows)
        for role, event in (('server','bind'),('server','echo'),('client1','bound'),('client1','receipt')):
            for field, value in (('session','other-session'),('grant',2),('lease',2),('cart',43),('owner',8)):
                self.rows = copy.deepcopy(original); self.records(role,event)[0][field] = value
                with self.subTest(role=role,event=event,field=field), self.assertRaises(ValueError):
                    self.analyze()
        for role,event in (('server','echo'),('client2','receipt')):
            self.rows = copy.deepcopy(original); self.records(role,event)[0]['seq'] = 3
            with self.subTest(role=role,event=event), self.assertRaisesRegex(ValueError,'sequence'):
                self.analyze()

    def test_consistently_changed_binding_mid_capture_is_not_held_only_proof(self):
        for field,value in (('session','rebooted'),('grant',2),('lease',2)):
            self.selection,self.logs,self.rows = fixture()
            nonce = self.records('client1','request')[1]['nonce']
            for rows in self.rows.values():
                for row in rows:
                    if row.get('nonce')==nonce and row['event']!='request': row[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError,'binding changed during'):
                self.analyze()

    def test_counter_identity_and_payload_bounds_are_strict(self):
        original = copy.deepcopy(self.rows)
        for field,value in (('owner',True),('owner',32768),('grant',0),('grant',2147483648),('lease',1.5),
                            ('lease',True),('cart',2147483648),('cart',-2147483649),('session',''),
                            ('session','x'*81),('nonce',''),('nonce','x'*121)):
            self.rows = copy.deepcopy(original); self.records('server','bind')[0][field] = value
            with self.subTest(field=field,value=value), self.assertRaises(ValueError):
                self.analyze()

    def test_real_signed_native_cart_ids_including_zero_are_valid(self):
        for cart in (-2147483648,0,2147483647):
            self.selection,self.logs,self.rows = fixture()
            self.logs['client1'] = [line.replace('"primary": 42','"primary": '+str(cart)).replace('"secondary": 42','"secondary": '+str(cart)) for line in self.logs['client1']]
            self.logs['server'] = [line.replace('"id": 42','"id": '+str(cart)) for line in self.logs['server']]
            for rows in self.rows.values():
                for row in rows:
                    if 'cart' in row: row['cart'] = cart
            with self.subTest(cart=cart):
                self.assertEqual(self.analyze()['cartID'],cart)

    def test_three_bounded_rounds_cannot_be_reordered_or_compressed(self):
        original = copy.deepcopy(self.rows)
        for field,value,index in (('round',2,0),('elapsed',-1,0),('elapsed',26001,2),
                                  ('elapsed',7999,1),('elapsed',17000,1),('elapsed',16000,0)):
            self.rows = copy.deepcopy(original); self.records('client1','request')[index][field] = value
            with self.subTest(field=field,value=value), self.assertRaises(ValueError):
                self.analyze()
        self.rows = copy.deepcopy(original); self.records('client2','request')[0]['wall'] = EPOCH-1
        with self.assertRaises(ValueError): self.analyze()

    def test_local_callback_order_and_shared_scenario_epoch_are_required(self):
        original = copy.deepcopy(self.rows)
        self.rows['client1'][0],self.rows['client1'][1] = self.rows['client1'][1],self.rows['client1'][0]
        with self.assertRaises(ValueError): self.analyze()
        self.rows = copy.deepcopy(original)
        self.rows['server'][0],self.rows['server'][1] = self.rows['server'][1],self.rows['server'][0]
        with self.assertRaises(ValueError): self.analyze()
        self.rows = copy.deepcopy(original)
        self.logs['client2'][0] = '[CART_MP] START epoch=999'
        with self.assertRaisesRegex(ValueError,'epoch'): self.analyze()

    def test_callback_order_is_checked_even_inside_same_millisecond(self):
        original = copy.deepcopy(self.rows)
        for role in ('client1','server'):
            self.rows = copy.deepcopy(original)
            self.rows[role][0]['wall'] = self.rows[role][1]['wall']
            self.rows[role][0],self.rows[role][1] = self.rows[role][1],self.rows[role][0]
            with self.subTest(role=role),self.assertRaisesRegex(ValueError,'stages reordered'):
                self.analyze()

    def test_missing_and_reused_native_owner_or_cart_evidence_is_rejected(self):
        baseline = copy.deepcopy(self.logs)
        self.logs['client1'] = [line for line in self.logs['client1'] if '[CART_MP_STATE]' not in line]
        with self.assertRaisesRegex(ValueError,'owner state'): self.analyze()
        self.logs = copy.deepcopy(baseline)
        self.logs['client1'][1] = self.logs['client1'][1].replace('"id": 7','"id": 8')
        with self.assertRaisesRegex(ValueError,'native owner'): self.analyze()
        self.logs = copy.deepcopy(baseline)
        self.logs['client1'][1] = self.logs['client1'][1].replace('"secondary": 42','"secondary": 43')
        with self.assertRaisesRegex(ValueError,'hands'): self.analyze()
        self.logs = copy.deepcopy(baseline)
        self.logs['server'][-1] = self.logs['server'][-1].replace('"id": 42','"id": 43')
        with self.assertRaisesRegex(ValueError,'descriptor'): self.analyze()

    def test_strict_json_duplicates_nonfinite_and_trailing_data_are_rejected(self):
        self.write(); path=self.profile/'server-launch.log'; original=path.read_text()
        raw=json.dumps(self.records('server','bind')[0])
        for replacement in (raw[:-1]+',"guarded":true}',raw.replace('"grant": 1','"grant": NaN'),raw+' garbage','[]'):
            path.write_text(original.replace(raw,replacement,1))
            with self.subTest(replacement=replacement),self.assertRaises(ValueError): API['analyze'](self.profile)

    def test_analyzer_and_cli_preserve_all_original_capture_files(self):
        self.write()
        sentinel=self.profile/'existing-analysis.json';sentinel.write_text('preserve-me')
        before={path.name:path.read_bytes() for path in self.profile.iterdir()}
        result=API['analyze'](self.profile)
        self.assertTrue(result['evidenceComplete'])
        cli=subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.profile)],
                           text=True,capture_output=True,timeout=15)
        self.assertEqual(cli.returncode,0,cli.stderr)
        self.assertEqual(json.loads(cli.stdout),result)
        self.assertEqual(before,{path.name:path.read_bytes() for path in self.profile.iterdir()})


if __name__ == '__main__':
    unittest.main()
