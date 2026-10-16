import unittest
from verify import verify


def logs(missing=False, timer='shared'):
    server = 'SERVER COMPLETE\n[AnimalTrailerSyncMPFix] ACTIVE 1.3\n'
    client = 'CLIENT COMPLETE\nCLIENT INGAME 42.21.0\nCLIENT WEAPON_NATIVE_EQUIP\n'
    server += 'SERVER START_POSITION nativeTeleport=true clientAck=true actual=10.5,20.5,0 expected=10.5,20.5,0\nSERVER FIXTURE trailer=7\n'
    client += 'CLIENT START_POSITION nativeTeleport=true serverAck=true actual=10.5,20.5,0 expected=10.5,20.5,0\nCLIENT FIXTURE 7\n'
    for i, kind in enumerate(['hen', 'hen', 'chick'], 1):
        server += f'SERVER SEEDED kind={kind} animal={i + 100} online={i + 200}\n'
        hand, animal = ('nil', 'nil') if missing else ('Base.Animal:test', str(i + 100))
        server += f'SERVER VERIFY index={i} count={3 - i} hand={hand} animal={animal}\n'
        client += f'CLIENT AFTER index={i} count={3 - i} hand={hand} animal={animal} queue=0\n'
        client += f'CLIENT QUEUE index={i} target={i + 100} ids=test entryDistance=0.5\n'
        client += f'RELEASE_AFTER item={i + 300} inventoryHas=true\nCLIENT ORDER_STATUS releases=1\n'
        if i == 1: client += 'CLIENT REPLAY PASS stale trailer snapshot reproduced; woven authoritative item snapshot repaired; hands, identities, neighbors and capacity preserved\n'
        for side in ['SERVER', 'CLIENT']:
            audit = f'{side} WHERE index={i} inventory={i + 300}/{i + 100} groundAlive= groundItems=\n'
            if side == 'SERVER': server += audit
            else: client += audit
        if not missing:
            server += f'SERVER DROP index={i} found=true handsEmpty=true\n'
            client += f'CLIENT DROP_VERIFIED index={i} found=true handsEmpty=true clientTrailer={3 - i}\n'
    server += 'SERVER TIMER periodicSendCounts=' + ('{201=4, 202=4, 203=4}' if timer == 'shared' else '{201=0, 202=0, 203=4}') + '\n'
    return server, client


class VerifyTests(unittest.TestCase):
    def test_start_requires_both_arrivals_before_fixture_and_nearby_native_grabs(self):
        server, client = logs()
        for broken_server, broken_client in [
            (server.replace('clientAck=true', 'clientAck=false'), client),
            (server, client.replace('serverAck=true', 'serverAck=false')),
            (server, client.replace('actual=10.5', 'actual=30.5')),
            (server, client.replace('expected=10.5,20.5,0', 'expected=11.5,20.5,0').replace('actual=10.5', 'actual=11.5')),
            (server, 'CLIENT FIXTURE 7\n' + client),
            (server, client.replace('entryDistance=0.5', 'entryDistance=25.0', 1)),
            (server, client.replace('entryDistance=0.5', 'entryDistance=nan', 1)),
        ]:
            with self.subTest(client=broken_client):
                with self.assertRaises(ValueError):
                    verify(broken_server, broken_client)

    def test_fixed_combined(self):
        self.assertIn('PASS', verify(*logs()))

    def test_timer_negative_control(self):
        self.assertIn('PASS', verify(*logs(timer='starved'), timer='starved'))
        with self.assertRaisesRegex(ValueError, 'not shared'):
            verify(*logs(timer='starved'))

    def test_equipment_negative_control(self):
        self.assertIn('PASS', verify(*logs(missing=True), scenario='equipment', hands='missing'))
        server, client = logs(missing=True)
        with self.assertRaisesRegex(ValueError, 'absent from inventory'):
            verify(server, client.replace('inventory=301/101', 'inventory='), scenario='equipment', hands='missing')

    def test_identity_and_completion(self):
        server, client = logs()
        for broken, error in [(client.replace('animal=102', 'animal=999'), 'Exact animal'), (client.replace('CLIENT COMPLETE', ''), 'did not finish')]:
            with self.assertRaisesRegex(ValueError, error):
                verify(server, broken)

    def test_drop_and_order_probe_are_required(self):
        server, client = logs()
        for broken, error in [(client.replace('found=true', 'found=false', 1), 'live drops'), (client.replace('RELEASE_AFTER', 'MISSED_RELEASE', 1), 'release all grants'), (client.replace('releases=1', 'releases=0', 1), 'release all grants')]:
            with self.assertRaisesRegex(ValueError, error):
                verify(server, broken)

    def test_inventory_identity_is_shared(self):
        server, client = logs()
        with self.assertRaisesRegex(ValueError, 'item ID differs'):
            verify(server, client.replace('inventory=301/101', 'inventory=999/101'))

    def test_timer_must_target_seeded_ids(self):
        server, client = logs()
        with self.assertRaisesRegex(ValueError, 'wrong animals'):
            verify(server.replace('{201=4', '{999=4'), client)

    def test_ghost_replay_is_not_a_timer_or_grab_pass(self):
        server, client = logs()
        self.assertIn('PASS', verify(server, client, scenario='ghost'))
        with self.assertRaisesRegex(ValueError, 'decoder replay'):
            verify(server, client.replace('CLIENT REPLAY PASS', 'CLIENT REPLAY FAIL', 1), scenario='ghost')
        for broken in (client.replace('stale trailer snapshot reproduced; woven authoritative item snapshot repaired; hands, identities, neighbors and capacity preserved',
                                      'baseline ghost reproduced; native repair'),
                       client.replace('capacity preserved', 'capacity changed'),
                       client + 'CLIENT REPLAY PASS stale trailer snapshot reproduced; woven authoritative item snapshot repaired; hands, identities, neighbors and capacity preserved\n'):
            with self.assertRaisesRegex(ValueError, 'decoder replay'):
                verify(server, broken, scenario='ghost')


if __name__ == '__main__':
    unittest.main()
