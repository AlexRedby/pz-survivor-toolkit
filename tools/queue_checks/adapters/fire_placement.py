"""Bind each Fire trial to fresh centered placement, setup and admission."""
import json
import re
from .. import placement


def records(text, marker):
    result = []
    for match in re.finditer(re.escape('[FIRE_TEST] ' + marker) + r'(?=\s|$)([^\r\n]*)', text):
        value = json.loads(match[1])
        if not isinstance(value, dict):
            raise ValueError('Malformed Fire ' + marker + ' envelope')
        result.append((match.start(), value))
    return result


def _key(row):
    return row.get('case'), row.get('trial')


def validate(selection, client, authority, results):
    """Check each process's chronology without comparing independent MP clocks."""
    expected = []
    for case in selection['cases']:
        result = next((row for row in results if row.get('id') == case), {})
        trial = result.get('trial')
        maximum = 8 if case == 'kindle-retry' else 1
        if type(trial) is not int or not 1 <= trial <= maximum:
            raise ValueError('Fire placement final trial is invalid: ' + case)
        expected.extend((case, value) for value in range(1, trial + 1))
    local, remote, prepared, admitted, receipts = (
        records(text, marker) for text, marker in (
            (client, 'CLIENT_PLACEMENT'), (authority, 'AUTHORITY_PLACEMENT'),
            (authority, 'PREPARED'), (client, 'ADMITTED'), (authority, 'AUTHORITY')))
    diagnostics = records(client, 'IGNITION_DIAG')
    ignition_trials = [key for key in expected if key[0] not in ('fuel', 'missing-target-after-expansion')]
    if ([_key(row) for _, row in diagnostics] != ignition_trials
            or any(type(row.get('trial')) is not int for _, row in diagnostics)):
        raise ValueError('Fire received ignition trials missing, duplicate, foreign or reordered')
    streams = (local, remote, prepared, admitted, receipts)
    if any([_key(row) for _, row in stream] != expected
           or any(type(row.get('trial')) is not int for _, row in stream) for stream in streams):
        raise ValueError('Fire placement/setup/admission missing, duplicate, foreign or reordered')
    publications = []
    for match in re.finditer(re.escape('[QUEUE_CHECK] ') + r'([^\r\n]*)', client):
        row = json.loads(match[1])
        if isinstance(row, dict) and row.get('suite') == 'fire' and row.get('event') == 'case':
            publications.append((match.start(), row))
    if [row.get('id') for _, row in publications] != selection['cases']:
        raise ValueError('Fire placement case publication differs')
    if selection['kind'] == 'mp':
        if (any(records(client, marker) for marker in ('AUTHORITY_PLACEMENT', 'PREPARED', 'AUTHORITY', 'REMOVED'))
                or any(records(authority, marker) for marker in ('CLIENT_PLACEMENT', 'ADMITTED', 'IGNITION_DIAG'))):
            raise ValueError('Fire placement published by wrong process')
    seen_ids = set()
    for i, (case, trial) in enumerate(expected):
        lp, local_row = local[i]; rp, remote_row = remote[i]
        pp, ids = prepared[i]; ap, admission = admitted[i]; vp, receipt = receipts[i]
        for row in (local_row, remote_row):
            if set(row) != {'case', 'trial', 'actor', 'target', 'proof'} or row['actor'] != 'client1':
                raise ValueError('Malformed Fire placement identity')
        target = local_row['target']
        placement.validate(local_row['proof'], target, 'local', centered=True)
        placement.validate(remote_row['proof'], remote_row['target'],
                           'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        if remote_row['target'] != target or selection['kind'] == 'sp' and remote_row != local_row:
            raise ValueError('Fire placement target or SP proof differs')
        standing = ids.get('placement')
        if (not isinstance(standing, dict) or set(standing) != {'x', 'y', 'z'}
                or any(type(value) is not int for value in standing.values()) or standing != target):
            raise ValueError('Fire placement differs from prepared identities')
        if (any(type(ids.get(key)) is not int for key in ('x', 'y', 'z'))
                or (ids['x'], ids['y'], ids['z']) != (target['x'] + 1, target['y'], target['z'])):
            raise ValueError('Fire target must be east of the centered standing tile')
        if admission != dict(case=case, trial=trial, actor='client1'):
            raise ValueError('Malformed Fire native admission identity')
        # Every setup creates new native items. A repeated ID could pair a fresh
        # placement receipt with resources from an earlier completed trial.
        resources = ids.get('resources')
        item_ids = ([ids.get('book')] + [row.get('id') for row in resources if isinstance(row, dict)]
                    if isinstance(resources, list) else [ids.get('log'), ids.get('book')])
        if (any(type(value) is not int for value in item_ids)
                or len(set(item_ids)) != len(item_ids) or seen_ids.intersection(item_ids)):
            raise ValueError('Fire trial item IDs are invalid, duplicate or stale')
        seen_ids.update(item_ids)
        cp = next(position for position, row in publications if row.get('id') == case)
        diagnostic = next((position for position, row in diagnostics if _key(row) == (case, trial)), None)
        if (diagnostic is not None and (not ap < diagnostic < cp
                or i + 1 < len(expected) and diagnostic >= local[i + 1][0]
                or selection['kind'] == 'sp' and diagnostic <= vp)):
            raise ValueError('Fire received ignition trial did not precede next placement or final case')
        if (not lp < ap < cp or not rp < pp < vp
                or selection['kind'] == 'sp' and not lp < rp < pp < ap < vp < cp
                or i and (admitted[i - 1][0] >= lp or receipts[i - 1][0] >= rp)
                or i and expected[i - 1][0] != case
                and next(position for position, row in publications if row.get('id') == expected[i - 1][0]) >= lp
                or selection['kind'] == 'sp' and i and receipts[i - 1][0] >= lp):
            raise ValueError('Fire placement did not precede setup and native admission')
    # A final case result belongs after its final native admission. In SP its
    # authoritative receipt is in this same stream and was checked above.
    return True
