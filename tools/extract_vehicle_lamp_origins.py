#!/usr/bin/env python3
"""Extract numeric lamp-face centroids from current vanilla FBX + shader masks.

Developer tool only. Requires numpy/Pillow and the game's bundled Jassimp.
The generated Lua contains coordinates, never model/texture assets.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

# vehicle_common.frag.h zones 18..21. Pure red/green are BODY zones.
LAMP_COLORS = {'HeadlightLeft': (192, 0, 0), 'HeadlightRight': (64, 0, 0),
               'HeadlightRearLeft': (0, 64, 0), 'HeadlightRearRight': (0, 192, 0)}


def blocks(text):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    children, direct, at = [], [], 0
    while at < len(text):
        start = text.find('{', at)
        if start < 0:
            direct.append(text[at:]); break
        prefix = text[at:start]
        match = re.search(r'([\w!]+(?:[ \t]+[\w.*]+)*)\s*$', prefix)
        if not match: raise ValueError('Cannot read script block header: '+repr(prefix[-160:]))
        direct.append(prefix[:match.start()])
        depth, end = 1, start + 1
        while depth:
            if text[end] == '{': depth += 1
            elif text[end] == '}': depth -= 1
            end += 1
        props, nested = blocks(text[start+1:end-1])
        children.append((match.group(1).split(), props, nested)); at = end
    props = re.findall(r'([\w!]+)\s*=\s*([^,]+),', ''.join(direct))
    return [(key, value.strip()) for key, value in props], children


def inventory(game):
    models, templates, vehicles = {}, {}, []
    for path in sorted((game/'media/scripts/generated/vehicles').rglob('*.txt')):
        text = path.read_text(encoding='utf-8-sig', errors='replace')
        if not re.search(r'\b(?:model|vehicle)\b', text): continue
        for module, _, children in blocks(text)[1]:
            if module[0] != 'module': continue
            for header, props, nested in children:
                if header[0] == 'model' and len(header) == 2:
                    models[header[1]] = dict(props)
                elif header[:2] == ['template', 'vehicle']:
                    templates[header[2]] = (props, nested)
                elif header[0] == 'vehicle':
                    vehicles.append((header[1], props, nested))
    def resolve(props, nested, active=()):
        result = {}
        for key, value in props:
            if key in ('template', 'template!') and value in templates:
                if value in active: raise ValueError('Template cycle: '+value)
                result.update(resolve(*templates[value], (*active, value)))
            elif key == 'textureMask': result['mask'] = value
        for header, child_props, _ in nested:
            if header == ['model']:
                value = dict(child_props).get('file')
                if value: result['model'] = value
        return result
    pairs = {}
    for name, props, nested in vehicles:
        value = resolve(props, nested)
        if 'model' not in value or 'mask' not in value: continue
        model = models.get(value['model'], {})
        mesh = model.get('mesh', '')
        if not mesh or not (game/'media/models_X'/Path(mesh).with_suffix('.fbx')).is_file(): continue
        pairs.setdefault((value['model'], value['mask']), {'vehicles': [], 'model': model})['vehicles'].append(name)
    return pairs


def sample_lamps(meshes, mask, mesh_scale, invert_x):
    """Integrate lamp texels over triangles, weighted by actual surface area."""
    h, w = mask.shape[:2]
    totals = {key: [0., np.zeros(3)] for key in LAMP_COLORS}
    for mesh in meshes:
        vertices = np.asarray(mesh['vertices'], dtype=float)
        transform = np.asarray(mesh['transform'], dtype=float)
        xyz = (np.c_[vertices[:, :3], np.ones(len(vertices))] @ transform.T)[:, :3] * mesh_scale
        # BaseVehicle.updateTransform mirror; matching ModelInstanceRenderData.
        xyz[:, 0] *= 1 if invert_x else -1
        uv = vertices[:, 3:5] * [w, h]
        for ids in mesh['triangles']:
            tri, pos = uv[ids], xyz[ids]
            matrix = np.column_stack([tri[1]-tri[0], tri[2]-tri[0]])
            det = np.linalg.det(matrix)
            area = np.linalg.norm(np.cross(pos[1]-pos[0], pos[2]-pos[0])) * .5
            if abs(det) < 1e-8 or area < 1e-10: continue
            lo = np.maximum(0, np.floor(tri.min(0)).astype(int))
            hi = np.minimum([w-1, h-1], np.ceil(tri.max(0)).astype(int))
            if (hi < lo).any(): continue
            xx, yy = np.meshgrid(np.arange(lo[0], hi[0]+1), np.arange(lo[1], hi[1]+1))
            points = np.c_[xx.ravel()+.5, yy.ravel()+.5]
            ab = (points-tri[0]) @ np.linalg.inv(matrix).T
            inside = (ab >= 0).all(1) & (ab.sum(1) <= 1)
            pixels = mask[yy.ravel(), xx.ravel()].astype(int)
            for key, color in LAMP_COLORS.items():
                keep = inside & (np.max(np.abs(pixels-color), axis=1) <= 2)
                if not keep.any(): continue
                weight = area / (abs(det)*.5)
                positions = pos[0] + ab[keep] @ (pos[1:]-pos[0])
                # StepVan reuses a tail zone for amber FRONT roof markers too.
                # Separate real emitters at the correct vehicle end; averaging
                # both ends would invent an origin inside the cabin.
                at_end = positions[:, 2] < 0 if 'Rear' in key else positions[:, 2] > 0
                positions = positions[at_end]
                totals[key][0] += len(positions) * weight
                totals[key][1] += positions.sum(0) * weight
    return {key: (total/count).tolist() for key, (count, total) in totals.items() if count > 0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, required=True)
    parser.add_argument('--java', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--cache', type=Path, help='Optional derived FBX JSON cache outside shipped assets')
    args = parser.parse_args()
    pairs = inventory(args.game)
    exported, cache, evidence = {}, {}, []
    tool = Path(__file__).with_name('VehicleLampMesh.java')
    for (model_name, mask_name), spec in sorted(pairs.items()):
        model = spec['model']; mesh_name = model['mesh']
        path = args.game/'media/models_X'/Path(mesh_name).with_suffix('.fbx')
        mask_path = args.game/'media/textures'/Path(mask_name).with_suffix('.png')
        if not mask_path.is_file(): continue
        if mesh_name not in cache:
            digest = hashlib.sha256(path.read_bytes()+tool.read_bytes()).hexdigest()
            cached = args.cache/(digest+'.json') if args.cache else None
            if cached and cached.is_file(): cache[mesh_name] = json.loads(cached.read_text())['meshes']
            else:
                run = subprocess.run([str(args.java), '--enable-native-access=ALL-UNNAMED',
                    '-Djava.library.path='+str(args.game), '-cp', str(args.game/'projectzomboid.jar'),
                    str(tool), str(path)], check=True, capture_output=True, text=True)
                cache[mesh_name] = json.loads(run.stdout)['meshes']
                if cached:
                    cached.parent.mkdir(parents=True, exist_ok=True)
                    cached.write_text(run.stdout)
        mask = np.asarray(Image.open(mask_path).convert('RGBA').convert('RGB'))
        anchors = sample_lamps(cache[mesh_name], mask, float(model.get('scale', '1')),
                              model.get('invertX', 'false') == 'true')
        if not anchors: continue
        if model_name in exported and exported[model_name] != anchors:
            raise ValueError('Different lamp masks for model '+model_name)
        exported[model_name] = anchors
        evidence.append({'model': model_name, 'mesh': mesh_name, 'mask': mask_name,
            'mesh_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'mask_sha256': hashlib.sha256(mask_path.read_bytes()).hexdigest(),
            'vehicles': spec['vehicles'], 'anchors': anchors})
    lines = ['-- Generated by tools/extract_vehicle_lamp_origins.py from B42.21 FBX and lamp masks.',
             '-- Coordinates are before VehicleScript model scale/offset; no artwork is included.', 'return {']
    for model, anchors in sorted(exported.items()):
        lines.append('    ["'+model+'"] = {')
        for key, value in anchors.items():
            lines.append('        '+key+' = {'+', '.join(f'{v:.7f}' for v in value)+'},')
        lines.append('    },')
    lines.append('}')
    args.output.write_text('\n'.join(lines)+'\n')
    args.evidence.write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps({'models': len(exported), 'model_mask_pairs': len(evidence),
                      'vehicles': sum(len(item['vehicles']) for item in evidence)}))


if __name__ == '__main__': main()
