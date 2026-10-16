import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
public final class WoodenWheelProbeCheck {
    static void close(double actual,double expected) {
        if(Math.abs(actual-expected)>2e-6)throw new AssertionError(actual+" != "+expected);
    }
    public static void main(String[] args) {
        var slot=new ModelSlotRenderData();
        for(double heading:new double[]{0,.3,Math.PI/2,Math.PI,-Math.PI/2}) {
            slot.animPlayerAngle=(float)(heading+Math.PI/2);
            var forward=WoodenWheelNativeProbe.world(slot,new Vector3f(0,0,-1),true);
            close(forward[0],1.5*Math.cos(heading));close(forward[1],1.5*Math.sin(heading));
            for(float bank:new float[]{-.18f,0,.18f}) {
                var cart=new Matrix4f().rotateZ(bank).rotateX(.4f).scale(76.5f);
                var normal=WoodenWheelNativeProbe.normal(WoodenWheelNativeProbe.world(slot,cart.transformDirection(new Vector3f(0,1,0)),true),
                    WoodenWheelNativeProbe.world(slot,cart.transformDirection(new Vector3f(0,0,1)),true));
                double length=Math.hypot(normal[0],normal[1]);
                close(-normal[1]/length,Math.cos(heading));close(normal[0]/length,Math.sin(heading));
                close(Math.sqrt(normal[0]*normal[0]+normal[1]*normal[1]+normal[2]*normal[2]),1);
            }
        }
        slot.animPlayerAngle=0;slot.x=10;slot.y=20;slot.z=2;
        var point=WoodenWheelNativeProbe.world(slot,new Vector3f(0,1,0),false);
        close(point[0],10);close(point[1],20);close(point[2],2.61237234);
        slot.x=10825;slot.y=10825;
        var shifted=WoodenWheelNativeProbe.world(slot,new Vector3f(.000001f,0,0),false);
        if(Math.abs(shifted[0]-slot.x)<1e-6)throw new AssertionError("large-coordinate model movement was quantized away");
        close(WoodenWheelNativeProbe.difference(new Matrix4f(),new Matrix4f().translation(.1f,0,0)),.1);
        close(WoodenWheelNativeProbe.distance(0,0,0,3,4,0),5);
        close(WoodenWheelNativeProbe.segment(new Matrix4f(),new Matrix4f().translation(3,4,0)),5);
        if(WoodenWheelNativeProbe.drive()!=Integer.MIN_VALUE)throw new AssertionError("diagnostic selfcheck unexpectedly has a live cart driver");
        System.out.println("WOOD_WHEEL_NATIVE_PROBE_CHECK_PASS");
    }
}
