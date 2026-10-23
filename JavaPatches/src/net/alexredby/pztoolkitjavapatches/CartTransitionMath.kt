package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Matrix4fc
import org.joml.Quaternionf
import org.joml.Vector3f
import org.joml.Vector3fc

/** Column-vector presentation transforms, before the native xfrm transpose. */
internal object CartTransitionMath {
    private const val ISO_HEIGHT = 2.44949f
    private const val EPS = .0001f

    // Rotation names/order follow InventoryItem: camera Rx(worldX), Ry(worldZ), Rz(worldY).
    @JvmRecord
    data class Placement(val x: Float, val y: Float, val z: Float, val xRotation: Float, val zRotation: Float,
                         val yRotation: Float, val worldScale: Float) {
        override fun toString() = "Placement[x=$x, y=$y, z=$z, xRotation=$xRotation, zRotation=$zRotation, yRotation=$yRotation, worldScale=$worldScale]"
    }

    @JvmRecord
    data class Progress(val crouch: Double, val reach: Double, val grip: Double, val lift: Double,
                        val center: Double, val balance: Double, val hinge: Double, val knees: Double) {
        override fun toString() = "Progress[crouch=$crouch, reach=$reach, grip=$grip, lift=$lift, center=$center, balance=$balance, hinge=$hinge, knees=$knees]"
    }

    @JvmRecord
    data class Stance(val x: Float, val y: Float, val z: Float, val slotAngle: Float) {
        override fun toString() = "Stance[x=$x, y=$y, z=$z, slotAngle=$slotAngle]"
    }

    @JvmRecord
    private data class Rigid(val translation: Vector3f?, val rotation: Quaternionf?, val scale: Float) {
        override fun toString() = "Rigid[translation=$translation, rotation=$rotation, scale=$scale]"
    }

    @JvmStatic
    fun smooth(fraction: Double): Double {
        if (!fraction.isFinite()) return Double.NaN
        val t = Math.max(0.0, Math.min(1.0, fraction))
        val u = Math.min(t, 1 - t)
        val value = u * u * u * (10 + u * (-15 + 6 * u))
        return if (t <= .5) value else 1 - value
    }

    @JvmStatic
    fun progress(fraction: Double, setdown: Boolean): Progress? {
        if (!fraction.isFinite()) return null
        var t = Math.max(0.0, Math.min(1.0, fraction))
        if (setdown) t = 1 - t
        // Knees/hips/chest descend together; fingers close before lifting.
        val crouch = phase(t, 0.0, .44)
        val lift = phase(t, .48, 1.0)
        val stance = phase(t, 0.0, .10)
        return Progress(crouch, phase(t, .24, .44), phase(t, .38, .48), lift, stance * (1 - lift),
            crouch * Math.sqrt(1 - lift), crouch * (1 - lift * lift), crouch)
    }

    private fun recoveryDistance(progress: Double, setdown: Boolean): Double {
        val phase = progress(progress, setdown) ?: throw NullPointerException()
        val balance = phase.balance
        val reach = smooth(phase.reach)
        val lift = phase.lift
        return progress + 4 * (if (progress <= (if (setdown) .52 else .48)) balance else 2 - balance) +
            6 * (if (setdown) 1 - reach else reach) + 3 * (if (setdown) 1 - lift else lift)
    }

    @JvmStatic
    fun recover(start: Double, elapsedSeconds: Double, setdown: Boolean): Double {
        if (!start.isFinite() || !elapsedSeconds.isFinite()) return Double.NaN
        val progress = Math.max(0.0, Math.min(1.0, start))
        val duration = .4 + .2 * progress
        if (elapsedSeconds <= 0) return progress
        if (elapsedSeconds >= duration) return 0.0
        // Pace the squat, hand contact and wheel lift together in the interrupted direction.
        val target = recoveryDistance(progress, setdown) * (1 - smooth(elapsedSeconds / duration))
        var low = 0.0
        var high = progress
        repeat(48) {
            val middle = (low + high) * .5
            if (recoveryDistance(middle, setdown) < target) low = middle else high = middle
        }
        return (low + high) * .5
    }

    @JvmStatic
    fun recoveryRelease(progress: Double, start: Double, authoredPickup: Boolean): Double {
        if (!progress.isFinite() || !start.isFinite() || start <= 0) return Double.NaN
        val remaining = Math.max(0.0, Math.min(1.0, progress / start))
        // recover already eases time; easing pickup again holds the hip against descending shafts.
        return if (authoredPickup) remaining else smooth(remaining)
    }

