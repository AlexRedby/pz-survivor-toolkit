#!/usr/bin/env python3
"""Reproduce shopping-cart wheel calibration from the six original SaucedCarts FBXs.

Only Python's standard library is required. Source positions follow the engine's
Z reflection and float32 conversion; no third-party model is copied or changed.
"""
import argparse
import hashlib
import math
from pathlib import Path
import struct
import zlib

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/'JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartShoppingWheelMesh.java'
MODELS=(('ShoppingCartModel','ShoppingCart_PZ.fbx'),
        ('ShoppingCartPartialModel','ShoppingCartHalfFull_PZ.fbx'),
        ('ShoppingCartFullModel','ShoppingCartFull_PZ.fbx'),
        ('ShoppingCartFlashlightModel','ShoppingCart_HandTorch.fbx'),
        ('ShoppingCartFlashlightPartialModel','ShoppingCartHalfFull_HandTorch.fbx'),
        ('ShoppingCartFlashlightFullModel','ShoppingCartFull_HandTorch.fbx'))

def read_nodes(path):
    """Read binary FBX nodes and numeric arrays without an importer dependency."""
    with path.open('rb') as stream:
        if stream.read(23)!=b'Kaydara FBX Binary  \x00\x1a\x00':
            raise ValueError(f'Expected binary FBX: {path}')
        version=struct.unpack('<I',stream.read(4))[0]
        header='<QQQB' if version>=7500 else '<IIIB'
        size=struct.calcsize(header)
        def prop():
            tag=stream.read(1).decode()
            scalar={'Y':'h','C':'?','I':'i','F':'f','D':'d','L':'q'}
            if tag in scalar:
                fmt='<'+scalar[tag]
                return struct.unpack(fmt,stream.read(struct.calcsize(fmt)))[0]
            if tag in 'SR':
                n=struct.unpack('<I',stream.read(4))[0];raw=stream.read(n)
                return raw.decode(errors='replace') if tag=='S' else raw
            if tag in 'fdilbc':
                n,encoding,length=struct.unpack('<III',stream.read(12));raw=stream.read(length)
                if encoding:raw=zlib.decompress(raw)
                fmt={'f':'f','d':'d','i':'i','l':'q','b':'B','c':'B'}[tag]
                return struct.unpack('<'+str(n)+fmt,raw)
            raise ValueError(f'Unsupported FBX property {tag!r}: {path}')
        def node():
            end,count,_,name_length=struct.unpack(header,stream.read(size))
            if not end:return None
            name=stream.read(name_length).decode();props=[prop() for _ in range(count)];children=[]
            while stream.tell()<end:
                child=node()
                if child is None:break
                children.append(child)
            stream.seek(end)
            return name,props,children
        roots=[]
        while True:
            item=node()
            if item is None:break
            roots.append(item)
        return roots

def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]
def mean(points):return [sum(p[i] for p in points)/len(points) for i in range(3)]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def matvec(matrix,point):return [dot(row,point) for row in matrix]

def physical_basis():
    # CartShopping.worldModel's measured native linear basis, followed by its
    # support rotation. Translation does not affect radius or the radial plane.
    basis=[[.002273866,.000111277506,3.159179e-10],
           [-.00014903705,.0016977666,4.819975e-9],
           [0,-7.437096e-11,.11050479]]
    normal=cross([r[2] for r in basis],matvec(basis,[218.725291729,17.093925655,-.006239582]))
    length=math.sqrt(dot(normal,normal));normal=[x/length for x in normal]
    axis=cross(normal,[0,1,0]);c=normal[1]
    def level(v):
        av=cross(axis,v);aav=cross(axis,av)
        return [v[i]+av[i]+aav[i]/(1+c) for i in range(3)]
    columns=[level([basis[i][j] for i in range(3)]) for j in range(3)]
    return [[columns[j][i] for j in range(3)] for i in range(3)]

