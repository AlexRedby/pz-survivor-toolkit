#!/usr/bin/env python3
"""Check a completed native run; this does not start the game."""
import argparse
import math
from pathlib import Path
import re


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(server, client, scenario='combined', timer='shared', hands='held'):
    starts = []
    for side, text, ack in [('SERVER', server, 'clientAck'), ('CLIENT', client, 'serverAck')]:
        pattern = side + r' START_POSITION nativeTeleport=true ' + ack + r'=true actual=(\S+) expected=(\S+)'
        matches = list(re.finditer(pattern, text))
        require(len(matches) == 1, 'Missing or duplicate confirmed native start position: ' + side)
        try:
            actual, expected = [list(map(float, value.split(','))) for value in matches[0].groups()]
        except ValueError:
            raise ValueError('Invalid native start position: ' + side)
        require(len(actual) == len(expected) == 3 and all(math.isfinite(x) for x in actual + expected)
                and all(abs(a - b) <= (0 if i == 2 else 0.15) for i, (a, b) in enumerate(zip(actual, expected))),
                'Native start position did not arrive: ' + side)
        require(matches[0].start() < text.find(side + ' FIXTURE '), 'Fixture preceded confirmed start position: ' + side)
        starts.append(expected)
    require(starts[0] == starts[1], 'Client/server start targets differ')
    queues = list(re.finditer(r'CLIENT QUEUE index=(\d+)[^\n]* entryDistance=(\S+)', client))
    require([m[1] for m in queues] == ['1', '2', '3']
            and all(math.isfinite(float(m[2])) and 0 <= float(m[2]) <= 1.6 for m in queues)
            and client.find('CLIENT FIXTURE ') < queues[0].start(), 'Native grabs must start beside the reachable trailer entry')
    seeded = re.findall(r'SERVER SEEDED kind=(\w+) animal=(\d+) online=(\d+)', server)
    after = re.findall(r'CLIENT AFTER index=(\d+) count=(\d+) hand=(\S+) animal=(\S+) queue=(\d+)', client)
    server_after = re.findall(r'SERVER VERIFY index=(\d+) count=(\d+) hand=(\S+) animal=(\S+)', server)
    require(len(seeded) == len(after) == len(server_after) == 3, 'Need exactly three seeds and client/server grab results')
    require(len({x[1] for x in seeded}) == len({x[2] for x in seeded}) == 3, 'Duplicate seeded animal identity')
    require([x[0] for x in seeded] == ['hen', 'hen', 'chick'], 'Wrong fixture animals')
    require('CLIENT COMPLETE' in client and 'SERVER COMPLETE' in server, 'Run did not finish')
    require('CLIENT INGAME 42.21.0' in client, 'Wrong engine build')
    require('KahluaException' not in server + client, 'Lua runtime exception')
    require('CLIENT WEAPON_NATIVE_EQUIP' in client, 'Missing native weapon case')
    for i, (_, animal, _) in enumerate(seeded):
        c, s = after[i], server_after[i]
        require(c[:2] == s[:2] == (str(i + 1), str(2 - i)) and c[4] == '0', 'Trailer count or queue mismatch')
        if hands == 'held':
            require(c[3] == s[3] == animal and c[2] != 'nil' and s[2] != 'nil', 'Exact animal not held by both sides')
        else:
            require(c[2:4] == s[2:4] == ('nil', 'nil'), 'Empty-hands control did not reproduce')
        item_ids = []
        for side, text in [('CLIENT', client), ('SERVER', server)]:
            match = re.search(side + r' WHERE index=' + str(i + 1) + r' inventory=(\S*) groundAlive=(\S*) groundItems=(\S*)', text)
            require(match is not None, 'Missing inventory/ground audit')
            items = [entry.split('/')[0] for entry in match[1].split(',') if entry.endswith('/' + animal)]
            require(len(items) == 1, 'Animal absent from inventory or duplicated')
            item_ids.append(items[0])
            if hands == 'missing':
                require(animal not in match[2].split(',') and not any(entry.endswith('/' + animal) for entry in match[3].split(',')), 'Target animal also on the ground')
        require(item_ids[0] == item_ids[1], 'Client/server inventory item ID differs')
    if hands == 'held':
        drops = re.findall(r'CLIENT DROP_VERIFIED index=(\d+) found=(\w+) handsEmpty=(\w+) clientTrailer=(\d+)', client)
        require(drops == [(str(i + 1), 'true', 'true', str(2 - i)) for i in range(3)], 'Need three exact native live drops and final empty trailer')
        require(re.findall(r'SERVER DROP index=(\d+) found=true handsEmpty=true', server) == ['1', '2', '3'], 'Server live drops not confirmed')
    if scenario in ('equipment', 'combined'):
        require(len(re.findall(r'CLIENT ORDER_STATUS[^\n]*releases=1\b', client)) == 3 and len(re.findall(r'RELEASE_AFTER item=\d+ inventoryHas=true', client)) == 3, 'Delivery-order probe did not release all grants before assertions')
    if scenario == 'ghost':
        require(len(re.findall('CLIENT REPLAY PASS stale trailer snapshot reproduced; woven authoritative item snapshot repaired; hands, identities, neighbors and capacity preserved', client)) == 1, 'Missing decoder replay and repair proof')
    if scenario in ('timer', 'combined'):
        match = re.search(r'SERVER TIMER periodicSendCounts=\{([^}]+)\}', server)
        require(match is not None, 'Missing direct periodic-send observation')
        counts = dict(re.findall(r'(\d+)=(\d+)', match[1]))
        require(set(counts) == {x[2] for x in seeded}, 'Timer counted the wrong animals')
        values = [int(counts[x[2]]) for x in seeded]
        if timer == 'shared':
            require(min(values) > 0 and len(set(values)) == 1, 'Due timer not shared by all three animals')
            require('[AnimalTrailerSyncMPFix] ACTIVE 1.3' in server, 'Tested server timer mod did not activate')
        else:
            require(values[:2] == [0, 0] and values[2] > 0, 'Vanilla timer starvation not reproduced')
    return 'NATIVE_ANIMAL_PASS scenario=' + scenario + ' hands=' + hands + ' timer=' + timer


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-log', type=Path, required=True)
    parser.add_argument('--client-log', type=Path, required=True)
    parser.add_argument('--scenario', choices=['equipment', 'ghost', 'timer', 'combined'], default='combined')
    parser.add_argument('--timer', choices=['shared', 'starved'], default='shared')
    parser.add_argument('--hands', choices=['held', 'missing'], default='held')
    args = parser.parse_args()
    print(verify(args.server_log.read_text(errors='replace'), args.client_log.read_text(errors='replace'), args.scenario, args.timer, args.hands))
