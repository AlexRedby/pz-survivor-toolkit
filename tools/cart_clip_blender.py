#!/usr/bin/env python3
"""Edit the existing 45-bone rigid cart clips in Blender.

blender --background --python tools/cart_clip_blender.py -- import \
    --template Bob_Idle.x --input poses.json --output cart.blend
blender --background --python tools/cart_clip_blender.py -- export \
    --input cart.blend --output edited.json

The first sample becomes the armature rest pose. Edit pose bones and their action;
export samples the original timestamps, including any constraints affecting them.
Object transforms and changed bone hierarchies are rejected. Use export --timing
keys to retain added/moved keys, or --bake-fps for curves and constrained motion.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import sys

# Blender's --python runner need not add the script directory to sys.path.
sys.path.insert(0,str(Path(__file__).resolve().parent))
import cart_clip_bake as baker


SCHEMA='pz-cart-native-poses-v1'
PROPERTY='pz_cart_clip'
FPS=60
# Model coordinates: native +Y becomes Blender +Z, native +Z becomes Blender -Y.
MODEL_BASIS=[1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,0,0,1]
# Native limbs use local +X along their length; Blender edit bones use local +Y.
BONE_BASIS=[0,-1,0,0, 1,0,0,0, 0,0,1,0, 0,0,0,1]
IDENTITY=[1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]


def native_to_blender(matrix):
    return baker.multiply(MODEL_BASIS,baker.multiply(matrix,BONE_BASIS))


def blender_to_native(matrix):
    return baker.multiply(baker.inverse_rigid(MODEL_BASIS),
                          baker.multiply(matrix,baker.inverse_rigid(BONE_BASIS)))


def matrix_rows(matrix):
    """Convert the native column-major array to mathutils' row-major constructor."""
    return [[matrix[col*4+row] for col in range(4)] for row in range(4)]


def column_matrix(rows):
    return [float(rows[row][col]) for col in range(4) for row in range(4)]


def parent_order(parents):
    if (not isinstance(parents,dict) or len(parents)!=45 or parents.get('Dummy01','missing') is not None
            or parents.get('Bip01')!='Dummy01' or parents.get('Translation_Data')!='Dummy01'
            or any(not isinstance(name,str) or parent is not None and parent not in parents
                   for name,parent in parents.items())):
        raise ValueError('expected the original 45-bone Bob hierarchy')
    ordered=[];visiting=set();done=set()
    def visit(name):
        if name in visiting:
            raise ValueError('cyclic native bone hierarchy')
        if name in done:
            return
        visiting.add(name)
        parent=parents[name]
        if parent is not None:
            visit(parent)
        visiting.remove(name);done.add(name);ordered.append(name)
    for name in parents:
        visit(name)
    return ordered


def validate_samples(samples,parents):
    parent_order(parents)
    if not isinstance(samples,list) or not 2<=len(samples)<=baker.MAX_SAMPLES:
        raise ValueError(f'expected 2..{baker.MAX_SAMPLES} samples')
    previous=-1;previous_tick=-1
    for index,sample in enumerate(samples):
        if not isinstance(sample,dict):
            raise ValueError(f'sample {index}: expected time and bones')
        time=sample.get('time');bones=sample.get('bones')
        if (type(time) not in (float,int) or not math.isfinite(time) or
                index==0 and time!=0 or not previous<time<=baker.MAX_DURATION):
            raise ValueError(f'sample {index}: invalid native sample time')
        tick=round(time*baker.TICKS_PER_SECOND)
        if tick<=previous_tick:
            raise ValueError('sample times collide at native microsecond precision')
        if not isinstance(bones,dict) or bones.keys()!=parents.keys():
            raise ValueError(f'sample {index}: bone names differ from the original template')
        for name,matrix in bones.items():
            baker.validate_matrix(matrix,f'sample {index} bone {name}')
        for name,parent in parents.items():
            local=bones[name] if parent is None else baker.multiply(baker.inverse_rigid(bones[parent]),bones[name])
            baker.validate_matrix(local,f'sample {index} local bone {name}')
        previous=time;previous_tick=tick


def sample_frames(times):
    # Blender stores F-curve frame coordinates as float32. Export must evaluate
    # the actual keys, not nearby doubles reconstructed from the native time.
    frames=[struct.unpack('f',struct.pack('f',1+FPS*time))[0] for time in times]
    if any(right<=left for left,right in zip(frames,frames[1:])):
        raise ValueError('native samples are too close for Blender frame precision')
    return frames


def pose_basis(rest,parent_rest,parent_pose,pose):
    """Invert Blender's unconnected, fully inheriting pose-bone composition."""
    if parent_rest is None:
        return baker.multiply(baker.inverse_rigid(rest),pose)
    return baker.multiply(baker.inverse_rigid(rest),baker.multiply(parent_rest,
        baker.multiply(baker.inverse_rigid(parent_pose),pose)))


def metadata_for(parents,samples):
    validate_samples(samples,parents)
    times=[sample['time'] for sample in samples]
    return dict(schema=SCHEMA,parents=parents,times=times,frames=sample_frames(times))


