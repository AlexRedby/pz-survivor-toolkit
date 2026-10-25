"""Pure held-cart challenge/echo evidence checks; never certifies runtime or migration."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re

MARKER = '[CART_LEASE] '
ROLES = ('server', 'client1', 'client2')
CLIENTS = ROLES[1:]
MAX_COUNTER = 2147483647
MAX_TIME = 9007199254740991


def require(value, message):
    if not value:
        raise ValueError(message)


def pairs(entries):
    result = {}
    for key, value in entries:
        require(key not in result, 'Duplicate JSON key: '+key)
        result[key] = value
    return result


def parse(text):
    def invalid(value):
        raise ValueError('Nonfinite JSON constant: '+value)
    result = json.loads(text, object_pairs_hook=pairs, parse_constant=invalid)
    def finite(value):
        if type(value) is float:
            require(math.isfinite(value), 'Nonfinite JSON number')
        elif isinstance(value, dict):
            for entry in value.values():
                finite(entry)
        elif isinstance(value, list):
            for entry in value:
                finite(entry)
    finite(result)
    return result


def integer(row, field, low, high):
    value = row.get(field)
    require(type(value) is int and low <= value <= high, 'Invalid lease '+field)
    return value


def text(row, field, maximum):
    value = row.get(field)
    require(isinstance(value, str) and 0 < len(value) <= maximum, 'Invalid lease '+field)
    return value


def marked(log, marker):
    return [parse(line.split(marker, 1)[1]) for line in log.splitlines() if marker in line]


def analyze(root):
    root = Path(root)
    selection = parse((root/'selection.json').read_text())
    require(isinstance(selection, dict) and selection.get('suite') == 'wooden_cart_multiplayer'
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and selection.get('cases') == ['owner_observer_motion'], 'Frozen selection does not match lease control capture')
    options = selection.get('options')
    require(isinstance(options, dict) and options.get('cart_lease_control') is True
            and options.get('mp_host') is True and options.get('cart_fast_motion') is True,
            'Explicit disposable menu Host 26-second lease control selection required')
    require('cart_wall_exit' not in options and all(options.get(key, False) is False for key in
            ('cart_actions', 'cart_inventory_equip', 'cart_hotkey_setdown')),
            'Lease control evidence requires the held-only ordinary motion bank')
    logs = {role: (root/(role+'-launch.log')).read_text() for role in ROLES}
    epochs = {role: re.findall(r'\[CART_MP\] START epoch=(\d+)', log) for role, log in logs.items()}
    require(all(len(values) == 1 for values in epochs.values())
            and len({values[0] for values in epochs.values()}) == 1, 'Unique shared native scenario epoch required')
    epoch = int(epochs['server'][0])
    states = marked(logs['client1'], '[CART_MP_STATE] ')
    require(states and all(isinstance(row, dict) for row in states), 'Missing native owner state evidence')
    owners = {integer(row, 'id', 0, 32767) for row in states if row.get('user') == 'client1'}
    require(len(owners) == 1, 'Unique current native owner required')
    owner = next(iter(owners))
    require(all(row.get('user') == 'client1' for row in states if row.get('id') == owner), 'Native owner ID reused')
    active = [row for row in states if row.get('user') == 'client1'
              and epoch <= integer(row, 'wall', 0, MAX_TIME) <= epoch+26000]
    require(active, 'Missing active native held-cart evidence')
    carts = {integer(row, 'primary', -2147483648, 2147483647) for row in active}
    require(len(carts) == 1, 'Native held cart changed')
    cart = next(iter(carts))
    require(all(integer(row, 'secondary', -2147483648, 2147483647) == cart for row in active), 'Native hands do not share exact cart')
    specs = marked(logs['server'], '[CART_MP] CART_SPEC ')
    require(len(specs) <= 1 and all(isinstance(row, dict) and integer(row, 'id', -2147483648, 2147483647) == cart for row in specs), 'Authoritative native cart descriptor differs')

    rows, indexed, counts = {}, {}, {}
    for role in ROLES:
        rows[role] = marked(logs[role], MARKER)
        require(rows[role], role+': missing lease control evidence')
        counts[role] = Counter()
        previous_wall = None
        for position, row in enumerate(rows[role]):
            require(isinstance(row, dict) and row.get('actor') == role, role+': foreign lease actor')
            require(row.get('event') != 'error', role+': lease probe error: '+str(row.get('reason')))
            event = row.get('event')
            allowed = ('bind', 'echo') if role == 'server' else ('request', 'bound', 'receipt')
            require(event in allowed, role+': unknown or foreign lease event')
            wall = integer(row, 'wall', 0, MAX_TIME)
            require(previous_wall is None or wall >= previous_wall, role+': lease local wall clock regressed')
            previous_wall = wall
            require(integer(row, 'owner', 0, 32767) == owner, role+': wrong native owner')
            nonce = text(row, 'nonce', 120)
            requester = row.get('requester') if role == 'server' else role
            require(requester in CLIENTS, role+': unknown requester')
            if event != 'request':
                require(row.get('guarded') is True, role+': missing actual native guard')
                text(row, 'session', 80)
                integer(row, 'grant', 1, MAX_COUNTER)
                integer(row, 'lease', 1, MAX_COUNTER)
                require(integer(row, 'cart', -2147483648, 2147483647) == cart, role+': wrong current native cart')
            if event in ('echo', 'receipt'):
                integer(row, 'seq', 1, 3)
                require(type(row.get('accepted')) is bool and row['accepted'] is (requester == 'client1'),
                        role+': source authority result differs')
            key = requester, nonce, owner, event
            require(key not in indexed, role+': duplicate lease event')
            indexed[key] = row, position
            counts[role][event] += 1
    require(counts['server'] == Counter(bind=6, echo=6), 'Server lease chain count differs')
    require(all(counts[role] == Counter(request=3, bound=3, receipt=3) for role in CLIENTS), 'Three lease rounds per client required')

    chains, used, nonces, bindings = [], set(), set(), set()
    for role in CLIENTS:
        requests = [row for row in rows[role] if row['event'] == 'request']
        require([integer(row, 'round', 1, 3) for row in requests] == [1, 2, 3], role+': missing or reordered lease rounds')
        for request in requests:
            round_ = request['round']
            elapsed = integer(request, 'elapsed', 0, 26000)
            require((round_-1)*8000 <= elapsed <= (round_*8000-1 if round_ < 3 else 26000),
                    role+': lease request outside scheduled round')
            require(epoch+elapsed <= request['wall'] <= epoch+26000, role+': request outside canonical active bank')
            nonce = request['nonce']
            require(nonce not in nonces, 'Fresh nonce reused across lease requests')
            nonces.add(nonce)
            chain = {}
            for event in ('request', 'bind', 'bound', 'echo', 'receipt'):
                key = role, nonce, owner, event
                require(key in indexed, role+': missing exact lease '+event)
                chain[event], position = indexed[key]
                chain[event+'Position'] = position
                used.add(key)
            require(chain['requestPosition'] < chain['boundPosition'] < chain['receiptPosition'], role+': client lease stages reordered')
            require(chain['bindPosition'] < chain['echoPosition'], role+': server lease stages reordered')
            bind = chain['bind']
            identity = tuple(bind[field] for field in ('session', 'grant', 'lease', 'cart'))
            bindings.add(identity)
            for event in ('bound', 'echo', 'receipt'):
                require(tuple(chain[event][field] for field in ('session', 'grant', 'lease', 'cart')) == identity,
                        role+': lease session/binding changed within chain')
            require(chain['echo']['seq'] == chain['receipt']['seq'] == round_, role+': lease sequence differs from request round')
            chains.append(dict(requester=role, nonce=nonce, ownerID=owner, round=round_, elapsedMs=elapsed,
                sampleToLogDelayMs=request['wall']-epoch-elapsed, session=bind['session'], grant=bind['grant'],
                lease=bind['lease'], cartID=cart, accepted=chain['receipt']['accepted']))
    require(set(indexed) == used, 'Unmatched extra lease evidence')
    require(len(bindings) == 1, 'Held-only server session/native binding changed during experiment')
    return dict(schema=1, diagnosticOnly=True, evidenceComplete=True, ownerID=owner, cartID=cart,
        epoch=epoch, roundsPerClient=3, completeChains=len(chains), nativeHeldBinding=dict(
            session=chains[0]['session'], grant=chains[0]['grant'], lease=chains[0]['lease']),
        logicalCommandMessages=dict(total=24, clientToServer=12, serverToClient=12),
        sourceFiles={role: role+'-launch.log' for role in ROLES}, chains=chains,
        qualification='Held-only current native binding and challenge/echo control-path evidence. No action, release, reconnect, full lifecycle, production migration or runtime PASS is established. Logical command counts are not wire bytes or delivery acknowledgements.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(args.profile), indent=2))


if __name__ == '__main__':
    main()
