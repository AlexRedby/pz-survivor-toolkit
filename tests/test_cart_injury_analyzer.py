"""Reject mislabeled/incomplete real-injury evidence without launching the game."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-injury.py'
spec = importlib.util.spec_from_file_location('cart_injury', SCRIPT)
injury = importlib.util.module_from_spec(spec)
spec.loader.exec_module(injury)
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import carts
try:
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None


def capture(names=None, variant='wooden-wheelbarrow', phase_delay=0):
    names = injury.scene_names() if names is None else names
    lines = ['[WOOD_BANK] RUN_STARTED']
    for index, name in enumerate(names):
        sex, load, side, severity = name.split('-')
        start = 100000 + index * 14000
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        x, heading = 0, 0
        duration = 12000 + (len(injury.PHASES) - 1) * phase_delay
        for i, (phase, planned, drive, gait) in enumerate(injury.PHASES):
            since = planned + i * phase_delay
            end = injury.PHASES[i + 1][1] + (i + 1) * phase_delay if i + 1 < len(injury.PHASES) else duration
            event = dict(case=name, phase=phase, wall=start + since, start=start, elapsed=since,
                         drive=drive, gait=gait, heal=phase == 'healed-forward')
            lines.append('[CART_INJURY] PHASE ' + json.dumps(event))
            for t in range(since, end, 100):
                healed = phase.startswith('healed-')
                if drive:
                    if phase == 'reverse':
                        x += .005 if t - since < 200 else 0 if t - since < 400 else -.02
                    else:
                        x += .02
                if phase in ('left', 'right'):
                    heading += .01 if phase == 'left' else -.01
                row = dict(case=name, phase=phase, start=start, wall=start + t, elapsed=t,
                           cartType=injury.TYPES[variant], female=sex == 'female', full=load == 'full',
                           id=42 + index, primaryID=42 + index, secondaryID=42 + index,
                           cargoID=-1 if load == 'empty' else 142 + index, cargoWeight=0 if load == 'empty' else 30,
                           x=x, y=0, heading=heading, acceptedHeading=heading, injury=0 if healed else (1 if side == 'left' else -1) * (.4 if severity == 'mild' else 1),
                           walkSpeed=1, legPace=1, stepX=0,
                           stepY=(1 if t - since < 200 else 0 if t - since < 400 else -1) if phase == 'reverse' else 1,
                           leftScratch=0, rightScratch=0, leftFracture=0, rightFracture=0,
                           run=False, sprint=False, requestedGait=gait, drive=drive,
                           motion=True, pivot=False, brake=False,
                           tracks='Bob_Walk=1@1;' if healed else 'Bob_Walk' + ('Light' if severity == 'mild' else 'Heavy') + 'Limp' + ('R' if side == 'left' else 'L') + '=.8@1;')
                if not healed:
                    row[side + ('Scratch' if severity == 'mild' else 'Fracture')] = 8 if severity == 'mild' else 35
                if phase == 'reverse':
                    row['tracks'] = 'Bob_WalkBwdNoAim1Hand=.8@1;'
                lines.append('[CART_INJURY] SAMPLE ' + json.dumps(row))
        lines.append('[CART_INJURY] END ' + json.dumps(dict(case=name,start=start,wall=start+duration,elapsed=duration)))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/tmp/video-{index}.mp4 frames=360 seconds={duration / 1000:.3f}')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=' + str(len(names)))
    return '\n'.join(lines)


def mutate_samples(log, callback):
    lines = []
    for line in log.splitlines():
        if '[CART_INJURY] SAMPLE ' in line:
            row = json.loads(line.split('[CART_INJURY] SAMPLE ', 1)[1])
            callback(row)
            line = '[CART_INJURY] SAMPLE ' + json.dumps(row)
        lines.append(line)
    return '\n'.join(lines)


class CartInjuryAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.names = ['male-empty-left-mild']
        self.log = capture(self.names)

    def test_full_matrix_includes_both_sexes_loads_sides_and_severities_for_each_cart(self):
        self.assertEqual(carts.scene_names('injury'), injury.scene_names())
        self.assertEqual(carts.SP_CASES['injury'], ('scenario-injury.lua', 16))
        self.assertIn('injury', carts.METAL_SP_CASES)
        self.assertIn('injury', carts.SHOPPING_SP_CASES)
        for variant in injury.TYPES:
            report = injury.analyze(capture(variant=variant), variant=variant)
            self.assertTrue(report['injuryVerified'], report['failures'])
            self.assertEqual(len(report['scenes']), 16)
            self.assertFalse(report['geometryVerified'])
            self.assertFalse(report['animationEquivalencePass'])

    def test_gait_requests_report_native_flags_without_replacing_them(self):
        report = injury.analyze(self.log, self.names)
        phases = {r['phase']: r for r in report['scenes'][0]['phases']}
        self.assertEqual(phases['run-request']['requestedGait'], 1)
        self.assertEqual(phases['sprint-request']['requestedGait'], 2)
        self.assertFalse(phases['run-request']['actualRun'])
        self.assertFalse(phases['sprint-request']['actualSprint'])
        self.assertGreater(phases['reverse']['distanceTiles'], 0)

    def test_event_relative_phases_preserve_durations_and_report_actual_recording_end(self):
        report = injury.analyze(capture(self.names, phase_delay=100), self.names)
        self.assertTrue(report['injuryVerified'], report['failures'])
        self.assertEqual(report['scenes'][0]['recordElapsedMs'], 12800)
        self.assertEqual(report['scenes'][0]['endWall'] - report['scenes'][0]['startWall'], 12800)

    def test_shortened_or_caught_up_phase_is_rejected_even_with_complete_samples(self):
        for phase, delta in (('right', -200), ('sprint-request', -1300)):
            lines = []
            for line in capture(self.names, phase_delay=100).splitlines():
                if '[CART_INJURY] PHASE ' in line:
                    event = json.loads(line.split('[CART_INJURY] PHASE ', 1)[1])
                    if event['phase'] == phase:
                        event['wall'] += delta; event['elapsed'] += delta
                        line = '[CART_INJURY] PHASE ' + json.dumps(event)
                lines.append(line)
            with self.assertRaisesRegex(ValueError, 'phase receipt'):
                injury.analyze('\n'.join(lines), self.names)

    def test_recording_end_is_required_and_final_stop_keeps_full_duration(self):
        log = capture(self.names, phase_delay=100)
        with self.assertRaisesRegex(ValueError, 'recording ends'):
            injury.analyze('\n'.join(l for l in log.splitlines() if '[CART_INJURY] END ' not in l), self.names)
        lines = []
        for line in log.splitlines():
            if '[CART_INJURY] END ' in line:
                end = json.loads(line.split('[CART_INJURY] END ', 1)[1])
                end['wall'] -= 200; end['elapsed'] -= 200
                line = '[CART_INJURY] END ' + json.dumps(end)
            lines.append(line)
        with self.assertRaisesRegex(ValueError, 'final phase'):
            injury.analyze('\n'.join(lines), self.names)

    def test_event_relative_schedule_does_not_allow_independent_sample_gaps(self):
        lines = []
        for line in capture(self.names, phase_delay=100).splitlines():
            if '[CART_INJURY] SAMPLE ' in line:
                row = json.loads(line.split('[CART_INJURY] SAMPLE ', 1)[1])
                if 4500 <= row['elapsed'] < 5200:
                    continue
            lines.append(line)
        with self.assertRaisesRegex(ValueError, 'temporal'):
            injury.analyze('\n'.join(lines), self.names)

    def test_healing_transition_margin_excludes_first_stale_engine_sample(self):
        log = mutate_samples(self.log, lambda r: r.update(injury=.229,leftScratch=8,tracks='Bob_WalkLightLimpR=.8@1;')
                             if r['phase'] == 'healed-forward' and r['elapsed'] < 9350 else None)
        report = injury.analyze(log, self.names)
        self.assertTrue(report['injuryVerified'], report['failures'])

    def test_animation_variable_without_actual_bodydamage_does_not_pass(self):
        log = mutate_samples(self.log, lambda r: r.update(leftScratch=0))
        report = injury.analyze(log, self.names)
        self.assertFalse(report['injuryVerified'])
        self.assertTrue(any('wrong real injury' in row[2] for row in report['failures']))

    def test_wrong_side_and_missing_native_limp_are_rejected(self):
        for update in (dict(injury=-.4), dict(tracks='Bob_Walk=1@1;'), dict(tracks='Bob_WalkLightLimpR=0@1;')):
            log = mutate_samples(self.log, lambda r: r.update(update) if r['phase'] == 'forward' else None)
            self.assertFalse(injury.analyze(log, self.names)['injuryVerified'])

    def test_reverse_must_be_backward_relative_to_actor_heading(self):
        log = mutate_samples(self.log, lambda r: r.update(heading=3.141592653589793) if r['phase'] == 'reverse' else None)
        report = injury.analyze(log, self.names)
        self.assertFalse(report['injuryVerified'])
        self.assertTrue(any('backward' in row[2] for row in report['failures']))

    def test_reverse_accepts_current_authored_and_historical_native_directional_clips(self):
        for variant in injury.TYPES:
            for clip in ('Toolkit_CartPivot_Backward', 'Bob_WalkBwdNoAim1Hand'):
                with self.subTest(variant=variant, clip=clip):
                    log = mutate_samples(capture(self.names, variant),
                                         lambda r: r.update(tracks=clip + '=.8@1;') if r['phase'] == 'reverse' else None)
                    report = injury.analyze(log, self.names, variant)
                    self.assertTrue(report['injuryVerified'], report['failures'])
        for track in ('Toolkit_CartPivot_Backward=0@1;', 'Toolkit_CartPivot_Backward=.8@0;'):
            with self.subTest(track=track):
                log = mutate_samples(self.log, lambda r: r.update(tracks=track) if r['phase'] == 'reverse' else None)
                report = injury.analyze(log, self.names)
                self.assertFalse(report['injuryVerified'])
                self.assertTrue(any('backward clip' in row[2] for row in report['failures']))

    def test_reverse_retains_its_native_directional_clip(self):
        log = mutate_samples(self.log, lambda r: r.update(tracks='Bob_WalkLightLimpL=.8@1;') if r['phase'] == 'reverse' else None)
        report = injury.analyze(log, self.names)
        self.assertFalse(report['injuryVerified'])
        self.assertTrue(any('backward clip' in row[2] for row in report['failures']))

    def test_reversal_requires_actual_rest_and_sustained_backward_travel(self):
        report = injury.analyze(self.log, self.names)
        reverse = next(p for p in report['scenes'][0]['phases'] if p['phase'] == 'reverse')['reversal']
        self.assertTrue(reverse['restBeforeReverse'])
        self.assertEqual(reverse['reverseStartDelayMs'], 400)
        self.assertLess(reverse['forwardTravelTiles'], -.03)
        for update in (dict(stepY=-1), dict(stepY=0)):
            log = mutate_samples(self.log, lambda r: r.update(update) if r['phase'] == 'reverse' else None)
            self.assertFalse(injury.analyze(log, self.names)['injuryVerified'])
        log = mutate_samples(self.log, lambda r: r.update(x=-r['x']) if r['phase'] == 'reverse' and r['elapsed'] >= 4800 else None)
        self.assertFalse(injury.analyze(log, self.names)['injuryVerified'])

    def test_shopping_reverses_immediately_but_wheelbarrows_require_rest(self):
        for variant in ('shopping-cart', 'wooden-wheelbarrow', 'metal-wheelbarrow'):
            log = mutate_samples(capture(self.names, variant), lambda r: r.update(stepY=-1, x=100 - r['elapsed'] * .0002)
                                 if r['phase'] == 'reverse' else None)
            report = injury.analyze(log, self.names, variant)
            self.assertEqual(report['injuryVerified'], variant == 'shopping-cart', report['failures'])
            reverse = next(p for p in report['scenes'][0]['phases'] if p['phase'] == 'reverse')['reversal']
            self.assertFalse(reverse['restBeforeReverse'])
            self.assertEqual(reverse['restRequired'], variant != 'shopping-cart')
        shopping = mutate_samples(capture(self.names, 'shopping-cart'), lambda r: r.update(stepY=-1, x=100 + r['elapsed'] * .0002)
                                  if r['phase'] == 'reverse' else None)
        self.assertFalse(injury.analyze(shopping, self.names, 'shopping-cart')['injuryVerified'])

    def test_mild_low_speed_uses_native_heavy_component_with_small_arc_mass(self):
        # Native Pick projects (WalkInjury=.2285, WalkSpeed=.11) outside the hull
        # to HeavyLimpR=.186175. Directional arcs can scale that below .15.
        self.assertAlmostEqual(injury.walk_components(.2285, .11)['Bob_WalkHeavyLimpR'], .186175)
        def low_speed(row):
            if row['phase'] in ('forward', 'left', 'right', 'run-request', 'sprint-request'):
                row.update(injury=.2285, walkSpeed=.11, tracks='Bob_WalkHeavyLimpR=.8@.09;')
        log = mutate_samples(self.log, low_speed)
        self.assertTrue(injury.analyze(log, self.names)['injuryVerified'])
        wrong = mutate_samples(log, lambda r: r.update(tracks='Bob_WalkLightLimpR=.8@.09;') if r['phase'] == 'left' else None)
        self.assertFalse(injury.analyze(wrong, self.names)['injuryVerified'])
        wrong = mutate_samples(log, lambda r: r.update(tracks='Bob_WalkHeavyLimpL=.8@.09;') if r['phase'] == 'left' else None)
        self.assertFalse(injury.analyze(wrong, self.names)['injuryVerified'])

    def test_native_light_heavy_ratio_requires_both_injury_and_speed(self):
        self.assertEqual(injury.walk_components(.2285, .56)['Bob_WalkHeavyLimpR'], 0)
        self.assertAlmostEqual(injury.walk_components(.2285, .56)['Bob_WalkLightLimpR'], .457)
        expected = injury.walk_components(-.2285, .455)
        self.assertAlmostEqual(expected['Bob_WalkHeavyLimpL'], .002)
        row = dict(injury=-.2285, walkSpeed=.455, clips=injury.tracks('Bob_WalkLightLimpL=.8@.2265;Bob_WalkHeavyLimpL=.8@.001;'))
        self.assertTrue(injury._walk_mix(row))
        row['clips'] = injury.tracks('Bob_WalkLightLimpL=.8@.1;Bob_WalkHeavyLimpL=.8@.1;')
        self.assertFalse(injury._walk_mix(row))

    def test_host_walk_after_run_accepts_native_negative_speed_projection(self):
        # Recorded Host heavy injury: WalkSpeed remains native RunSpeed=-.1376667
        # during the return to Walk; Pick gives Heavy=.4742833, Slow=.5257167.
        expected = injury.walk_components(1, -.1376667)
        self.assertAlmostEqual(expected['Bob_WalkHeavyLimpR'], .474283315)
        row = dict(injury=1, walkSpeed=-.1376667,
                   clips=injury.tracks('Bob_WalkHeavyLimpR=.95@.47428334;Bob_WalkSlow=.95@.52571666;'))
        self.assertTrue(injury._walk_mix(row))
        self.assertEqual(injury.walk_components(.1, -.5)['Bob_WalkHeavyLimpR'], 0)

    def test_native_source_topology_is_read_and_reference_drift_rejected(self):
        node = injury.ET.parse(ROOT / 'PZSurvivorToolkit/42/media/AnimSets/player/movement/toolkit_cart_walk.xml').getroot()
        node.find('m_Name').text = 'defaultWalk'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'media/AnimSets/player/movement/defaultWalk.xml'
            path.parent.mkdir(parents=True)
            injury.ET.ElementTree(node).write(path)
            self.assertEqual(injury._walk_source(directory), str(path))
            blends = node.findall('m_2DBlends')
            blends[0].attrib['referenceID'], blends[1].attrib['referenceID'] = blends[1].attrib['referenceID'], blends[0].attrib['referenceID']
            injury.ET.ElementTree(node).write(path)
            with self.assertRaisesRegex(ValueError, 'topology'):
                injury._walk_source(directory)

    @unittest.skipUnless(LuaRuntime, 'Lupa required for fixture clothing lifecycle regression')
    def test_fixture_clothing_does_not_accumulate_or_remove_nonfixture_inventory(self):
        source = (SCRIPT.parent / 'scenario-injury.lua').read_text()
        helper = source.split('local function dress()\n', 1)[1].split('local function nextCase()\n', 1)[0]
        LuaRuntime().execute('''
local inventory={items={}}
function inventory:AddItem(name)
 local item={name=name,container=self,weight=1}
 function item:getContainer() return self.container end
 function item:getBodyLocation() return self.name end
 self.items[#self.items+1]=item
 return item
end
function inventory:Remove(item)
 for i,value in ipairs(self.items) do if value==item then table.remove(self.items,i);item.container=nil;return end end
 error('Removing foreign item')
end
local owned={inventory:AddItem('existing-clothes'),inventory:AddItem('cart'),inventory:AddItem('cargo')}
local p={worn={}}
function p:getInventory() return inventory end
function p:clearWornItems() self.worn={} end
function p:setWornItem(slot,item) self.worn[slot]=item end
local fixtureClothing={}
local function dress()
''' + helper + '''
for scene=1,16 do
 local previous=fixtureClothing
 dress()
 assert(#inventory.items==6,'Actor inventory gained clothing weight')
 for _,item in ipairs(previous) do assert(item.container==nil,'Old fixture garment retained') end
 for _,item in ipairs(owned) do assert(item.container==inventory,'Nonfixture identity removed') end
end
''')

    def test_healing_must_clear_real_injury_and_limp_tracks(self):
        for update in (dict(injury=-.4), dict(leftScratch=8), dict(tracks='Bob_WalkLightLimpL=.8@1;')):
            log = mutate_samples(self.log, lambda r: r.update(update) if r['phase'] == 'healed-forward' else None)
            self.assertFalse(injury.analyze(log, self.names)['injuryVerified'])

    def test_changed_cart_and_full_cargo_identity_are_rejected(self):
        for names, update in ((self.names, dict(primaryID=999)), (['female-full-right-heavy'], dict(cargoID=999))):
            log = mutate_samples(capture(names), lambda r: r.update(update) if r['phase'] == 'reverse' else None)
            with self.assertRaisesRegex(ValueError, 'ownership|cart/cargo'):
                injury.analyze(log, names)

    def test_missing_recording_phase_or_sample_window_is_rejected(self):
        for marker in ('[CART_INJURY] PHASE ', '[CART_INJURY] SAMPLE '):
            lines = [line for line in self.log.splitlines() if not (marker in line and '"phase": "right"' in line)]
            with self.assertRaisesRegex(ValueError, 'phase|temporal'):
                injury.analyze('\n'.join(lines), self.names)
        with self.assertRaisesRegex(ValueError, 'receipts'):
            injury.analyze(self.log.replace('[WOOD_BANK] COMPLETE male-empty-left-mild', '[WOOD_BANK] COMPLETE female-empty-left-mild'), self.names)

    def test_invalid_tracks_are_rejected_cleanly(self):
        for value in ('missing-weight', 'Bob_Walk=nan@1;', 'Bob_Walk=1@2;'):
            log = mutate_samples(self.log, lambda r: r.update(tracks=value))
            with self.assertRaisesRegex(ValueError, 'track'):
                injury.analyze(log, self.names)

    def test_render_probe_window_must_cover_both_edges_and_have_successful_grip(self):
        matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        records = [dict(wallTimeMillis=100000 + t, model='WheelbarrowWood', female=False,
                        cart=matrix, bones={'Bip01_L_Hand': matrix}, result=True, threw=False) for t in range(0, 12000, 100)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def write(body, grip):
                for name, rows in (('body-clearance.jsonl', body), ('wood-grip-poses.jsonl', grip)):
                    (root / name).write_text(''.join(json.dumps(r) + '\n' for r in rows))
            write(records, records)
            report = injury.analyze(self.log, self.names, profile=root)
            self.assertTrue(report['probeCoverageVerified'])
            broken = copy.deepcopy(records);broken[20]['result'] = False
            write(records, broken)
            with self.assertRaisesRegex(ValueError, 'grip solve'):
                injury.analyze(self.log, self.names, profile=root)
            write(records, records[:-10])
            with self.assertRaisesRegex(ValueError, 'temporal'):
                injury.analyze(self.log, self.names, profile=root)
            write(records, records)
            with self.assertRaisesRegex(ValueError, 'temporal'):
                injury.analyze(capture(self.names, phase_delay=100), self.names, profile=root)

    def test_fixture_changes_bodydamage_and_never_forces_walkinjury_or_gait_flags(self):
        source = (SCRIPT.parent / 'scenario-injury.lua').read_text()
        self.assertIn('p:setGodMod(false)', source)
        self.assertIn('toolkitCartInjurySupported(p)', source)
        self.assertIn('actorInventoryWeight=p:getInventory():getCapacityWeight()', source)
        self.assertIn('part:setScratchTime(8)', source)
        self.assertIn('part:setFractureTime(35)', source)
        self.assertIn('RestoreToFullHealth()', source)
        self.assertNotRegex(source, r'setVariable\([\'"]WalkInjury')
        self.assertNotIn(':setRunning(', source)
        self.assertNotIn(':setSprinting(', source)


if __name__ == '__main__':
    unittest.main()