def source(path):
    objects=next(n for n in read_nodes(path) if n[0]=='Objects')[2]
    geometries=[n for n in objects if n[0]=='Geometry']
    if len(geometries)!=1:raise ValueError(f'Expected one geometry: {path}')
    geometry=geometries[0][2]
    raw=next(n[1][0] for n in geometry if n[0]=='Vertices')
    points=[(f32(raw[i]),f32(raw[i+1]),f32(-raw[i+2])) for i in range(0,len(raw),3)]
    indices=next(n[1][0] for n in geometry if n[0]=='PolygonVertexIndex')
    parents=list(range(len(points)));faces=[];face=[]
    def root(i):
        while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
        return i
    for index in indices:
        end=index<0;face.append(~index if end else index)
        if end:
            if len(face)<3:raise ValueError(f'Degenerate source face: {path}')
            faces.append(face);r=root(face[0])
            for i in face[1:]:parents[root(i)]=r
            face=[]
    if face:raise ValueError(f'Unterminated FBX polygon: {path}')
    groups={}
    for i in range(len(points)):groups.setdefault(root(i),[]).append(i)
    tires=[ids for ids in groups.values() if len(ids)==64 and max(points[i][1] for i in ids)<50]
    front_posts=[ids for ids in groups.values() if len(ids)==12 and max(points[i][1] for i in ids)<100 and mean([points[i] for i in ids])[0]>0]
    if len(tires)!=4 or len(front_posts)!=2:raise ValueError(f'Expected four tires and two front posts: {path}')
    # Rear +Z, rear -Z, front +Z, front -Z, front post +Z, front post -Z.
    tires.sort(key=lambda ids:(mean([points[i] for i in ids])[0],-mean([points[i] for i in ids])[2]))
    front_posts.sort(key=lambda ids:-mean([points[i] for i in ids])[2])
    parts=[]
    for ids in tires+front_posts:
        local={vertex:i for i,vertex in enumerate(ids)}
        part_faces=[face for face in faces if face[0] in local]
        if any(any(i not in local for i in face) for face in part_faces):raise ValueError('Mixed source component')
        parts.append(([points[i] for i in ids],[[local[i] for i in face] for face in part_faces]))
    return points,faces,parts

def point_hash(points):
    # Unsigned IEEE754 xyz bit tuples sorted lexicographically, deduplicated,
    # then serialized as little-endian uint32 xyz triples. Native UV/normal
    # splitting does not affect this signature.
    bits=sorted({struct.unpack('<III',struct.pack('<fff',*p)) for p in points})
    return hashlib.sha256(b''.join(struct.pack('<III',*p) for p in bits)).hexdigest()

