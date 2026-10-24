"""Reject gross opposite-leg intersections in an offline native-pose study.

Run inside Blender (BVH dependency):
  Blender --background --python tools/cart_turn_clearance.py -- \
    --poses world-poses.json --trousers Bob_Trousers.x --output clearance.json

Checks every supplied pose, including actual side-exclusive trouser surfaces.
Crotch/waist connector faces are excluded; this is a sampled gross-defect gate,
not continuous-time collision detection or a native gameplay clearance result.
"""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cart_blender_preview import parse_body, skin_vertices


def segment_distance(p, end_p, q, end_q):
    """Closest distance between two finite 3D segments, including their ends."""
    u, v, w = end_p-p, end_q-q, p-q
    a, b, c, d, e = u.dot(u), u.dot(v), v.dot(v), u.dot(w), v.dot(w)
    def point_segment(point, start, direction, length_squared):
        t=max(0., min(1., (point-start).dot(direction)/length_squared))
        return (point-start-t*direction).length
    result=min(point_segment(p,q,v,c),point_segment(end_p,q,v,c),
               point_segment(q,p,u,a),point_segment(end_q,p,u,a))
    determinant=a*c-b*b
    if determinant>1e-12:
        s=(b*e-c*d)/determinant;t=(a*e-b*d)/determinant
        if 0<=s<=1 and 0<=t<=1:result=min(result,(w+s*u-t*v).length)
    return result


def check_clearance(samples, trousers):
    if len(samples)<2:raise ValueError('Expected at least two native poses')
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    weights={s:[0.]*len(trousers.vertices) for s in ('L','R')}
    for name,skin in trousers.skin.items():
        for side in weights:
            if name.startswith('Bip01_'+side+'_'):
                for index,weight in zip(skin.indices,skin.weights):weights[side][index]+=weight
    # Include only wholly side-exclusive triangles, never the connecting crotch seam.
    faces={s:[f for f in trousers.faces if all(weights[s][i]>=.95 for i in f)] for s in weights}
    if not all(faces.values()):raise ValueError('No exclusive leg geometry found')
    min_spacing=float('inf');min_segments=float('inf');intersections=[]
    for frame,row in enumerate(samples):
        bones=row['bones']
        def at(side,part):
            m=bones['Bip01_'+side+'_'+part]
            return Vector((m[12],-m[14],m[13]))
        lateral=(at('L','Thigh')-at('R','Thigh')).normalized()
        min_spacing=min(min_spacing,(at('L','Foot')-at('R','Foot')).dot(lateral))
        legs={s:[at(s,n) for n in ('Thigh','Calf','Foot')] for s in weights}
        for i in range(2):
            for j in range(2):
                min_segments=min(min_segments,segment_distance(legs['L'][i],legs['L'][i+1],legs['R'][j],legs['R'][j+1]))
        vertices=[Vector(p) for p in skin_vertices(trousers,bones)]
        trees={s:BVHTree.FromPolygons(vertices,faces[s],all_triangles=True,epsilon=0.) for s in weights}
        hits=trees['L'].overlap(trees['R'])
        if hits:intersections.append(dict(frame=frame+1,time=row['time'],triangle_pairs=len(hits)))
    return dict(scope='Every supplied pose; exclusive native trouser surfaces, excluding crotch connectors.',
                samples=len(samples),exclusive_triangles={s:len(f) for s,f in faces.items()},
                intersecting_frames=intersections,min_signed_ankle_spacing=min_spacing,
                min_opposed_leg_segment_distance=min_segments,
                passed=not intersections and min_spacing>=.08 and min_segments>=.06)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--poses',type=Path,required=True)
    parser.add_argument('--trousers',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    report=check_clearance(json.loads(args.poses.read_text()),parse_body(args.trousers.read_text(),mesh_name='Bob_Trousers'))
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('CART_TURN_CLEARANCE',json.dumps(report),flush=True)
    if not report['passed']:raise ValueError('Gross opposite-leg crossing; see clearance report')