def validate_metadata(metadata):
    if not isinstance(metadata,dict) or metadata.get('schema')!=SCHEMA:
        raise ValueError('missing supported cart authoring metadata')
    parent_order(metadata.get('parents'))
    times=metadata.get('times');frames=metadata.get('frames')
    # Reuse the exact native time rules without requiring a source clip on export.
    samples=[dict(time=time,bones={name:IDENTITY for name in metadata['parents']}) for time in times] if isinstance(times,list) else None
    validate_samples(samples,metadata['parents'])
    if frames!=sample_frames(times):
        raise ValueError('original Blender sample frames were changed')


def blender_api():
    try:
        import bpy
        from mathutils import Matrix
    except ImportError as error:
        raise RuntimeError('run this command with Blender --background --python') from error
    return bpy,Matrix


def export_metadata(metadata,frames):
    """Retain exact source times at unchanged float32 frames; map edited keys."""
    validate_metadata(metadata)
    original=dict(zip(metadata['frames'],metadata['times']))
    frames=sorted(set(frames))
    times=[original.get(frame,(frame-1)/FPS) for frame in frames]
    result=dict(metadata,times=times,frames=sample_frames(times))
    validate_metadata(result)
    return result


def authored_metadata(obj,metadata,bake_fps=None):
    bpy,_=blender_api()
    action=obj.animation_data.action if obj.animation_data else None
    if action is None:
        raise ValueError('the authoring rig has no action')
    curves=[curve for curve in action.fcurves if curve.data_path.startswith('pose.bones[')]
    if not curves or any(curve.mute or curve.modifiers for curve in curves):
        raise ValueError('expected unmuted pose curves without F-curve modifiers')
    if any(track.strips for track in obj.animation_data.nla_tracks):
        raise ValueError('NLA strips are unsupported; use the rig action directly')
    frames=sorted(set(float(key.co.x) for curve in curves for key in curve.keyframe_points))
    if len(frames)<2 or frames[0]!=1:
        raise ValueError('pose keys must start at frame 1 and contain at least two frames')
    if bake_fps is not None:
        if not math.isfinite(bake_fps) or not 1<=bake_fps<=240:
            raise ValueError('bake fps must be in 1..240')
        scene=bpy.context.scene
        step=scene.render.fps/scene.render.fps_base/bake_fps
        count=math.ceil((frames[-1]-1)/step)
        if count+len(frames)>baker.MAX_SAMPLES:
            raise ValueError('baked export exceeds the native sample budget')
        authored=frames.copy()
        for i in range(count):
            frame=sample_frames([i*step/FPS])[0]
            # Keep authored timestamps when the regular grid lands almost on a
            # key. Native .x keys have microsecond precision, Blender float32.
            if all(abs(frame-key)/FPS>4e-6 for key in authored):
                frames.append(frame)
        frames=sorted(set(frames))
    elif (obj.animation_data.drivers
          or any(key.interpolation!='LINEAR' for curve in curves for key in curve.keyframe_points)
          or any(bone.constraints for bone in obj.pose.bones)):
        raise ValueError('nonlinear curves or constraints require --bake-fps (for example 60)')
    return export_metadata(metadata,frames)


def evaluated_samples(obj,metadata):
    bpy,_=blender_api();validate_metadata(metadata)
    parents=metadata['parents'];scene=bpy.context.scene
    if set(obj.data.bones.keys())!=set(parents):
        raise ValueError('armature bone names differ from the original template')
    for name,parent in parents.items():
        actual=obj.data.bones[name].parent
        if (None if actual is None else actual.name)!=parent:
            raise ValueError(f'native parent changed for {name}')
    samples=[]
    for time,frame in zip(metadata['times'],metadata['frames']):
        whole=math.floor(frame);scene.frame_set(whole,subframe=frame-whole)
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        if max(abs(a-b) for a,b in zip(column_matrix(evaluated.matrix_world),IDENTITY))>1e-6:
            raise ValueError('edit pose bones; the armature object transform must remain identity')
        bones={name:blender_to_native(column_matrix(evaluated.pose.bones[name].matrix)) for name in parents}
        samples.append(dict(time=time,bones=bones))
    validate_samples(samples,parents)
    return samples


