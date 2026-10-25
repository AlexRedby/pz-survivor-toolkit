package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Quaternionf
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.SkinningData

/** Doorway contacts in vehicle-local coordinates; the native passenger itself never moves here. */
internal object VehicleStepPose {
    class References(
        val standingRoot: Vector3f,
        val standingLeft: Matrix4f,
        val standingRight: Matrix4f,
        val drivingRoot: Vector3f,
        val drivingLeft: Matrix4f,
        val drivingRight: Matrix4f,
    )

    class Contacts(
        val pelvis: Vector3f,
        val left: Vector3f,
        val right: Vector3f,
        val leftRotation: Float,
        val rightRotation: Float,
        val leadingLeft: Boolean,
    )

    @JvmStatic
    fun smooth(start: Float, end: Float, time: Float): Float {
        val t = ((time - start) / (end - start)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun curve(time: Float, vararg keys: Float): Float {
        for (i in 0 until keys.size - 2 step 2) if (time <= keys[i + 2])
            return keys[i + 1] + (keys[i + 3] - keys[i + 1]) * smooth(keys[i], keys[i + 2], time)
        return keys.last()
    }

    /** Body bends after the lead step, then settles into the exact driving endpoint. */
    @JvmStatic
    fun chairTime(time: Float, exiting: Boolean): Float =
        if (exiting) 1f - curve(time, 0f, 0f, .4f, .3f, .65f, .7f, .88f, .94f, 1f, 1f)
        else curve(time, 0f, 0f, .38f, .2f, .58f, .5f, .84f, .9f, 1f, 1f)

    @JvmStatic
    fun drivingBlend(time: Float, exiting: Boolean): Float =
        if (exiting) 1f - smooth(0f, .42f, time) else smooth(.58f, 1f, time)

    @JvmStatic
    fun world(origin: Vector3f, model: Vector3f): Vector3f =
        Vector3f(origin).add(1.5f * model.x, 1.5f * model.y, -1.5f * model.z)

    @JvmStatic
    fun model(origin: Vector3f, world: Vector3f): Vector3f =
        Vector3f(
            (world.x - origin.x) / 1.5f,
            (world.y - origin.y) / 1.5f,
            (origin.z - world.z) / 1.5f,
        )

    private fun point(matrix: Matrix4f) = matrix.getTranslation(Vector3f())

    private fun swing(from: Vector3f, to: Vector3f, weight: Float, lift: Float): Vector3f =
        Vector3f(from).lerp(to, weight).add(0f, Math.sin(Math.PI * weight).toFloat() * lift, 0f)

    @JvmStatic
    fun contacts(
        ref: References,
        outside: Vector3f,
        inside: Vector3f,
        time: Float,
        exiting: Boolean,
    ): Contacts {
        val start = world(outside, ref.standingRoot)
        val end = world(inside, ref.drivingRoot)
        val firstLeft = world(outside, point(ref.standingLeft))
        val firstRight = world(outside, point(ref.standingRight))
        val lastLeft = world(inside, point(ref.drivingLeft))
        val lastRight = world(inside, point(ref.drivingRight))
        val inward = Vector3f(inside.x - outside.x, 0f, inside.z - outside.z)
        val leadingLeft = Vector3f(firstLeft).sub(firstRight).dot(inward) > 0f
        val firstLead = if (leadingLeft) firstLeft else firstRight
        val firstTrail = if (leadingLeft) firstRight else firstLeft
        val lastLead = if (leadingLeft) lastLeft else lastRight
        val lastTrail = if (leadingLeft) lastRight else lastLeft
        val travel: Float
        val height: Float
        val lead: Vector3f
        val trail: Vector3f
        val leadRotation: Float
        val trailRotation: Float
        val pelvis: Vector3f
        if (!exiting) {
            travel = curve(time, 0f, 0f, .12f, -.025f, .38f, .27f, .58f, .5f, .84f, .98f, 1f, 1f)
            height = curve(time, 0f, 0f, .12f, .025f, .38f, .25f, .58f, .65f, .84f, 1f, 1f, 1f)
            pelvis = Vector3f(start).lerp(end, travel)
            pelvis.y = start.y + (end.y - start.y) * height
            pelvis.z += .02f * Math.sin(Math.PI * time).toFloat()
            val threshold = Vector3f(firstLead).fma(.42f, inward).add(0f, 0f, .12f)
            threshold.y = lastLead.y
            leadRotation = smooth(.67f, .97f, time)
            lead =
                if (time < .67f) swing(firstLead, threshold, smooth(.1f, .36f, time), .12f)
                else swing(threshold, lastLead, leadRotation, .06f)
            trailRotation = smooth(.52f, .9f, time)
            trail = swing(firstTrail, lastTrail, trailRotation, .12f)
        } else {
            // Exit has a separate support sequence: the near-side foot lands outside
            // before the far foot lifts. Reversing entry would overlap both swings.
            travel = curve(time, 0f, 0f, .1f, .03f, .4f, .52f, .65f, .83f, .88f, .98f, 1f, 1f)
            height = curve(time, 0f, 0f, .1f, 0f, .4f, .05f, .65f, .55f, .88f, .98f, 1f, 1f)
            pelvis = Vector3f(end).lerp(start, travel)
            pelvis.y = end.y + (start.y - end.y) * height
            pelvis.z += .1f * Math.sin(Math.PI * time).toFloat()
            val leadSwing = smooth(.08f, .4f, time)
            val trailSwing = smooth(.42f, .86f, time)
            lead = swing(lastLead, firstLead, leadSwing, .12f)
            trail = swing(lastTrail, firstTrail, trailSwing, .12f)
            leadRotation = 1f - leadSwing
            trailRotation = 1f - trailSwing
        }
        return Contacts(
            pelvis,
            if (leadingLeft) lead else trail,
            if (leadingLeft) trail else lead,
            if (leadingLeft) leadRotation else trailRotation,
            if (leadingLeft) trailRotation else leadRotation,
            leadingLeft,
        )
    }

    private fun ankle(from: Matrix4f, to: Matrix4f, weight: Float, position: Vector3f): Matrix4f {
        val rotation =
            from
                .getNormalizedRotation(Quaternionf())
                .normalize()
                .slerp(to.getNormalizedRotation(Quaternionf()).normalize(), weight)
        return Matrix4f().translationRotate(position.x, position.y, position.z, rotation)
    }

    /**
     * All-or-nothing caller-owned pose solve; no actor transforms or native track state are
     * modified.
     */
    @JvmStatic
    fun solve(
        actor: SkinningData,
        poses: Array<Matrix4f?>,
        ref: References,
        outside: Vector3f,
        inside: Vector3f,
        time: Float,
        exiting: Boolean,
    ): Vector3f? {
        if (
            !time.isFinite() ||
                time !in 0f..1f ||
                !outside.isFinite ||
                !inside.isFinite ||
                Vector3f(inside).sub(outside).let { it.x * it.x + it.z * it.z } < .04f
        )
            return null
        val root = actor.getBone("Bip01") ?: return null
        val contacts = contacts(ref, outside, inside, time, exiting)
        val origin =
            Vector3f(contacts.pelvis)
                .sub(world(Vector3f(), point(poses[root.index] ?: return null)))
        for (left in listOf(true, false)) {
            val name = if (left) "Bip01_L_Foot" else "Bip01_R_Foot"
            val bone = actor.getBone(name) ?: return null
            val current = poses[bone.index] ?: return null
            val target =
                ankle(
                    if (left) ref.standingLeft else ref.standingRight,
                    if (left) ref.drivingLeft else ref.drivingRight,
                    if (left) contacts.leftRotation else contacts.rightRotation,
                    model(origin, if (left) contacts.left else contacts.right),
                )
            if (
                !current.equals(target, 2e-6f) &&
                    !CartGrip.reach(poses, actor, name, target, null, false)
            )
                return null
        }
        return origin
    }
}
