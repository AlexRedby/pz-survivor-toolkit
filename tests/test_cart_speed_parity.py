import importlib.util
import json
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-speed-parity.py'
spec = importlib.util.spec_from_file_location('cart_speed_parity', SCRIPT)
speed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(speed)


def capture(names=None, variant='wooden-wheelbarrow', candidate_ratio=1, demote=False):
    names = names or ['male-empty-left-mild']
    output = ['[WOOD_BANK] RUN_STARTED 100000']
    now, frame = 100000, 0
    for name in names:
        female, full = name.startswith('female-'), '-full-' in name
        injury = name.split('-', 2)[2]
        output.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={now}')
        def emit(tag, row):
            output.append('[CART_SPEED] '+tag+' '+json.dumps(dict(case=name, **row)))
        scene_wall = now
        emit('SCENE', dict(wall=now, cartType=speed.TYPES[variant], targetWeight=8, targetMax=12, fullBankCount=20, statsControl='neutral-each-tick'))
        for trial in range(1, 7):
            mode, gait = ('bare' if trial % 2 else 'cart'), (trial-1)//2
            start, x = now, 0
            emit('TRIAL', dict(trial=trial, mode=mode, gait=gait, mono=now, wall=now, heading=-3*math.pi/4))
            actual = 1 if demote and gait == 2 else gait
            for phase_index, (phase, duration, drive) in enumerate(speed.PHASES):
                begin = now
                emit('PHASE', dict(trial=trial, phase=phase, mono=begin, elapsed=begin-start, drive=drive, gait=gait if drive else 0))
                for offset in range(0 if phase_index == 0 else 50, duration+1, 50):
                    timestamp = begin+offset
                    if drive:
                        x += .05*(1+actual)*(candidate_ratio if mode == 'cart' else 1)
                    wounds = dict(leftScratch=0, rightScratch=0, leftFracture=0, rightFracture=0)
                    scalar = 0
                    if injury != 'healthy':
                        side, severity = injury.split('-')
                        wounds[side+('Scratch' if severity == 'mild' else 'Fracture')] = 8 if severity == 'mild' else 35
                        scalar = .3 if side == 'left' else -.3
                    row = dict(trial=trial, mode=mode, gait=gait, phase=phase, mono=timestamp, wall=timestamp,
                               elapsed=timestamp-start, phaseElapsed=offset, frame=frame,
                               x=x*math.cos(-3*math.pi/4), y=x*math.sin(-3*math.pi/4), z=7, heading=-3*math.pi/4,
                               run=bool(drive and actual == 1), sprint=bool(drive and actual == 2), drive=drive,
                               runKey=bool(drive and gait == 1), sprintKey=bool(drive and gait == 2),
                               cartType=speed.TYPES[variant], cartID=50, cargoID=51 if full else -1, cargoWeight=25 if full else 0,
                               cartRunSpeedModifier=1, nativeRunSpeedModifier=1, nativeWeapon='barehand' if mode == 'bare' else 'twohanded', heldModels='none|none' if mode == 'bare' else 'Cart|none',
                               primaryID=50 if mode == 'cart' else -1, secondaryID=50 if mode == 'cart' else -1,
                               cartCount=1 if mode == 'cart' else 0, ballastID=52 if mode == 'bare' else -1,
                               ballastWeight=5 if mode == 'bare' else 0, inventoryWeight=8, capacityWeight=8,
                               maxWeight=12, targetWeight=8, targetMax=12, female=female, full=full, wornCount=3,
                               outfitIDs='10,11,12', skill=10, walkSpeed=.8, runSpeed=.9, injury=scalar, slowFactor=0, thermalMovement=1,
                               endurance=1, fatigue=0, pain=0, panic=0, hunger=0, thirst=0, stress=0,
                               heavyLoad=0, enduranceMoodle=0, painMoodle=0,
                               motion=mode == 'cart', steering=mode == 'cart', tracks='Bob_Walk=1@1;',
                               statsControl='neutral-each-tick', **wounds)
                    emit('SAMPLE', row);frame += 1
                now += duration
                emit('PHASE_END', dict(trial=trial, phase=phase, mono=now, elapsed=duration))
            emit('TRIAL_END', dict(trial=trial, mono=now, wall=now))
            now += 10
        emit('SCENE_END', dict(mono=now-10, wall=now-10))
        output.append(f'[WOOD_BANK] COMPLETE {name} wall={scene_wall}')
    output.append(f'[WOOD_BANK] ALL_COMPLETE cases={len(names)}')
    return '\n'.join(output)


def mutate(log, change, tag='SAMPLE'):
    lines = []
    for line in log.splitlines():
        prefix = '[CART_SPEED] '+tag+' '
        if line.startswith(prefix):
            row = json.loads(line[len(prefix):]);change(row)
            line = prefix+json.dumps(row)
        lines.append(line)
    return '\n'.join(lines)


