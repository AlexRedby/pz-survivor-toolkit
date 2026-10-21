package net.alexredby.pztoolkitjavapatches;

import java.util.Arrays;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.scripting.objects.ModelScript;
import zombie.inventory.InventoryItem;
import sun.misc.Unsafe;

public final class CartWheelSpinTest {
    private static void close(double actual, double expected, String message) {
        if(Math.abs(actual-expected)>1e-6) throw new AssertionError(message+": "+actual+" != "+expected);
    }

    private static void metalGeometry(Unsafe unsafe) throws Exception {
        var profile=CartWheelbarrow.METAL;
        if(CartWheelbarrow.forModel("WheelbarrowMetal")!=profile
            || CartWheelbarrow.forType("SaucedWheelbarrow.WheelbarrowMetal")!=profile
            || CartWheelbarrow.forModel("ShoppingCartModel")!=null || CartWheelbarrow.forItem(null)!=null)
            throw new AssertionError("wheelbarrow profile routing changed");
        int[] indices={0,1,2134,2135,2136,2994,2995,2996,3687};
        if(!Arrays.deepEquals(CartWheelSpin.ranges(profile,indices),new int[][]{{0,3,0},{3,3,1},{6,3,0}}))
            throw new AssertionError("metal wheel middle range was not partitioned");
        for(int[] invalid:new int[][]{{2134,2135,2136},{2994,2995,2996},{0,1,3688},{2135,2136,2994},{0,1,2}})
            if(CartWheelSpin.ranges(profile,invalid)!=null) throw new AssertionError("unsafe metal geometry accepted");
        close(CartWheelSpin.advance(profile,.3,profile.worldRadius()*Math.PI/2),.3-Math.PI/2,"metal rolling radius");
        var held=profile.held(new Matrix4f());var center=profile.center(new Vector3f());
        var fixed=held.transformPosition(new Vector3f(center));
        var point=new Vector3f(center).add(0,-profile.radius(),0);
        for(float angle:new float[]{0,.4f,(float)Math.PI/2,(float)Math.PI,-.4f}) {
            var spun=CartWheelSpin.transform(profile,new Matrix4f(held).transpose(),angle,new Matrix4f()).transpose();
            if(spun.transformPosition(new Vector3f(center)).distance(fixed)>1e-6f)
                throw new AssertionError("metal axle moved during wheel rotation");
            close(spun.transformPosition(new Vector3f(point)).distance(fixed),profile.worldRadius()/1.5,"metal tire radius changed");
        }
        close(-fixed.z*1.5,profile.axle(),"metal steering axle differs from rendered tire");
        close(-fixed.x*1.5,profile.lateral(),"metal lateral axle differs from rendered tire");
        var item=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);
        item.setModule("SaucedWheelbarrow");item.setType("WheelbarrowMetal");
        close(CartWheelSpin.follow(item,0,0,0,held),0,"first metal pose");
        float travel=(float)(profile.worldRadius()*.7);
        close(CartWheelSpin.follow(item,0,-travel,0,held),-.7,"metal actual axle travel");
        var tilted=new Matrix4f(held).translate(center).rotateX(.4f).translate(-center.x,-center.y,-center.z);
        close(CartWheelSpin.follow(item,0,-travel,0,tilted),-1.1,"metal stationary tire counter-rotation");
        // Returned geometry must not expose the shared profile's calibration to callers.
        held.identity();center.zero();
        if(profile.held(new Matrix4f()).equals(held) || profile.center(new Vector3f()).equals(center))
            throw new AssertionError("mutable geometry escaped its profile");
    }

    public static void main(String[] args) throws Exception {
        int[] elements={0,1,1113,1114,1115,8115,4,5,6,7,8,9};
        int[] original=elements.clone();
        int[][] runs=CartWheelSpin.ranges(elements);
        if(!Arrays.deepEquals(runs,new int[][]{{0,3,1},{3,3,0},{6,6,1}})
            || !Arrays.equals(elements,original)) throw new AssertionError("original indexed geometry was changed or partitioned incorrectly");
        for(int[] invalid:new int[][]{ {},{0,1},{0,1,1114},{-1,0,1},{0,1,8116},{0,1,2},{1114,1115,1116} }) {
            if(CartWheelSpin.ranges(invalid)!=null) throw new AssertionError("unsafe geometry accepted: "+Arrays.toString(invalid));
        }
        double phase=.3;
        close(CartWheelSpin.advance(phase,0),phase,"blocked cart spun");
        close(CartWheelSpin.advance(phase,CartWheelSpin.WORLD_RADIUS*Math.PI/2),phase-Math.PI/2,"accepted forward travel");
        close(CartWheelSpin.advance(phase,-CartWheelSpin.WORLD_RADIUS*Math.PI/2),phase+Math.PI/2,"accepted reverse travel");
        for(double invalid:new double[]{Double.NaN,Double.POSITIVE_INFINITY,2,-2})
            close(CartWheelSpin.advance(phase,invalid),phase,"teleport/nonfinite travel spun wheel");
        close(CartWheelSpin.advance(0,CartWheelSpin.WORLD_RADIUS*Math.PI*2),0,"one circumference");
        var center=new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z);
        var point=new Vector3f(center).add(0,-CartWheelSpin.RADIUS,0);
        var cart=new Matrix4f().translation(.2f,.3f,-.7f).rotateXYZ(.18f,.4f,-.15f).scale(76.5f);
        var stored=new Matrix4f(cart).transpose();
        var before=new Matrix4f(stored);
        for(float angle:new float[]{0,.4f,(float)Math.PI/2,(float)Math.PI,-.4f}) {
            var spun=CartWheelSpin.transform(stored,angle,new Matrix4f()).transpose();
            if(!stored.equals(before)) throw new AssertionError("shared parent transform changed");
            var fixed=cart.transformPosition(new Vector3f(center));
            if(spun.transformPosition(new Vector3f(center)).distance(fixed)>1e-6f)
                throw new AssertionError("wheel axle moved while spinning");
            close(spun.transformPosition(new Vector3f(point)).distance(fixed),CartWheelSpin.RADIUS*76.5,"wheel radius changed");
            if(angle!=0 && spun.transformPosition(new Vector3f(point)).distance(cart.transformPosition(new Vector3f(point)))<.001f)
                throw new AssertionError("wheel did not visibly rotate");
        }
        var unsafeField=Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        var unsafe=(Unsafe)unsafeField.get(null);
        var item=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);
        item.setModule("SaucedWheelbarrow");item.setType("WheelbarrowWood");
        var identity=new Matrix4f().scale(76.5f);
        close(CartWheelSpin.follow(item,0,0,0,identity),0,"first world pose");
        double distance=CartWheelSpin.WORLD_RADIUS*.7;
        close(CartWheelSpin.follow(item,0,(float)-distance,0,identity),-.7,"actual axle travel");
        var tilted=new Matrix4f(identity).translate(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z)
            .rotateX(.4f).translate(-CartWheelSpin.CENTER_X,-CartWheelSpin.CENTER_Y,-CartWheelSpin.CENTER_Z);
        close(CartWheelSpin.follow(item,0,(float)-distance,0,tilted),-1.1,"stationary tire compensates cart pitch");
        var banked=new Matrix4f(tilted).rotateLocalZ(.12f);
        var centerBefore=tilted.transformPosition(new Vector3f(center));
        banked.translateLocal(centerBefore.sub(banked.transformPosition(new Vector3f(center))));
        close(CartWheelSpin.follow(item,0,(float)-distance,0,banked),-1.1,"bank did not introduce a false pitch change");
        close(CartWheelSpin.itemPhase(item),-1.1,"same item retains rendered phase");
        close(CartWheelSpin.follow(item,0,(float)-distance,0,tilted),-1.1,"held/world handoff continuity");
        close(CartWheelSpin.follow(item,0,0,0,tilted),-.4,"reverse travel");
        close(CartWheelSpin.follow(item,50,50,0,tilted),-.4,"teleport does not spin wheel");
        if(!Double.isNaN(CartWheelSpin.follow(item,Float.NaN,0,0,identity))) throw new AssertionError("invalid pose accepted");
        close(CartWheelSpin.itemPhase(item),-.4,"invalid pose poisoned phase");
        var other=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);other.setModule("SaucedWheelbarrow");other.setType("WheelbarrowWood");
        close(CartWheelSpin.follow(other,0,0,0,identity),0,"phase leaked to a different cart");
        other.setType("WheelbarrowMetal");
        close(CartWheelSpin.follow(other,0,0,0,CartWheelbarrow.METAL.held(new Matrix4f())),0,"type change reused wooden wheel pose");
        var slot=new ModelSlotRenderData();
        var data=new ModelInstanceRenderData();
        data.modelInstance=new ModelInstance();data.modelInstance.modelScript=new ModelScript();
        data.modelInstance.modelScript.name="WheelbarrowWood";
        slot.modelData.add(data);
        var read=CartWheelSpin.class.getDeclaredMethod("phase",ModelInstanceRenderData.class);read.setAccessible(true);
        CartWheelSpin.prepare(slot,.7);
        close((Double)read.invoke(null,data),.7,"simulation angle was not snapshotted");
        CartWheelSpin.prepare(slot,Double.NaN);
        if(read.invoke(null,data)!=null) throw new AssertionError("recycled render data kept a stale wheel angle");
        data.modelInstance.modelScript.name="WheelbarrowMetal";
        CartWheelSpin.prepare(slot,.9);
        close((Double)read.invoke(null,data),.9,"metal wheel phase was not snapshotted");
        data.modelInstance.modelScript.name="ShoppingCartModel";
        CartWheelSpin.prepare(slot,.2);
        if(read.invoke(null,data)!=null) throw new AssertionError("shopping cart entered wheelbarrow split drawing");
        metalGeometry(unsafe);
        System.out.println("CART_WHEEL_SPIN_PASS");
    }
}
