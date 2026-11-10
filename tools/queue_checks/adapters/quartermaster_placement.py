"""Require a fresh centered SP placement before each native transfer round."""
import json
import re

from .. import placement


MARKER = '[QM_TRANSFER_PLACEMENT]'
TRANSFER_MARKER = '[QM_TRANSFER]'
PHASES = ('success', 'partial', 'rejected', 'withdraw', 'custom')
OUTCOMES = (
    'PHASE success moved=2 remaining=0 tailRead=true queueObserved=true',
    'PHASE partial moved=1 remaining=1 tailRead=true queueObserved=true',
    'PHASE rejected moved=0 remaining=2 tailRead=false queueObserved=false',
    'PHASE withdraw moved=1 remaining=1 tailRead=true queueObserved=true',
    'CUSTOM protected=3 queueUnchanged=true',
    'COMPLETE case=manifest',
)


def _object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('Duplicate Quartermaster placement JSON field: ' + key)
        value[key] = item
    return value


def _tile(value):
    return (isinstance(value, dict) and set(value) == {'x', 'y', 'z'}
            and all(type(item) is int and abs(item) < 1000000 for item in value.values()))


def validate(selection, client, foreign=()):
    """Use raw process order; proof timing is local to its own placement epoch."""
    if (selection.get('kind') != 'sp' or selection.get('cases') != ['manifest']
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1):
        raise ValueError('Quartermaster transfer placement requires one SP manifest client')
    if any(MARKER in text or TRANSFER_MARKER in text for text in foreign):
        raise ValueError('Quartermaster transfer evidence published by a foreign process')
    records = list(re.finditer(r'(\[QM_TRANSFER_PLACEMENT\]|\[QM_TRANSFER\])([^\r\n]*)', client))
    expected = [(MARKER, event, phase, index)
                if event != 'OUTCOME' else (TRANSFER_MARKER, OUTCOMES[index - 1], phase, index)
                for index, phase in enumerate(PHASES, 1)
                for event in ('LAYOUT', 'LOCAL', 'PREPARED', 'ADMITTED', 'OUTCOME')]
    expected.append((TRANSFER_MARKER, OUTCOMES[-1], None, None))
    if len(records) != len(expected):
        raise ValueError('Missing or duplicate Quartermaster placement/setup/admission/outcome evidence')
    target = None
    tokens = set()
    epoch = None
    for record, (marker, event, phase, index) in zip(records, expected):
        if record[1] != marker:
            raise ValueError('Reordered Quartermaster placement/setup/admission/outcome evidence')
        if marker == TRANSFER_MARKER:
            if record[2] != ' ' + event:
                raise ValueError('Missing, duplicate, reordered or incorrect native transfer outcomes')
            continue
        prefix = ' ' + event + ' '
        if not record[2].startswith(prefix):
            raise ValueError('Unknown or reordered Quartermaster placement event')
        row = json.loads(record[2][len(prefix):], object_pairs_hook=_object)
        fields = {'case', 'phase', 'index', 'token', 'target'}
        fields |= {'proof'} if event == 'LOCAL' else {'boxes'} if event in ('LAYOUT', 'PREPARED') else set()
        if (not isinstance(row, dict) or set(row) != fields or row.get('case') != 'manifest'
                or row.get('phase') != phase or type(row.get('index')) is not int or row['index'] != index
                or not isinstance(row.get('token'), str) or not row['token'] or len(row['token']) > 256
                or any(character.isspace() for character in row['token']) or not _tile(row.get('target'))):
            raise ValueError('Malformed Quartermaster placement identity/schema')
        if event == 'LAYOUT':
            if row['token'] in tokens or target is not None and row['target'] != target:
                raise ValueError('Stale Quartermaster placement epoch or target drift')
            tokens.add(row['token'])
            target = row['target']
            epoch = row['token']
        if row['target'] != target or row['token'] != epoch:
            raise ValueError('Quartermaster placement epoch/target differs')
        if event in ('LAYOUT', 'PREPARED'):
            boxes = row['boxes']
            expected_boxes = [dict(target, x=target['x'] + 1), dict(target, y=target['y'] + 1)]
            if (not isinstance(boxes, list) or len(boxes) != 2 or not all(_tile(box) for box in boxes)
                    or boxes != expected_boxes):
                raise ValueError('Quartermaster physical boxes must be east and south of placement')
        if event == 'LOCAL':
            placement.validate(row['proof'], target, 'local', centered=True)
    return True
