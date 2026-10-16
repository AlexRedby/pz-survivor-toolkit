"""Conservative body/shaft AABB proof. Overlap is inconclusive, not intersection."""
import argparse
import json
from pathlib import Path
import numpy as np
from clearance_geometry import model, rows, separation, shafts, skin, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-java-dir', type=Path, required=True)
    parser.add_argument('--mesh-vbo', type=Path, required=True, help='Read-only native wooden vertex buffer: 8 little-endian floats per vertex')
    parser.add_argument('--capture', type=Path, required=True, help='Complete body-clearance JSONL')
    parser.add_argument('--output', type=Path, required=True, help='Result directory; existing result files are refused')
    args = parser.parse_args()
    models = {sex: model(args.game_java_dir, sex) for sex in (False, True)}
    _, handles = shafts(args.mesh_vbo)
    frames = []
    for row in rows(args.capture):
        mesh = models[row['female']]
        body = skin(row, mesh)
        cart = np.asarray(row['cart']).reshape(4, 4).T
        frame = {'time': row['wallTimeMillis'], 'female': row['female']}
        for side, points in handles.items():
            handle = (points @ cart.T)[:, :3]
            for region, mask in mesh[2].items():
                assert mask.any(), 'Missing body region'
                frame[f'{side}_{region}'] = separation(body[mask], handle)
        frames.append(frame)
    assert frames, 'No captured frames'
    keys = ['L_hip', 'R_hip', 'L_belly', 'R_belly']
    result = {'frames': len(frames), 'limit': __doc__,
              'minimumGap': {key: min(row[key] for row in frames) for key in keys},
              'inconclusiveFrames': {key: sum(row[key] <= 0 for row in frames) for key in keys}}
    args.output.mkdir(parents=True, exist_ok=True)
    write_json(args.output / 'clearance-frames.json', frames)
    write_json(args.output / 'clearance-metrics.json', result)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
