"""Native raw cart FBX geometry basis and malformed-reference rejection."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from cart_blender_scene import fbx_geometry


def fixture(indices=(0,1,2,-4)):
    def array(code,fmt,values):
        payload=struct.pack('<'+str(len(values))+fmt,*values)
        return code.encode()+struct.pack('<III',len(values),0,len(payload))+payload
    offset=27
    def node(name,properties=(),children=()):
        nonlocal offset
        start=offset;offset+=13+len(name)+sum(map(len,properties))
        contents=b''.join(child() for child in children)+bytes(13);offset+=13
        return struct.pack('<IIIB',offset,len(properties),sum(map(len,properties)),len(name))+name.encode()+b''.join(properties)+contents
    result=node('Geometry',children=(lambda:node('Vertices',[array('d','d',(0,0,1,1,0,2,1,1,3,0,1,4))]),lambda:node('PolygonVertexIndex',[array('i','i',indices)])))
    return b'Kaydara FBX Binary  \x00\x1a\x00'+struct.pack('<I',7400)+result+bytes(13)


class CartGeometryTest(unittest.TestCase):
    def read(self,raw):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'cart.fbx';path.write_bytes(raw);return fbx_geometry(path)
    def test_cart_points_receive_native_z_reflection_and_winding(self):
        vertices,faces=self.read(fixture())
        self.assertEqual(vertices[2],(1,1,-3));self.assertEqual(faces,[(3,2,1,0)])
    def test_invalid_or_incomplete_faces_rejected(self):
        for raw in (b'not FBX',fixture((0,1,7,-4)),fixture((0,1,2)),fixture((0,-2))):
            with self.subTest(raw=raw[-20:]),self.assertRaises(ValueError):self.read(raw)


if __name__=='__main__':unittest.main()