    @JvmStatic
    fun recoveryClearance(start: Double, elapsedSeconds: Double): Double {
        if (!start.isFinite() || !elapsedSeconds.isFinite()) return Double.NaN
        val origin = Math.max(0.0, Math.min(1.0, start))
        val u = Math.max(0.0, Math.min(1.0, elapsedSeconds / (.4 + .2 * origin)))
        return (progress(origin, false) ?: throw NullPointerException()).lift * u * (1 - u)
    }

    @JvmStatic
    fun nativeHeight(phase: Progress?, idle: Double, low: Double, cart: Double): Double {
        val value = phase ?: throw NullPointerException()
        val lowWeight = .10 * value.crouch * (1 - value.lift)
        return idle * (1 - value.lift - lowWeight) + low * lowWeight + cart * value.lift
    }

    private fun phase(t: Double, start: Double, end: Double): Double =
        if (t <= start) 0.0 else if (t >= end) 1.0 else smooth((t - start) / (end - start))

    private fun finite(vararg values: Float): Boolean {
        for (value in values) if (!value.isFinite()) return false
        return true
    }

    private fun affine(matrix: Matrix4fc?): Boolean = matrix != null && matrix.isFinite &&
        Math.abs(matrix.m03()) < EPS && Math.abs(matrix.m13()) < EPS &&
        Math.abs(matrix.m23()) < EPS && Math.abs(matrix.m33() - 1) < EPS

    private fun invertible(matrix: Matrix4fc?): Boolean = affine(matrix) &&
        (matrix ?: throw NullPointerException()).determinant().isFinite() && Math.abs(matrix.determinant()) > 1e-12f

    private fun valid(pose: Placement?): Boolean = pose != null &&
        finite(pose.x, pose.y, pose.z, pose.xRotation, pose.zRotation, pose.yRotation, pose.worldScale) && pose.worldScale > 0

    private fun rotation(pose: Placement): Matrix4f = Matrix4f().rotationXYZ(
        Math.toRadians(pose.xRotation.toDouble()).toFloat(), Math.toRadians(pose.zRotation.toDouble()).toFloat(),
        Math.toRadians(pose.yRotation.toDouble()).toFloat())

    /** model = inverse(world attachment) * transposed native mesh transform * model script scale. */
    @JvmStatic
    fun worldToActor(pose: Placement?, model: Matrix4fc?, actorX: Float, actorY: Float,
                     actorZ: Float, slotAngle: Float, out: Matrix4f?): Boolean {
        if (out == null || !valid(pose) || !invertible(model) || !finite(actorX, actorY, actorZ, slotAngle)) return false
        val placement = pose ?: throw NullPointerException()
        val result = Matrix4f().rotationY(-slotAngle - Math.PI.toFloat())
            .translate((placement.x - actorX) / 1.5f, ISO_HEIGHT * (placement.z - actorZ) / 1.5f,
                -(placement.y - actorY) / 1.5f)
            .mul(rotation(placement)).mul(model).scale(placement.worldScale)
        if (!result.isFinite) return false
        out.set(result)
        return true
    }

    private fun rigid(matrix: Matrix4fc?): Rigid? {
        if (!affine(matrix)) return null
        val value = matrix ?: throw NullPointerException()
        val x = value.getColumn(0, Vector3f())
        val y = value.getColumn(1, Vector3f())
        val z = value.getColumn(2, Vector3f())
        val sx = x.length()
        val sy = y.length()
        val sz = z.length()
        if (!finite(sx, sy, sz) || sx <= 1e-8f || Math.abs(sx - sy) > EPS * sx || Math.abs(sx - sz) > EPS * sx) return null
        x.div(sx); y.div(sy); z.div(sz)
        if (Math.abs(x.dot(y)) > EPS || Math.abs(x.dot(z)) > EPS || Math.abs(y.dot(z)) > EPS ||
            x.cross(y, Vector3f()).dot(z) < 1 - EPS) return null
        val quaternion = Matrix4f(value).scale(1 / sx).getNormalizedRotation(Quaternionf())
        if (!quaternion.isFinite) return null
        return Rigid(value.getTranslation(Vector3f()), quaternion.normalize(), sx)
    }

