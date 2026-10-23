package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f

/** Measured cart tire/feet support for the unheld model, before the native item yaw. */
object CartWorldSupport {
    // Native VBO 34c9a265...: lowest left/right support-foot vertices.
    private val LEFT = Vector3f(-8.86394978f, -20.28660011f, 37.90950012f)
    private val RIGHT = Vector3f(-38.22069931f, -20.28660011f, 37.90950012f)
    // Solve footY*cos(a)-footZ*sin(a) = wheelCenterY*cos(a)-wheelCenterZ*sin(a)-radius.
    // The cylindrical envelope supports every retained wheel shader phase, rather than one polygon vertex.
    private val PITCH = Math.toRadians(5.637007483322471).toFloat()
    private const val FLOOR = .008f - .00175f * 2.44949f / 1.5f
    @JvmStatic fun pitch(): Float = PITCH

    /** Native direct drawing adds .00175 world Z; the atlas and action placement do not. */
    @JvmStatic fun applyDirect(type: String?, transform: Matrix4f?, laterScale: Float): Boolean {
        if (!apply(type, transform, laterScale)) return false
        if ("SaucedCarts.ShoppingCart" == type) transform!!.m31(transform.m31() - .00175f * 2.44949f / 1.5f)
        return true
    }

    /** laterScale is the scale native code applies after this call; it never scales model translation. */
    @JvmStatic fun apply(type: String?, transform: Matrix4f?, laterScale: Float): Boolean {
        if ("SaucedCarts.ShoppingCart" == type) return CartShopping.support(transform, laterScale)
        if ("SaucedWheelbarrow.WheelbarrowMetal" != type || transform == null || !transform.isFinite
            || !java.lang.Float.isFinite(laterScale) || laterScale <= 0) return false
        val scale = transform.getScale(Vector3f())
        if (scale.x <= 0 || Math.abs(scale.x - scale.y) > scale.x * .0001f
            || Math.abs(scale.x - scale.z) > scale.x * .0001f || transform.determinant() <= 0) return false
        val profile = CartWheelbarrow.METAL
        val axle = profile.center(Vector3f())
        val effective = Matrix4f(transform).scale(laterScale)
        val before = effective.transformPosition(axle, Vector3f())
        val result = Matrix4f(transform)
        // Absolute calibration makes a repeated readiness callback harmless.
        val current = Math.atan2(result.m12().toDouble(), result.m11().toDouble()).toFloat()
        result.rotateX(PITCH - current)
        effective.set(result).scale(laterScale)
        val after = effective.transformPosition(axle, Vector3f())
        result.m30(result.m30() + before.x - after.x).m32(result.m32() + before.z - after.z)
        effective.set(result).scale(laterScale)
        val lowest = Math.min(CartGrounding.wheelbarrowLowest(effective, profile),
            Math.min(effective.transformPosition(LEFT, Vector3f()).y, effective.transformPosition(RIGHT, Vector3f()).y))
        result.m31(result.m31() + FLOOR - lowest)
        if (!result.isFinite) return false
        transform.set(result)
        return true
    }
}
