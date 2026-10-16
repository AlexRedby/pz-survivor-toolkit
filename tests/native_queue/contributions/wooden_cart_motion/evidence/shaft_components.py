from fbx_mesh import read_nodes
import numpy as np
from collections import Counter
from pathlib import Path
def build_components(path):
 obj=next(n for n in read_nodes(path) if n[0]=='Objects');geom=next(n for n in obj[2] if n[0]=='Geometry');V=next(n[1][0] for n in geom[2] if n[0]=='Vertices').reshape(-1,3).copy();V[:,2]*=-1
 pvi=next(n[1][0] for n in geom[2] if n[0]=='PolygonVertexIndex');parent=np.arange(len(V));polys=[];a=[]
 def root(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for x in pvi:
  a.append(int(x if x>=0 else -x-1))
  if x<0:
   polys.append(a)
   for j in a[1:]:parent[root(j)]=root(a[0])
   a=[]
 groups={}
 for i in range(len(V)):groups.setdefault(root(i),[]).append(i)
 components=[]
 for ids in groups.values():
  v=V[ids]
  if v[:,1].max()<=.003:continue
  pol=[p for p in polys if p[0] in ids];tri=np.array([[p[0],p[j],p[j+1]] for p in pol for j in range(1,len(p)-1)]);normal=np.cross(V[tri[:,1]]-V[tri[:,0]],V[tri[:,2]]-V[tri[:,0]]);length=np.linalg.norm(normal,axis=1);normal=normal[length>1e-15]/length[length>1e-15,None];p=V[tri[length>1e-15,0]];normal*=np.where(np.sum((v.mean(0)-p)*normal,axis=1)>0,-1,1)[:,None];dist=np.einsum('vnc,nc->vn',v[:,None,:]-p[None,:,:],normal)
  edgeCounts=Counter(tuple(sorted((tuple(np.round(t[j],10)),tuple(np.round(t[(j+1)%3],10))))) for t in V[tri] for j in range(3));closed=all(n==2 for n in edgeCounts.values())
  components.append(dict(closed=closed,vertices=v,triangles=V[tri],normals=normal,planes=np.sum(p*normal,axis=1),edges=np.concatenate([V[np.roll(p,-1)]-V[p] for p in pol]),convexViolation=float(dist.max()),side='L' if v[:,0].mean()>0 else 'R'))
 return V,components
