"""Actual closed FBX shaft components against body triangles, in raw cart coordinates.
API intersects(triangles, side): (...,3,3) -> (...) bool. Both triangle edges
and enclosed body vertices count. Uses six connected shaft/brace meshes (four closed solids);
native vertex buffer matches original FBX after import Z reflection.
"""
import numpy as np
components=[]
EPS=1e-10

def segment_hits(a,b,tri):
 d=b-a;e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(d,e2);det=np.einsum('ij,ij->i',e1,h);good=abs(det)>1e-20;inv=np.divide(1.,det,out=np.zeros_like(det),where=good);s=a-tri[:,0];u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=inv*np.einsum('ij,ij->i',d,q);t=inv*np.einsum('ij,ij->i',e2,q);return good&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>=-1e-8)&(t<=1+1e-8)

def cross2(a,b):return a[:,0]*b[:,1]-a[:,1]*b[:,0]
def coplanar_hits(a,b):
 normal=np.cross(a[:,1]-a[:,0],a[:,2]-a[:,0]);other=np.cross(b[:,1]-b[:,0],b[:,2]-b[:,0]);length=np.linalg.norm(normal,axis=1);olength=np.linalg.norm(other,axis=1);unit=normal/np.maximum(length,1e-30)[:,None];mask=(length>1e-20)&(olength>1e-20)&(np.linalg.norm(np.cross(unit,other/np.maximum(olength,1e-30)[:,None]),axis=1)<1e-7)&(np.max(abs(np.einsum('nvc,nc->nv',b-a[:,0,None,:],unit)),axis=1)<EPS);hit=np.zeros(len(a),bool)
 for drop in range(3):
  ids=np.where(mask&(np.argmax(abs(unit),axis=1)==drop))[0]
  if not len(ids):continue
  x=np.delete(a[ids],drop,axis=2);y=np.delete(b[ids],drop,axis=2);ok=np.zeros(len(ids),bool)
  for i in range(3):
   p=x[:,i];d=x[:,(i+1)%3]-p
   for j in range(3):
    q=y[:,j];e=y[:,(j+1)%3]-q;den=cross2(d,e);valid=abs(den)>1e-20;t=np.divide(cross2(q-p,e),den,out=np.zeros_like(den),where=valid);u=np.divide(cross2(q-p,d),den,out=np.zeros_like(den),where=valid);ok|=valid&(t>=-1e-8)&(t<=1+1e-8)&(u>=-1e-8)&(u<=1+1e-8)
  for p,t in [(x[:,0],y),(y[:,0],x)]:
   signs=np.stack([cross2(t[:,(i+1)%3]-t[:,i],p-t[:,i]) for i in range(3)],axis=1);ok|=(signs.min(1)>=-1e-14)|(signs.max(1)<=1e-14)
  hit[ids]=ok
 return hit

def inside(points,solid):
 # Arbitrary non-axis ray avoids the authored face diagonals; deduplicate hits
 # on shared edges so triangulation does not change odd/even parity.
 assert solid['closed'], 'Odd/even containment requires a closed component'
 ray=np.array([.739,.371,.563]);tri=solid['triangles'];out=np.zeros(len(points),bool);e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(ray,e2);det=np.einsum('ij,ij->i',e1,h);valid=abs(det)>1e-20;inv=np.divide(1.,det,out=np.zeros_like(det),where=valid)
 for start in range(0,len(points),2048):
  p=points[start:start+2048];s=p[:,None,:]-tri[None,:,0,:];u=np.einsum('ntc,tc->nt',s,h)*inv;q=np.cross(s,e1[None,:,:]);v=np.einsum('ntc,c->nt',q,ray)*inv;t=np.einsum('ntc,tc->nt',q,e2)*inv;ok=valid[None,:]&(u>=-1e-9)&(v>=-1e-9)&(u+v<=1+1e-9)&(t>=-EPS);ts=np.sort(np.where(ok,t,np.inf),axis=1);unique=np.isfinite(ts)&np.concatenate([np.ones((len(p),1),bool),np.diff(np.where(np.isfinite(ts),ts,1e30),axis=1)>EPS],axis=1);out[start:start+len(p)]=unique.sum(1)%2==1
 return out

def intersects(triangles,side):
 shape=triangles.shape[:-2];alltri=np.asarray(triangles).reshape(-1,3,3);result=np.zeros(len(alltri),bool)
 for solid in components:
  if solid['side']!=side:continue
  st=solid['triangles'];low=solid['vertices'].min(0);high=solid['vertices'].max(0);ids=np.where((alltri.max(1)>=low-EPS).all(1)&(alltri.min(1)<=high+EPS).all(1)&~result)[0]
  for start in range(0,len(ids),1024):
   ix=ids[start:start+1024];bt=alltri[ix];pair=(bt[:,None,:,:].max(2)>=st[None,:,:,:].min(2)-EPS).all(2)&(bt[:,None,:,:].min(2)<=st[None,:,:,:].max(2)+EPS).all(2);bi,si=np.where(pair);hit=np.zeros(len(bt),bool)
   if len(bi):
    a=bt[bi];b=st[si];h=coplanar_hits(a,b)
    for edge in range(3):h|=segment_hits(a[:,edge],a[:,(edge+1)%3],b)|segment_hits(b[:,edge],b[:,(edge+1)%3],a)
    hit[np.unique(bi[h])]=True
   remain=np.where(~hit)[0]
   if len(remain) and solid['closed']:
    points=bt[remain].reshape(-1,3);mask=(points>=low-EPS).all(1)&(points<=high+EPS).all(1);contained=np.zeros(len(points),bool);contained[mask]=inside(points[mask],solid);hit[remain]|=contained.reshape(-1,3).any(1)
   result[ix]|=hit
 return result.reshape(shape)

