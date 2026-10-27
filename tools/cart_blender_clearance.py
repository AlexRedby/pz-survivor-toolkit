"""Author/export a cart correction envelope in Blender's Graph Editor.

Blender --background --python this_file -- prepare SCENE.blend OUTPUT_DIRECTORY
Blender --background --python this_file -- export AUTHORED.blend OUTPUT_DIRECTORY

The envelope parameter is the retired share (1 - outgoing Loot blend weight),
not wall time or pickup progress. Output is a bounded data asset and a Kotlin
linear sampler generated from the evaluated Blender F-curve. Runtime activation
and native IK still need an isolated game check.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys


def prepare(source,output):
    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()),use_scripts=False)
    output.mkdir(parents=True,exist_ok=False)
    curve=bpy.data.objects.new('Equip clearance envelope',None);bpy.context.scene.collection.objects.link(curve)
    curve['parameter']='frame 1..61 = retired share 0..1 of outgoing Bob_IdleLooting_Mid'
    curve['units']='Native model-space forward advance; positive Blender Y corresponds to native -Z'
    # Deliberately author a short, shallow curve; endpoints remain exactly zero.
    for progress,advance in ((0,0),(.18,.003),(.5,.008),(.82,.006),(1,0)):
        curve.location.y=advance;curve.keyframe_insert('location',index=1,frame=1+60*progress)
    action=curve.animation_data.action;action.name='Wood cart equip clearance'
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation='BEZIER';key.handle_left_type='AUTO_CLAMPED';key.handle_right_type='AUTO_CLAMPED'
        first,last=fcurve.keyframe_points[0],fcurve.keyframe_points[-1]
        first.handle_right_type='FREE';first.handle_right=(4.6,0)
        last.handle_left_type='FREE';last.handle_left=(57.4,0)
    replay=bpy.context.scene.get('inventory_loot_weights')
    if replay:
        delta=bpy.data.objects['Editable cart correction']
        delta.animation_data_clear();delta.location=(0,0,0)
        progress=bpy.data.objects.new('Recorded inventory retired share',None)
        bpy.context.scene.collection.objects.link(progress)
        for row in json.loads(replay):
            progress.location.x=1-row['weight'] if row['held'] else 0
            progress.keyframe_insert('location',index=0,frame=row['frame'])
        for fcurve in progress.animation_data.action.fcurves:
            for key in fcurve.keyframe_points:key.interpolation='LINEAR'
        live=delta.constraints.new('ACTION');live.name='Live envelope at recorded native blend'
        live.target=progress;live.transform_channel='LOCATION_X';live.min=0;live.max=1
        live.frame_start=1;live.frame_end=61;live.action=action;live.mix_mode='REPLACE'
        delta['scope']='Live Action constraint evaluates edited curve at recorded Loot weights; arms remain recorded, native IK must be checked in PZ.'
        probe=min((row for row in json.loads(replay) if row['held']),key=lambda row:abs(row['weight']-.5))
        frame=probe['frame'];scene=bpy.context.scene
        def observed():
            scene.frame_set(int(frame),subframe=frame-int(frame));graph=bpy.context.evaluated_depsgraph_get()
            share=progress.evaluated_get(graph).matrix_world.translation.x
            actual=delta.evaluated_get(graph).matrix_world.translation.y
            expected=float(action.fcurves[0].evaluate(1+60*share))
            assert abs(actual-expected)<2e-6,'Live Blender preview disagrees with exported curve'
            return actual
        before=observed();original_action=action.copy();key=action.fcurves[0].keyframe_points[2]
        key.co.y+=.001;action.fcurves[0].update();changed=observed()
        assert changed-before>.0005,'Graph Editor edits do not update the cart preview'
        mutated=action;action=original_action;curve.animation_data.action=action;live.action=action
        assert abs(observed()-before)<1e-7
        bpy.data.actions.remove(mutated)
        scene['live_clearance_edit_check']='PASS: envelope edits update the evaluated cart correction'
    bpy.ops.object.select_all(action='DESELECT');curve.select_set(True);bpy.context.view_layer.objects.active=curve
    bpy.ops.wm.save_as_mainfile(filepath=str((output/'authored.blend').resolve()))


def kotlin_sampler(values):
    array=',\n        '.join(','.join(f'{v:.10g}f' if v else '0f' for v in values[i:i+8]) for i in range(0,len(values),8))
    return '''package net.alexredby.pztoolkitjavapatches

/** Generated from Blender's evaluated clearance curve; regenerate with tools/cart_blender_clearance.py. */
internal object CartEquipClearanceCurve {
    private val ADVANCE = floatArrayOf(
        ARRAY
    )
    @JvmStatic
    fun sample(retiredShare: Float): Float {
        if (!java.lang.Float.isFinite(retiredShare) || retiredShare <= 0 || retiredShare >= 1) return 0f
        val position = retiredShare * (ADVANCE.size - 1)
        val index = Math.min(ADVANCE.size - 2, position.toInt())
        return ADVANCE[index] + (position - index) * (ADVANCE[index + 1] - ADVANCE[index])
    }
}
'''.replace('ARRAY',array)


def export(source,output):
    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()),use_scripts=False)
    obj=bpy.data.objects['Equip clearance envelope'];action=obj.animation_data.action
    curves=[curve for curve in action.fcurves if curve.data_path=='location' and curve.array_index==1]
    assert len(curves)==1 and not curves[0].modifiers and not curves[0].mute,'Require one unmodified clearance curve'
    curve=curves[0]
    def value(progress):return float(curve.evaluate(1+60*progress))
    output.mkdir(parents=True,exist_ok=False)
    count=120
    while True:
        values=[value(i/count) for i in range(count+1)]
        assert abs(values[0])<1e-8 and abs(values[-1])<1e-8,'Both endpoints must remain zero'
        assert all(0<=point<=.02 for point in values),'Bounded forward-only envelope required'
        values[0]=values[-1]=0.
        def linear(progress):
            scaled=progress*count;index=min(count-1,int(scaled));amount=scaled-index
            return values[index]+amount*(values[index+1]-values[index])
        error=max(abs(value(i/(10*count))-linear(i/(10*count))) for i in range(10*count+1))
        if error<2e-6:break
        assert count<1920,f'Blender/runtime curve approximation too coarse: {error}'
        count*=2
    data={'schema':'pz-cart-clearance-curve-v1','parameter':'retired outgoing inventory Loot share',
          'axis':'native negative model Z','samples':values,'maximumApproximationError':error,
          'sourceBlendSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
          'scope':'Wooden inventory-equip transition; runtime gating and native grip remain separate.'}
    (output/'wood_cart_equip_clearance.json').write_text(json.dumps(data,indent=2)+'\n')
    (output/'CartEquipClearanceCurve.kt').write_text(kotlin_sampler(values))
    (output/'report.json').write_text(json.dumps({'blenderEvaluatedSamples':len(values),'maxApproximationError':error,'endpointsZero':True,'runtimeTested':False},indent=2)+'\n')
    print(json.dumps(data,indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation',choices=['prepare','export']);parser.add_argument('source',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    (prepare if args.operation=='prepare' else export)(args.source,args.output)


if __name__=='__main__':main()
