"""Build the self-contained Blender authoring scene (run through cart_blender.py)."""
import json
import math
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
import cart_clip_blender as bridge


def fbx_geometry(path):
    """Read raw binary FBX geometry, using the native importer's cart Z reflection.

    This deliberately ignores FBX authoring-camera/material/animation data. The
    calibrated native cart matrices supply scale and placement, not FBX units.
    """
    raw=Path(path).read_bytes()
    if not raw.startswith(b'Kaydara FBX Binary  \x00\x1a\x00'):raise ValueError('expected binary cart FBX')
    version=struct.unpack_from('<I',raw,23)[0];fmt='<QQQB' if version>=7500 else '<IIIB';size=struct.calcsize(fmt);offset=27
    def prop():
        nonlocal offset
        code=chr(raw[offset]);offset+=1
        types={'Y':'h','C':'?','I':'i','F':'f','D':'d','L':'q'}
        if code in types:
            f='<'+types[code];v=struct.unpack_from(f,raw,offset)[0];offset+=struct.calcsize(f);return v
        if code in 'SR':
            n=struct.unpack_from('<I',raw,offset)[0];offset+=4;v=raw[offset:offset+n];offset+=n;return v
        if code in 'fdilbc':
            n,encoding,length=struct.unpack_from('<III',raw,offset);offset+=12
            if n>10_000_000 or length>len(raw)-offset:raise ValueError('invalid FBX array length')
            v=raw[offset:offset+length];offset+=length
            if encoding not in (0,1):raise ValueError('invalid FBX array encoding')
            v=zlib.decompress(v) if encoding else v
            f={'f':'f','d':'d','i':'i','l':'q','b':'B','c':'B'}[code]
            if len(v)!=n*struct.calcsize(f):raise ValueError('invalid FBX array payload')
            return struct.unpack('<'+str(n)+f,v)
        raise ValueError(f'unsupported FBX property {code}')
    geometries=[]
    def node(depth=0):
        nonlocal offset
        if depth>64 or offset+size>len(raw):raise ValueError('malformed FBX node')
        end,count,_,length=struct.unpack_from(fmt,raw,offset);offset+=size
        if end==0:return None
        if not offset<=end<=len(raw) or count>1_000_000:raise ValueError('invalid FBX node bounds')
        name=raw[offset:offset+length].decode();offset+=length
        values=[prop() for _ in range(count)];children=[]
        while offset<end:
            child=node(depth+1)
            if child is None:break
            children.append(child)
        offset=end
        if name=='Geometry':geometries.append(children)
        return name,values,children
    while offset+size<=len(raw):
        if node() is None:break
    vertices=[];faces=[]
    for geometry in geometries:
        data={name:values for name,values,_ in geometry}
        if 'Vertices' not in data or 'PolygonVertexIndex' not in data:continue
        v=data['Vertices'][0];base=len(vertices)
        if len(v)%3:raise ValueError('invalid FBX vertices')
        vertices.extend((v[i],v[i+1],-v[i+2]) for i in range(0,len(v),3))
        polygon=[]
        for index in data['PolygonVertexIndex'][0]:
            vertex=-index-1 if index<0 else index
            if not 0<=vertex<len(v)//3:raise ValueError('invalid FBX face vertex')
            polygon.append(base+vertex)
            if index<0:
                if len(polygon)<3:raise ValueError('invalid FBX polygon')
                faces.append(tuple(reversed(polygon)));polygon=[]
        if polygon:raise ValueError('unterminated FBX polygon')
    if not vertices or not faces or not all(math.isfinite(v) for p in vertices for v in p):raise ValueError('missing/invalid cart geometry')
    return vertices,faces