class SpeedParityTests(unittest.TestCase):
    def setUp(self):
        self.names = ['male-empty-left-mild']
        self.log = capture(self.names)

    def analyze(self, log=None):
        return speed.analyze(self.log if log is None else log, self.names)

    def test_native_pairs_accept_all_variants_sexes_loads_and_real_injuries(self):
        for variant in speed.TYPES:
            names = speed.scene_names()
            report = speed.analyze(capture(names, variant), names, variant)
            self.assertTrue(report['speedParityVerified'], report['failures'])
            self.assertFalse(report['partialCoverage'])
            self.assertEqual(report['fullBankCount'], 20)
            self.assertEqual(len(report['scenes']), 20)
            self.assertFalse(report['animationEquivalencePass'])

    def test_fixed_three_percent_oracle_measures_cruise_separately(self):
        report = self.analyze(capture(self.names, candidate_ratio=1.04))
        self.assertFalse(report['speedParityVerified'])
        self.assertEqual(report['tolerance'], .03)
        pair = report['scenes'][0]['pairs'][0]
        self.assertAlmostEqual(pair['cartToBareRatio'], 1.04)
        self.assertIn('braking', report['scenes'][0]['trials'][0])
        self.assertIn('acceleration', report['scenes'][0]['trials'][0])

    def test_matching_injured_demotion_is_explicit(self):
        report = self.analyze(capture(self.names, demote=True))
        self.assertTrue(report['speedParityVerified'], report['failures'])
        self.assertEqual(report['scenes'][0]['pairs'][2]['actualGait'], 'run')
        self.assertTrue(report['scenes'][0]['pairs'][2]['demoted'])

    def test_mismatched_actual_native_gait_fails(self):
        log = mutate(self.log, lambda r: r.update(sprint=False, run=True) if r['mode']=='cart' and r['gait']==2 and r['drive'] else None)
        self.assertFalse(self.analyze(log)['speedParityVerified'])

    def test_healthy_demotion_fails(self):
        names = ['female-full-healthy']
        self.assertFalse(speed.analyze(capture(names, demote=True), names)['speedParityVerified'])

    def test_bare_cart_ballast_weight_maximum_and_stats_corruption_rejected(self):
        changes = [dict(cartCount=1), dict(primaryID=50), dict(inventoryWeight=9), dict(capacityWeight=0),
                   dict(maxWeight=13), dict(ballastID=-1), dict(pain=.01), dict(endurance=.99),
                   dict(statsControl='uncontrolled'), dict(cartType='Base.Log')]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.analyze(mutate(self.log, lambda r: r.update(change) if r['mode']=='bare' else None))

    def test_native_moodles_walkspeed_or_slowfactor_mismatch_fails(self):
        for key, value in [('heavyLoad', 1), ('enduranceMoodle', 1), ('painMoodle', 1), ('walkSpeed', .75), ('slowFactor', .1), ('thermalMovement', .9)]:
            with self.subTest(key=key):
                log = mutate(self.log, lambda r: r.update({key:value}) if r['mode']=='cart' else None)
                self.assertFalse(self.analyze(log)['speedParityVerified'])

    def test_controller_isolation_injury_and_tracks_corruption_rejected(self):
        for change in [dict(motion=True), dict(steering=True), dict(injury=-.3), dict(leftScratch=0), dict(tracks='Bob_Walk=nan@1;'), dict(nativeWeapon='cart'), dict(heldModels='Cart|none')]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.analyze(mutate(self.log, lambda r: r.update(change) if r['mode']=='bare' and r['phase']=='cruise' else None))

    def test_bare_native_oracle_rejects_even_slow_positive_weight_cart_tracks(self):
        for name in ('ToolkitCartWalk', 'Toolkit_WoodCart_Stop', 'Bob_Cart_Walk'):
            for rate in (0, .01, 1):
                log = mutate(self.log, lambda r: r.update(tracks='Bob_Walk=1@1;'+name+'='+str(rate)+'@0.000001;') if r['mode']=='bare' and r['phase']=='cruise' else None)
                with self.subTest(name=name, rate=rate), self.assertRaisesRegex(ValueError, 'native speed tracks'):
                    self.analyze(log)
        self.assertEqual(speed.TOLERANCE, .03)

    def test_missing_script_modifier_names_the_unavailable_native_field(self):
        log = mutate(self.log, lambda r: r.pop('cartRunSpeedModifier'))
        with self.assertRaisesRegex(ValueError, 'Missing speed telemetry fields: cartRunSpeedModifier'):
            self.analyze(log)

    def test_missing_samples_nonfinite_values_and_duplicate_phases_rejected(self):
        # Remove a whole interval, not one replaceable cadence sample.
        shortened = '\n'.join(line for line in self.log.splitlines() if not ('[CART_SPEED] SAMPLE' in line and '"phase": "cruise"' in line and 2000 <= json.loads(line.split(' SAMPLE ',1)[1])['phaseElapsed'] <= 2500))
        with self.assertRaisesRegex(ValueError, 'temporal'):
            self.analyze(shortened)
        with self.assertRaises(ValueError):
            self.analyze(mutate(self.log, lambda r: r.update(x=float('nan'))))
        phase = next(line for line in self.log.splitlines() if '[CART_SPEED] PHASE ' in line)
        with self.assertRaisesRegex(ValueError, 'phases'):
            self.analyze(self.log+'\n'+phase)

    def test_fixture_never_drives_baseline_with_production_motion_helpers(self):
        source = (SCRIPT.parent/'scenario-speed-parity.lua').read_text()
        self.assertIn('p:getInventoryWeight()', source)
        self.assertIn('cartLabNativePoseHeading', source)
        self.assertIn('p:updateHandEquips()', source)
        self.assertIn('cartLabScriptRunSpeedModifier(cart)', source)
        self.assertNotIn('getScriptItem().runSpeedModifier', source)
        self.assertNotIn('cartLabPoseHeading(', source)
        self.assertNotIn('CartSteeringHooks', source)
        self.assertNotRegex(source, r'setVariable\([\'"](?:WalkSpeed|RunSpeed|WalkInjury)')
        self.assertNotIn(':setRunning(', source)
        self.assertNotIn(':setSprinting(', source)
        tick = source.split('local function tick()',1)[1].split('WoodPrototypeTick=',1)[0]
        self.assertNotIn(':setX(', tick)


if __name__ == '__main__':
    unittest.main()
