from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.adapters.vehicle_inventory import analyze,PHASES,MARKER


def evidence():
    logs={role:[] for role in ('server','client1','client2')}
    logs['server'] += [MARKER+'PEER client1 connection=11:101',MARKER+'PEER client2 connection=22:202',MARKER+'REJOIN connection=33:303']
    for phase in PHASES:
        vehicle=1 if PHASES.index(phase)<PHASES.index('replacement') else 2
        logs['server'].append(MARKER+f'STATE {phase} vehicle={vehicle} contents=6:GloveBox=[101:Base.Wrench];')
        for role in logs:logs[role].append(MARKER+f'PASS {role} {phase}')
        for role in ('client2','client1'):logs['server'].append(MARKER+f'ACK {role} {phase}')
        recipients=(11,22) if phase in ('initial','late-add','late-remove','nested-add','nested-remove','replacement') else (11,33)
        kind='full' if phase in ('initial','replacement') else 'add' if phase in ('late-add','nested-add','post-rejoin-add') else 'remove' if phase in ('late-remove','nested-remove','post-rejoin-remove') else None
        if kind:
            for guid in recipients:logs['server'].append(MARKER+f'WIRE phase={phase} kind={kind} vehicle={vehicle} channel=0 guid={guid}')
    logs['server'] += [MARKER+'MUSIC vehicle=1',MARKER+'MUSIC vehicle=2']
    logs['client2'] += [MARKER+'NATIVE_EXIT client2',MARKER+'NATIVE_RECONNECT client2']
    for role in logs:logs[role].append(MARKER+'COMPLETE '+role)
    return {role:'\n'.join(rows) for role,rows in logs.items()}


class VehicleInventoryEvidence(unittest.TestCase):
    def test_complete_two_recipient_traffic_and_replica_checks(self):self.assertEqual(analyze(evidence())[0],[])
    def test_late_delta_on_old_channel_is_rejected(self):
        logs=evidence();logs['server']=logs['server'].replace('kind=add vehicle=1 channel=0','kind=add vehicle=1 channel=1');self.assertTrue(analyze(logs)[0])
    def test_nested_delta_on_old_channel_is_rejected(self):
        logs=evidence();logs['server']=logs['server'].replace('phase=nested-add kind=add vehicle=1 channel=0','phase=nested-add kind=add vehicle=1 channel=1');self.assertTrue(analyze(logs)[0])
    def test_initial_delta_is_rejected_even_with_full_snapshot(self):
        logs=evidence();logs['server']+='\n'+MARKER+'WIRE phase=initial kind=add vehicle=1 channel=0 guid=11';self.assertTrue(analyze(logs)[0])
    def test_new_recipient_needs_own_initial_snapshot(self):
        logs=evidence();logs['server']=logs['server'].replace(MARKER+'WIRE phase=initial kind=full vehicle=1 channel=0 guid=22','');self.assertTrue(analyze(logs)[0])
    def test_same_guid_with_a_new_native_connection_is_valid(self):
        logs=evidence();logs['server']=logs['server'].replace('REJOIN connection=33:303','REJOIN connection=22:303').replace('guid=33','guid=22');self.assertEqual(analyze(logs)[0],[])
    def test_actual_replaced_guest_connection_is_required(self):
        logs=evidence();logs['server']=logs['server'].replace('REJOIN connection=33:303','REJOIN connection=22:202');self.assertTrue(analyze(logs)[0])
    def test_both_clients_must_confirm_every_phase(self):
        logs=evidence();logs['server']=logs['server'].replace(MARKER+'ACK client2 native-return','');self.assertTrue(analyze(logs)[0])
    def test_snapshots_cannot_substitute_for_later_deltas(self):
        logs=evidence();logs['server']=logs['server'].replace('phase=late-add kind=add','phase=late-add kind=full');self.assertTrue(analyze(logs)[0])


if __name__=='__main__':unittest.main()
