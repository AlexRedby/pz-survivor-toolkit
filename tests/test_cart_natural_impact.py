"""Natural collision proof must reject injected, missing, or unbounded evidence."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

BASE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('impact_fixture', BASE/'test_cart_impact_analyzer.py')
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)
analyzer = legacy.analyzer


def line(marker, row):
    return marker+' '.join(f'{key}={str(value).lower() if isinstance(value, bool) else value}' for key, value in row.items())


def state(t, sprint=True, held=False):
    protected = sprint and 2080 <= t < 3520
    collision = protected and t < 2720
    return dict(timeMs=0, watch=True, actor=True, local=True,
                state='CollideWithWallState' if collision else 'PlayerGetUpState' if protected else 'PlayerMovementState',
                action='collide' if collision else 'getup' if protected else 'sprint' if sprint and t < 2000 else 'run' if not sprint and t < 4000 else 'idle',
                run=not sprint and t < 4000, sprint=sprint and t < 2000,
                ignore=protected, getup=protected and not collision, hit=False, knocked=False, ragdoll=False,
                primary=1 if held else -1, secondary=1 if held else -1,
                dir='W', wallType=4, collidedN=False, collidedS=False, collidedE=False,
                collidedW=2000 <= t < 2040, collidedDoor=False, collideType='wall',
                naturalEvents=int(sprint and t >= 2000), injectedEvents=0, otherEvents=0,
                origin='native-checkHitWall' if sprint and t >= 2000 else 'none')


def receipt(row, **extra):
    return '[CART_NATURAL_HIT] '+json.dumps(dict(row, **extra))


def watch(start, held=False):
    row = state(0, held=held)
    row.update(timeMs=start-10, run=False, sprint=False, action='idle')
    return receipt(row, kind='watch', origin='watch-control', movingObjectSha256='a'*64, actionContextSha256='b'*64)


def fixture(root, name='male-empty-native-impact'):
    text, names = legacy.fixture(root, name)
    lines, poses = [], []
    for index, control in enumerate(analyzer.NATURAL_CONTROLS):
        start, sprint = 70000+10000*index, control == 'natural-sprint-wall'
        lines += [watch(start), line('[CART_NATURAL_CONTROL] START ', dict(spec=control, wall=start, x=7.5, y=20, wallX=4))]
        for t in range(0, 8001, 40):
            row = state(t, sprint=sprint)
            row['timeMs'] = start+t
            if sprint and t == 2000:
                event = dict(row, sprint=True)
                lines.append(receipt(event, kind='event', event='collideWithWall', layer='none', stack='zombie.characters.action.ActionContext.reportEvent;zombie.iso.IsoMovingObject.checkHitWall'))
                lines.append(line('[CART_NATURAL_CONTROL] INPUT_STOP ', dict(spec=control, wall=start+t, elapsed=t)))
            elif not sprint and t == 4000:
                lines.append(line('[CART_NATURAL_CONTROL] INPUT_STOP ', dict(spec=control, wall=start+t, elapsed=t)))
            lines.append(line('[CART_NATURAL_SAMPLE] ', dict(spec=control, wall=start+t, elapsed=t, x=7.5-3*min(t/2000, 1), y=20, **row, tracks='diagnostic')))
            poses.append(dict(wallTimeMillis=start+t, bones={key: legacy.MATRIX[:] for key in analyzer.BONEMAP},
                              tracks=[dict(name='Bob_SprintIntoWall' if row['state'] == 'CollideWithWallState' else 'Bob_GetUp_Back' if row['state'] == 'PlayerGetUpState' else 'Bob_Idle', weight=1)],
                              cartModel=False, cartModelCount=0))
        lines += [line('[CART_NATURAL_CONTROL] COMPLETE ', dict(spec=control, wall=start, file=control+'.mp4', frames=240, seconds=8)),
                  receipt(dict(row, timeMs=start+8500, watch=False), kind='watch', origin='watch-control',
                          movingObjectSha256='a'*64, actionContextSha256='b'*64)]
    guarded = name.endswith('sprint-wall')
    if guarded:
        def settle_legacy(row):
            t = int(row['elapsed'])
            if t >= 6000:
                row.update(sprint=False, action='movement' if 7000 <= t < 9500 else 'idle')
        text = legacy.samples(text, settle_legacy)
    lines.append(watch(legacy.START-2590, held=True))
    for entry in text.splitlines():
        if '[CART_IMPACT_SAMPLE] ' in entry:
            old = analyzer.fields(entry.split('[CART_IMPACT_SAMPLE] ', 1)[1])
            t = int(old['elapsed'])
            row = state(t)
            row.update(timeMs=legacy.START+t, naturalEvents=0,
                       injectedEvents=int(not guarded and t >= 2000),
                       origin='injected-cartLabWallEvent' if not guarded and t >= 2000 else 'none')
            for key in ('state', 'action', 'run', 'sprint', 'ignore', 'getup', 'hit', 'knocked', 'ragdoll', 'primary', 'secondary'):
                value = old[key]
                row[key] = value == 'true' if value in ('true', 'false') else float(value) if key in ('primary', 'secondary') else value
            row['collidedW'] = False
            if guarded and t >= 6000:
                row.update(sprint=False, action='movement' if 7000 <= t < 9500 else 'idle')
            if not guarded and t == 2000:
                lines.append(receipt(row, kind='event', event='collideWithWall', layer='none', stack='wooden_cart_motion.Main.wallEvent;zombie.characters.action.ActionContext.reportEvent'))
            lines.append(line('[CART_NATURAL_CART] ', dict(case=name, wall=legacy.START+t, elapsed=t,
                               drive=1 if 1000 <= t < 6000 else 4 if 7000 <= t < 9500 else 0, **row,
                               footprint='front=1.5' if guarded or t < 2080 else 'inactive',
                               blocked=False, recovering=False, clear=True)))
    lines.append(receipt(dict(row, timeMs=legacy.START+12500, watch=False), kind='watch', origin='watch-control',
                         movingObjectSha256='a'*64, actionContextSha256='b'*64))
    original = [json.loads(l) for l in (root/'action-tail-poses.jsonl').read_text().splitlines()]
    legacy.write_json(root, 'action-tail-poses.jsonl', poses+original)
    return text+'\n'+'\n'.join(lines), names


def mutate_samples(text, marker, mutate):
    output = []
    for entry in text.splitlines():
        if entry.startswith(marker):
            row = analyzer.fields(entry[len(marker):])
            mutate(row)
            entry = line(marker, row)
        output.append(entry)
    return '\n'.join(output)


class NaturalImpactTests(unittest.TestCase):
    def check_rejected(self, transform, name='male-empty-native-impact', message=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text, names = fixture(root, name)
            text = transform(root, text)
            with self.assertRaisesRegex(AssertionError, message or '.'):
                analyzer.analyze(root, text, names, require_natural=True)

    def test_bounded_natural_controls_and_explicit_injection_pass(self):
        for name in ('male-empty-native-impact', 'female-full-sprint-wall'):
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                text, names = fixture(root, name)
                result = analyzer.analyze(root, text, names, require_natural=True)
                natural = result['naturalImpact']
                self.assertTrue(natural['functionalPass'])
                self.assertEqual([r['eventSource'] for r in natural['controls']], ['none', 'native-checkHitWall'])
                self.assertEqual(natural['cases'][0]['eventSource'], 'none' if name.endswith('sprint-wall') else 'injected-cartLabWallEvent')
                self.assertTrue(any('visual animation quality' in limit for limit in result['limits']))

    def test_same_millisecond_event_uses_log_order_without_weakening_counters(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text, names = fixture(root)
            entries = text.splitlines()
            event_index = next(i for i, entry in enumerate(entries) if entry.startswith('[CART_NATURAL_HIT]') and '"kind": "event"' in entry and 'native-checkHitWall' in entry)
            event = entries.pop(event_index)
            sample_index = next(i for i, entry in enumerate(entries) if entry.startswith('[CART_NATURAL_SAMPLE] spec=natural-sprint-wall wall=82000 '))
            row = analyzer.fields(entries[sample_index].split('[CART_NATURAL_SAMPLE] ', 1)[1])
            row.update(naturalEvents=0, origin='none')
            entries[sample_index] = line('[CART_NATURAL_SAMPLE] ', row)
            entries.insert(sample_index+1, event)
            reordered = '\n'.join(entries)
            self.assertTrue(analyzer.analyze(root, reordered, names, require_natural=True)['naturalImpact']['functionalPass'])
            row.update(naturalEvents=1, origin='native-checkHitWall')
            entries[sample_index] = line('[CART_NATURAL_SAMPLE] ', row)
            bad = '\n'.join(entries)
            with self.assertRaises(AssertionError): analyzer.analyze(root, bad, names, require_natural=True)

    def test_watch_control_origin_is_required(self):
        self.check_rejected(lambda root, text: text.replace('"origin": "watch-control"', '"origin": "none"'))

    def test_legacy_default_does_not_claim_natural_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text, names = legacy.fixture(root)
            self.assertIsNone(analyzer.analyze(root, text, names)['naturalImpact'])
            with self.assertRaises(AssertionError): analyzer.analyze(root, text, names, require_natural=True)

    def test_fake_or_injected_native_provenance_fails(self):
        for defect in ('injected', 'missing native stack', 'injected stack', 'counter', 'missing SHA', 'wrong actor', 'wall type', 'direction'):
            with self.subTest(defect=defect):
                def transform(root, text):
                    if defect == 'injected': return text.replace('native-checkHitWall', 'injected-cartLabWallEvent')
                    if defect == 'missing native stack': return text.replace('zombie.iso.IsoMovingObject.checkHitWall', 'fake.checkHitWall')
                    if defect == 'injected stack': return text.replace('zombie.iso.IsoMovingObject.checkHitWall', 'zombie.iso.IsoMovingObject.checkHitWall;wooden_cart_motion.Main.wallEvent')
                    if defect == 'counter': return text.replace('naturalEvents=1', 'naturalEvents=0')
                    if defect == 'missing SHA': return text.replace('a'*64, 'unknown')
                    if defect == 'wrong actor': return text.replace('actor=true', 'actor=false')
                    if defect == 'wall type': return text.replace('"wallType": 4', '"wallType": 0')
                    return text.replace('"dir": "W"', '"dir": "E"')
                self.check_rejected(transform)

    def test_natural_event_and_complete_getup_are_mandatory(self):
        for defect in ('missing event', 'missing getup', 'missing collision', 'no idle', 'input continues', 'holding cart', 'no Run contact'):
            with self.subTest(defect=defect):
                def transform(root, text):
                    if defect == 'missing event': return '\n'.join(l for l in text.splitlines() if not (l.startswith('[CART_NATURAL_HIT]') and '"kind": "event"' in l and 'native-checkHitWall' in l))
                    if defect == 'missing getup': return mutate_samples(text, '[CART_NATURAL_SAMPLE] ', lambda r: r.update(state='PlayerMovementState') if r['state'] == 'PlayerGetUpState' else None)
                    if defect == 'missing collision': return mutate_samples(text, '[CART_NATURAL_SAMPLE] ', lambda r: r.update(state='PlayerMovementState') if r['state'] == 'CollideWithWallState' else None)
                    if defect == 'no idle': return mutate_samples(text, '[CART_NATURAL_SAMPLE] ', lambda r: r.update(action='walk') if float(r['elapsed']) >= 7000 else None)
                    if defect == 'input continues': return text.replace('INPUT_STOP spec=natural-sprint-wall wall=82000 elapsed=2000', 'INPUT_STOP spec=natural-sprint-wall wall=84000 elapsed=4000')
                    if defect == 'holding cart': return mutate_samples(text, '[CART_NATURAL_SAMPLE] ', lambda r: r.update(primary=1))
                    return mutate_samples(text, '[CART_NATURAL_SAMPLE] ', lambda r: r.update(collidedW=False) if r['spec'] == 'natural-run-wall' else None)
                self.check_rejected(transform)

    def test_bounded_state_and_actual_render_coverage_are_mandatory(self):
        for defect in ('sample gap', 'reordered sample', 'short window', 'missing impact clip', 'missing getup clip', 'render gap', 'invalid bones'):
            with self.subTest(defect=defect):
                def transform(root, text):
                    if defect == 'sample gap': return '\n'.join(l for l in text.splitlines() if not (l.startswith('[CART_NATURAL_SAMPLE]') and 'spec=natural-sprint-wall' in l and 2000 <= float(analyzer.fields(l)['elapsed']) < 2500))
                    if defect == 'reordered sample':
                        lines = text.splitlines()
                        indices = [i for i, l in enumerate(lines) if l.startswith('[CART_NATURAL_SAMPLE]')]
                        lines[indices[0]], lines[indices[1]] = lines[indices[1]], lines[indices[0]]
                        return '\n'.join(lines)
                    if defect == 'short window': return '\n'.join(l for l in text.splitlines() if not (l.startswith('[CART_NATURAL_SAMPLE]') and float(analyzer.fields(l)['elapsed']) >= 7500))
                    file = root/'action-tail-poses.jsonl'
                    rows = [json.loads(l) for l in file.read_text().splitlines()]
                    if defect == 'render gap': rows = [r for r in rows if not 82100 <= r['wallTimeMillis'] < 82600]
                    elif defect == 'invalid bones': rows[0]['bones'] = {}
                    else:
                        clip = 'Bob_SprintIntoWall' if defect == 'missing impact clip' else 'Bob_GetUp_Back'
                        for r in rows:
                            if r['wallTimeMillis'] < legacy.START:
                                for track in r['tracks']:
                                    if track['name'] == clip: track['name'] = 'Bob_Idle'
                    legacy.write_json(root, file.name, rows)
                    return text
                self.check_rejected(transform)

    def test_guarded_cart_unexpected_natural_event_fails(self):
        def transform(root, text):
            row = state(2000, held=True)
            row.update(timeMs=legacy.START+2000, sprint=True)
            event = receipt(row, kind='event', event='collideWithWall', layer='none', stack='zombie.iso.IsoMovingObject.checkHitWall')
            return text.replace('[CART_NATURAL_CART] case=female-full-sprint-wall wall=102000', event+'\n[CART_NATURAL_CART] case=female-full-sprint-wall wall=102000')
        self.check_rejected(transform, 'female-full-sprint-wall')

    def test_guarded_cart_requires_safe_frontal_contact(self):
        for key, value in (('clear', False), ('recovering', True), ('collidedW', True), ('footprint', 'inactive')):
            with self.subTest(key=key):
                def transform(root, text):
                    return mutate_samples(text, '[CART_NATURAL_CART] ', lambda r: r.update({key: value}) if 5000 <= float(r['elapsed']) < 5800 else None)
                self.check_rejected(transform, 'female-full-sprint-wall')

    def test_guarded_cart_requires_stationary_contact_brace_even_when_clear(self):
        def transform(root, text):
            return mutate_samples(text, '[CART_IMPACT_SAMPLE] ', lambda r: r.update(brace=0) if 5000 <= float(r['elapsed']) < 5800 else None)
        self.check_rejected(transform, 'female-full-sprint-wall', 'Missing hard-contact stance')

    def test_cart_release_cannot_be_relabelled_natural(self):
        self.check_rejected(lambda root, text: text.replace('injected-cartLabWallEvent', 'native-checkHitWall'))


if __name__ == '__main__': unittest.main()