def self_check():
 global components
 crossing=np.array([[[0,-1,-1],[0,1,-1],[0,0,1.]]])
 assert segment_hits(np.array([[-2,0,0.]]),np.array([[2,0,0.]]),crossing)[0]
 assert not segment_hits(np.array([[-2,2,0.]]),np.array([[2,2,0.]]),crossing)[0]
 xy=np.array([[[0,0,0],[1,0,0],[0,1,0.]]])
 assert coplanar_hits(xy,xy+.1*np.array([1,1,0]))[0]
 assert not coplanar_hits(xy,xy+np.array([2,2,0]))[0]
 v=np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1.]])
 f=np.array([[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],[1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7]])
 cube=dict(vertices=v,triangles=v[f],closed=True,side='test')
 assert inside(np.array([[0,0,0],[2,0,0.]]),cube).tolist()==[True,False]
 saved=components
 try:
  components=[cube]
  contained=np.array([[[-.1,0,0],[.1,0,0],[0,.1,0.]]])
  assert intersects(contained,'test')[0]
  assert not intersects(contained+3,'test')[0]
  assert intersects(np.array([[[-2,0,0],[2,0,0],[0,2,0.]]]),'test')[0]
  assert intersects(np.array([[[-.5,-.5,1],[.5,-.5,1],[0,.5,1.]]]),'test')[0]
 finally:components=saved
 assert abs(triangle_distance(xy,xy+[0,0,1])[0]-1)<1e-12
 assert triangle_distance(xy,xy+.1*np.array([1,1,0]))[0]==0
 assert abs(point_triangle_distance(np.array([[.2,.2,1]]),xy)[0]-1)<1e-12
 return {'crossing':True,'coplanarOverlapDisjoint':True,'containedPoints':True,'containedTriangle':True,'distanceChecks':True}


def point_triangle_distance(p,t):
 a=t[:,0];e=t[:,1]-a;f=t[:,2]-a;n=np.cross(e,f);n2=np.einsum('ij,ij->i',n,n);w=p-a;dot=np.einsum('ij,ij->i',w,n);proj=p-n*np.divide(dot,n2,out=np.zeros_like(dot),where=n2>1e-30)[:,None];q=proj-a;ee=np.einsum('ij,ij->i',e,e);ff=np.einsum('ij,ij->i',f,f);ef=np.einsum('ij,ij->i',e,f);qe=np.einsum('ij,ij->i',q,e);qf=np.einsum('ij,ij->i',q,f);den=ee*ff-ef*ef;u=np.divide(qe*ff-qf*ef,den,out=np.zeros_like(den),where=abs(den)>1e-30);v=np.divide(qf*ee-qe*ef,den,out=np.zeros_like(den),where=abs(den)>1e-30);inside=(n2>1e-30)&(u>=0)&(v>=0)&(u+v<=1);dist=np.where(inside,abs(dot)/np.sqrt(np.maximum(n2,1e-30)),np.inf)
 for i in range(3):
  a=t[:,i];d=t[:,(i+1)%3]-a;l=np.einsum('ij,ij->i',d,d);s=np.clip(np.divide(np.einsum('ij,ij->i',p-a,d),l,out=np.zeros_like(l),where=l>1e-30),0,1);dist=np.minimum(dist,np.linalg.norm(p-a-s[:,None]*d,axis=1))
 return dist

def triangle_distance(a,b):
 dist=np.full(len(a),np.inf)
 for i in range(3):dist=np.minimum(dist,point_triangle_distance(a[:,i],b));dist=np.minimum(dist,point_triangle_distance(b[:,i],a))
 for i in range(3):
  p=a[:,i];u=a[:,(i+1)%3]-p
  for j in range(3):
   q=b[:,j];v=b[:,(j+1)%3]-q;w=p-q;aa=np.einsum('ij,ij->i',u,u);bb=np.einsum('ij,ij->i',u,v);cc=np.einsum('ij,ij->i',v,v);dd=np.einsum('ij,ij->i',u,w);ee=np.einsum('ij,ij->i',v,w);den=aa*cc-bb*bb;good=abs(den)>1e-30;s=np.divide(bb*ee-cc*dd,den,out=np.zeros_like(den),where=good);t=np.divide(aa*ee-bb*dd,den,out=np.zeros_like(den),where=good);valid=good&(s>=0)&(s<=1)&(t>=0)&(t<=1);d=np.linalg.norm(w+s[:,None]*u-t[:,None]*v,axis=1);dist=np.minimum(dist,np.where(valid,d,np.inf))
 hit=coplanar_hits(a,b)
 for edge in range(3):hit|=segment_hits(a[:,edge],a[:,(edge+1)%3],b)|segment_hits(b[:,edge],b[:,(edge+1)%3],a)
 return np.where(hit,0.,dist)

def minimum_gap(triangles,side,limit=.02/76.5):
 """Minimum surface separation in raw cart units, clipped above limit.
 Caller must also run intersects(): containment does not imply surface contact.
 """
 flat=np.asarray(triangles).reshape(-1,3,3);answer=limit
 for solid in components:
  if solid['side']!=side:continue
  st=solid['triangles'];lo=st.min(1);hi=st.max(1)
  for start in range(0,len(flat),512):
   bt=flat[start:start+512];delta=np.maximum(np.maximum(lo[None,:,:]-bt.max(1)[:,None,:],bt.min(1)[:,None,:]-hi[None,:,:]),0);bi,si=np.where(np.linalg.norm(delta,axis=2)<answer)
   if len(bi):answer=min(answer,float(triangle_distance(bt[bi],st[si]).min()))
 return answer

if __name__=='__main__':
 print('actual_mesh self-check PASS',self_check())
