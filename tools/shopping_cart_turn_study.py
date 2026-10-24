"""Author a world-space shopping turn study inside Blender; never install game assets.

Example (external game/model inputs remain owned by their installations):
  Blender --background --python tools/shopping_cart_turn_study.py -- \
    --game GAME_JAVA --jdk JDK --kotlin-home KOTLIN --cart-fbx ShoppingCart_PZ.fbx \
    --output build/blender/shopping-turn-study --render

The generated .blend and JSON are a motion study, not directly playable gait clips:
world translation/yaw are baked for viewing. Runtime extraction/selection is separate.
"""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import cart_clip_blender as bridge
from cart_blender_preview import build_preview
from cart_blender_scene import fbx_geometry


def smooth(t):
    t = max(0., min(1., t))
    return t*t*t*(10+t*(-15+6*t))


def main(args):
    import bpy
    from mathutils import Matrix, Vector
    sys.path.insert(0, str(ROOT))
    from JavaPatches.build import require_current_patch_jar
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    patch = ROOT / 'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
    require_current_patch_jar(patch, ROOT / 'JavaPatches')
    template = (args.game / 'media/anims_X/Bob/Bob_Idle.x').read_text()
    _, parents = bridge.baker.template_parts(template)
    names = bridge.parent_order(parents)
    base = json.loads((ROOT / 'assets/animations/cart_pivot_idle.json').read_text())[0]['bones']
    neutral = {n: Matrix(bridge.matrix_rows(bridge.native_to_blender(base[n]))) for n in names}
    descendants = {n: [c for c in names if c == n or n in ancestors(c, parents)] for n in names}
    def native(poses):
        return {n: bridge.blender_to_native(bridge.column_matrix(poses[n])) for n in names}
    def csv(path, frames):
        with path.open('w') as f:
            f.write(','.join(names)+'\n')
            f.write(','.join(str(names.index(parents[n])) if parents[n] else '-1' for n in names)+'\n')
            for time, poses in frames:
                model_poses = native(poses)
                f.write(','.join(map(str, [time, *(v for n in names for v in model_poses[n])]))+'\n')
    def run(command, log):
        with log.open('w') as f:
            subprocess.run(list(map(str, command)), stdout=f, stderr=subprocess.STDOUT, check=True, timeout=120)
    classpath = os.pathsep.join(map(str, [patch, args.game/'projectzomboid.jar']))
    classes = output/'classes'; classes.mkdir()
    from cart_jvm import patch_build
    build = patch_build()
    build.compile_kotlin(args.jdk, args.kotlin_home,
        str(args.kotlin_home/'lib/kotlin-stdlib.jar')+os.pathsep+classpath, classes,
        [ROOT/'tools/ShoppingTurnStudyFit.kt'], module_name='shopping_study',
        options=['-Xfriend-paths='+str(patch)], run=lambda command: run(command,output/'compile.log'))
    build.stage_kotlin_runtime(args.kotlin_home, classes)
    relocator = build.build_kotlin_relocator(args.jdk,args.kotlin_home,output,
        run=lambda command: run(command,output/'relocator-compile.log'))
    run([*relocator,classes,'--tests'],output/'relocator.log')
    java = [args.jdk/'bin/java', '-Xmx384m', '-Djava.awt.headless=true', '-cp', str(classes)+os.pathsep+classpath, 'ShoppingTurnStudyFit']
    def translate(poses, bone, delta):
        move = Matrix.Translation(delta)
        for n in descendants[bone]: poses[n] = move @ poses[n]
    def aim(poses, bone, child, target):
        origin = poses[bone].translation.copy()
        before = poses[child].translation-origin
        after = target-origin
        q = before.rotation_difference(after)
        change = Matrix.Translation(origin) @ q.to_matrix().to_4x4() @ Matrix.Translation(-origin)
        for n in descendants[bone]: poses[n] = change @ poses[n]
    def orient(poses, bone, target):
        origin = poses[bone].translation.copy()
        change = Matrix.Translation(origin) @ (target.to_3x3() @ poses[bone].to_3x3().inverted()).to_4x4() @ Matrix.Translation(-origin)
        for n in descendants[bone]: poses[n] = change @ poses[n]
    def solve_leg(poses, side, foot):
        thigh, calf, ankle = ['Bip01_'+side+'_'+n for n in ('Thigh','Calf','Foot')]
        hip = poses[thigh].translation.copy(); end = foot.translation
        a = (neutral[calf].translation-neutral[thigh].translation).length
        b = (neutral[ankle].translation-neutral[calf].translation).length
        offset = end-hip; distance = offset.length
        if not abs(a-b)+1e-5 < distance < a+b-1e-5:
            raise ValueError(f'Unreachable {side} leg: {distance:.6f}, reach {a+b:.6f}')
        axis = offset.normalized()
        foot_turn = foot.to_quaternion() @ feet0[side].to_quaternion().inverted()
        pole = (foot_turn @ Vector((0,1,0)) + Vector((0,1,0))).normalized()
        pole -= axis*pole.dot(axis)
        pole.normalize(); along = (a*a-b*b+distance*distance)/(2*distance)
        knee = hip+axis*along+pole*math.sqrt(max(0., a*a-along*along))
        aim(poses, thigh, calf, knee); aim(poses, calf, ankle, end); orient(poses, ankle, foot)
        assert (poses[ankle].translation-end).length < 1e-5
    # Preserve the native foot's full orientation and toe offset; lift the measured sole to Z=0.
    soles = .001546
    feet0 = {s: neutral['Bip01_'+s+'_Foot'].copy() for s in ('L','R')}
    for foot in feet0.values(): foot.translation.z += soles
    def pose(world, feet, left_weight=.5):
        poses = {n: m.copy() for n,m in neutral.items()}
        inv = world.inverted(); local_feet = {s: inv @ feet[s] for s in feet}
        desired = world @ neutral['Bip01_Pelvis'].translation
        support_blend = .5+.18*(left_weight-.5)
        ankle_center = feet['L'].translation*support_blend+feet['R'].translation*(1-support_blend)
        neutral_ankles = (feet0['L'].translation+feet0['R'].translation)*.5
        offset = neutral['Bip01_Pelvis'].translation-neutral_ankles
        forward_offset = world.to_3x3() @ Vector((offset.x,offset.y,0))
        target = ankle_center+forward_offset
        difference = Vector((target.x-desired.x,target.y-desired.y,0))
        if difference.length > .075: difference *= .075/difference.length
        local_shift = inv.to_3x3() @ difference
        local_shift.z = -.022
        # Support-relative weight transfer reduces the reach needed by the planted leg.
        translate(poses, 'Bip01_Pelvis', local_shift)
        extra = 0.
        for s in feet:
            hip = poses['Bip01_'+s+'_Thigh'].translation
            end = local_feet[s].translation
            a = (neutral['Bip01_'+s+'_Calf'].translation-neutral['Bip01_'+s+'_Thigh'].translation).length
            b = (neutral['Bip01_'+s+'_Foot'].translation-neutral['Bip01_'+s+'_Calf'].translation).length
            horizontal = (Vector((hip.x,hip.y))-Vector((end.x,end.y))).length
            reach = a+b-.008
            if horizontal >= reach: raise ValueError('Step exceeds horizontal leg reach')
            extra = min(extra, end.z+math.sqrt(reach*reach-horizontal*horizontal)-hip.z)
        translate(poses, 'Bip01_Pelvis', Vector((0,0,extra)))
        for s in feet: solve_leg(poses, s, local_feet[s])
        return poses
    seed = pose(Matrix.Identity(4), feet0)
    csv(output/'seed.csv', [(0., seed)])
    run([*java, 'geometry', output/'seed.csv', output/'geometry.json'], output/'geometry.log')
    geometry = json.loads((output/'geometry.json').read_text())
    cart_local = Matrix(bridge.matrix_rows(bridge.MODEL_BASIS)) @ Matrix(bridge.matrix_rows(geometry['cart']))
    rear = Vector((geometry['rear'][0], -geometry['rear'][2], 0))
    radius = rear.y
    (output/'cart-matrix.csv').write_text(','.join(map(str, geometry['cart'])))
    settings = dict(schema='shopping-turn-study-v1', scope='Offline world-space draft; not an installed or runtime-ready gait.',
                    degrees=args.degrees, direction=args.direction, step_seconds=.44, degrees_per_step=45,
                    pre_seconds=.28, post_seconds=.32, swing_height=.045, swing_window=[.10,.76],
                    rear=list(rear), radius=radius, source_clip='cart_pivot_idle.json', playback_rate=1)
    (output/'study.json').write_text(json.dumps(settings, indent=2)+'\n')
    sign = 1 if args.direction == 'left' else -1
    count = round(args.degrees/45); step = settings['step_seconds']; pre = settings['pre_seconds']
    # One final collecting step places the foot that still trails at the final heading.
    duration = pre + (count+1)*step + settings['post_seconds']
    total = round(duration*60)
    def heading(time):
        u = max(0., min(count*step, time-pre))
        # Equal total angle with a brief continuous acceleration/deceleration, not a stop per foot.
        length = count*step; ramp = .12; speed = math.radians(args.degrees)/(length-ramp)
        if u < ramp: distance = speed*u*u/(2*ramp)
        elif u > length-ramp: distance = math.radians(args.degrees)-speed*(length-u)**2/(2*ramp)
        else: distance = speed*(u-ramp/2)
        return sign*distance
    def world_at(time):
        rot = Matrix.Rotation(heading(time), 4, 'Z')
        return Matrix.Translation(rear) @ rot @ Matrix.Translation(-rear)
    # +X foot leads when the cart nose turns left: the handles travel to the operator's right.
    leading = 'L' if sign > 0 else 'R'
    plan = []; previous = {s: m.copy() for s,m in feet0.items()}
    for i in range(count+1):
        side = leading if i%2 == 0 else ('R' if leading == 'L' else 'L')
        target = world_at(pre+min(i+1,count)*step) @ feet0[side]
        plan.append((side, previous[side].copy(), target, pre+i*step))
        previous[side] = target
    raw=[]; traces=[]; max_leg_error=0.; min_knee=180.; max_drop=0.
    for frame in range(total+1):
        time=frame/60; feet={s:m.copy() for s,m in feet0.items()}; supports={s:True for s in feet}
        left_weight=.5+((0 if leading == 'L' else 1)-.5)*smooth(time/pre)
        for i,(side,start,end,begin) in enumerate(plan):
            phase=(time-begin)/step
            if phase<0: break
            u=(phase-.10)/.66; w=smooth(u)
            rotation=start.to_quaternion().slerp(end.to_quaternion(),w)
            a=start.translation-rear; b=end.translation-rear
            angle_a=math.atan2(a.y,a.x)
            angle_delta=math.atan2(math.sin(math.atan2(b.y,b.x)-angle_a),math.cos(math.atan2(b.y,b.x)-angle_a))
            distance=math.hypot(a.x,a.y)*(1-w)+math.hypot(b.x,b.y)*w
            angle=angle_a+angle_delta*w
            location=Vector((rear.x+distance*math.cos(angle),rear.y+distance*math.sin(angle),start.translation.z*(1-w)+end.translation.z*w))
            if 0<u<1: location.z+=settings['swing_height']*math.sin(math.pi*u)**2
            feet[side]=Matrix.LocRotScale(location,rotation,Vector((1,1,1)))
            supports[side]=not 0<u<1
            transfer=smooth((phase-.76)/.24)
            left_weight=transfer if side=='L' else 1-transfer
        if time>pre+(count+1)*step:
            left_weight=left_weight+(.5-left_weight)*smooth((time-pre-(count+1)*step)/settings['post_seconds'])
        world=world_at(time)
        local=pose(world,feet,left_weight)
        for side in feet:
            ids=['Bip01_'+side+'_'+n for n in ('Thigh','Calf','Foot')]
            upper=local[ids[0]].translation-local[ids[1]].translation
            lower=local[ids[2]].translation-local[ids[1]].translation
            min_knee=min(min_knee,math.degrees(upper.angle(lower)))
            for a,b in zip(ids,ids[1:]):
                max_leg_error=max(max_leg_error, abs((local[b].translation-local[a].translation).length-(neutral[b].translation-neutral[a].translation).length))
        max_drop=max(max_drop,neutral['Bip01_Pelvis'].translation.z-local['Bip01_Pelvis'].translation.z)
        traces.append(dict(time=time,heading=heading(time),world=bridge.column_matrix(world),
                           feet={s:bridge.column_matrix(m) for s,m in feet.items()},support=supports,left_weight=left_weight))
        raw.append((time,local))
    csv(output/'local-input.csv',raw)
    run([*java,'fit',output/'local-input.csv',output/'local-poses.json',output/'cart-matrix.csv'],output/'grip.log')
    fitted=json.loads((output/'local-poses.json').read_text());samples=[]
    basis=Matrix(bridge.matrix_rows(bridge.MODEL_BASIS));base_inverse=basis.inverted()
    max_foot_error=0.;max_planted_drift=0.
    for row,trace in zip(fitted,traces):
        world=Matrix(bridge.matrix_rows(trace['world']));change=base_inverse@world@basis
        models={n:bridge.column_matrix(change@Matrix(bridge.matrix_rows(row['bones'][n]))) for n in names}
        samples.append(dict(time=row['time'],bones=models))
        for side in feet0:
            actual=Matrix(bridge.matrix_rows(bridge.native_to_blender(models['Bip01_'+side+'_Foot'])))
            expected=Matrix(bridge.matrix_rows(trace['feet'][side]))
            max_foot_error=max(max_foot_error,max(abs(actual[r][c]-expected[r][c]) for r in range(4) for c in range(4)))
    for a,b in zip(traces,traces[1:]):
        for side in feet0:
            if a['support'][side] and b['support'][side]:
                ma=Matrix(bridge.matrix_rows(a['feet'][side]));mb=Matrix(bridge.matrix_rows(b['feet'][side]))
                max_planted_drift=max(max_planted_drift,(ma.translation-mb.translation).length)
    assert max_leg_error<2e-5 and max_foot_error<2e-5 and max_planted_drift<1e-6, (max_leg_error,max_foot_error,max_planted_drift)
    (output/'world-poses.json').write_text(json.dumps(samples,separators=(',',':')))
    (output/'contacts.json').write_text(json.dumps(traces,separators=(',',':')))
    scene_path=output/'study.blend';bridge.import_clip(template,samples,scene_path)
    rig=bpy.data.objects['CartClip'];body=build_preview(rig,args.game/'media/models_X/Skinned/MaleBody.x')
    # Hide covered study-body faces beneath the actual native trousers.
    pants=build_preview(rig,args.game/'media/models_X/Skinned/Clothes/Bob_Trousers.x',mesh_name='Bob_Trousers')
    pants.name='Native trousers'
    from cart_blender_preview import parse_body,skin_vertices
    initial_surface=skin_vertices(parse_body((args.game/'media/models_X/Skinned/MaleBody.x').read_text()),samples[0]['bones'])
    import bmesh
    editable=bmesh.new();editable.from_mesh(body.data)
    editable.verts.ensure_lookup_table()
    bmesh.ops.delete(editable,geom=[f for f in editable.faces if f.material_index==2 or max(initial_surface[v.index][2] for v in f.verts)<.56],context='FACES')
    editable.to_mesh(body.data);editable.free()
    scene=bpy.context.scene
    def material(name,color):
        m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);return m
    pants.data.materials.clear();pants.data.materials.append(material('Trousers',(.10,.19,.28)))
    for polygon in pants.data.polygons: polygon.material_index=0
    vertices,faces=fbx_geometry(args.cart_fbx)
    mesh=bpy.data.meshes.new('ShoppingCart original FBX');mesh.from_pydata(vertices,[],faces);mesh.update()
    cart=bpy.data.objects.new('Actual held shopping cart',mesh);scene.collection.objects.link(cart)
    mesh.materials.append(material('Cart steel',(.62,.66,.69)));cart.rotation_mode='QUATERNION'
    for trace in traces:
        world=Matrix(bridge.matrix_rows(trace['world']));cart.matrix_world=world@cart_local
        for prop in ('location','rotation_quaternion','scale'):cart.keyframe_insert(prop,frame=1+60*trace['time'])
    for curve in cart.animation_data.action.fcurves:
        for key in curve.keyframe_points:key.interpolation='LINEAR'
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002))
    floor=bpy.context.object;floor.name='Sole ground';floor.data.materials.append(material('Floor',(.19,.21,.24)))
    # A fixed axle marker makes the orbit visible; it is not a replacement rendered wheel.
    bpy.ops.mesh.primitive_torus_add(major_radius=.028,minor_radius=.003,location=(rear.x,rear.y,.004))
    bpy.context.object.name='Rear axle pivot marker';bpy.context.object.data.materials.append(material('Pivot',(.94,.48,.08)))
    for side,color in [('L',(.95,.42,.12)),('R',(.12,.65,.93))]:
        for i,(s,start,end,begin) in enumerate(plan):
            if s!=side:continue
            p=end.translation
            bpy.ops.mesh.primitive_torus_add(major_radius=.022,minor_radius=.0014,location=(p.x,p.y,.002))
            bpy.context.object.data.materials.append(material('Foot landing '+side,color))
    scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1280;scene.render.resolution_y=720
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL'
    scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
    scene.world=bpy.data.worlds.new('Study world');scene.world.color=(.22,.24,.27)
    scene.view_settings.view_transform='Standard';scene.render.fps=60;scene.frame_end=total+1
    camera_data=bpy.data.cameras.new('Study camera');camera=bpy.data.objects.new('Study camera',camera_data);scene.collection.objects.link(camera)
    camera.location=(2.0,-2.3,1.8);target=Vector((rear.x,rear.y,.42))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.type='ORTHO';camera_data.ortho_scale=2.3;scene.camera=camera
    rig.hide_render=True;rig.hide_set(True)
    scene['study_scope']=settings['scope'];scene['playback_rate']=1
    # Compare evaluated clothing deformation to independent direct native LBS at stance/swing samples.
    pants_source=parse_body((args.game/'media/models_X/Skinned/Clothes/Bob_Trousers.x').read_text(),mesh_name='Bob_Trousers')
    max_skin_error=0.
    for i in range(0,len(samples),max(1,len(samples)//12)):
        scene.frame_set(1+i)
        evaluated=pants.evaluated_get(bpy.context.evaluated_depsgraph_get())
        expected=skin_vertices(pants_source,samples[i]['bones'])
        max_skin_error=max(max_skin_error,max((Vector(point)-vertex.co).length for point,vertex in zip(expected,evaluated.data.vertices)))
    assert max_skin_error<2e-5, max_skin_error
    scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(scene_path))
    report=dict(scope=settings['scope'],samples=len(samples),duration_seconds=duration,
                max_leg_length_error=max_leg_error,max_foot_target_error=max_foot_error,
                max_planted_drift=max_planted_drift,max_pelvis_lowering=max_drop,min_knee_degrees=min_knee,
                max_clothing_skin_error=max_skin_error,
                cart_rear_orbit_radius=radius,grip_check=(output/'grip.log').read_text().strip(),
                limitation='Authored nominal arc only. Not a native gameplay, transition, collision, or Host check.')
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('SHOPPING_TURN_STUDY_READY',json.dumps(report),flush=True)
    if args.render:
        frames=output/'frames';frames.mkdir();scene.frame_step=2;scene.render.filepath=str(frames/'frame-')
        bpy.ops.render.render(animation=True)


def ancestors(name,parents):
    result=[]
    while parents[name] is not None:
        name=parents[name];result.append(name)
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game',type=Path,required=True);parser.add_argument('--jdk',type=Path,required=True)
    parser.add_argument('--kotlin-home',type=Path,required=True);parser.add_argument('--cart-fbx',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--render',action='store_true')
    parser.add_argument('--degrees',type=int,choices=[90,180],default=180)
    parser.add_argument('--direction',choices=['left','right'],default='left')
    main(parser.parse_args(sys.argv[sys.argv.index('--')+1:]))
