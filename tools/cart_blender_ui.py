"""Session-only sidebar. Loaded explicitly by cart_blender.py edit, never by .blend auto-run."""
import json
from pathlib import Path
import subprocess
import sys
import bpy
from bpy.props import BoolProperty,IntProperty


class CART_OT_export(bpy.types.Operator):
    bl_idname='cart.export_checked';bl_label='Save + Export to PZ';bl_description='Save this scene and create a separate native-verified export snapshot'
    def execute(self,context):
        try:
            path=Path(context.scene['cart_workspace']);config=json.loads(path.read_text())
            bpy.ops.wm.save_as_mainfile(filepath=config['scene'])
            command=[config['python'],str(Path(config['root'])/'tools/cart_blender.py'),'export',str(path.parent)]
            if context.scene.cart_bake:command+=['--bake-fps',str(context.scene.cart_bake_fps)]
            result=subprocess.run(command,capture_output=True,text=True)
            text=bpy.data.texts.get('LAST EXPORT') or bpy.data.texts.new('LAST EXPORT');text.clear();text.write(result.stdout+result.stderr)
            if result.returncode:
                self.report({'ERROR'},'Export failed; see LAST EXPORT in Text Editor or exports/* logs');return {'CANCELLED'}
            self.report({'INFO'},result.stdout.splitlines()[0]);return {'FINISHED'}
        except (OSError,KeyError,ValueError) as error:
            self.report({'ERROR'},str(error));return {'CANCELLED'}


class CART_PT_workflow(bpy.types.Panel):
    bl_label='PZ Cart Animation';bl_idname='CART_PT_workflow';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='PZ Cart'
    @classmethod
    def poll(cls,context):return 'cart_workspace' in context.scene
    def draw(self,context):
        layout=self.layout;scene=context.scene
        layout.label(text='Live body preview')
        layout.prop(scene.tool_settings,'use_keyframe_insert_auto',text='Auto Key')
        layout.prop(scene,'cart_bake',text='Bake curves / constraints')
        if scene.cart_bake:layout.prop(scene,'cart_bake_fps',text='Bake FPS')
        layout.operator('cart.export_checked',icon='EXPORT')
        layout.label(text='Exports stay separate from game files.',icon='INFO')
        layout.label(text='Runtime grip / transitions: check in PZ.')


for cls in (CART_OT_export,CART_PT_workflow):bpy.utils.register_class(cls)
bpy.types.Scene.cart_bake=BoolProperty(name='Bake',default=False)
bpy.types.Scene.cart_bake_fps=IntProperty(name='Bake FPS',default=60,min=1,max=240)
print('PZ_CART_SIDEBAR_READY')
