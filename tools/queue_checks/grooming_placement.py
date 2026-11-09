"""Bind settled grooming placement to authority setup and native admission."""
import json
import re

from . import placement


def _records(text, prefix, marker):
    records = []
    for match in re.finditer(re.escape(prefix + marker) + r'(?=\s|$)([^\r\n]*)', text):
        value = json.loads(match[1])
        if not isinstance(value, dict):
            raise ValueError('Malformed grooming ' + marker + ' record')
        records.append((match.start(), value))
    return records


def validate(selection, client, authority, rows, prefix, baseline_marker):
    """Use process-local publication order; never compare clocks across roles."""
    cases = list(selection['cases'])
    local = _records(client, prefix, 'CLIENT_PLACEMENT')
    remote = _records(authority, prefix, 'AUTHORITY_PLACEMENT')
    admitted = _records(client, prefix, 'ADMITTED')
    prepared = _records(authority, prefix, 'PREPARED')
    baselines = _records(authority, prefix, baseline_marker)
    verified = _records(authority, prefix, 'VERIFIED')
    native = [record for marker in ('CANCEL', 'EDIT', 'BEFORE_TAIL', 'IDLE', 'OUTCOME', 'ACK')
              for record in _records(client, prefix, marker)]
    publications = []
    for match in re.finditer(re.escape('[QUEUE_CHECK] ') + r'([^\r\n]*)', client):
        value = json.loads(match[1])
        if isinstance(value, dict) and value.get('event') == 'case':
            publications.append((match.start(), value))
    streams = (local, remote, admitted, prepared, baselines, verified)
    if (any([value.get('case', value.get('baseline', {}).get('case')) if isinstance(value, dict) else None
             for _, value in stream] != cases for stream in streams)
            or [value.get('id') for _, value in publications] != cases
            or [row.get('id') for row in rows] != cases):
        raise ValueError('Grooming placement/setup/admission missing, duplicate, foreign or reordered')
    if selection['kind'] == 'mp' and (_records(client, prefix, 'AUTHORITY_PLACEMENT')
            or _records(authority, prefix, 'CLIENT_PLACEMENT') or _records(authority, prefix, 'ADMITTED')):
        raise ValueError('Grooming placement published by wrong process')
    for i, case in enumerate(cases):
        lp, local_row = local[i]; rp, remote_row = remote[i]
        ap, admission = admitted[i]; pp, ids = prepared[i]
        bp, _ = baselines[i]; vp, _ = verified[i]; cp, _ = publications[i]
        for receipt in (local_row, remote_row):
            if set(receipt) != {'case', 'actor', 'target', 'proof'} or receipt['actor'] != 'client1':
                raise ValueError('Malformed grooming placement identity')
        target = local_row['target']
        placement.validate(local_row['proof'], target, 'local')
        placement.validate(remote_row['proof'], remote_row['target'], 'replica' if selection['kind'] == 'mp' else 'local')
        if (remote_row['target'] != target or target != local[0][1]['target']
                or selection['kind'] == 'sp' and remote_row != local_row):
            raise ValueError('Grooming placement target or SP proof differs')
        if ids.get('placement') != target or rows[i].get('ids', {}).get('placement') != target:
            raise ValueError('Grooming placement differs from prepared identities')
        if admission != dict(case=case, actor='client1'):
            raise ValueError('Malformed grooming native admission identity')
        if (not lp < ap < cp or not rp < pp < bp < vp
                or selection['kind'] == 'sp' and not lp < rp < bp < ap < vp < cp
                or any(position <= ap for position, value in native if value.get('case') == case)
                or i and (publications[i - 1][0] >= lp or verified[i - 1][0] >= rp)):
            raise ValueError('Grooming placement did not precede setup and native admission')
