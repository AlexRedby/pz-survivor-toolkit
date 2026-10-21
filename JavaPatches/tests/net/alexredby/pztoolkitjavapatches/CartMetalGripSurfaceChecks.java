package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.SkinningData;

/** Full measured hand triangles against the finite shaft, including faces between contact samples. */
public final class CartMetalGripSurfaceChecks {
    private static final double SCALE=.0091743395, ZMIN=52.2465, ZMAX=85.63253;
    private record Contact(String part,int[] source,double[] bary) {}
    private record Weight(String bone,float weight,Vector3f point) {}
    private record Vertex(int source,Vector3f fixed,List<Weight> weights) {}
    private static final class Rig {
        boolean female,left;
        final Map<String,Matrix4f> bones=new HashMap<>();
        final List<Vertex> vertices=new ArrayList<>();
        final List<int[]> faces=new ArrayList<>();
        final List<double[]> ring=new ArrayList<>();
        final List<Contact> contacts=new ArrayList<>();
    }
    private static List<Rig> fixtures() throws Exception {
        var path=Path.of(System.getProperty("pz.test.project","."))
            .resolve("JavaPatches/tests/fixtures/metal-hand-surfaces.csv");
        var result=new ArrayList<Rig>();Rig rig=null;
        for(String line:Files.readAllLines(path)) {
            if(line.isBlank() || line.startsWith("#")) continue;
            var c=line.split(",");
            switch(c[0]) {
                case "rig" -> {
                    rig=new Rig();rig.female=c[1].equals("female");rig.left=c[2].equals("L");result.add(rig);
                }
                case "bone" -> {
                    var m=new float[16];for(int i=0;i<16;i++)m[i]=Float.parseFloat(c[i+2]);
                    rig.bones.put(c[1],new Matrix4f().set(m));
                }
                case "vertex" -> rig.vertices.add(new Vertex(Integer.parseInt(c[1]),point(c,2),new ArrayList<>()));
                case "weight" -> rig.vertices.get(rig.vertices.size()-1).weights.add(new Weight(c[1],Float.parseFloat(c[2]),point(c,3)));
                case "face" -> rig.faces.add(new int[]{Integer.parseInt(c[1]),Integer.parseInt(c[2]),Integer.parseInt(c[3])});
                case "contact" -> rig.contacts.add(new Contact(c[1],
                    new int[]{Integer.parseInt(c[2]),Integer.parseInt(c[3]),Integer.parseInt(c[4])},
                    new double[]{Double.parseDouble(c[5]),Double.parseDouble(c[6]),Double.parseDouble(c[7])}));
                case "ring" -> rig.ring.add(new double[]{Double.parseDouble(c[1]),Double.parseDouble(c[2])});
                default -> throw new AssertionError("Unknown mesh fixture row: "+c[0]);
            }
        }
        if(result.size()!=4 || result.stream().anyMatch(r->r.vertices.size()!=34 || r.faces.size()!=42 || r.ring.size()<30 || r.contacts.size()!=3))
            throw new AssertionError("Incomplete native hand/shaft fixtures");
        return result;
    }
    private static Vector3f point(String[] c,int i) {
        return new Vector3f(Float.parseFloat(c[i]),Float.parseFloat(c[i+1]),Float.parseFloat(c[i+2]));
    }
    private static SkinningData actor(String side) {
        var ids=new HashMap<String,Integer>();var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        String[] names={"Bip01_Spine","Bip01_"+side+"_Hand","Bip01_"+side+"_Finger0","Bip01_"+side+"_Finger1"};
        for(int i=0;i<names.length;i++){ids.put(names[i],i);offsets.add(new org.lwjgl.util.vector.Matrix4f());}
        return new SkinningData(new HashMap<>(),offsets,offsets,offsets,List.of(-1,0,1,1),ids);
    }
    private static List<double[]> planes(Rig rig) {
        var result=new ArrayList<double[]>();
        for(int i=0;i<rig.ring.size();i++) {
            var a=rig.ring.get(i);var b=rig.ring.get((i+1)%rig.ring.size());
            double dx=b[0]-a[0],dy=b[1]-a[1],length=Math.hypot(dx,dy);
            result.add(new double[]{dy/length,-dx/length,0,(a[0]*dy-a[1]*dx)/length});
        }
        result.add(new double[]{0,0,-1,-ZMIN});result.add(new double[]{0,0,1,ZMAX});return result;
    }
    private static double areaInside(Vector3d[] triangle,List<double[]> planes) {
        var polygon=new ArrayList<>(List.of(triangle));
        for(var plane:planes) {
            var next=new ArrayList<Vector3d>();
            if(polygon.isEmpty()) return 0;
            var previous=polygon.get(polygon.size()-1);double a=distance(previous,plane);
            for(var current:polygon) {
                double b=distance(current,plane);
                if((a<=0)!=(b<=0)) next.add(new Vector3d(current).sub(previous).mul(a/(a-b)).add(previous));
                if(b<=0) next.add(current);
                previous=current;a=b;
            }
            polygon=next;
        }
        double area=0;
        for(int i=1;i+1<polygon.size();i++)
            area+=new Vector3d(polygon.get(i)).sub(polygon.get(0))
                .cross(new Vector3d(polygon.get(i+1)).sub(polygon.get(0))).length()*.5;
        return area*SCALE*SCALE;
    }
    private static double distance(Vector3d p,double[] plane) {
        // One micrometre inward avoids classifying an exactly tangent face as penetration.
        return p.x*plane[0]+p.y*plane[1]+p.z*plane[2]-plane[3]+.000001/SCALE;
    }
    private static Matrix4f legacy(Rig rig,Matrix4f cart) {return legacy(rig,cart,false);}
    private static Matrix4f legacy(Rig rig,Matrix4f cart,boolean transition) {
        var axis=cart.transformDirection(new Vector3f(0,0,1)).normalize();
        var down=cart.transformDirection(new Vector3f(0,-1,0)).normalize();
        var inward=down.cross(axis,new Vector3f()).normalize().mul(rig.left?1:-1);
        float radial=(float)Math.toRadians(5),beta=(float)Math.toRadians(40);
        if(transition) {
            var held=CartWheelbarrow.METAL.held(new Matrix4f());
            double heldAngle=Math.atan2(held.m21(),Math.hypot(held.m20(),held.m22()));
            double angle=Math.atan2(cart.m21(),Math.hypot(cart.m20(),cart.m22()));
            double lift=Math.max(0,Math.min(1,(angle+CartWorldSupport.pitch())/(heldAngle+CartWorldSupport.pitch())));
            radial=(float)Math.toRadians(-20+25*lift);
        }
        var x=down.mul((float)Math.cos(radial),new Vector3f()).fma((float)Math.sin(radial),inward);
        var z=inward.mul((float)Math.cos(radial),new Vector3f()).fma(-(float)Math.sin(radial),down);
        x.mul((float)Math.cos(beta)).fma(-(float)Math.sin(beta),axis).normalize();
        var y=z.cross(x,new Vector3f()).normalize();z=x.cross(y,new Vector3f()).normalize();
        var hand=new Matrix4f().m00(x.x).m01(x.y).m02(x.z).m10(y.x).m11(y.y).m12(y.z).m20(z.x).m21(z.y).m22(z.z);
        var point=cart.transformPosition(new Vector3f(rig.left?-7.409948f:-39.674755f,6.614635f,81.45f));
        float palmX=rig.female?.056f:.057f,depth=rig.female?.025f:.022f;
        return hand.setTranslation(point.x-hand.m00()*palmX-hand.m20()*depth,
            point.y-hand.m01()*palmX-hand.m21()*depth,point.z-hand.m02()*palmX-hand.m22()*depth);
    }
    private static int intersections(Rig rig,Matrix4f cart,boolean old,boolean transition) {
        String side=rig.left?"L":"R";var hand=old?legacy(rig,cart):new Matrix4f();
        if(!old && !(transition?CartGrip.transitionTarget("WheelbarrowMetal",rig.left,rig.female,new Matrix4f(),cart,hand)
            :CartGrip.target("WheelbarrowMetal",rig.left,rig.female,new Matrix4f(),cart,hand)))
            throw new AssertionError("Metal hand target unavailable");
        if(!old) {
            var prior=legacy(rig,cart,transition);
            if(hand.getTranslation(new Vector3f()).distance(prior.getTranslation(new Vector3f()))>.015f)
                throw new AssertionError("Hand correction moved the accepted arm stance");
            for(int col=0;col<3;col++) if(hand.getColumn(col,new Vector3f()).distance(prior.getColumn(col,new Vector3f()))>.000002f)
                throw new AssertionError("Hand correction changed the accepted wrist orientation");
            if(transition) {
                double heldAngle=Math.atan2(CartWheelbarrow.METAL.held(new Matrix4f()).m21(),
                    Math.hypot(CartWheelbarrow.METAL.held(new Matrix4f()).m20(),CartWheelbarrow.METAL.held(new Matrix4f()).m22()));
                double angle=Math.atan2(cart.m21(),Math.hypot(cart.m20(),cart.m22()));
                if(Math.abs(angle-heldAngle)<.000001) {
                    var steady=new Matrix4f();CartGrip.target("WheelbarrowMetal",rig.left,rig.female,new Matrix4f(),cart,steady);
                    if(!hand.equals(steady,.000002f)) throw new AssertionError("Wrist changed at held handoff");
                }
            }
        }
        var thumb=new Matrix4f(hand).mul(rig.bones.get("Finger0"));
        var finger=new Matrix4f(hand).mul(rig.bones.get("Finger1"));
        Matrix4f[] poses={new Matrix4f(),hand,thumb,finger};
        if(old) finger.set(hand).translate(rig.bones.get("Finger1").getTranslation(new Vector3f())).rotateY(rig.female?-1.7f:-1.5f);
        else {
            var t=thumb.getTranslation(new Vector3f());var f=finger.getTranslation(new Vector3f());
            CartGrip.closeFingers(poses,actor(side),side,CartGrip.grasp(rig.female,"WheelbarrowMetal"),true);
            if(poses[2].getTranslation(new Vector3f()).distance(t)>.000002f
                || poses[3].getTranslation(new Vector3f()).distance(f)>.000002f)
                throw new AssertionError("Metal closure moved a native knuckle");
        }
        var inverse=new Matrix4f(hand).invert();var local=new HashMap<String,Matrix4f>();
        local.put("Hand",new Matrix4f());local.put("Finger0",new Matrix4f(inverse).mul(poses[2]));
        local.put("Finger1",new Matrix4f(inverse).mul(poses[3]));
        var toCart=new Matrix4f(cart).invert().mul(hand);var points=new Vector3d[rig.vertices.size()];
        for(int i=0;i<points.length;i++) {
            var v=rig.vertices.get(i);var p=new Vector3f(v.fixed);
            for(var w:v.weights)p.fma(w.weight,local.get(w.bone).transformPosition(new Vector3f(w.point)));
            toCart.transformPosition(p);points[i]=new Vector3d(p.x,p.y,p.z);
        }
        int hits=0;var planes=planes(rig);
        for(var face:rig.faces) {
            Vector3d[] triangle={points[face[0]],points[face[1]],points[face[2]]};
            if(areaInside(triangle,planes)>1e-12)hits++;
        }
        if(!old) contact(rig,points);
        return hits;
    }
    private static double physicalGap(Vector3d point,Rig rig) {
        double xy=Double.POSITIVE_INFINITY;boolean inside=true;
        for(int i=0;i<rig.ring.size();i++) {
            var a=rig.ring.get(i);var b=rig.ring.get((i+1)%rig.ring.size());
            double x=b[0]-a[0],y=b[1]-a[1],px=point.x-a[0],py=point.y-a[1];
            inside&=px*y-py*x<=1e-8;
            double t=Math.max(0,Math.min(1,(px*x+py*y)/(x*x+y*y)));
            xy=Math.min(xy,Math.hypot(px-t*x,py-t*y));
        }
        if(inside)xy=0;
        double axial=Math.max(0,Math.max(ZMIN-point.z,point.z-ZMAX));
        return Math.hypot(xy,axial)*SCALE;
    }
    private static void contact(Rig rig,Vector3d[] points) {
        var support=new HashMap<String,Vector3d>();
        for(var patch:rig.contacts) {
            var p=new Vector3d();double sum=0;
            var ids=new int[3];
            for(int k=0;k<3;k++) {
                int id=-1;
                for(int i=0;i<rig.vertices.size();i++)if(rig.vertices.get(i).source==patch.source[k]){id=i;break;}
                if(id<0 || patch.bary[k]<0)throw new AssertionError("Invalid measured contact patch");
                ids[k]=id;sum+=patch.bary[k];p.fma(patch.bary[k],points[id]);
            }
            if(Math.abs(sum-1)>1e-9 || rig.faces.stream().noneMatch(face->
                java.util.Arrays.stream(face).allMatch(i->i==ids[0] || i==ids[1] || i==ids[2])))
                throw new AssertionError("Contact patch is not on an actual native triangle");
            double gap=physicalGap(p,rig);
            if(gap>.0025 || p.z<ZMIN || p.z>ZMAX)
                throw new AssertionError("Physical surface contact missed shaft: female="+rig.female+" left="+rig.left+" part="+patch.part+" gap="+gap);
            support.put(patch.part,p);
        }
        double center=rig.left?-7.409948:-39.674755;
        var thumb=new Vector3d(support.get("Finger0")).sub(center,6.614635,0);thumb.z=0;thumb.normalize();
        var finger=new Vector3d(support.get("Finger1")).sub(center,6.614635,0);finger.z=0;finger.normalize();
        if(thumb.dot(finger)>-.25)throw new AssertionError("Thumb and mitten no longer oppose the shaft");
    }
    public static void check() throws Exception {
        int checked=0,oldHits=0;
        for(var rig:fixtures()) {
            var held=CartWheelbarrow.METAL.held(new Matrix4f());
            int baseline=intersections(rig,held,true,false);
            if(baseline!=(rig.female?13:14))throw new AssertionError("Old native hand overlap no longer reproduced: "+baseline);
            oldHits+=baseline;
            for(int step=-1;step<=40;step++) {
                double heldAngle=Math.atan2(held.m21(),Math.hypot(held.m20(),held.m22()));
                float pitch=(float)(CartWorldSupport.pitch()-(heldAngle+CartWorldSupport.pitch())*step/40);
                var cart=step<0?held:new Matrix4f().translation(.13f,.24f,-.71f).rotateY(.7f).rotateX(pitch).scale((float)SCALE);
                int hits=intersections(rig,cart,false,step>=0);
                if(hits!=0)throw new AssertionError("Native metal hand surface intersects shaft: female="+rig.female+" left="+rig.left+" pitchStep="+step+" triangles="+hits);
                checked++;
            }
        }
        System.out.println("CART_METAL_GRIP_SURFACE_PASS paths="+checked+" oldIntersectingTriangles="+oldHits);
    }
    public static void main(String[] args) throws Exception {check();}
}
