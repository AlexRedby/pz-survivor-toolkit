package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.WeakHashMap;
import org.joml.Matrix4f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.SkinningData;

/** Same-render-slot source cage fit. Native feet, root motion and network state stay native. */
final class CartLegClearance {
    private static final double MARGIN=.001, EPS=1e-6;
    private record Asset(int revision,String path,int profile) {}
    private static final WeakHashMap<ModelMesh,Asset> assets=new WeakHashMap<>();
    private static final class Scratch {
        final Matrix4f pose=new Matrix4f(),inverse=new Matrix4f();
        final org.lwjgl.util.vector.Matrix4f nativeMatrix=new org.lwjgl.util.vector.Matrix4f();
        final double[] triangle=new double[9],range=new double[2];
        double[] points=new double[0],low=new double[256],high=new double[256];
        double[][] primitives;
        int count;
        void add(double a,double b) {
            if(count==low.length) {low=Arrays.copyOf(low,count*2);high=Arrays.copyOf(high,count*2);}
            low[count]=a;high[count++]=b;
        }
    }
    private static final ThreadLocal<Scratch> scratch=ThreadLocal.withInitial(Scratch::new);

    /** Validate the exact calibrated source once per native mesh revision. Never parse meshes in a frame. */
    private static synchronized int profile(ModelMesh mesh) {
        if(mesh==null || mesh.fullPath==null) return -1;
        var old=assets.get(mesh);
        if(old!=null && old.revision==mesh.modificationCount && old.path.equals(mesh.fullPath)) return old.profile;
        int selected=-1;
        try {
            String path=mesh.fullPath.replace('\\','/');
            for(int i=0;i<=CartLegClearanceData.SKINS.length;i++) {
                boolean cart=i==CartLegClearanceData.SKINS.length;
                String suffix=cart?CartLegClearanceData.WOOD.suffix():CartLegClearanceData.SKINS[i].suffix();
                if(!path.endsWith(suffix)) continue;
                long bytes=cart?CartLegClearanceData.WOOD.bytes():CartLegClearanceData.SKINS[i].bytes();
                String hash=cart?CartLegClearanceData.WOOD.sha256():CartLegClearanceData.SKINS[i].sha256();
                var source=Path.of(mesh.fullPath);
                if(bytes<=0 || bytes>16*1024*1024 || Files.size(source)!=bytes) break;
                var digest=MessageDigest.getInstance("SHA-256");
                try(var input=Files.newInputStream(source)) {
                    byte[] buffer=new byte[16384];long read=0;int n;
                    while((n=input.read(buffer))!=-1) {
                        read+=n;if(read>bytes) break;digest.update(buffer,0,n);
                    }
                    if(read==bytes && HexFormat.of().formatHex(digest.digest()).equals(hash)) selected=i;
                }
                break;
            }
        } catch(java.io.IOException | java.security.NoSuchAlgorithmException | RuntimeException unavailable) {
            // Unsupported/reloaded assets keep their existing presentation.
        }
        assets.put(mesh,new Asset(mesh.modificationCount,mesh.fullPath,selected));
        return selected;
    }

    private static boolean skin(zombie.core.skinnedmodel.model.ModelInstanceRenderData data,
                                CartLegClearanceData.Skin source,Scratch s,SkinningData actor,Matrix4f[] poses) {
        if(!(data.modelInstance.model.tag instanceof SkinningData target) || data.matrixPalette==null) return false;
        int required=source.vertexCount()*3;
        if(s.points.length<required) s.points=new double[required];
        Arrays.fill(s.points,0,required,0);
        var palette=data.matrixPalette;int before=palette.position();
        try {
            for(int bone=0;bone<source.bones().length;bone++) {
                Integer index=target.boneIndices.get(source.bones()[bone]);
                if(index==null || index<0 || (long)(index+1)*16>palette.limit()
                    || index>=target.boneOffset.size() || target.boneOffset.get(index)==null) return false;
                palette.position(index*16);s.nativeMatrix.load(palette);
                PZMath.convertMatrix(s.nativeMatrix,s.pose).transpose();
                PZMath.convertMatrix(target.boneOffset.get(index),s.inverse).transpose();
                if(!s.pose.isFinite() || !s.inverse.isFinite() || Math.abs(s.inverse.determinant())<1e-12f) return false;
                s.pose.mul(s.inverse.invert());
                if(!validPose(s.pose)) return false;
                var pending=actor.getBone(source.bones()[bone]);
                if(pending!=null && CartGrip.upperBody(pending)) {
                    if(pending.index<0 || pending.index>=poses.length || poses[pending.index]==null) return false;
                    s.pose.set(poses[pending.index]);
                    if(!validPose(s.pose)) return false;
                }
                accumulate(source,bone,s.pose,s.points);
            }
            for(int i=0;i<required;i++) if(!Double.isFinite(s.points[i])) return false;
            return true;
        } finally {palette.position(before);}
    }

