"""Native collision release requires exact ownership and phase-aware render evidence."""
import csv
import importlib.util
import json
import math
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-impact.py'
spec = importlib.util.spec_from_file_location('cart_impact', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)
START = 100000
MATRIX = [1., 0, 0, 0, 0, 1., 0, 0, 0, 0, 1., 0, 0, 0, 0, 1.]


def sample_line(row):
    return '[CART_IMPACT_SAMPLE] '+' '.join(f'{k}={str(v).lower() if isinstance(v, bool) else v}' for k, v in row.items())


def samples(text, mutate):
    lines = []
    for line in text.splitlines():
        if '[CART_IMPACT_SAMPLE] ' in line:
            row = analyzer.fields(line.split('[CART_IMPACT_SAMPLE] ', 1)[1])
            mutate(row)
            line = sample_line(row)
        lines.append(line)
    return '\n'.join(lines)


def write_json(root, filename, rows):
    (root/filename).write_text(''.join(json.dumps(r)+'\n' for r in rows))


def fixture(root, name='male-empty-native-impact'):
    guarded = name.endswith('sprint-wall')
    full = '-full-' in name
    lines = ['[WOOD_BANK] RUN_STARTED', f'[WOOD_BANK] CASE {name} attempt=0 wall={START}']
    if guarded:
        lines.append(f'[CART_COLLISION_LAYOUT] case={name} wallX=4')
    else:
        lines.append(f'[CART_IMPACT_EVENT] case={name} wall={START+2000} elapsed=2000 source=native-action-event')
        lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed=2000 gait=0 drive=0')
    poses, grips, world, wheels = [], [], [], []
    for t in range(0, 12000, 40):
        state = 'CollideWithWallState' if not guarded and 2080 <= t < 2720 else 'PlayerGetUpState' if not guarded and 2720 <= t < 3520 else 'PlayerMovementState'
        protected = state in analyzer.PROTECTED
        held = guarded or t < 2080
        quiet = guarded and 4000 <= t < 6000
        walking = 7000 <= t < 9500
        sprint = not protected and (guarded or 1000 <= t <= 2000)
        x = 10-4.3*max(0, min(1, (t-1000)/3000)) if guarded else 10
        x += max(0, min(t, 9500)-7000)/2000
        row = dict(case=name, wall=START+t, elapsed=t, x=x, y=20,
                   state=state, action='collide' if state == 'CollideWithWallState' else 'getup' if protected else 'sprint' if sprint else 'walk' if walking else 'idle',
                   run=False, sprint=sprint, enabled=held, steering=held,
                   hit=False, knocked=False, getup=state == 'PlayerGetUpState', ragdoll=False, ignore=protected,
                   pivot=held, brake=False, stepX=0, stepY=1 if held and not quiet else 0,
                   pace=1 if held and not quiet else 0, brace=1 if quiet else 0,
                   id=1, primary=1 if held else -1, secondary=1 if held else -1,
                   cargo=2 if full else 0, cargoIds='101,102' if full else 'empty', itemPhase=.5,
                   inventoryCount=int(held), inInventory=held, worldExact=not held,
                   worldCount=int(not held), woodCount=int(not held), worldId=-1 if held else 1,
                   worldPersistent=not held, worldX=0 if held else 10.5, worldY=0 if held else 20,
                   worldZ=0 if held else 7, rotation=0)
        lines.append(sample_line(row))
        poses.append(dict(wallTimeMillis=START+t, bones={key: MATRIX[:] for key in analyzer.BONEMAP},
                          tracks=[dict(name='Bob_SprintIntoWall' if state == 'CollideWithWallState' else 'Bob_Idle', weight=1)],
                          cartModel=held, cartModelCount=int(held)))
        grips.append(dict(wallTimeMillis=START+t, result=held, threw=False))
        if held:
            wheels.append(dict(event='draw', wallTimeMillis=START+t, phase=.5, wheelX=1, wheelY=2, wheelZ=7, contactZ=7))
        else:
            world.append(dict(wallTimeMillis=START+t, itemId=1, renderStatus='Ready', matrixOrder='column-major',
                              x=10.5, y=20, z=7, angle=[0, 0, 0], transform=MATRIX[:], alpha=1))
    lines += [f'[WOOD_BANK] COMPLETE {name} wall={START}', '[WOOD_BANK] ALL_COMPLETE cases=1']
    write_json(root, 'action-tail-poses.jsonl', poses)
    write_json(root, 'wood-grip-poses.jsonl', grips)
    write_json(root, 'world-cart-poses.jsonl', world)
    with (root/'wood-wheel-native.csv').open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=['event', 'wallTimeMillis', 'phase', 'wheelX', 'wheelY', 'wheelZ', 'contactZ'])
        writer.writeheader()
        writer.writerows(wheels)
    return '\n'.join(lines), [name]


