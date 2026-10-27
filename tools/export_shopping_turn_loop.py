#!/usr/bin/env python3
"""Extract the accepted upright shopping turn as detached, actor-local visual clips.

Generation requires the two turn-body studies and a native Bob_Idle.x template.
--check verifies committed sources and deterministic native bakes without studies.
The first sample carries provenance metadata; the array remains cart_clip_bake input.
No animation graph, deferred movement, installation or game process is changed.
"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

import cart_clip_bake as baker


ROOT = Path(__file__).resolve().parents[1]
FPS = 60
PERIOD = .8
FRAME_COUNT = 48
POSE_TOLERANCE = 1e-4
VELOCITY_TOLERANCE = .002
ROOT_BONES = ('Dummy01', 'Bip01', 'Translation_Data')
EXPECTED = {
    'schema': 'shopping-turn-study-v3', 'motion': 'turn-body',
    'turn_kind': 'rolling rear axle', 'rear_rolling_radius': .30,
    'degrees_per_step': 22.5, 'step_seconds': .40,
    'swing_height': .025, 'swing_window': [.05, .95],
    'landing_lookahead_steps': 1.55, 'pelvis_lowering_range': [.022, .050],
    'root_ramp_seconds': .24, 'weight_transfer_window': [.15, 1.0],
    'chest_peak_degrees': 10, 'playback_rate': 1,
}


def close(actual, expected):
    if isinstance(expected, list):
        return (isinstance(actual, list) and len(actual) == len(expected)
                and all(close(a, b) for a, b in zip(actual, expected)))
    if isinstance(expected, (float, int)):
        return (type(actual) in (float, int) and math.isfinite(actual)
                and abs(actual - expected) <= 1e-8)
    return actual == expected


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def max_matrix_difference(a, b):
    return max(abs(x - y) for name in a for x, y in zip(a[name], b[name]))


def derivative_error(rows, start, end):
    """Compare centered derivatives at repeated contacts, using outside source rows.

    Opposite one-sided differences differ naturally under nonzero acceleration;
    the same centered stencil at both ends measures periodic velocity instead.
    """
    dt = 2 / FPS
    return max(abs(((rows[start + 1]['bones'][name][axis]
                     - rows[start - 1]['bones'][name][axis])
                    - (rows[end + 1]['bones'][name][axis]
                       - rows[end - 1]['bones'][name][axis])) / dt)
               for name in rows[start]['bones'] for axis in range(16))


def validate_settings(settings, side):
    for name, expected in EXPECTED.items():
        require(close(settings.get(name), expected),
                f'{side}: unsupported study {name}: {settings.get(name)!r}')
    require(settings.get('direction') == side, f'{side}: study direction differs')
    require(settings.get('source_clip') == 'cart_pivot_idle.json',
            f'{side}: unsupported source pose')
    rear = settings.get('rear')
    require(isinstance(rear, list) and len(rear) == 3
            and all(type(v) in (float, int) and math.isfinite(v) for v in rear),
            f'{side}: invalid rear geometry')
    require(close(settings.get('pelvis_peak_degrees'),
                  math.degrees(math.atan2(rear[1], .30))),
            f'{side}: pelvis no longer follows the accepted independent turn')


def validate_samples(samples, parents, canonical):
    require(isinstance(samples, list) and len(samples) == FRAME_COUNT + 1,
            'expected 49 samples for a 60 Hz, .8 second loop')
    for index, row in enumerate(samples):
        require(isinstance(row, dict) and close(row.get('time'), index / FPS),
                f'sample {index}: invalid sample time')
        bones = row.get('bones')
        require(isinstance(bones, dict) and bones.keys() == parents.keys(),
                f'sample {index}: expected native Bob skeleton')
        for name, matrix in bones.items():
            baker.validate_matrix(matrix, f'sample {index}/{name}')
        for name in ROOT_BONES:
            require(max(abs(a - b) for a, b in zip(bones[name], canonical[name])) < 1e-6,
                    f'sample {index}/{name}: world motion or noncanonical root')
    require(max_matrix_difference(samples[0]['bones'], samples[-1]['bones']) == 0,
            'exported loop must close exactly')


def extract(study, side, parents, canonical):
    require(study.is_dir(), f'{side}: study directory missing: {study}')
    settings = json.loads((study / 'study.json').read_text())
    validate_settings(settings, side)
    # Only the fitted native actor-local file is accepted. The similarly shaped
    # world-poses.json contains a baked trajectory and must never become a clip.
    pose_path = study / 'local-poses.json'
    rows = json.loads(pose_path.read_text())
    contacts = json.loads((study / 'contacts.json').read_text())
    require(len(rows) == len(contacts), f'{side}: incomplete contacts/poses')
    require(all(close(row['time'], i / FPS) for i, row in enumerate(rows)),
            f'{side}: study must be sampled at 60 Hz')
    pre = settings['pre_seconds']
    # Both original contacts have been replaced after two steps. A half-cycle
    # offset makes the next swinging anatomical foot L for both turn directions.
    shift = .4 if side == 'right' else 0.
    start = round((pre + 2 * settings['step_seconds'] + shift) * FPS)
    end = start + FRAME_COUNT
    require(0 < start and end + 1 < len(rows), f'{side}: study is too short')
    ramp = settings['root_ramp_seconds']
    require(rows[start - 1]['time'] > pre + ramp
            and rows[end + 1]['time'] < pre + settings['turn_seconds'] - ramp,
            f'{side}: no complete settled two-step cruise interval')
    velocity = derivative_error(rows, start, end)
    seam = max_matrix_difference(rows[start]['bones'], rows[end]['bones'])
    require(seam <= POSE_TOLERANCE, f'{side}: actor-space pose seam {seam}')
    require(velocity <= VELOCITY_TOLERANCE, f'{side}: velocity seam {velocity}')
    require(contacts[start]['support'] == {'L': True, 'R': True},
            f'{side}: loop anchor is not double support')
    first_swing = next((r['support'] for r in contacts[start:end]
                        if not all(r['support'].values())), None)
    require(first_swing == {'L': False, 'R': True},
            f'{side}: loop does not begin with anatomical left swing')
    rates = [(b['heading'] - a['heading']) * FPS
             for a, b in zip(contacts[start:end], contacts[start + 1:end + 1])]
    speed = sum(rates) / len(rates)
    require(max(abs(rate - speed) for rate in rates) < 1e-7,
            f'{side}: extraction includes root acceleration')
    samples = [dict(time=i / FPS, bones=copy.deepcopy(rows[start + i]['bones']))
               for i in range(FRAME_COUNT + 1)]
    # Remove only native float fit noise at the duplicate end key. The measured
    # pre-correction seam and periodic derivative remain recorded below.
    samples[-1]['bones'] = copy.deepcopy(samples[0]['bones'])
    metadata = {
        'schema': 'shopping-turn-visual-loop-v1', 'coordinate_space': 'native actor-local',
        'direction': side, 'duration_seconds': PERIOD, 'fps': FPS,
        'canonical_phase': 'left foot swings first', 'phase_shift_seconds': shift,
        'source_interval_seconds': [rows[start]['time'], rows[end]['time']],
        'source_phase_offset_seconds': rows[start]['time'] - (pre + .8 + shift),
        'reference_angular_speed_radians': speed,
        'reference_angular_speed_degrees': math.degrees(speed),
        'source_pose_seam_max': seam, 'source_velocity_seam_max': velocity,
        'export_pose_seam_max': 0., 'root_motion': 'none; canonical native roots retained',
        'study_settings': settings,
        'source_sha256': {name: digest(study / name)
                          for name in ('study.json', 'local-poses.json', 'contacts.json')},
    }
    samples[0]['metadata'] = metadata
    validate_samples(samples, parents, canonical)
    return samples, metadata


def check_metadata(samples, side):
    meta = samples[0].get('metadata', {})
    if meta.get('schema') == 'shopping-turn-native-walk-v2':
        source = meta.get('source', {})
        require(meta.get('coordinate_space') == 'native actor-local'
                and meta.get('direction') == side
                and close(meta.get('period_seconds'), PERIOD)
                and meta.get('fps') == FPS
                and meta.get('canonical_phase') == 'left foot swings first'
                and close(meta.get('source_phase_offset'), .5),
                f'{side}: invalid native-walk loop metadata')
        require(source.get('path') == 'assets/animations/cart_pivot_walk.json'
                and source.get('sha256') == digest(ROOT / source['path']),
                f'{side}: native walking source changed; regenerate the shopping gait')
        sign = -1 if side == 'left' else 1
        require(close(meta.get('pelvis_yaw_degrees'), sign * 25)
                and close(meta.get('chest_yaw_degrees'), sign * 8)
                and close(meta.get('leg_abduction_degrees'), 2),
                f'{side}: unexpected body-leading turn')
        return meta
    require(meta.get('schema') == 'shopping-turn-visual-loop-v1'
            and meta.get('coordinate_space') == 'native actor-local'
            and meta.get('direction') == side, f'{side}: missing visual-loop provenance')
    validate_settings(meta.get('study_settings', {}), side)
    require(close(meta.get('phase_shift_seconds'), .4 if side == 'right' else 0.),
            f'{side}: anatomical phase shift changed')
    require(0 <= meta.get('source_pose_seam_max', math.inf) <= POSE_TOLERANCE
            and 0 <= meta.get('source_velocity_seam_max', math.inf) <= VELOCITY_TOLERANCE,
            f'{side}: source seam is not validated')
    expected_speed = math.radians(meta['study_settings']['degrees']) / (
        meta['study_settings']['turn_seconds'] - meta['study_settings']['root_ramp_seconds'])
    if side == 'right':
        expected_speed = -expected_speed
    require(close(meta.get('reference_angular_speed_radians'), expected_speed),
            f'{side}: reference angular speed differs from study')
    return meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--left-study', type=Path)
    parser.add_argument('--right-study', type=Path)
    parser.add_argument('--template', type=Path, help='native Bob_Idle.x')
    parser.add_argument('--game', type=Path, help='game Java directory containing media/')
    parser.add_argument('--output', type=Path, default=ROOT,
                        help='project root for assets/animations and PZSurvivorToolkit/')
    parser.add_argument('--check', action='store_true', help='verify existing assets; never write')
    parser.add_argument('--report', type=Path, help='optional JSON report; default stdout only')
    args = parser.parse_args()
    template = args.template or (args.game / 'media/anims_X/Bob/Bob_Idle.x' if args.game else None)
    if template is None:
        parser.error('pass --template Bob_Idle.x or --game GAME_JAVA')
    if not args.check and (args.left_study is None or args.right_study is None):
        parser.error('generation requires --left-study and --right-study')
    if args.check and args.report:
        parser.error('--check does not write reports; read stdout')
    try:
        source = template.read_text()
        _, parents = baker.template_parts(source)
        canonical_path = ROOT / 'assets/animations/cart_pivot_idle.json'
        canonical = json.loads(canonical_path.read_text())[0]['bones']
        report = {}
        prepared = []
        for side, study in (('left', args.left_study), ('right', args.right_study)):
            json_path = args.output / f'assets/animations/shopping_turn_{side}.json'
            clip_name = 'Toolkit_ShoppingTurn_' + side.title()
            native_path = args.output / f'PZSurvivorToolkit/42/media/anims_X/Bob/{clip_name}.x'
            if args.check:
                samples = json.loads(json_path.read_text())
                validate_samples(samples, parents, canonical)
                meta = check_metadata(samples, side)
                if study is not None:
                    regenerated, _ = extract(study, side, parents, canonical)
                    require(samples == regenerated, f'{side}: source differs from study')
            else:
                samples, meta = extract(study, side, parents, canonical)
            native = baker.bake(source, samples, clip_name)
            if args.check:
                require(native_path.read_text() == native, f'{side}: native clip needs rebaking')
            else:
                prepared.append((json_path, json.dumps(samples, separators=(',', ':')) + '\n'))
                prepared.append((native_path, native))
            report[side] = dict(meta, source=str(json_path), native=str(native_path))
        for path, content in prepared:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        result = json.dumps(report, indent=2) + '\n'
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(result)
        print(result, end='')
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