def import_clip(template,samples,output):
    _,parents=baker.template_parts(template)
    metadata=metadata_for(parents,samples);order=parent_order(parents)
    bpy,Matrix=blender_api()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    armature=bpy.data.armatures.new('CartNativeSkeleton')
    obj=bpy.data.objects.new('CartClip',armature);bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active=obj;obj.select_set(True);obj.show_in_front=True
    rest={name:native_to_blender(samples[0]['bones'][name]) for name in order}
    bpy.ops.object.mode_set(mode='EDIT')
    for name in order:
        bone=armature.edit_bones.new(name);bone.length=.04
        bone.matrix=Matrix(matrix_rows(rest[name]))
        parent=parents[name]
        if parent is not None:
            bone.parent=armature.edit_bones[parent];bone.use_connect=False
    bpy.ops.object.mode_set(mode='POSE')
    for bone in obj.pose.bones:
        bone.rotation_mode='QUATERNION'
    scene=bpy.context.scene;scene.render.fps=FPS;scene.render.fps_base=1
    scene.frame_start=1;scene.frame_end=math.ceil(metadata['frames'][-1])
    previous={};old_interpolation=bpy.context.preferences.edit.keyframe_new_interpolation_type
    bpy.context.preferences.edit.keyframe_new_interpolation_type='LINEAR'
    try:
        for sample,frame in zip(samples,metadata['frames']):
            poses={name:native_to_blender(sample['bones'][name]) for name in order}
            for name in order:
                parent=parents[name]
                basis=pose_basis(rest[name],rest[parent] if parent else None,
                                 poses[parent] if parent else None,poses[name])
                location,rotation,scale=Matrix(matrix_rows(basis)).decompose()
                if max(abs(value-1) for value in scale)>1e-3:
                    raise ValueError(f'non-rigid Blender pose basis for {name}')
                if name in previous and rotation.dot(previous[name])<0:
                    rotation.negate()
                previous[name]=rotation.copy();bone=obj.pose.bones[name]
                bone.location=location;bone.rotation_quaternion=rotation;bone.scale=(1,1,1)
                bone.keyframe_insert(data_path='location',frame=frame,group=name)
                bone.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=name)
    finally:
        bpy.context.preferences.edit.keyframe_new_interpolation_type=old_interpolation
    obj.animation_data.action.name='CartClip'
    # keyframe_insert can ignore the user preference (Blender 4.5 creates
    # Bezier keys). Native tracks interpolate local positions and normalized
    # quaternions linearly, so set the actual action keys explicitly.
    for curve in obj.animation_data.action.fcurves:
        for key in curve.keyframe_points:
            key.interpolation='LINEAR'
    obj[PROPERTY]=json.dumps(metadata,separators=(',',':'))
    reconstructed=evaluated_samples(obj,metadata)
    error=max(abs(a-b) for source,actual in zip(samples,reconstructed) for name in parents
              for a,b in zip(source['bones'][name],actual['bones'][name]))
    if error>2e-4:
        raise ValueError(f'Blender sample roundtrip exceeded 0.0002: {error}')
    scene.frame_set(1);bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(output.resolve()))
    print(f'CART_BLENDER_IMPORTED samples={len(samples)} bones=45 maxMatrixError={error:.9g}')


def export_clip(input_path,output,timing='original',bake_fps=None,verify_output=None):
    bpy,_=blender_api()
    bpy.ops.wm.open_mainfile(filepath=str(input_path.resolve()),use_scripts=False)
    objects=[obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE' and PROPERTY in obj]
    if len(objects)!=1:
        raise ValueError('expected exactly one cart authoring armature')
    obj=objects[0];metadata=json.loads(obj[PROPERTY])
    if timing=='keys' or bake_fps is not None:
        metadata=authored_metadata(obj,metadata,bake_fps)
    samples=evaluated_samples(obj,metadata)
    output.write_text(json.dumps(samples,separators=(',',':'))+'\n')
    if verify_output is not None:
        frames=metadata['frames']
        dense=export_metadata(metadata,frames+[(a+b)/2 for a,b in zip(frames,frames[1:]) if (b-a)/FPS>4e-6])
        with verify_output.open('w') as stream:
            for sample in evaluated_samples(obj,dense):
                for name,matrix in sample['bones'].items():
                    stream.write('\t'.join(map(str,[sample['time'],name,*matrix]))+'\n')
    print(f'CART_BLENDER_EXPORTED samples={len(samples)} bones=45')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='command',required=True)
    incoming=commands.add_parser('import');incoming.add_argument('--template',type=Path,required=True)
    incoming.add_argument('--input',type=Path,required=True);incoming.add_argument('--output',type=Path,required=True)
    outgoing=commands.add_parser('export');outgoing.add_argument('--input',type=Path,required=True)
    outgoing.add_argument('--output',type=Path,required=True)
    outgoing.add_argument('--timing',choices=('original','keys'),default='original')
    outgoing.add_argument('--bake-fps',type=float)
    outgoing.add_argument('--verify-output',type=Path)
    if argv is None:
        argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    sources=[args.input]+([args.template] if args.command=='import' else [])
    outputs=[args.output]+([args.verify_output] if getattr(args,'verify_output',None) else [])
    if len({p.resolve() for p in outputs})!=len(outputs) or any(p.resolve() in [source.resolve() for source in sources] for p in outputs):
        parser.error('output must differ from input and template')
    if args.command=='import' and args.output.suffix.lower()!='.blend':
        parser.error('import output must be a .blend scene')
    try:
        if args.command=='import':
            import_clip(args.template.read_text(),json.loads(args.input.read_text()),args.output)
        else:
            export_clip(args.input,args.output,args.timing,args.bake_fps,args.verify_output)
    except (ValueError,OSError,RuntimeError,TypeError) as error:
        parser.error(str(error))


if __name__=='__main__':
    main()