def calibration(parts):
    basis=physical_basis();centers=[mean(p) for p,_ in parts[:4]]
    swivels=[]
    for points,_ in parts[4:]:
        swivels.append(mean(sorted(points,key=lambda p:p[1])[len(points)//2:]))
    covariance=[0.,0.,0.];radii=[]
    for points,_ in parts[:4]:
        physical=[matvec(basis,p) for p in points];center=mean(physical)
        radial=[(p[0]-center[0],p[1]-center[1]) for p in physical]
        covariance[0]+=2*sum(x*x for x,y in radial)/len(radial)/4
        covariance[1]+=2*sum(x*y for x,y in radial)/len(radial)/4
        covariance[2]+=2*sum(y*y for x,y in radial)/len(radial)/4
        radii.append((max(y for x,y in radial)-min(y for x,y in radial))/2)
    radius=sum(radii)/4;a,b,d=covariance
    determinant=math.sqrt(a*d-b*b);scale=math.sqrt(a+d+2*determinant)
    # Positive-definite inverse square root of the 2x2 radial covariance.
    sa,sd=a+determinant,d+determinant;den=sa*sd-b*b
    normalize=[radius*scale*sd/den,-radius*scale*b/den,-radius*scale*b/den,radius*scale*sa/den]
    return centers,swivels,normalize,radius,basis

def jf(value):
    text=format(f32(value),'.9g')
    if '.' not in text and 'e' not in text:text+='.0'
    return text+'f'
def float_row(values):return '{'+','.join(jf(v) for v in values)+'}'
def int_row(values):return '{'+','.join(map(str,values))+'}'

def generate(folder):
    models=[];parts=None
    for name,filename in MODELS:
        points,faces,current=source(folder/filename)
        if parts is None:parts=current
        elif current!=parts:raise ValueError(f'Wheel/support geometry differs across variants: {filename}')
        models.append((name,point_hash(points),sum(len(f)-2 for f in faces)))
    centers,swivels,normalize,radius,basis=calibration(parts)
    part_triangles=[sum(len(f)-2 for f in faces) for _,faces in parts]
    moving_triangles=sum(part_triangles)
    lines=['package net.alexredby.pztoolkitjavapatches;','',
           '/** Generated by tools/generate_shopping_cart_wheels.py; do not edit by hand. */',
           'final class CartShoppingWheelMesh {',
           '    // Parts 1..4: rear +Z/-Z, front +Z/-Z tires; 5..6: front +Z/-Z supports.',
           '    // Body includes both fixed rear supports. Source raw coordinates reflect engine Z.',
           '    static final String[] MODELS={'+','.join('"'+m[0]+'"' for m in models)+'};',
           '    // Deduplicate and sort unsigned float-bit xyz tuples; hash little-endian uint32 xyz.',
           '    static final String[] POSITION_HASHES={']
    lines+=['        "'+m[1]+'"'+(',' if i<len(models)-1 else '') for i,m in enumerate(models)]
    lines+=['    };','    static final int[] TRIANGLES='+int_row([m[2] for m in models])+';',
            '    static final int[] BODY_TRIANGLES='+int_row([m[2]-moving_triangles for m in models])+';',
            '    static final int[] PART_TRIANGLES='+int_row(part_triangles)+';',
            '    static final float[][] CENTERS={'+','.join(float_row(c) for c in centers)+'};',
            '    static final float[][] SWIVELS={'+','.join(float_row(p) for p in swivels)+'};',
            '    // Row-major physical XY correction to a circle at the original vertical support radius.',
            '    static final float[] NORMALIZE='+float_row(normalize)+';',
            '    static final float RADIUS='+jf(radius)+';',
            '    // Row-major native world-model linear basis after CartShopping support leveling.',
            '    static final float[] PHYSICAL_BASIS='+float_row([v for row in basis for v in row])+';',
            '    static final float[][][] PART_POINTS={']
    for part,(points,_) in enumerate(parts):
        lines.append('        { // Part '+str(part+1))
        lines+=['            '+float_row(p)+(',' if i<len(points)-1 else '') for i,p in enumerate(points)]
        lines.append('        }'+(',' if part<len(parts)-1 else ''))
    lines+=['    };','    // Original polygons. Validate native triangles against these faces, independent of triangulation.','    static final int[][][] PART_FACES={']
    for part,(_,faces) in enumerate(parts):
        lines.append('        { // Part '+str(part+1))
        lines+=['            '+int_row(f)+(',' if i<len(faces)-1 else '') for i,f in enumerate(faces)]
        lines.append('        }'+(',' if part<len(parts)-1 else ''))
    lines+=['    };','    private CartShoppingWheelMesh() {}','}','']
    return '\n'.join(lines)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models',required=True,type=Path,help='Original SaucedCarts/42/media/models_x/weapons/2handed folder')
    parser.add_argument('--check',action='store_true',help='Verify committed calibration without writing files')
    args=parser.parse_args();content=generate(args.models)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text()!=content:raise ValueError(f'Generated output differs: {OUTPUT}')
    else:OUTPUT.write_text(content)
    print('SHOPPING_WHEELS_'+('REPRODUCED' if args.check else 'GENERATED')+' models=6 tires=4 swivelSupports=2')

if __name__=='__main__':main()
