package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Vector3f;

/** Measured metal tire/feet support for the unheld model, before the native item yaw. */
public final class CartWorldSupport {
    // Native VBO 34c9a265...: lowest left/right support-foot vertices.
    private static final Vector3f LEFT=new Vector3f(-8.86394978f,-20.28660011f,37.90950012f);
    private static final Vector3f RIGHT=new Vector3f(-38.22069931f,-20.28660011f,37.90950012f);
    // Solve footY*cos(a)-footZ*sin(a) = wheelCenterY*cos(a)-wheelCenterZ*sin(a)-radius.
    // The cylindrical envelope supports every retained wheel shader phase, rather than one polygon vertex.
    private static final float PITCH=(float)Math.toRadians(5.637007483322471);
    private static final float FLOOR=.008f-.00175f*2.44949f/1.5f;

    /** laterScale is the scale native code applies after this call; it never scales model translation. */
    public static boolean apply(String type, Matrix4f transform, float laterScale) {
        if(!"SaucedWheelbarrow.WheelbarrowMetal".equals(type) || transform==null || !transform.isFinite()
            || !Float.isFinite(laterScale) || laterScale<=0) return false;
        var scale=transform.getScale(new Vector3f());
        if(scale.x<=0 || Math.abs(scale.x-scale.y)>scale.x*.0001f
            || Math.abs(scale.x-scale.z)>scale.x*.0001f || transform.determinant()<=0) return false;
        var profile=CartWheelbarrow.METAL;
        var axle=profile.center(new Vector3f());
        var effective=new Matrix4f(transform).scale(laterScale);
        var before=effective.transformPosition(axle,new Vector3f());
        var result=new Matrix4f(transform);
        // Absolute calibration makes a repeated readiness callback harmless.
        float current=(float)Math.atan2(result.m12(),result.m11());
        result.rotateX(PITCH-current);
        effective.set(result).scale(laterScale);
        var after=effective.transformPosition(axle,new Vector3f());
        result.m30(result.m30()+before.x-after.x).m32(result.m32()+before.z-after.z);
        effective.set(result).scale(laterScale);
        float lowest=Math.min(CartGrounding.wheelbarrowLowest(effective,profile),
            Math.min(effective.transformPosition(LEFT,new Vector3f()).y,effective.transformPosition(RIGHT,new Vector3f()).y));
        result.m31(result.m31()+FLOOR-lowest);
        if(!result.isFinite()) return false;
        transform.set(result);
        return true;
    }

    private CartWorldSupport() {}
}
