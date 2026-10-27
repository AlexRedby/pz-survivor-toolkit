"""Replay a captured native inventory-equip transition, including actual trousers.

Run with Blender --background --python tools/cart_blender_replay.py --
  --profile PROFILE --log LOG --game GAME --cart-fbx MODEL --output NEW_DIRECTORY

This is a measured replay, not a replacement pickup clip. The saved scene is
self-contained. Captured bones, skinning and cart placement are checked against
the evaluated Blender meshes at every captured sample. Missing unweighted Nub
bones inherit their parent; they do not influence either native mesh.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import cart_clip_blender as bridge
from cart_blender_preview import build_preview,parse_body
from cart_blender_scene import fbx_geometry


def source_rows(profile,log,scene):
    events=[]
    for line in log.read_text().splitlines():
        match=re.search(r'\[CART_APPROACH_EVENT\] (\{.*\})',line)
        if match:
            row=json.loads(match[1])
            if row['case']==scene:events.append(row)
    assert [row['event'] for row in events]==['prepared','queued','terminal','settled'],'Require one complete successful scene'
    first,end=events[0]['wall'],events[-1]['wall']
    tails=[json.loads(line) for line in (profile/'action-tail-poses.jsonl').read_text().splitlines()]
    tails=[row for row in tails if first<=row['wallTimeMillis']<=end]
    carts=[json.loads(line) for line in (profile/'body-clearance.jsonl').read_text().splitlines()]
    carts=[row for row in carts if first<=row['wallTimeMillis']<=end and row.get('model')=='WheelbarrowWood']
    assert len(tails)>20 and carts,'Missing native pose/cart captures'
    assert all(row.get('female') is False for row in tails),'This replay requires the captured male outfit'
    assert events[0].get('pantsModel','').lower()=='skinned/clothes/bob_trousers','Require actual baggy-jeans receipt'
    return events,tails,carts


def skin_points(body,bones):
    from mathutils import Matrix,Vector
    points=[Vector((0,0,0)) for _ in body.vertices]
    for name,weight in body.skin.items():
        if not weight.indices:continue
        transform=Matrix(bridge.matrix_rows(bones[name]))@Matrix(bridge.matrix_rows(weight.offset))
        for index,amount in zip(weight.indices,weight.weights):
            points[index]+=amount*(transform@Vector(body.vertices[index]))
    basis=Matrix(bridge.matrix_rows(bridge.MODEL_BASIS))
    return [basis@point for point in points]


def build(args):
    import bpy
    from mathutils import Matrix,Vector
    events,rows,carts=source_rows(args.profile,args.log,args.scene)
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    template=(args.game/'media/anims_X/Bob/Bob_Idle.x').read_text()
    _,parents=bridge.baker.template_parts(template)
    origin=rows[0]['wallTimeMillis'];samples=[]
    for row in rows:
        bones=dict(row['bones'])
        for name in bridge.parent_order(parents):
            if name not in bones:
                assert name.endswith('Nub') and parents[name] in bones,'Missing a native influencing bone'
                bones[name]=bones[parents[name]]
        samples.append(dict(time=(row['wallTimeMillis']-origin)/1000,bones=bones))
    scene_path=output/'replay.blend'
    bridge.import_clip(template,samples,scene_path)
    rig=bpy.data.objects['CartClip'];rig.name='Native transition replay'
    body_path=args.game/'media/models_X/Skinned/MaleBody.x'
    pants_path=args.game/'media/models_X/Skinned/Clothes/Bob_Trousers.x'
    body=build_preview(rig,body_path);body.name='Native body'
    pants=build_preview(rig,pants_path,mesh_name='Bob_Trousers');pants.name='Worn baggy jeans'
    for polygon in pants.data.polygons:polygon.use_smooth=False
    material=bpy.data.materials.new('Jeans');material.diffuse_color=(.06,.14,.27,1)
    hit=bpy.data.materials.new('Measured contact faces 9 and 20');hit.diffuse_color=(1,.06,.015,1)
    pants.data.materials.clear();pants.data.materials.append(material);pants.data.materials.append(hit)
    for polygon in pants.data.polygons:polygon.material_index=int(polygon.index in (9,20))
    scene=bpy.context.scene
    vertices,faces=fbx_geometry(args.cart_fbx)
    mesh=bpy.data.meshes.new('Actual wooden cart FBX');mesh.from_pydata(vertices,[],faces);mesh.update()
    cart=bpy.data.objects.new('Native cart',mesh);scene.collection.objects.link(cart)
    wood=bpy.data.materials.new('Wood');wood.diffuse_color=(.35,.17,.055,1);mesh.materials.append(wood)
    delta=bpy.data.objects.new('Editable cart correction',None);scene.collection.objects.link(delta);cart.parent=delta
    delta['scope']='Candidate offset in Blender model axes. Replay only until exported and applied by runtime.'
    basis=Matrix(bridge.matrix_rows(bridge.MODEL_BASIS))
    cart.rotation_mode='QUATERNION'
    for captured in carts:
        frame=1+60*(captured['wallTimeMillis']-origin)/1000
        cart.matrix_basis=basis@Matrix(bridge.matrix_rows(captured['cart']))
        for prop in ('location','rotation_quaternion','scale'):cart.keyframe_insert(prop,frame=frame)
    for sample,row in zip(samples,rows):
        frame=1+60*sample['time']
        cart.hide_render=not row.get('cartModel',False);cart.hide_viewport=cart.hide_render
        for prop in ('hide_render','hide_viewport'):cart.keyframe_insert(prop,frame=frame)
    for curve in cart.animation_data.action.fcurves:
        for key in curve.keyframe_points:key.interpolation='CONSTANT' if curve.data_path.startswith('hide_') else 'LINEAR'
    # Verify the evaluated live modifiers, not just the imported bone matrices.
    native_models=[(body,parse_body(body_path.read_text())),(pants,parse_body(pants_path.read_text(),mesh_name='Bob_Trousers'))]
    error=0.
    for sample in samples:
        frame=1+60*sample['time'];scene.frame_set(int(frame),subframe=frame-int(frame))
        graph=bpy.context.evaluated_depsgraph_get()
        for obj,native in native_models:
            actual=obj.evaluated_get(graph)
            expected=skin_points(native,sample['bones'])
            error=max(error,max((point-vertex.co).length for point,vertex in zip(expected,actual.data.vertices)))
    assert error<2e-5,f'Native/Blender skinning mismatch: {error}'
    cart_error=0.
    for captured in carts:
        frame=1+60*(captured['wallTimeMillis']-origin)/1000
        scene.frame_set(int(frame),subframe=frame-int(frame))
        measured=basis@Matrix(bridge.matrix_rows(captured['cart']))
        actual=cart.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world
        cart_error=max(cart_error,max(abs(measured[i][j]-actual[i][j]) for i in range(4) for j in range(4)))
    assert cart_error<2e-4,f'Native/Blender cart matrix mismatch: {cart_error}'
    scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1280;scene.render.resolution_y=720
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True
    scene.world=bpy.data.worlds.new('Replay studio');scene.world.color=(.2,.22,.25)
    scene.view_settings.view_transform='Standard';scene.render.fps=60
    scene.frame_end=round(1+60*samples[-1]['time'])
    def camera(name,location,target,scale):
        data=bpy.data.cameras.new(name);obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj)
        obj.location=location;obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
        data.type='ORTHO';data.ortho_scale=scale;return obj
    scene.camera=camera('Contact close-up',(1.2,-1.1,.58),(.09,.0,.45),.38)
    camera('Whole transition',(2.4,-1.6,1.3),(0,.1,.45),1.9)
    for event in events:
        marker=scene.timeline_markers.new(event['event']);marker.frame=round(1+60*(event['wall']-origin)/1000)
    scene['capture_origin_wall_ms']=str(origin);scene['native_skinning_max_error']=error
    scene['inventory_loot_weights']=json.dumps([{'frame':1+60*sample['time'],
        'held':row.get('cartModel',False),
        'weight':max([track['weight'] for track in row.get('tracks',[]) if track['name']=='Bob_IdleLooting_Mid'] or [0])}
        for sample,row in zip(samples,rows)])
    scene['scope']='Measured inventory equip replay, including outgoing Loot blend. Red trousers faces mark the original contact location.'
    scene.tool_settings.use_keyframe_insert_auto=True
    bpy.ops.object.select_all(action='DESELECT');delta.select_set(True);bpy.context.view_layer.objects.active=delta
    contact=events[2]['wall']+250
    scene.frame_set(round(1+60*(contact-origin)/1000))
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
    bpy.ops.wm.save_as_mainfile(filepath=str(scene_path))
    report={'schema':'pz-cart-native-replay-v1','scene':args.scene,'originWallMillis':origin,
            'samples':len(samples),'nativeSkinningMaxError':error,'tolerance':2e-5,
            'nativeCartMatrixMaxError':cart_error,'cartMatrixTolerance':2e-4,
            'missingUnweightedNubs':10,'authoringSkeletonBones':45,'capturedBones':35,
            'sourceHashes':{name:hashlib.sha256((args.profile/name).read_bytes()).hexdigest() for name in ('action-tail-poses.jsonl','body-clearance.jsonl')},
            'nativeCartPairingLimit':'Cart matrices keyed and verified at actual held-capture timestamps; interpolated display between those samples, hidden before held.',
            'runtimeFixApplied':False}
    (output/'replay-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('profile','log','game','cart-fbx','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scene',choices=['container-equip'],default='container-equip')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);build(args)


if __name__=='__main__':main()