    private static boolean validPose(Matrix4f pose) {
        float determinant=pose.determinant();
        return pose.isFinite() && Float.isFinite(determinant) && Math.abs(determinant)>1e-12f;
    }

    static void accumulate(CartLegClearanceData.Skin source,int bone,Matrix4f pose,double[] points) {
        for(int j=0;j<source.influenceBone().length;j++) if(source.influenceBone()[j]==bone) {
            int point=source.influenceVertex()[j]*3,k=j*4;
            double x=source.weightedPoints()[k],y=source.weightedPoints()[k+1],z=source.weightedPoints()[k+2],w=source.weightedPoints()[k+3];
            points[point]+=pose.m00()*x+pose.m10()*y+pose.m20()*z+pose.m30()*w;
            points[point+1]+=pose.m01()*x+pose.m11()*y+pose.m21()*z+pose.m31()*w;
            points[point+2]+=pose.m02()*x+pose.m12()*y+pose.m22()*z+pose.m32()*w;
        }
    }

    static double shift(ModelSlotRenderData slot,ModelInstance owner,ModelMesh cart,Matrix4f transform,float pressure,
                        SkinningData actor,Matrix4f[] poses) {
        if(owner==null || owner.animPlayer==null || actor==null || poses==null || !transform.isFinite() || !Float.isFinite(pressure)
            || profile(cart)!=CartLegClearanceData.SKINS.length) return Double.NaN;
        var s=scratch.get();s.count=0;
        var raw=CartLegClearanceData.WOOD.primitives();
        if(s.primitives==null) {
            s.primitives=new double[raw.length][];
            for(int i=0;i<raw.length;i++) s.primitives[i]=new double[raw[i].length];
        }
        for(int i=0;i<raw.length;i++) for(int j=0;j<raw[i].length;j+=3) {
            double x=raw[i][j],y=raw[i][j+1],z=raw[i][j+2];var p=s.primitives[i];
            p[j]=transform.m00()*x+transform.m10()*y+transform.m20()*z+transform.m30();
            p[j+1]=transform.m01()*x+transform.m11()*y+transform.m21()*z+transform.m31();
            p[j+2]=transform.m02()*x+transform.m12()*y+transform.m22()*z+transform.m32();
        }
        int bodies=0;
        for(var data:slot.modelData) if(data.modelInstance==owner) bodies++;
        if(bodies!=1) return Double.NaN;
        boolean body=false;
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance==null || instance.animPlayer!=owner.animPlayer || instance.model==null
                || instance.model.isStatic || data.matrixPalette==null) continue;
            int id=profile(instance.model.mesh);
            if(id<0 || id>=CartLegClearanceData.SKINS.length || instance==owner && id>1) {if(instance==owner) return Double.NaN;continue;}
            var source=CartLegClearanceData.SKINS[id];
            if(!skin(data,source,s,actor,poses)) return Double.NaN;
            if(instance==owner) body=true;
            var faces=source.triangles();
            for(int i=0;i<faces.length;i+=3) {
                for(int v=0;v<3;v++) System.arraycopy(s.points,faces[i+v]*3,s.triangle,v*3,3);
                for(var primitive:s.primitives) if(intervalWithinDomain(s.triangle,primitive,MARGIN,-.030,.030,s.range))
                    s.add(s.range[0],s.range[1]);
            }
        }
        if(!body) return Double.NaN;
        double bank=CartSteeringMath.woodenTurnAmount(pressure);
        double selected=choose(s.low,s.high,s.count,-.030+.022*bank,.030-.012*bank);
        return selected;
    }

    /** Conservative nonzero-fit gate; unsupported fast/edge poses retain their existing placement. */
    static boolean withinFootprint(Matrix4f transform) {
        var points=CartLegClearanceData.WOOD.footprintPoints();
        for(int i=0;i<points.length;i+=3) {
            double x=points[i],y=points[i+1],z=points[i+2];
            double lateral=-1.5*(transform.m00()*x+transform.m10()*y+transform.m20()*z+transform.m30());
            double forward=-1.5*(transform.m02()*x+transform.m12()*y+transform.m22()*z+transform.m32());
            if(!CartFootprint.contains(forward,lateral,CartFootprint.WALK_FRONT,.001)) return false;
        }
        return true;
    }

    /** Skip cross-leg/shaft pairs that cannot touch anywhere inside the bounded lateral corridor. */
    static boolean intervalWithinDomain(double[] triangle,double[] primitive,double margin,double min,double max,double[] out) {
        double ta=Math.min(triangle[0],Math.min(triangle[3],triangle[6]));
        double tb=Math.max(triangle[0],Math.max(triangle[3],triangle[6]));
        double pa=Double.POSITIVE_INFINITY,pb=Double.NEGATIVE_INFINITY;
        for(int i=0;i<primitive.length;i+=3) {pa=Math.min(pa,primitive[i]);pb=Math.max(pb,primitive[i]);}
        if(tb-min+margin+2*EPS<pa || ta-max-margin-2*EPS>pb) return false;
        return interval(triangle,primitive,margin,out);
    }

    /** Continuous triangle/convex primitive SAT: cart +X is body -X. Includes coplanar braces. */
    static boolean interval(double[] triangle,double[] primitive,double margin,double[] out) {
        if(triangle==null || primitive==null || out==null || out.length<2 || triangle.length!=9
            || primitive.length!=9 && primitive.length!=12 || !Double.isFinite(margin) || margin<0) return false;
        for(double v:triangle) if(!Double.isFinite(v)) return false;
        for(double v:primitive) if(!Double.isFinite(v)) return false;
        for(int axis=1;axis<3;axis++) {
            double ta=Double.POSITIVE_INFINITY,tb=-ta,pa=ta,pb=-ta;
            for(int i=axis;i<9;i+=3) {ta=Math.min(ta,triangle[i]);tb=Math.max(tb,triangle[i]);}
            for(int i=axis;i<primitive.length;i+=3) {pa=Math.min(pa,primitive[i]);pb=Math.max(pb,primitive[i]);}
            if(tb+margin<pa || pb+margin<ta) return false;
        }
        double px=primitive[3]-primitive[0],py=primitive[4]-primitive[1],pz=primitive[5]-primitive[2];
        double qx=primitive[6]-primitive[0],qy=primitive[7]-primitive[1],qz=primitive[8]-primitive[2];
        double crossX=py*qz-pz*qy,crossY=pz*qx-px*qz,crossZ=px*qy-py*qx;
        if(primitive.length==9) {
            if(crossX*crossX+crossY*crossY+crossZ*crossZ<1e-24) return false;
        } else if(Math.abs(crossX*(primitive[9]-primitive[0])+crossY*(primitive[10]-primitive[1])
                +crossZ*(primitive[11]-primitive[2]))<1e-24) return false;
        out[0]=Double.NEGATIVE_INFINITY;out[1]=Double.POSITIVE_INFINITY;
        // Face normals, then cross products of every pair of edges. For triangles, also in-plane edge normals.
        double tx=triangle[3]-triangle[0],ty=triangle[4]-triangle[1],tz=triangle[5]-triangle[2];
        double ux=triangle[6]-triangle[0],uy=triangle[7]-triangle[1],uz=triangle[8]-triangle[2];
        double nx=ty*uz-tz*uy,ny=tz*ux-tx*uz,nz=tx*uy-ty*ux;
        if(nx*nx+ny*ny+nz*nz<1e-24 || !axis(triangle,primitive,margin,nx,ny,nz,out)) return false;
        for(int a=0;a<primitive.length/3-2;a++) for(int b=a+1;b<primitive.length/3-1;b++) for(int c=b+1;c<primitive.length/3;c++) {
            int ia=a*3,ib=b*3,ic=c*3;
            double ax=primitive[ib]-primitive[ia],ay=primitive[ib+1]-primitive[ia+1],az=primitive[ib+2]-primitive[ia+2];
            double bx=primitive[ic]-primitive[ia],by=primitive[ic+1]-primitive[ia+1],bz=primitive[ic+2]-primitive[ia+2];
            double fx=ay*bz-az*by,fy=az*bx-ax*bz,fz=ax*by-ay*bx;
            if(!axis(triangle,primitive,margin,fx,fy,fz,out)) return false;
            if(primitive.length==9) for(int edge=0;edge<3;edge++) {
                int j=edge*3,k=(edge+1)%3*3;
                double ex=primitive[k]-primitive[j],ey=primitive[k+1]-primitive[j+1],ez=primitive[k+2]-primitive[j+2];
                if(!axis(triangle,primitive,margin,fy*ez-fz*ey,fz*ex-fx*ez,fx*ey-fy*ex,out)) return false;
            }
        }
        for(int edge=0;edge<3;edge++) {
            int j=edge*3,k=(edge+1)%3*3;
            double ax=triangle[k]-triangle[j],ay=triangle[k+1]-triangle[j+1],az=triangle[k+2]-triangle[j+2];
            if(primitive.length==9 && !axis(triangle,primitive,margin,ny*az-nz*ay,nz*ax-nx*az,nx*ay-ny*ax,out)) return false;
            for(int a=0;a<primitive.length/3;a++) for(int b=a+1;b<primitive.length/3;b++) {
                int ia=a*3,ib=b*3;
                double bx=primitive[ib]-primitive[ia],by=primitive[ib+1]-primitive[ia+1],bz=primitive[ib+2]-primitive[ia+2];
                if(!axis(triangle,primitive,margin,ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx,out)) return false;
            }
        }
        return out[0]<=out[1];
    }

    private static boolean axis(double[] t,double[] p,double margin,double x,double y,double z,double[] out) {
        double length=Math.sqrt(x*x+y*y+z*z);
        if(length<1e-12) return true;
        x/=length;y/=length;z/=length;
        double ta=Double.POSITIVE_INFINITY,tb=-ta,pa=ta,pb=-ta;
        for(int i=0;i<t.length;i+=3) {double v=t[i]*x+t[i+1]*y+t[i+2]*z;ta=Math.min(ta,v);tb=Math.max(tb,v);}
        for(int i=0;i<p.length;i+=3) {double v=p[i]*x+p[i+1]*y+p[i+2]*z;pa=Math.min(pa,v);pb=Math.max(pb,v);}
        double low=pa-tb-margin,high=pb-ta+margin;
        if(Math.abs(x)<1e-12) return low<=1e-10 && high>=-1e-10;
        double a=low/-x,b=high/-x;
        out[0]=Math.max(out[0],Math.min(a,b));out[1]=Math.min(out[1],Math.max(a,b));
        return out[0]<=out[1]+1e-10;
    }

    /** Only the connected forbidden component containing zero matters. No sorting/allocation per frame. */
    static double choose(double[] low,double[] high,int count,double min,double max) {
        if(low==null || high==null || !Double.isFinite(min) || !Double.isFinite(max) || min>0 || max<0 || min>max
            || count<0 || count>low.length || count>high.length) return Double.NaN;
        double a=0,b=0;boolean collision=false,changed;
        for(int i=0;i<count;i++) {
            if(Double.isNaN(low[i]) || Double.isNaN(high[i]) || low[i]>high[i]) return Double.NaN;
            if(low[i]<=0 && high[i]>=0) {collision=true;a=Math.min(a,low[i]);b=Math.max(b,high[i]);}
        }
        if(!collision) return 0;
        do {
            changed=false;
            for(int i=0;i<count;i++) {
                if(Double.isNaN(low[i]) || Double.isNaN(high[i]) || low[i]>high[i]) return Double.NaN;
                if(low[i]<=b+2*EPS && high[i]>=a-2*EPS) {
                    collision=true;
                    double nextA=Math.min(a,low[i]),nextB=Math.max(b,high[i]);
                    if(nextA<a || nextB>b) {a=nextA;b=nextB;changed=true;}
                }
            }
        } while(changed);
        if(!collision) return 0;
        a-=EPS;b+=EPS;
        if(a<min) return b<=max?b:Double.NaN;
        if(b>max) return a;
        return Math.abs(a)<Math.abs(b)?a:b;
    }
    private CartLegClearance() {}
}
