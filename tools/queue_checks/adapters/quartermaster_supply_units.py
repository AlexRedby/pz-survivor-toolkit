"""Exact native drainable-use receipts for the Quartermaster crafting adapter."""
import json
from pathlib import Path
import re

from . import craft

MARKER = '[QM_USES] '
CASES = ['full', 'carried', 'partial']


def complete(role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + r'COMPLETE(?:\s|$)', text)) == 1


def records(text):
    result = []
    for match in re.finditer(re.escape(MARKER) + r'(PREPARED|VERIFIED|RESULT) (.*)', text):
        value = json.loads(match.group(2))
        if type(value) is not dict:
            raise ValueError('Invalid supply-unit receipt envelope')
        result.append((match.group(1), value))
    return result


def verify(root, selection):
    root, issues, outcomes = Path(root), [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        if not complete('client1', text) or MARKER + 'FAIL ' in text + authority:
            raise ValueError('Supply-unit completion missing/duplicated or fixture failed')
        local = records(text)
        receipts = [(kind, value) for kind, value in records(authority) if kind != 'RESULT']
        results = [value for kind, value in local if kind == 'RESULT']
        if ([(kind, value.get('case')) for kind, value in receipts] != [
                (kind, case) for case in CASES for kind in ('PREPARED', 'VERIFIED')]
                or [value.get('case') for value in results] != CASES
                or text.count(MARKER + 'CLEANUP') != 1 or authority.count(MARKER + 'CLEANUP') != 1):
            raise ValueError('Supply-unit authority/result order or cleanup differs')
        identities = []
        for index, case in enumerate(CASES, 1):
            prep, receipt, result = receipts[(index-1)*2][1], receipts[(index-1)*2+1][1], results[index-1]
            count = 3 if case == 'partial' else 2
            if (set(prep) != {'index', 'case', 'ids', 'source'} or prep['index'] != index
                    or not craft._matches(prep, dict(index=index, case=case))
                    or not craft._ids(prep['ids'], count) or type(prep['source']) is not dict
                    or set(prep['source']) != {'x', 'y', 'z', 'index'}
                    or not all(type(value) is int for value in prep['source'].values())
                    or prep['source']['index'] < 0):
                raise ValueError('Supply preparation identities differ: ' + case)
            expected = [(0, 0), (0, 0), (2, 4)] if case == 'partial' else [(2 if case == 'full' else 1, 2), (2, 4)]
            items = [dict(id=item, container=location, uses=uses) for item, (location, uses) in zip(prep['ids'], expected)]
            if (set(receipt) != {'index', 'case', 'items', 'outputIds', 'outputs', 'consumedUses'}
                    or not craft._matches(receipt, dict(index=index, case=case, items=items, outputs=1, consumedUses=2))
                    or not craft._ids(receipt['outputIds'], 1)
                    or not craft._matches(result, dict(index=index, case=case, walked=case != 'carried',
                                                       picked=case != 'carried', crafted=True, returned=case == 'full', receipt=receipt))):
                raise ValueError('Supply remaining uses, exact fetch or native effect differs: ' + case)
            identities += prep['ids'] + receipt['outputIds']
        if not craft._ids(identities):
            raise ValueError('Supply fixture identities overlap')
        outcomes.append(dict(actor='client1', case='uses', status='passed', outcome=dict(scenarios=results)))
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
        outcomes = [dict(actor='client1', case='uses', status='failed', reason=str(error))]
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Fixture-driven vanilla/Neat Storage and craft button callbacks; no physical mouse or layout assertion.',
        'Native two-use DuctTape recipe: full remote, sufficient carried and partial carried/remote rolls.',
        'Exact authoritative identities, two consumed uses and one output per craft; fresh one-client SP/menu Host.']})
