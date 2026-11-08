"""Validate attributed diagnostic evidence without inventing performance gates."""
import json
import math
import re
from pathlib import Path


def verify(root, text, selection):
    def rows(kind):
        return [json.loads(x) for x in re.findall(r'\[STORAGE_PROFILE\] SELECTION_' + kind + r' (\{[^\r\n]+\})', text)]
    def number(x):
        return type(x) in (int, float) and math.isfinite(x) and x >= 0
    item_type = selection.get('options', {}).get('inventory_selection_item', 'Base.Nails')
    cohorts = {
        'Base.Nails': ('nonfluid', 'none', {'fuel': False, 'disinfectant': False}),
        'Base.PetrolCan': ('fluid', 'Petrol', {'fuel': True, 'disinfectant': False, 'beverage': False, 'alcoholic': False, 'empty': False}),
        'Base.Whiskey': ('fluid', 'Whiskey', {'fuel': False, 'disinfectant': True, 'beverage': True, 'alcoholic': True, 'empty': False}),
    }
    if not isinstance(item_type, str) or item_type not in cohorts:
        raise ValueError('Unsupported selection observer item cohort')
    branch, fluid_type, usage = cohorts[item_type]
    state_keys = ('itemType', 'branch', 'isFluid', 'isDrainable', 'fluidType', 'fluidAmount', 'fluidCapacity',
                  'fillPolicy', 'verifiedItems', 'stateVerified', 'usageWitness')
    def state(row):
        if not isinstance(row, dict):
            raise ValueError('Selection observer workload receipt missing')
        witness = row.get('usageWitness')
        amount, capacity = row.get('fluidAmount'), row.get('fluidCapacity')
        if (row.get('itemType') != item_type or row.get('branch') != branch
                or row.get('isFluid') is not (branch == 'fluid') or row.get('isDrainable') is not False
                or row.get('fluidType') != fluid_type or row.get('verifiedItems') != 4800
                or row.get('stateVerified') is not True
                or row.get('fillPolicy') != ('setup-full-capacity' if branch == 'fluid' else 'native-nonfluid')
                or not number(amount) or not number(capacity)
                or (branch == 'fluid' and not (amount == capacity and amount > 0.15))
                or (branch == 'nonfluid' and (amount != 0 or capacity != 0))
                or not isinstance(witness, dict) or witness != usage
                or any(type(value) is not bool for value in witness.values())):
            raise ValueError('Selection observer item type, branch or immutable fluid state differs')
        return {key: row[key] for key in state_keys}
    if rows('FAIL') or len(rows('SETUP')) != 1 or len(rows('RESTORED')) != 1:
        raise ValueError('Selection observer setup/cleanup failed')
    setup = rows('SETUP')[0]
    if setup.get('count') != 4800:
        raise ValueError('Selection observer setup population differs')
    expected_state = state(setup)
    samples = rows('SAMPLE')
    expected = [(mode + '-' + state, i) for mode in ('clean', 'vanilla') for state in ('collapsed', 'expanded') for i in range(1, 8)]
    if [(r.get('phase'), r.get('index')) for r in samples] != expected:
        raise ValueError('Selection observer sample sequence incomplete')
    for row in samples:
        if (row.get('count') != 4800 or row.get('emptySelection') is not True or row.get('identityVerified') is not True
                or row.get('observerOverheadIncluded') is not True or not number(row.get('outerMs'))):
            raise ValueError('Selection observer workload or timing invalid')
        mode = row['phase'].split('-')[0]
        observed=row.get('workload', {})
        if state(row) != expected_state or state(observed) != expected_state:
            raise ValueError('Selection observer fluid state changed across samples')
        if (observed.get('renderer')!=mode or observed.get('mode')!='details' or observed.get('classMatches') is not True
                or observed.get('probeItems')!=4800 or observed.get('groups')!=1
                or observed.get('expanded') is not row['phase'].endswith('-expanded')):
            raise ValueError('Selection observer actual view state differs')
        leaves=row.get('mapperLabels')
        if (not isinstance(leaves,list) or not 1<=len(leaves)<=2 or len(set(leaves))!=len(leaves)
                or any(label not in ('mapper.'+mode,'mapper.bc') for label in leaves)):
            raise ValueError('Selection observer actual mapper identity missing')
        for name in (*leaves, 'presentation.refresh'):
            if row.get('metrics', {}).get(name, {}).get('calls', 0) < 1:
                raise ValueError('Selection observer expected span did not execute: ' + name)
        for name, m in row['metrics'].items():
            if (type(m.get('calls')) is not int or m['calls'] < 1 or m.get('errors') != 0
                    or not all(number(m.get(k)) for k in ('inclusiveMs', 'exclusiveMs', 'maxMs'))
                    or m['exclusiveMs'] > m['inclusiveMs'] or len(m.get('samplesMs', [])) > 256
                    or m.get('droppedSamples') != 0 or not all(number(x) for x in m['samplesMs'])):
                raise ValueError('Invalid selection span: ' + name)
    inputs = json.loads((Path(root) / 'selection-observer-inputs.json').read_text())
    if inputs.get('test_only') is not True or len(inputs.get('sources', [])) != 9:
        raise ValueError('Selection observer provenance missing')
    restored=rows('RESTORED')[0]
    if state(restored) != expected_state:
        raise ValueError('Selection observer fluid state changed before cleanup')
    if (restored.get('ownedRemoved') != 4800 or restored.get('identityVerified') is not True
            or type(restored.get('originals')) is not int or restored.get('remaining')!=restored['originals']):
        raise ValueError('Selection probe cleanup population differs')
    return {'selection_samples': samples, 'selection_observer': inputs, 'selection_workload': expected_state,
            'scope': 'native synchronous refresh callback costs; observer overhead included; not frame/FPS latency'}
