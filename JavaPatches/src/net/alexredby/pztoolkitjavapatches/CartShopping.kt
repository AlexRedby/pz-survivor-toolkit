package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Quaternionf
import org.joml.Vector3f
import zombie.inventory.InventoryItem

/** Shopping-cart action geometry; its imported mesh has nonuniform axis scales. */
internal object CartShopping {
    @JvmStatic
    fun item(item: InventoryItem?): Boolean =
        item != null && "SaucedCarts.ShoppingCart".equals(item.getFullType())

    @JvmStatic
    fun model(model: String?): Boolean =
        when (model) {
            "ShoppingCartModel",
            "ShoppingCartPartialModel",
            "ShoppingCartFullModel",
            "ShoppingCartFlashlightModel",
            "ShoppingCartFlashlightPartialModel",
            "ShoppingCartFlashlightFullModel" -> true
            else -> false
        }

    // Native atlas ItemParams transform, before world yaw, for the current shopping FBX.
    @JvmStatic
    fun worldModel(out: Matrix4f?): Matrix4f? {
        val result = out ?: throw NullPointerException()
        result.set(
            .002273866f,
            -.00014903705f,
            0f,
            0f,
            .000111277506f,
            .0016977666f,
            -7.437096e-11f,
            0f,
            3.159179e-10f,
            4.819975e-9f,
            .11050479f,
            0f,
            0f,
            0f,
            0f,
            1f,
        )
        return if (support(result, 1f)) result else null
    }

    // Measured axle-center separation and lowest tire vertex in the native VBO.
    private val AXLES = Vector3f(218.725291729f, 17.093925655f, -.006239582f)
    private val CONTACT = Vector3f(110.046699524f, 8.371052742f, .983569264f)
    private val BAR = Vector3f(-150.07166f, 343.47412f, -.0000065f)

    /**
     * Level the four tire centers, preserving the bar horizontally; keep the imported axis scales.
     */
    @JvmStatic
    fun support(transform: Matrix4f?, laterScale: Float): Boolean {
        if (
            transform == null ||
                !transform.isFinite() ||
                !laterScale.isFinite() ||
                laterScale <= 0 ||
                transform.determinant() <= 0
        )
            return false
        val effective = Matrix4f(transform).scale(laterScale)
        val forward = effective.transformDirection(AXLES, Vector3f())
        val side = effective.transformDirection(Vector3f(0f, 0f, 1f))
        val normal = side.cross(forward, Vector3f())
        if (normal.lengthSquared() < 1e-12f) return false
        normal.normalize()
        if (normal.y < 0) normal.negate()
        if (normal.y < .9f) return false
        val pivot = effective.transformPosition(BAR, Vector3f())
        val rotation = Quaternionf().rotationTo(normal, Vector3f(0f, 1f, 0f))
        val change =
            Matrix4f().translation(pivot).rotate(rotation).translate(-pivot.x, -pivot.y, -pivot.z)
        change.mul(effective, effective)
        effective.m31(effective.m31() + .008f - effective.transformPosition(CONTACT, Vector3f()).y)
        effective.scale(1 / laterScale)
        if (!effective.isFinite()) return false
        transform.set(effective)
        return true
    }

    /**
     * Match the world model's actual scale; the native hand attachment otherwise shrinks it about
     * 5%.
     */
    @JvmStatic
    fun align(
        transform: Matrix4f?,
        model: Matrix4f?,
        worldScale: Float,
        delta: Matrix4f?,
    ): Boolean {
        if (
            transform == null ||
                delta == null ||
                model == null ||
                !model.isFinite() ||
                !worldScale.isFinite() ||
                worldScale <= 0 ||
                Math.abs(model.determinant()) < 1e-12f
        )
            return false
        val residual = Matrix4f(transform).mul(Matrix4f(model).invert())
        if (!CartTransitionMath.blend(residual, residual, 0.0, Matrix4f())) return false
        val scale = residual.getColumn(0, Vector3f()).length()
        val adjusted = Matrix4f(transform)
        val pivot = adjusted.transformPosition(BAR, Vector3f())
        Matrix4f()
            .translation(pivot)
            .scale(worldScale / scale)
            .translate(-pivot.x, -pivot.y, -pivot.z)
            .mul(adjusted, adjusted)
        if (!support(adjusted, 1f)) return false
        transform.set(adjusted)
        // The actor keeps the native torso/gait; only the arms solve the corrected bar.
        delta.identity()
        return true
    }

    @JvmStatic fun held(out: Matrix4f?): Matrix4f? = held(out, worldModel(Matrix4f()), 1f)

    // B42.21 native Bob_Cart_Idle attachment capture, shared by the six fill/light models.
    @JvmStatic
    fun held(out: Matrix4f?, model: Matrix4f?, worldScale: Float): Matrix4f? {
        val result = out ?: throw NullPointerException()
        result.set(
            -5.080325e-10f,
            -.00022194229f,
            -.0021531826f,
            0f,
            7.381783e-10f,
            .0016076594f,
            -.00016571165f,
            0f,
            .104969054f,
            -6.051497e-8f,
            -1.0280073e-8f,
            0f,
            -.0016536561f,
            .0033783615f,
            -.44702002f,
            1f,
        )
        return if (align(result, model, worldScale, Matrix4f())) result else null
    }

    // Scale around the native hand bar, just as align() does. Cache the affine offset so
    // steering does not allocate matrices/vectors on every movement update.
    private val rearAxle = run {
        val held = held(Matrix4f()) ?: error("Invalid shopping-cart steering geometry")
        val bar = held.transformPosition(BAR, Vector3f())
        val rear = Vector3f()
        for (i in 0..1) {
            val p = CartShoppingWheelMesh.CENTERS[i]
            rear.add(p[0], p[1], p[2])
        }
        held.transformPosition(rear.mul(.5f))
        // Model.vectorToWorldCoords maps forward model -Z to 1.5 world tiles.
        doubleArrayOf(-1.5 * bar.z, -1.5 * (rear.z - bar.z))
    }

    @JvmStatic
    fun axle(worldScale: Float): Double =
        if (worldScale.isFinite() && worldScale > 0) rearAxle[0] + rearAxle[1] * worldScale else 0.0

    @JvmStatic
    fun progress(value: Double, setdown: Boolean): CartTransitionMath.Progress? {
        if (!value.isFinite()) return null
        val t = Math.max(0.0, Math.min(1.0, if (setdown) 1 - value else value))
        val body = CartTransitionMath.smooth(t)
        return CartTransitionMath.Progress(
            0.0,
            CartTransitionMath.smooth((t - .10) / .60),
            CartTransitionMath.smooth((t - .55) / .27),
            body,
            0.0,
            0.0,
            0.0,
            0.0,
        )
    }
}
