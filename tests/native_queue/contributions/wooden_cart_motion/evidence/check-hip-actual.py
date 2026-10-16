"""Actual wooden shaft triangles versus native skinned hip/body or trousers triangles."""
import argparse
import json
from pathlib import Path
import numpy as np
import actual_mesh
from clearance_geometry import model, rows, shafts, skin, write_json
from shaft_components import build_components


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-java-dir', type=Path, required=True)
    parser.add_argument('--mesh', type=Path, required=True, help='Locally installed wooden wheelbarrow binary FBX')
    parser.add_argument('--mesh-vbo', type=Path, required=True, help='Native vertex buffer used to verify the FBX import')
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pants', action='store_true', help='Use Kate/Bob trousers instead of naked body')
    args = parser.parse_args()
    vertices, actual_mesh.components = build_components(args.mesh)
    native, _ = shafts(args.mesh_vbo)
    source = {tuple(value) for value in np.round(vertices, 7)}
    assert all(tuple(value) in source for value in np.round(native, 7)), 'Native VBO does not match FBX after import Z reflection'
    assert all(component['closed'] or len(component['vertices']) == 16 for component in actual_mesh.components), 'Mesh topology changed: recalibrate open surfaces'
    models = {sex: model(args.game_java_dir, sex, args.pants) for sex in (False, True)}
    frames = []
    for row in rows(args.capture):
        mesh = models[row['female']]
        body = skin(row, mesh)
        cart = np.asarray(row['cart']).reshape(4, 4).T
        local = (np.c_[body, np.ones(len(body))] @ np.linalg.inv(cart).T)[:, :3]
        faces = mesh[3][mesh[2]['hip'][mesh[3]].any(1)]
        assert len(faces), 'No selected hip triangles'
        frame = {'time': row['wallTimeMillis'], 'female': row['female']}
        for side in 'LR':
            frame[side] = int(actual_mesh.intersects(local[faces], side).sum())
        frames.append(frame)
    assert frames, 'No captured frames'
    args.output.mkdir(parents=True, exist_ok=True)
    write_json(args.output / ('pants-triangle-frames.json' if args.pants else 'hip-triangle-frames.json'), frames)
    intersections = {side: sum(row[side] > 0 for row in frames) for side in 'LR'}
    print(json.dumps({'frames': len(frames), 'intersectingFrames': intersections, 'pants': args.pants}, indent=2))
    if any(intersections.values()):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
