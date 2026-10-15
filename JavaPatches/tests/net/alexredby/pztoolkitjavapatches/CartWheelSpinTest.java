package net.alexredby.pztoolkitjavapatches;

import java.util.Arrays;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.scripting.objects.ModelScript;

public final class CartWheelSpinTest {
    private static void close(double actual, double expected, String message) {
        if(Math.abs(actual-expected)>1e-6) throw new AssertionError(message+": "+actual+" != "+expected);
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
        if(read.invoke(null,data)!=null) throw new AssertionError("metal wheel was modified");
        System.out.println("CART_WHEEL_SPIN_PASS");
    }
}
