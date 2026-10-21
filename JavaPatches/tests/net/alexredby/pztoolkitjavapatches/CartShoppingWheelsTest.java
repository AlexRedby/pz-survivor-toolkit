package net.alexredby.pztoolkitjavapatches;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import sun.misc.Unsafe;
import zombie.inventory.InventoryItem;

/** Four-wheel movement and source-topology checks without an OpenGL context. */
public final class CartShoppingWheelsTest {
    private static Unsafe unsafe;
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static void close(double actual,double expected,double tolerance,String message){
        check(Double.isFinite(actual)&&Math.abs(actual-expected)<=tolerance,message+": "+actual+" expected "+expected);
    }
    private static double difference(double a,double b){return Math.IEEEremainder(a-b,Math.PI*2);}
    private static InventoryItem item()throws Exception {
        var item=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);
        item.setModule("SaucedCarts");item.setType("ShoppingCart");return item;
    }
    private static Vector3f point(float[] p){return new Vector3f(p[0],p[1],p[2]);}
    private static CartShoppingWheels.Frame follow(InventoryItem item,float x,float y,float angle,Matrix4f cart,long time){
        var frame=CartShoppingWheels.follow(item,x,y,angle,cart,time);
        check(frame!=null,"valid pose rejected");
        check(frame.phases.length==4&&frame.casters.length==2&&frame.relative.length==7,"incomplete wheel snapshot");
        for(double p:frame.phases)check(Double.isFinite(p),"nonfinite wheel phase");
        for(double c:frame.casters)check(Double.isFinite(c),"nonfinite caster angle");
        for(var t:frame.relative)check(t!=null&&t.isFinite(),"nonfinite part transform");
        return frame;
    }
    private static void same(CartShoppingWheels.Frame a,CartShoppingWheels.Frame b,String where){
        for(int i=0;i<4;i++)close(difference(a.phases[i],b.phases[i]),0,3e-5,where+" wheel "+i);
        for(int i=0;i<2;i++)close(difference(a.casters[i],b.casters[i]),0,3e-5,where+" caster "+i);
    }
    private static double radius(){return CartShoppingWheelMesh.RADIUS*1.5;}

    private static void straightAndReverse()throws Exception {
        var item=item();var cart=CartShopping.worldModel(new Matrix4f());
        var start=follow(item,0,0,0,cart,1_000_000_000L);
        var forward=follow(item,-.008f,0,0,cart,1_020_000_000L);
        for(int i=0;i<4;i++)close(difference(forward.phases[i],start.phases[i]),-.008/radius(),3e-5,"forward tire "+i);
        var reverse=follow(item,0,0,0,cart,1_040_000_000L);
        for(int i=0;i<2;i++)close(difference(reverse.phases[i],forward.phases[i]),.008/radius(),3e-5,"rear reverse tire "+i);
        for(int i=2;i<4;i++)check(difference(reverse.phases[i],forward.phases[i])>0,"front reverse tire did not roll backwards");
        for(int i=0;i<2;i++)check(Math.abs(difference(reverse.casters[i],forward.casters[i]))<=.20001,"reverse caster snapped");
        var stopped=follow(item,0,0,0,cart,1_060_000_000L);
        same(reverse,stopped,"stopped");
        for(int i=0;i<7;i++)check(reverse.relative[i].equals(stopped.relative[i],2e-5f),"stopped part transform drifted");
        // Repeated reverse samples remain bounded even while casters turn through a half turn.
        var previous=stopped;
        for(int step=1;step<=30;step++) {
            var next=follow(item,.004f*step,0,0,cart,1_060_000_000L+step*20_000_000L);
            for(int i=0;i<2;i++)check(Math.abs(difference(next.casters[i],previous.casters[i]))<=.20001,"caster reversal discontinuity");
            previous=next;
        }
        check(Math.abs(previous.casters[0])>1&&Math.abs(previous.casters[1])>1,"reverse casters never followed movement");
    }
    private static double[] centerWorld(Matrix4f cart,int wheel,float x,float y,float angle){
        var p=cart.transformPosition(point(CartShoppingWheelMesh.CENTERS[wheel]),new Vector3f());
        double c=Math.cos(angle),s=Math.sin(angle);
        return new double[]{x-1.5*(c*p.x+s*p.z),y+1.5*(-s*p.x+c*p.z)};
    }
    private static void turns()throws Exception {
        var cart=CartShopping.worldModel(new Matrix4f());
        for(float angle:new float[]{.04f,-.04f}) {
            var item=item();var before=follow(item,0,0,0,cart,2_000_000_000L);
            float x=(float)(-.02*Math.cos(angle*.5)),y=(float)(-.02*Math.sin(angle*.5));
            var after=follow(item,x,y,angle,cart,2_020_000_000L);
            for(int i=0;i<2;i++) {
                var a=centerWorld(cart,i,0,0,0);var b=centerWorld(cart,i,x,y,angle);
                double accepted=-(b[0]-a[0])*Math.cos(angle*.5)-(b[1]-a[1])*Math.sin(angle*.5);
                close(difference(after.phases[i],before.phases[i]),-accepted/radius(),3e-5,"independent rear center arc "+i);
            }
            double outer=Math.abs(after.phases[angle>0?0:1]),inner=Math.abs(after.phases[angle>0?1:0]);
            check(outer>inner+.2,"inside and outside rear tires shared a phase");
        }
    }
    private static void continuityAndInvalid()throws Exception {
        var item=item();var cart=CartShopping.worldModel(new Matrix4f());
        follow(item,0,0,0,cart,3_000_000_000L);
        var before=follow(item,-.01f,0,0,cart,3_020_000_000L);
        // Equivalent global geometry represented by different actor/attachment coordinates.
        var attached=new Matrix4f().translation(.12f,0,-.08f).mul(cart);
        var attachedBefore=new Matrix4f(attached);
        var handoff=follow(item,.17f,.12f,0,attached,3_040_000_000L);
        same(before,handoff,"equipped/world coordinate handoff");
        check(attached.equals(attachedBefore),"follow mutated caller attachment");
        var other=follow(item(),0,0,0,cart,3_040_000_000L);
        for(double p:other.phases)close(p,0,1e-9,"phase leaked between cart items");
        var invalid=new Matrix4f(cart).m00(Float.NaN);
        check(CartShoppingWheels.follow(item,Float.NaN,0,0,cart,3_050_000_000L)==null,"NaN position accepted");
        check(CartShoppingWheels.follow(item,0,Float.POSITIVE_INFINITY,0,cart,3_050_000_000L)==null,"infinite position accepted");
        check(CartShoppingWheels.follow(item,0,0,Float.NaN,cart,3_050_000_000L)==null,"NaN heading accepted");
        check(CartShoppingWheels.follow(item,0,0,0,invalid,3_050_000_000L)==null,"NaN matrix accepted");
        check(CartShoppingWheels.follow(item,0,0,0,null,3_050_000_000L)==null,"null matrix accepted");
        check(CartShoppingWheels.follow(item,0,0,0,new Matrix4f(cart).scale(0),3_050_000_000L)==null,"singular matrix accepted");
        check(CartShoppingWheels.follow(item,0,0,0,new Matrix4f(cart).scale(-1,1,1),3_050_000_000L)==null,"reflection accepted");
        check(CartShoppingWheels.follow(item,0,0,0,cart,-1)==null,"invalid sample time accepted");
        check(CartShoppingWheels.follow(null,0,0,0,cart,3_050_000_000L)==null,"null item accepted");
        var unsupported=item();unsupported.setType("Other");
        check(CartShoppingWheels.follow(unsupported,0,0,0,cart,3_050_000_000L)==null,"unsupported item accepted");
        same(handoff,follow(item,.17f,.12f,0,attached,3_060_000_000L),"invalid pose poisoned ledger");
        var teleport=follow(item,50,50,0,attached,3_080_000_000L);
        same(handoff,teleport,"teleport");
        var resumed=follow(item,49.992f,50,0,attached,3_100_000_000L);
        close(difference(resumed.phases[0],teleport.phases[0]),-.008/radius(),1e-4,"travel after teleport");
        same(resumed,follow(item,49.992f,50,0,attached,3_120_000_000L),"stopped after teleport");
    }
    private static void circularGeometry()throws Exception {
        for(var cart:new Matrix4f[]{CartShopping.worldModel(new Matrix4f()),CartShopping.held(new Matrix4f())}) {
            var item=item();var original=new Matrix4f(cart);
            var axle=cart.transformDirection(new Vector3f(0,0,1)).normalize();
            var forward=new Vector3f(0,1,0).cross(axle).normalize();
            for(int step=0;step<12;step++) {
                float travel=.012f*step;
                var frame=follow(item,-1.5f*forward.x*travel,1.5f*forward.z*travel,0,cart,4_000_000_000L+step*20_000_000L);
                check(CartShoppingWheels.transform(cart,frame,0,false,new Matrix4f()).equals(cart,2e-5f),"body moved with tire animation");
                for(int part=5;part<=6;part++)check(CartShoppingWheels.transform(cart,frame,part,false,new Matrix4f()).equals(cart,2e-5f),"straight support spun with tire");
                for(int i=0;i<4;i++) {
                    var center=cart.transformPosition(point(CartShoppingWheelMesh.CENTERS[i]),new Vector3f());
                    var transform=CartShoppingWheels.transform(cart,frame,i+1,false,new Matrix4f());
                    var transposed=CartShoppingWheels.transform(new Matrix4f(cart).transpose(),frame,i+1,true,new Matrix4f()).transpose();
                    check(transform.equals(transposed,3e-5f),"native transpose path changed tire pose");
                    check(transform.transformPosition(point(CartShoppingWheelMesh.CENTERS[i]),new Vector3f()).distance(center)<2e-5,"tire axle moved during roll");
                    float minimum=Float.POSITIVE_INFINITY;
                    for(float[] raw:CartShoppingWheelMesh.PART_POINTS[i]) {
                        var p=transform.transformPosition(point(raw),new Vector3f());minimum=Math.min(minimum,p.y);
                        var radial=new Vector3f(p).sub(center);radial.fma(-radial.dot(axle),axle);
                        close(radial.length(),CartShoppingWheelMesh.RADIUS,3e-6,"tire did not remain a physical circle");
                    }
                    check(minimum>=.00797f&&minimum<=.00818f,"rotated tire lost floor support: "+minimum);
                }
            }
            check(cart.equals(original),"wheel animation mutated source cart matrix");
        }
    }
    private static List<int[]> fan(int[][] faces){
        var result=new ArrayList<int[]>();
        for(var f:faces)for(int i=1;i<f.length-1;i++)result.add(new int[]{f[0],f[i],f[i+1]});
        return result;
    }
    private static void topology(){
        for(int part=0;part<6;part++) {
            var triangles=fan(CartShoppingWheelMesh.PART_FACES[part]);
            check(CartShoppingWheels.topology(CartShoppingWheelMesh.PART_POINTS[part],CartShoppingWheelMesh.PART_FACES[part],triangles),"calibrated convex source polygons rejected");
            var duplicate=new ArrayList<>(triangles);duplicate.set(1,duplicate.get(0));
            check(!CartShoppingWheels.topology(CartShoppingWheelMesh.PART_POINTS[part],CartShoppingWheelMesh.PART_FACES[part],duplicate),"duplicate source triangle accepted");
        }
        float[][] square={{0,0,0},{1,0,0},{1,1,0},{0,1,0}};int[][] faces={{0,1,2,3}};
        check(CartShoppingWheels.topology(square,faces,List.of(new int[]{0,1,3},new int[]{1,2,3})),"alternative valid diagonal rejected");
        for(List<int[]> invalid:List.of(List.of(new int[]{0,1,2}),List.of(new int[]{0,1,2},new int[]{0,1,2}),
            List.of(new int[]{0,0,1},new int[]{0,2,3}),List.of(new int[]{0,1,7},new int[]{0,2,3}),
            List.of(new int[]{-1,1,2},new int[]{0,2,3})))
            check(!CartShoppingWheels.topology(square,faces,invalid),"invalid or duplicate topology accepted");
        float[][] split={{0,0,0},{1,0,0},{1,1,0},{0,1,0},{2,0,0},{3,0,0},{3,1,0},{2,1,0}};
        check(!CartShoppingWheels.topology(split,new int[][]{{0,1,2,3},{4,5,6,7}},List.of(new int[]{0,1,4})),"mixed source faces accepted");
        for(float value:new float[]{Float.NaN,Float.POSITIVE_INFINITY}) {
            var bad=new float[][]{{value,0,0},{1,0,0},{1,1,0},{0,1,0}};
            check(!CartShoppingWheels.topology(bad,faces,fan(faces)),"nonfinite topology accepted");
        }
        check(!CartShoppingWheels.topology(new float[][]{{0,0,0},{1,0,0},{2,0,0}},new int[][]{{0,1,2}},List.of(new int[]{0,1,2})),"zero-area triangle accepted");
        float[] tire=new float[64*3];for(int i=0;i<64;i++)System.arraycopy(CartShoppingWheelMesh.PART_POINTS[0][i],0,tire,i*3,3);
        check(CartShoppingWheels.pointHash(tire).equals("1c543017d267f985c4d2b97f1ce60a791db29fa72413c24fc8edee0efd962f4f"),"float-bit signature differs from independent source audit");
        var expanded=new float[tire.length*2];
        for(int i=0;i<64;i++)for(int j=0;j<2;j++)System.arraycopy(tire,(63-i)*3,expanded,(i*2+j)*3,3);
        check(CartShoppingWheels.pointHash(tire).equals(CartShoppingWheels.pointHash(expanded)),"UV/normal position duplication or vertex order changed signature");
        check(CartShoppingWheels.partition(null,new int[0])==null&&CartShoppingWheels.partition(tire,null)==null
            &&CartShoppingWheels.partition(new float[1],new int[0])==null&&CartShoppingWheels.partition(tire,new int[]{0,1})==null
            &&CartShoppingWheels.partition(tire,new int[]{0,1,2})==null,"uncalibrated/malformed mesh accepted");
    }
    // Optional offline full-model fixtures: packed xyz float32 LE, then native or source-derived triangle int32 LE.
    private static void fullMesh(Path positions,Path indices)throws Exception {
        var p=ByteBuffer.wrap(Files.readAllBytes(positions)).order(ByteOrder.LITTLE_ENDIAN);
        var e=ByteBuffer.wrap(Files.readAllBytes(indices)).order(ByteOrder.LITTLE_ENDIAN);
        check(p.remaining()%12==0&&e.remaining()%12==0,"malformed offline fixture");
        var xyz=new float[p.remaining()/4];var elements=new int[e.remaining()/4];
        for(int i=0;i<xyz.length;i++)xyz[i]=p.getFloat();for(int i=0;i<elements.length;i++)elements[i]=e.getInt();
        var original=elements.clone();var runs=CartShoppingWheels.partition(xyz,elements);
        check(runs!=null,"calibrated full mesh rejected");check(Arrays.equals(elements,original),"partition changed native EBO");
        int offset=0;var counts=new int[7];
        for(var run:runs){check(run[0]==offset&&run[1]>0&&run[1]%3==0,"index run gap/overlap");offset+=run[1];counts[run[2]]+=run[1]/3;}
        check(offset==elements.length,"partition omitted original triangles");
        for(int i=1;i<7;i++)check(counts[i]==CartShoppingWheelMesh.PART_TRIANGLES[i-1],"wrong moving triangle count");
        var corrupt=elements.clone();corrupt[0]=xyz.length/3;
        check(CartShoppingWheels.partition(xyz,corrupt)==null,"out-of-range native index accepted");
        var mixed=elements.clone();var tireRun=Arrays.stream(runs).filter(r->r[2]==1).findFirst().orElseThrow();
        var otherRun=Arrays.stream(runs).filter(r->r[2]==2).findFirst().orElseThrow();mixed[tireRun[0]]=elements[otherRun[0]];
        check(CartShoppingWheels.partition(xyz,mixed)==null,"cross-wheel native triangle accepted");
        var duplicate=elements.clone();System.arraycopy(elements,tireRun[0],duplicate,tireRun[0]+3,3);
        check(CartShoppingWheels.partition(xyz,duplicate)==null,"duplicate native tire triangle accepted");
        var nonfinite=xyz.clone();nonfinite[0]=Float.NaN;
        check(CartShoppingWheels.partition(nonfinite,elements)==null,"nonfinite native mesh accepted");
    }
    public static void main(String[] args)throws Exception {
        var field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        straightAndReverse();turns();continuityAndInvalid();circularGeometry();topology();
        if(args.length==2)fullMesh(Path.of(args[0]),Path.of(args[1]));else check(args.length==0,"expected optional xyz-f32le and elements-i32le paths");
        System.out.println("CART_SHOPPING_WHEELS_PASS (signed center travel, independent turn phases, bounded casters, item/handoff continuity, circular floor support, source topology)");
    }
}