def actual_draw_fixture(root):
    def cart(angle):
        c, s, scale = math.cos(angle), math.sin(angle), 76.5
        matrix = [scale, 0, 0, 0, 0, scale*c, scale*s, 0, 0, -scale*s, scale*c, 0, 0, 0, 0, 1.]
        axle = analyzer.CART_POINTS['axle']
        transformed = analyzer.matrix_point(matrix, axle)
        for i in range(3): matrix[12+i] = scale*axle[i]-transformed[i]
        return matrix
    first = START+2080
    rows = [dict(source='held', wall=first-20, itemId=-1, x=10.5, y=20, angle=math.pi, phase=0, cart=cart(.18))]
    for t in range(0, 401, 20):
        u = min(t/240, 1)
        smooth = u*u*u*(10+u*(-15+6*u))
        rows.append(dict(source='world', wall=first+t, itemId=1, x=10.5, y=20, angle=math.pi,
                         phase=0, cart=cart(.18*(1-smooth))))
    write_json(root, 'wheel-roll-draws.jsonl', rows)
    return rows


def recoil_motion(text, forward=0, rebound=.6):
    def move(row):
        t = float(row['elapsed'])
        if t < 2080:
            return
        if t <= 2280:
            delta = -forward*(t-2080)/200
        else:
            delta = -forward+rebound*min(1, (t-2280)/400)
        row['x'] = float(row['x'])+delta
    return samples(text, move)