    /** Reject shear, reflection and nonuniform residual scale instead of inventing a world pose. */
    @JvmStatic
    fun actorToWorldPlacement(transform: Matrix4fc?, model: Matrix4fc?, actorX: Float,
                              actorY: Float, actorZ: Float, slotAngle: Float): Placement? {
        if (!affine(transform) || !invertible(model) || !finite(actorX, actorY, actorZ, slotAngle)) return null
        val local = Matrix4f().rotationY(slotAngle + Math.PI.toFloat()).mul(transform).mul(Matrix4f(model).invert())
        val parts = rigid(local) ?: return null
        val r = Matrix4f().rotation(parts.rotation)
        val translation = Vector3f(parts.translation).fma(parts.scale - 1,
            r.transformDirection((model ?: throw NullPointerException()).getTranslation(Vector3f()), Vector3f()))
        val cosBeta = Math.hypot(r.m00().toDouble(), r.m10().toDouble())
        val beta = Math.atan2(r.m20().toDouble(), cosBeta)
        val alpha: Double
        val gamma: Double
        if (cosBeta > .000001) {
            alpha = Math.atan2(-r.m21().toDouble(), r.m22().toDouble())
            gamma = Math.atan2(-r.m10().toDouble(), r.m00().toDouble())
        } else {
            alpha = Math.atan2(Math.signum(beta) * r.m01(), r.m11().toDouble())
            gamma = 0.0
        }
        val result = Placement(actorX + translation.x * 1.5f, actorY - translation.z * 1.5f,
            actorZ + translation.y * 1.5f / ISO_HEIGHT, Math.toDegrees(alpha).toFloat(),
            Math.toDegrees(beta).toFloat(), Math.toDegrees(gamma).toFloat(), parts.scale)
        val check = rotation(result)
        if (!valid(result) || !check.equals(r, .0005f)) return null
        return result
    }

    @JvmStatic
    fun blend(from: Matrix4fc?, to: Matrix4fc?, fraction: Double, out: Matrix4f?): Boolean {
        if (out == null || !fraction.isFinite()) return false
        val a = rigid(from)
        val b = rigid(to)
        if (a == null || b == null) return false
        if (fraction <= 0) { out.set(from); return true }
        if (fraction >= 1) { out.set(to); return true }
        val t = fraction.toFloat()
        val result = Matrix4f().translationRotateScale(
            (a.translation ?: throw NullPointerException()).lerp(b.translation, t, Vector3f()),
            (a.rotation ?: throw NullPointerException()).slerp(b.rotation, t, Quaternionf()), a.scale + (b.scale - a.scale) * t)
        if (!result.isFinite) return false
        out.set(result)
        return true
    }

    /** Blend placement residuals while retaining an imported mesh's nonuniform basis. */
    @JvmStatic
    fun blendModel(from: Matrix4fc?, to: Matrix4fc?, model: Matrix4fc?, fraction: Double, out: Matrix4f?): Boolean {
        if (!invertible(model) || !affine(from) || !affine(to) || out == null) return false
        val inverse = Matrix4f(model).invert()
        if (!blend(Matrix4f(from).mul(inverse), Matrix4f(to).mul(inverse), fraction, out)) return false
        out.mul(model)
        return out.isFinite
    }

    /** Match horizontal handle spacing/direction; differing heights belong to the reach animation. */
    @JvmStatic
    fun stance(pose: Placement?, model: Matrix4fc?, held: Matrix4fc?, leftHandle: Vector3fc?, rightHandle: Vector3fc?): Stance? {
        if (!valid(pose) || !invertible(model) || held == null || rigid(Matrix4f(held).mul(Matrix4f(model).invert())) == null ||
            leftHandle == null || rightHandle == null || !leftHandle.isFinite || !rightHandle.isFinite) return null
        val placement = pose ?: throw NullPointerException()
        val ground = rotation(placement).mul(model).scale(placement.worldScale)
        val worldLeft = ground.transformPosition(leftHandle, Vector3f())
        val worldRight = ground.transformPosition(rightHandle, Vector3f())
        val heldLeft = held.transformPosition(leftHandle, Vector3f())
        val heldRight = held.transformPosition(rightHandle, Vector3f())
        val worldDx = 1.5f * (worldLeft.x - worldRight.x)
        val worldDy = -1.5f * (worldLeft.z - worldRight.z)
        val heldDx = heldLeft.x - heldRight.x
        val heldDz = heldLeft.z - heldRight.z
        if (Math.hypot(worldDx.toDouble(), worldDy.toDouble()) < 1e-8 || Math.hypot(heldDx.toDouble(), heldDz.toDouble()) < 1e-8) return null
        val angle = (Math.atan2(worldDy.toDouble(), worldDx.toDouble()) - Math.PI + Math.atan2(heldDz.toDouble(), heldDx.toDouble())).toFloat()
        val c = Math.cos(angle.toDouble()).toFloat()
        val s = Math.sin(angle.toDouble()).toFloat()
        val hx = (heldLeft.x + heldRight.x) * .5f
        val hz = (heldLeft.z + heldRight.z) * .5f
        val x = placement.x + 1.5f * (worldLeft.x + worldRight.x) * .5f + 1.5f * (c * hx + s * hz)
        val y = placement.y - 1.5f * (worldLeft.z + worldRight.z) * .5f + 1.5f * (s * hx - c * hz)
        return if (finite(x, y, angle)) Stance(x, y, placement.z, angle) else null
    }
}
