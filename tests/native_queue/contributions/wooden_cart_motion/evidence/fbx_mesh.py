"""Small read-only binary FBX array reader for the existing wooden mesh."""
import struct,zlib
from pathlib import Path
import numpy as np
def read_nodes(path):
 f=Path(path).open('rb');f.seek(23);version=struct.unpack('<I',f.read(4))[0];fmt='<QQQB' if version>=7500 else '<IIIB';size=struct.calcsize(fmt)
 def prop():
  t=f.read(1).decode();types={'Y':'h','C':'?','I':'i','F':'f','D':'d','L':'q'}
  if t in types:return struct.unpack('<'+types[t],f.read(struct.calcsize(types[t])))[0]
  if t in 'SR':n=struct.unpack('<I',f.read(4))[0];v=f.read(n);return v.decode(errors='replace') if t=='S' else v
  if t in 'fdilbc':
   n,encoding,nb=struct.unpack('<III',f.read(12));v=f.read(nb);v=zlib.decompress(v) if encoding else v;return np.frombuffer(v,dtype={'f':'<f4','d':'<f8','i':'<i4','l':'<i8','b':'u1','c':'u1'}[t],count=n)
  raise ValueError(t)
 def node():
  end,np_,nb,nl=struct.unpack(fmt,f.read(size))
  if end==0:return None
  name=f.read(nl).decode();p=[prop() for _ in range(np_)];children=[]
  while f.tell()<end:
   c=node()
   if c is None:break
   children.append(c)
  f.seek(end);return name,p,children
 roots=[]
 while True:
  n=node()
  if n is None:break
  roots.append(n)
 return roots
if __name__=='__main__':
 def dump(ns):
  for name,p,ch in ns:
   if name=='Geometry':
    print(name,p)
    for k,v,_ in ch:
     if k in ['Vertices','PolygonVertexIndex']:print(k,len(v[0]),np.min(v[0]),np.max(v[0]),v[0][:12])
   dump(ch)
 import argparse
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("mesh",type=Path);args=parser.parse_args()
 dump(read_nodes(args.mesh))