class ImpactTests(unittest.TestCase):
    def test_strict_recoil_is_optional_and_accepts_bounded_native_recovery(self):
        for sex in ('male', 'female'):
            for load in ('empty', 'full'):
                with self.subTest(sex=sex, load=load), tempfile.TemporaryDirectory() as path:
                    root = Path(path)
                    text, names = fixture(root, f'{sex}-{load}-native-impact')
                    self.assertIsNone(analyzer.analyze(root, text, names)['cases'][0]['emergencyRecoil'])
                    with self.assertRaisesRegex(AssertionError, 'backward rebound .* below .5'):
                        analyzer.analyze(root, text, names, require_recoil=True)
                    actual_draw_fixture(root)
                    report = analyzer.analyze(root, recoil_motion(text), names, require_settle=True, require_recoil=True)
                    measured = report['cases'][0]['emergencyRecoil']
                    self.assertEqual(measured['firstDroppedWall'], START+2080)
                    self.assertEqual(measured['lastCollisionWall'], START+2680)
                    self.assertEqual(measured['firstGetupWall'], START+2720)
                    self.assertEqual(measured['forwardIntrusionTiles'], 0)
                    self.assertAlmostEqual(measured['backwardReboundTiles'], .6)
                    self.assertIn('no body/pose visual pass', measured['scope'])

    def test_recoil_rejects_archived_native07_forward_intrusion(self):
        # Native07 first exact-drop -> minimum X, recorded in baseline-motion.json.
        for name, intrusion in [('male-full-native-impact', .365234375),
                                ('female-empty-native-impact', .5078125)]:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root, name)
                text = recoil_motion(text, forward=intrusion)
                # Existing ownership, render and recovery gates accepted this old motion.
                self.assertTrue(analyzer.analyze(root, text, names)['functionalPass'])
                with self.assertRaisesRegex(AssertionError, 'forward intrusion .* exceeds .02'):
                    analyzer.analyze(root, text, names, require_recoil=True)

    def test_recoil_bounds_exclude_getup_and_later_intentional_walk(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            text, names = fixture(root)
            # A frozen/reduced rebound cannot borrow the later successful recovery walk.
            for amount in (0, .49):
                with self.subTest(rebound=amount), self.assertRaisesRegex(AssertionError, 'backward rebound .* below .5'):
                    analyzer.analyze(root, recoil_motion(text, rebound=amount), names, require_recoil=True)
            def getup_only(row):
                if float(row['elapsed']) >= 2720:
                    row['x'] = float(row['x'])+.6
            with self.assertRaisesRegex(AssertionError, 'backward rebound .* below .5'):
                analyzer.analyze(root, samples(text, getup_only), names, require_recoil=True)
            # The documented thresholds admit small coordinate jitter and native rebound.
            self.assertTrue(analyzer.analyze(root, recoil_motion(text, forward=.02, rebound=.5), names,
                                            require_recoil=True)['functionalPass'])
            with self.assertRaisesRegex(AssertionError, 'forward intrusion .* exceeds .02'):
                analyzer.analyze(root, recoil_motion(text, forward=.021), names, require_recoil=True)

    def test_strict_actual_draw_settle_is_optional_and_accepts_smooth_receipts(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            text, names = fixture(root)
            self.assertTrue(analyzer.analyze(root, text, names)['functionalPass'])
            with self.assertRaisesRegex(AssertionError, 'Missing actual split draw receipts'):
                analyzer.analyze(root, text, names, require_settle=True)
            actual_draw_fixture(root)
            measured = analyzer.analyze(root, text, names, require_settle=True)['cases'][0]['actualDrawSettle']
            self.assertEqual(measured['handoffGapMs'], 20)
            self.assertLess(measured['maxHandleStepTilesPerSecond'], 2)
            self.assertGreater(measured['middleHandleDistanceToEndpointXY'], .02)
            self.assertLess(measured['axleDriftXY'], .00001)

    def test_actual_draw_settle_rejects_native03_one_frame_flip_and_other_defects(self):
        for defect, message in [('native03 flip', 'handle step exceeds'), ('wrong item', 'Foreign actual'),
                                ('stale held', 'Missing recent actual held'), ('handoff jump', 'point jump exceeds'),
                                ('axle drift', 'axle drift exceeds'), ('too few timestamps', 'Insufficient actual'),
                                ('early completion', 'completed before'), ('missing middle', 'draw at 80..120'),
                                ('missing endpoint', 'endpoint after 300'), ('nonfinite', 'Invalid actual draw pose')]:
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root)
                rows = actual_draw_fixture(root)
                first, ground = rows[1]['wall'], rows[-1]['cart'][:]
                if defect == 'native03 flip':
                    # Observed native03 shape: held-matching first draw, ground on the next draw 9ms later.
                    for row in rows[2:]: row['cart'] = ground[:]
                    rows[2]['wall'] = first+9
                elif defect == 'wrong item': rows[2]['itemId'] = 2
                elif defect == 'stale held': rows[0]['wall'] = first-151
                elif defect == 'handoff jump': rows[0]['x'] += .04
                elif defect == 'axle drift': rows[2]['x'] += .02
                elif defect == 'too few timestamps': rows = rows[:1]+[r for r in rows[1:] if r['wall']-first in (0, 100, 200, 320, 400)]
                elif defect == 'early completion':
                    # Small changes obey the speed limit but still finish well before the required mid-window.
                    source = rows[0]['cart']
                    for row in rows:
                        row['cart'] = [a+(b-a)*.01 for a, b in zip(ground, source)]
                elif defect == 'missing middle': rows = [r for r in rows if not 80 <= r['wall']-first <= 120]
                elif defect == 'missing endpoint': rows = [r for r in rows if r['wall']-first <= 300]
                else: rows[1]['cart'][0] = float('nan')
                write_json(root, 'wheel-roll-draws.jsonl', rows)
                with self.assertRaisesRegex(AssertionError, message):
                    analyzer.analyze(root, text, names, require_settle=True)

    def test_mesh_points_compose_native_euler_before_world_projection(self):
        row = dict(x=10, y=20, z=7, angle=[90, 90, 90], transform=MATRIX[:])
        for name, point in analyzer.CART_POINTS.items():
            expected = [10+1.5*point[2], 20-1.5*point[0], 7-(1.5/2.44949)*point[1]]
            for actual, value in zip(analyzer.world_cart_points(row)[name], expected):
                self.assertAlmostEqual(actual, value)

    def test_early_cart_only_settle_preserves_all_static_world_anchors(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            text, names = fixture(root)
            rows = [json.loads(line) for line in (root/'world-cart-poses.jsonl').read_text().splitlines()]
            drop = rows[0]['wallTimeMillis']
            for row in rows:
                row['transform'][13] = .1*max(0, 1-(row['wallTimeMillis']-drop)/240)
            write_json(root, 'world-cart-poses.jsonl', rows)
            report = analyzer.analyze(root, text, names)
            settle = report['cases'][0]['emergencySettle']
            self.assertEqual(settle['staticFromWallTimeMillis'], drop+240)
            self.assertEqual(settle['trajectory'][-1]['wallTimeMillis'], drop+240)
            self.assertEqual(settle['trajectory'][0]['points'].keys(), analyzer.CART_POINTS.keys())
            self.assertGreater(settle['trajectory'][0]['points']['leftHandle'][2],
                               settle['trajectory'][-1]['points']['leftHandle'][2])
            self.assertIsNone(settle['lastHeld'])
            self.assertTrue(any('no held mesh' in s for s in settle['missingEvidence']))
            rows[0]['transform'][0] = float('nan')
            write_json(root, 'world-cart-poses.jsonl', rows)
            with self.assertRaisesRegex(AssertionError, 'Nonfinite world render pose'):
                analyzer.analyze(root, text, names)

    def test_composed_static_mesh_allows_euler_folding_but_rejects_late_change(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            text, names = fixture(root)
            rows = [json.loads(line) for line in (root/'world-cart-poses.jsonl').read_text().splitlines()]
            for i, row in enumerate(rows):
                if i % 2:
                    row['angle'] = [0, 0, 90]
                else:
                    # The same Rz(90) folded into the column-major root matrix.
                    row['transform'] = [0, 1., 0, 0, -1., 0, 0, 0, 0, 0, 1., 0, 0, 0, 0, 1.]
            write_json(root, 'world-cart-poses.jsonl', rows)
            self.assertTrue(analyzer.analyze(root, text, names)['functionalPass'])
            rows[7]['transform'][12] += .1
            write_json(root, 'world-cart-poses.jsonl', rows)
            with self.assertRaisesRegex(AssertionError, 'World cart mesh leapt'):
                analyzer.analyze(root, text, names)

    def test_handoff_diagnostics_report_measured_points_and_missing_source_fields(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            text, names = fixture(root)
            held = dict(wallTimeMillis=START+2040, slotX=10, slotY=20, slotAngle=analyzer.math.pi, cart=MATRIX[:])
            write_json(root, 'body-clearance.jsonl', [held])
            settle = analyzer.analyze(root, text, names)['cases'][0]['emergencySettle']
            self.assertEqual(settle['lastHeld']['gapToFirstWorldMs'], 40)
            for delta in settle['handoffDelta'].values():
                self.assertAlmostEqual(delta['xy'], .5)
                self.assertIsNone(delta['z'])
            self.assertTrue(any('slotZ absent' in s for s in settle['missingEvidence']))
            self.assertTrue(any('itemId absent' in s for s in settle['missingEvidence']))
            held.update(slotZ=7, itemId=1)
            write_json(root, 'body-clearance.jsonl', [held])
            settle = analyzer.analyze(root, text, names)['cases'][0]['emergencySettle']
            self.assertEqual(settle['missingEvidence'], [])
            self.assertTrue(all(abs(delta['z']) < 1e-10 for delta in settle['handoffDelta'].values()))

    def test_world_floor_uses_native_column_major_matrix_and_euler_order(self):
        row = dict(z=7, angle=[0, 0, 0], transform=MATRIX[:])
        row['transform'][13] = 10
        self.assertAlmostEqual(analyzer.world_wheel_floor(row), 7+(1.5/2.44949)*(10-.0041269097-.001062454))
        row.update(angle=[90, 0, 0], transform=MATRIX[:])
        self.assertAlmostEqual(analyzer.world_wheel_floor(row), 7+(1.5/2.44949)*(.0010569958-.001062454))
        row['angle'] = [0, 0, 90]
        self.assertAlmostEqual(analyzer.world_wheel_floor(row), 7+(1.5/2.44949)*(-6.642862e-6-.00024333253))

    def test_uncalibrated_floor_offset_remains_explicit_diagnostic(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            text, names = fixture(root)
            file = root/'world-cart-poses.jsonl'
            rows = [json.loads(line) for line in file.read_text().splitlines()]
            for row in rows: row['transform'][13] += 10
            write_json(root, file.name, rows)
            report = analyzer.analyze(root, text, names)
            self.assertGreater(report['cases'][0]['worldWheelFloorMaxOffset'], 6)
            self.assertTrue(any('diagnostic until calibrated' in limit for limit in report['limits']))

    def test_complete_eight_case_lifecycles(self):
        for name in analyzer.CASES:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root, name)
                result = analyzer.analyze(root, text, names)
                self.assertTrue(result['functionalPass'])
                case = result['cases'][0]
                if name.endswith('native-impact'):
                    self.assertEqual(case['protectedStates'], ['CollideWithWallState', 'PlayerGetUpState'])
                    self.assertEqual(case['releaseLatencyMs'], 80)
                    self.assertGreater(case['worldRenderSamples'], 200)

    def test_guarded_wall_needs_contact_settle_and_exact_ownership(self):
        for defect in ('no contact', 'lateral motion', 'no brace', 'wheel motion', 'missing hand', 'world duplicate', 'inventory duplicate'):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root, 'male-empty-sprint-wall')
                def mutate(r):
                    t = int(r['elapsed'])
                    if defect == 'no contact': r['x'] = 10
                    elif defect == 'lateral motion': r['y'] = t/1000
                    elif defect == 'no brace': r['brace'] = 0
                    elif defect == 'wheel motion': r['itemPhase'] = t/1000
                    elif defect == 'missing hand': r['secondary'] = -1
                    elif defect == 'world duplicate': r['worldCount'] = 1
                    else: r['inventoryCount'] = 2
                with self.assertRaises(AssertionError):
                    analyzer.analyze(root, samples(text, mutate), names)

    def test_rejects_missing_or_unsafe_native_evidence(self):
        defects = ('retained controller', 'no getup', 'nan', 'wrong owner', 'cargo changed', 'cargo identity', 'inventory duplicate',
                   'no actual sprint', 'no recovery', 'no walk', 'early movement', 'continued sprint', 'missing phase samples',
                   'late release', 'missing release', 'duplicate world', 'cloned world', 'world lost', 'not persistent',
                   'world moved', 'reequipped', 'nonfinite world', 'wrong tracked id')
        for defect in defects:
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root, 'female-full-native-impact')
                def mutate(r):
                    t = int(r['elapsed'])
                    if defect == 'retained controller' and t == 2200: r['enabled'] = True
                    elif defect == 'no getup': r['state'] = r['state'].replace('PlayerGetUpState', 'PlayerMovementState')
                    elif defect == 'nan' and t == 0: r['itemPhase'] = 'nan'
                    elif defect == 'wrong owner' and t == 0: r['secondary'] = 2
                    elif defect == 'cargo changed' and t == 5000: r['cargo'] = 3
                    elif defect == 'cargo identity' and t == 5000: r['cargoIds'] = '101,103'
                    elif defect == 'inventory duplicate' and t == 0: r['inventoryCount'] = 2
                    elif defect == 'no actual sprint': r['sprint'] = False
                    elif defect == 'no recovery' and t > 3500: r['ignore'] = True
                    elif defect == 'no walk': r['x'] = 10
                    elif defect == 'early movement' and 4000 <= t < 6900: r['x'] = 10+(t-4000)/2000
                    elif defect == 'continued sprint' and t == 5000: r['sprint'] = True
                    elif defect in ('late release', 'missing release') and t >= 2080 and (t < 2400 or defect == 'missing release'):
                        r.update(primary=1, secondary=1, inventoryCount=1, inInventory=True, worldCount=0, woodCount=0,
                                 worldExact=False, worldId=-1, worldPersistent=False)
                    elif defect == 'duplicate world' and t == 6000: r['worldCount'] = 2
                    elif defect == 'cloned world' and t == 6000: r['woodCount'] = 2
                    elif defect == 'world lost' and t == 6000: r['worldExact'] = False
                    elif defect == 'not persistent' and t == 6000: r['worldPersistent'] = False
                    elif defect == 'world moved' and t == 6000: r['worldX'] = 11
                    elif defect == 'reequipped' and t == 6000: r.update(primary=1, secondary=1, inventoryCount=1, inInventory=True)
                    elif defect == 'nonfinite world' and t == 6000: r['worldZ'] = 'nan'
                    elif defect == 'wrong tracked id' and t == 6000: r['id'] = 2
                text = samples(text, mutate)
                if defect == 'missing phase samples': text = '\n'.join(line for line in text.splitlines() if 'state=CollideWithWallState' not in line)
                with self.assertRaises(AssertionError):
                    analyzer.analyze(root, text, names)

    def test_native_event_and_completed_window_are_mandatory(self):
        for defect in ('missing', 'wrong source', 'late', 'nonfinite', 'incomplete', 'missing input stop'):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root)
                if defect == 'missing': text = '\n'.join(l for l in text.splitlines() if '[CART_IMPACT_EVENT]' not in l)
                elif defect == 'wrong source': text = text.replace('source=native-action-event', 'source=physical-wall')
                elif defect == 'late': text = text.replace('wall=102000 elapsed=2000 source', 'wall=103000 elapsed=3000 source')
                elif defect == 'nonfinite': text = text.replace('wall=102000 elapsed=2000 source', 'wall=nan elapsed=2000 source')
                elif defect == 'missing input stop': text = text.replace('gait=0 drive=0', 'gait=2 drive=5')
                else: text = text.replace('ALL_COMPLETE cases=1', 'ALL_COMPLETE cases=0')
                with self.assertRaises(AssertionError): analyzer.analyze(root, text, names)

    def test_missing_render_files_and_empty_evidence_fail(self):
        for filename in ('action-tail-poses.jsonl', 'wood-grip-poses.jsonl', 'world-cart-poses.jsonl'):
            for missing in (False, True):
                with self.subTest(filename=filename, missing=missing), tempfile.TemporaryDirectory() as path:
                    root = Path(path)
                    text, names = fixture(root)
                    if missing: (root/filename).unlink()
                    else: (root/filename).write_text('')
                    with self.assertRaises(AssertionError): analyzer.analyze(root, text, names)

    def test_world_render_rejects_bad_rows_beside_good_rows(self):
        for defect in ('nonfinite matrix', 'nonfinite clock', 'nonfinite pose', 'short matrix', 'short angle', 'hidden', 'suppressed', 'alpha',
                       'wrong identity', 'motion', 'mesh jump', 'floating', 'gap', 'late', 'missing recovery phase'):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root)
                file = root/'world-cart-poses.jsonl'
                rows = [json.loads(line) for line in file.read_text().splitlines()]
                row = next(r for r in rows if r['wallTimeMillis'] == START+5000)
                if defect == 'nonfinite matrix': row['transform'][0] = float('nan')
                elif defect == 'nonfinite clock': row['wallTimeMillis'] = float('nan')
                elif defect == 'nonfinite pose': row['angle'][0] = float('inf')
                elif defect == 'short matrix': row['transform'] = MATRIX[:-1]
                elif defect == 'short angle': row['angle'] = []
                elif defect == 'hidden': row['transitionHidden'] = True
                elif defect == 'suppressed': row['renderStatus'] = 'Suppressed'
                elif defect == 'alpha': row['alpha'] = 0
                elif defect == 'wrong identity': row['itemId'] = 2
                elif defect == 'motion': row['x'] += 1
                elif defect == 'mesh jump': row['transform'][13] = 10
                elif defect == 'floating':
                    for r in rows: r['z'] += 1
                elif defect == 'gap': rows = [r for r in rows if not START+5000 <= r['wallTimeMillis'] < START+5600]
                elif defect == 'late': rows = rows[20:]
                else: rows = [r for r in rows if not START+2720 <= r['wallTimeMillis'] < START+3520]
                write_json(root, file.name, rows)
                with self.assertRaises(AssertionError): analyzer.analyze(root, text, names)

    def test_tail_and_grip_reject_invalid_and_post_release_application(self):
        for defect in ('grip', 'grip exception', 'post-release grip', 'bones', 'tracks', 'held model', 'held count', 'tail gap', 'nan clock'):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root)
                file = root/('wood-grip-poses.jsonl' if 'grip' in defect else 'action-tail-poses.jsonl')
                rows = [json.loads(line) for line in file.read_text().splitlines()]
                row = next(r for r in rows if r['wallTimeMillis'] == START+(5000 if defect in ('post-release grip', 'held model', 'held count') else 1000))
                if defect == 'grip': row['result'] = False
                elif defect == 'grip exception': row['threw'] = True
                elif defect == 'post-release grip': row['result'] = True
                elif defect == 'bones': row['bones'] = {}
                elif defect == 'tracks': row['tracks'][0]['weight'] = float('nan')
                elif defect == 'held model': row['cartModel'] = True
                elif defect == 'held count': row['cartModelCount'] = 1
                elif defect == 'nan clock': row['wallTimeMillis'] = float('nan')
                else: rows = [r for r in rows if not START+5000 <= r['wallTimeMillis'] < START+5600]
                write_json(root, file.name, rows)
                with self.assertRaises(AssertionError): analyzer.analyze(root, text, names)

    def test_split_wheel_requires_approach_and_forbids_post_release_draws(self):
        for defect in ('nan', 'gap', 'post-release', 'nan clock'):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as path:
                root = Path(path)
                text, names = fixture(root)
                file = root/'wood-wheel-native.csv'
                with file.open() as stream:
                    reader = csv.DictReader(stream)
                    keys = reader.fieldnames
                    rows = list(reader)
                if defect == 'nan': next(r for r in rows if r['wallTimeMillis'] == str(START+1000))['phase'] = 'NaN'
                elif defect == 'gap': rows = [r for r in rows if not START+1100 <= int(r['wallTimeMillis']) < START+1600]
                elif defect == 'post-release': rows.append(dict(rows[-1], wallTimeMillis=START+5000))
                else: rows[0]['wallTimeMillis'] = 'nan'
                with file.open('w') as stream:
                    writer = csv.DictWriter(stream, fieldnames=keys)
                    writer.writeheader()
                    writer.writerows(rows)
                with self.assertRaises(AssertionError): analyzer.analyze(root, text, names)


if __name__ == '__main__': unittest.main()
