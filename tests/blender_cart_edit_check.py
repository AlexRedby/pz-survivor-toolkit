"""Blender integration helper: verify added/retimed keys, body edits and UI export.

Run explicitly with Blender --background --python-exit-code 1 --python THIS -- WORKSPACE.
Creates a separate verification scene/workspace inside WORKSPACE; never edits its source scene.
"""
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import bpy
import cart_clip_blender as bridge
from cart_blender_ui import CART_PT_workflow

path=Path(sys.argv[sys.argv.index('--')+1]).resolve()
config=json.loads((path/'workspace.json').read_text())
bpy.ops.wm.open_mainfile(filepath=config['scene'],use_scripts=False)
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE' and bridge.PROPERTY in o)
body=bpy.data.objects['CartPreviewBody']
original=json.loads(rig[bridge.PROPERTY]);moved_index=10
old=original['frames'][moved_index];new=old+.35
for curve in rig.animation_data.action.fcurves:
    for key in curve.keyframe_points:
        if float(key.co.x)==old:
            delta=new-old;key.co.x+=delta;key.handle_left.x+=delta;key.handle_right.x+=delta
    curve.update()
new=float(rig.animation_data.action.fcurves[0].keyframe_points[moved_index].co.x)
frame=(original['frames'][15]+original['frames'][16])/2
bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
def vertices():
    evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [v.co.copy() for v in evaluated.data.vertices]
a=vertices();bone=rig.pose.bones['Bip01_Spine'];bone.location.z+=.015
bone.keyframe_insert(data_path='location',frame=frame,group=bone.name)
for curve in rig.animation_data.action.fcurves:
    for key in curve.keyframe_points:key.interpolation='LINEAR'
bpy.context.view_layer.update();b=vertices();delta=max((p-q).length for p,q in zip(a,b));assert delta>.005,delta
metadata=bridge.authored_metadata(rig,original)
assert original['times'][moved_index] not in metadata['times']
assert abs(metadata['times'][moved_index]-(new-1)/60)<1e-7
assert any(abs(t-(frame-1)/60)<1e-7 for t in metadata['times'])
assert len(metadata['times'])==len(original['times'])+1
assert CART_PT_workflow.poll(bpy.context)
# Nonlinear edits must be explicitly sampled, never silently exported as old timestamps.
rig.animation_data.action.fcurves[0].keyframe_points[10].interpolation='BEZIER'
try:bridge.authored_metadata(rig,original)
except ValueError as error:assert 'bake' in str(error)
else:raise AssertionError('nonlinear export was silently accepted')
baked=bridge.authored_metadata(rig,original,60);assert len(baked['times'])>len(metadata['times'])
rig.animation_data.action.fcurves[0].keyframe_points[10].interpolation='LINEAR'
folder=path/'verification';folder.mkdir(exist_ok=True);config['scene']=str(folder/'edited.blend')
(folder/'workspace.json').write_text(json.dumps(config,indent=2)+'\n')
bpy.context.scene['cart_workspace']=str(folder/'workspace.json')
bpy.ops.wm.save_as_mainfile(filepath=config['scene'])
bpy.ops.wm.open_mainfile(filepath=config['scene'],use_scripts=False)
assert bpy.context.scene.objects['CartPreviewBody'].data.shape_keys is None
assert not bpy.app.handlers.frame_change_post
result=bpy.ops.cart.export_checked();assert result=={'FINISHED'},result
reports=list((folder/'exports').glob('*/report.json'));assert reports
report=json.loads(reports[-1].read_text());assert report['native_roundtrip']=='PASS'
(folder/'edit-proof.json').write_text(json.dumps({'live_mesh_delta':delta,'original_samples':len(original['times']),'edited_samples':len(metadata['times']),'bake60_samples':len(baked['times']),'new_and_retimed_keys':True,'save_reopen':True,'sidebar_export':True,'native_report':str(reports[-1]),'source_unchanged':report['source_unchanged_since_prepare']},indent=2)+'\n')
print('CART_EDIT_WORKFLOW_PASS',delta,report)
# Exercise the actual nonlinear export path, not just its timestamp selection.
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE' and bridge.PROPERTY in o)
curve=next(c for c in rig.animation_data.action.fcurves if c.data_path=='pose.bones["Bip01_Spine"].location' and c.array_index==2)
for key in curve.keyframe_points:
    key.interpolation='BEZIER';key.handle_left_type='AUTO';key.handle_right_type='AUTO'
curve.update();bpy.context.scene.cart_bake=True;bpy.context.scene.cart_bake_fps=60
result=bpy.ops.cart.export_checked();assert result=={'FINISHED'},result
reports=list((folder/'exports').glob('*/report.json'))
baked_reports=[p for p in reports if json.loads(p.read_text()).get('requested_bake_fps')==60]
assert baked_reports
print('CART_BEZIER_BAKE_PASS',baked_reports[-1])