def build_scene(config_path):
    import bpy
    from mathutils import Matrix,Vector
    from cart_blender_preview import build_preview
    path=Path(config_path);config=json.loads(path.read_text())
    bridge.import_clip(Path(config['template']).read_text(),json.loads(Path(config['source']).read_text()),Path(config['scene']))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE' and bridge.PROPERTY in o)
    body=build_preview(rig,Path(config['body']))
    # Bone length is a display/edit handle, independent of exported transforms.
    # Extend limb handles to their child joints instead of tiny equal-size sticks.
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        children=[child for child in bone.children if not child.name.endswith('Nub')]
        if children:
            distance=min((child.head-bone.head).length for child in children)
            if .015<distance<.5:bone.length=distance
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.data.display_type='OCTAHEDRAL'
    scene=bpy.context.scene;metadata=json.loads(rig[bridge.PROPERTY]);last=metadata['frames'][-1]
    scene.frame_end=round(last) if abs(last-round(last))<1e-3 else math.ceil(last)
    scene.render.fps=60;scene.render.fps_base=config['duration']/metadata['times'][-1]
    scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH'
    scene.display.shading.show_shadows=True;scene.world=bpy.data.worlds.new('Cart studio');scene.world.color=(.2,.22,.25)
    scene.view_settings.view_transform='Standard';scene['cart_workspace']=str(path.resolve())
    scene['cart_scope']=config['scope'];scene.tool_settings.use_keyframe_insert_auto=True
    scene.tool_settings.auto_keying_mode='ADD_REPLACE_KEYS';bpy.context.preferences.edit.keyframe_new_interpolation_type='LINEAR'
    def material(name,color):
        m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);return m
    def mesh(name,vertices,faces,color):
        data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
        obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);data.materials.append(material(name,color));return obj
    cart=config.get('cart')
    if cart:
        vertices,faces=fbx_geometry(cart['path']);obj=mesh('Cart reference',vertices,faces,(.32,.15,.055))
        obj['scope']='Calibrated reference only; runtime IK/grounding remains in PZ.'
        center=Vector(cart['axle']);ground=Matrix(bridge.matrix_rows(cart['ground']));held=Matrix(bridge.matrix_rows(cart['held']))
        gt,gq,gs=ground.decompose();ht,hq,hs=held.decompose();obj.rotation_mode='QUATERNION'
        for i in range(121):
            u=i/120;v=max(0,min(1,(u-cart['lift_start'])/(1-cart['lift_start'])));w=v*v*v*(10+v*(-15+6*v))
            matrix=Matrix.LocRotScale(gt.lerp(ht,w),gq.slerp(hq,w),gs.lerp(hs,w));matrix.translation+=(ground@center).lerp(held@center,w)-matrix@center
            obj.matrix_world=Matrix(bridge.matrix_rows(bridge.MODEL_BASIS))@matrix
            for prop in ('location','rotation_quaternion','scale'):obj.keyframe_insert(prop,frame=1+(last-1)*u)
        for curve in obj.animation_data.action.fcurves:
            for key in curve.keyframe_points:key.interpolation='LINEAR'
        obj.hide_select=True
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012));floor=bpy.context.object;floor.name='Reference floor';floor.data.materials.append(material('Floor',(.16,.18,.21)));floor.hide_select=True
    cam=bpy.data.cameras.new('Cart camera');camera=bpy.data.objects.new('Cart camera',cam);scene.collection.objects.link(camera)
    camera.location=(2.4,-1.6,1.3);camera.rotation_euler=(Vector((0,.35,.4))-camera.location).to_track_quat('-Z','Y').to_euler();cam.type='ORTHO';cam.ortho_scale=2.1;scene.camera=camera;camera.hide_select=True
    text=bpy.data.texts.new('START HERE')
    text.write('PZ CART ANIMATION\n\nSelect CartClip, Pose Mode. Space: play/pause; drag timeline to scrub.\nAuto Key is enabled. Move/rotate bones; I inserts keys. Dope Sheet retimes selected keys.\nN sidebar > PZ Cart: Save + Export verifies the native .x, including between keys.\nFor Bezier curves or authoring constraints, enable Bake. Sampling adapts up to 240 fps.\nExported snapshots are separate from source assets and installed mods.\n\nThe body is live LBS skinning and works after reopening without scripts.\nThe cart is a calibrated reference; runtime hand IK, clothing and transitions require PZ.\nOpen via: python3 tools/cart_blender.py edit WORKSPACE\n')
    bpy.ops.object.select_all(action='DESELECT');rig.hide_set(False);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='POSE');rig.data.bones.active=rig.data.bones.get('Bip01_Spine');rig.show_in_front=True
    for bone in rig.data.bones:bone.select=bone.name=='Bip01_Spine'
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active;space.region_3d.view_perspective='CAMERA';space.overlay.show_floor=False;space.show_region_ui=True;space.shading.color_type='MATERIAL'
            elif area.type=='TIMELINE':area.type='DOPESHEET_EDITOR';area.spaces.active.mode='DOPESHEET'
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=config['scene'])
    print('CART_AUTHORING_SCENE_READY',config['scene'])


if __name__=='__main__':build_scene(sys.argv[sys.argv.index('--')+1])
