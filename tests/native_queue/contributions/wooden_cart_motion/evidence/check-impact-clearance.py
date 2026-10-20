"""Prepared post-release leg/trouser triangles versus wooden handles; not a visual-quality pass."""
import argparse
import bisect
import json
import math
from pathlib import Path
import re
import numpy as np
import actual_mesh
from clearance_geometry import model, skin, shafts, write_json
from shaft_components import build_components


def actor_matrix(row):
    c, s = math.cos(row['slotAngle']), math.sin(row['slotAngle'])
    matrix = np.eye(4)
    matrix[:3, :3] = [[-1.5*c, 0, -1.5*s], [-1.5*s, 0, 1.5*c], [0, 1.5/2.44949, 0]]
    matrix[:3, 3] = [row['slotX'], row['slotY'], row['slotZ']]
    assert np.isfinite(matrix).all(), 'Nonfinite actor placement'
    return matrix


def world_matrix(row):
    # Same native Rx * Ry * Rz composition as analyze-impact.world_cart_points.
    x, y, z = map(math.radians, row['angle'])
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    matrix = np.eye(4)
    matrix[:3, :3] = np.array([[1.5, 0, 0], [0, 0, -1.5], [0, 1.5/2.44949, 0]]) @ rx @ ry @ rz
    matrix[:3, 3] = [row['x'], row['y'], row['z']]
    result = matrix @ np.asarray(row['transform']).reshape(4, 4).T
    assert np.isfinite(result).all(), 'Nonfinite cart placement'
    return result


def leg_faces(mesh, side):
    selected = np.zeros(mesh[0], bool)
    for name, ids, weights, _ in mesh[1]:
        if name in ('Bip01_'+side+'_Thigh', 'Bip01_'+side+'_Calf'):
            selected[ids[weights > 0]] = True
    result = mesh[3][selected[mesh[3]].any(1)]
    assert len(result), 'No leg triangles'
    return result


def paired_frames(tails, worlds, start, item, release):
    frames = [r for r in tails if r.get('impact') is True and start <= r['wallTimeMillis'] < start+12000]
    cart = [r for r in worlds if r.get('renderStatus') == 'Ready' and r['itemId'] == item
            and start <= r['wallTimeMillis'] < start+12000]
    assert len(frames) >= 20 and cart, 'Missing post-release body/cart poses'
    times = [r['wallTimeMillis'] for r in cart]
    assert all(b >= a for a, b in zip(times, times[1:])), 'Unordered cart poses'
    assert all(0 < b['wallTimeMillis']-a['wallTimeMillis'] <= 150 for a, b in zip(frames, frames[1:])), 'Body pose coverage gap'
    paired = []
    for row in frames:
        t = row['wallTimeMillis']
        # The native collision state can precede exact drop by one update; do not pair it with a future released cart.
        if t < times[0]:
            continue
        index = bisect.bisect_left(times, t)
        world = min(cart[max(0, index-1):index+1], key=lambda r: abs(r['wallTimeMillis']-t))
        assert abs(world['wallTimeMillis']-t) <= 40, 'Unsynchronized body/world preparation'
        assert type(row['female']) is bool and row.get('cartModel') is False, 'Released actor still has a held cart model'
        paired.append((row, world))
    # A late-only clear fall must not hide the short thigh contact immediately after release.
    early = [r['wallTimeMillis'] for r, _ in paired if release-40 <= r['wallTimeMillis'] <= release+490]
    assert early and abs(early[0]-release) <= 40 and early[-1] >= release+450, 'Missing early release-pose coverage'
    assert all(0 < b-a <= 50 for a, b in zip(early, early[1:])), 'Early release-pose coverage gap'
    yield from paired


def analyze(profile, game, mesh_path, scenes):
    def read(name):
        return [json.loads(line) for line in (profile/name).read_text().splitlines() if line.strip()]
    vertices, actual_mesh.components = build_components(mesh_path)
    native, _ = shafts(profile/'WheelbarrowWood.bin')
    source = {tuple(v) for v in np.round(vertices, 7)}
    assert all(tuple(v) in source for v in np.round(native, 7)), 'Native VBO differs from analyzed FBX'
    models = {(female, pants): model(game, female, pants) for female in (False, True) for pants in (False, True)}
    tails, worlds = read('action-tail-poses.jsonl'), read('world-cart-poses.jsonl')
    text = (profile/'console.txt').read_text()
    completed = [(name, int(t)) for name, t in re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', text)]
    selected = [name for name in scenes if name.endswith('-native-impact')]
    records, summary = [], []
    for scene in selected:
        starts = [t for name, t in completed if name == scene]
        assert len(starts) == 1, 'Missing/repeated selected scene'
        start = starts[0]
        samples = [dict(token.split('=', 1) for token in line.split() if '=' in token)
                   for line in text.splitlines() if '[CART_IMPACT_SAMPLE] ' in line and 'case='+scene+' ' in line]
        ids = {int(row['id']) for row in samples if start <= int(row['wall']) < start+12000}
        assert len(ids) == 1, 'Missing/ambiguous exact scene cart'
        item = ids.pop()
        drops = [int(r['wall']) for r in samples if start <= int(r['wall']) < start+12000
                 and r.get('worldExact') == 'true' and r.get('primary') == '-1'
                 and r.get('secondary') == '-1' and r.get('state') == 'CollideWithWallState']
        assert drops, 'No exact native collision release'
        release = min(drops)
        frames = []
        for row, world in paired_frames(tails, worlds, start, item, release):
            convert = np.linalg.inv(world_matrix(world)) @ actor_matrix(row)
            frame = dict(scene=scene, time=row['wallTimeMillis'], elapsed=row['wallTimeMillis']-start,
                         pairingGapMs=world['wallTimeMillis']-row['wallTimeMillis'])
            for pants in (False, True):
                mesh = models[row['female'], pants]
                body = skin(row, mesh)
                local = (np.c_[body, np.ones(len(body))] @ convert.T)[:, :3]
                for leg in ('L', 'R'):
                    faces = leg_faces(mesh, leg)
                    for shaft in ('L', 'R'):
                        frame[('pants' if pants else 'body')+leg+shaft] = int(actual_mesh.intersects(local[faces], shaft).sum())
            frames.append(frame)
        assert len(frames) >= 20, 'Insufficient paired post-release poses'
        hits = [r for r in frames if any(v for k, v in r.items() if k.startswith(('pants', 'body')))]
        summary.append(dict(scene=scene, frames=len(frames), intersectingFrames=len(hits),
                            contactIntervalMs=[hits[0]['elapsed'], hits[-1]['elapsed']] if hits else None))
        records.extend(frames)
    return dict(scope='Prepared native skin and stock Bob/Kate trousers versus exact released wooden handle meshes; SP selected scenes only.',
                meshPass=(not any(r['intersectingFrames'] for r in summary)) if selected else None, scenes=summary, frames=records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--game-java-dir', type=Path, required=True)
    parser.add_argument('--mesh', type=Path, required=True)
    parser.add_argument('--scene', action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.profile, args.game_java_dir, args.mesh, args.scene)
    write_json(args.output, result)
    print(json.dumps({k: v for k, v in result.items() if k != 'frames'}, indent=2))
    if result['meshPass'] is False:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
