package net.alexredby.pztoolkitjavapatches

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.SkinningData

/** Short world-space support contacts; only the cosmetic leg palettes are changed. */
internal object CartShoppingFeet {
    data class Root(val x: Double, val y: Double, val angle: Double) {
        fun world(point: Vector3f): Vector3f =
            Vector3f(
                (x - 1.5 * (cos(angle) * point.x + sin(angle) * point.z)).toFloat(),
                point.y,
                (y + 1.5 * (-sin(angle) * point.x + cos(angle) * point.z)).toFloat(),
            )

        fun local(point: Vector3f): Vector3f {
            val dx = point.x - x
            val dy = point.z - y
            return Vector3f(
                ((-cos(angle) * dx - sin(angle) * dy) / 1.5).toFloat(),
                point.y,
                ((-sin(angle) * dx + cos(angle) * dy) / 1.5).toFloat(),
            )
        }
    }

    class Frame
    internal constructor(internal val targets: Array<Matrix4f?>, internal val influence: Float)

    // Keep native swing/roll and add only a small planar stance residual.
    private const val MAX_CORRECTION = .025f

    private class Contact {
        var point: Vector3f? = null
        val correction = Vector3f()
        val release = Vector3f()
        var swinging = true
    }

    class State {
        private val contacts = Array(2) { Contact() }
        private var previous: Root? = null
        private var previousPhase = Double.NaN
        private var previousTime = Double.NaN
        private var age = 0.0
        private var cached: Frame? = null
        private var previousTurn = Float.NaN
        private var previousWalk = Float.NaN
        private var quietUntil = Double.NEGATIVE_INFINITY

        fun clear() {
            for (contact in contacts) {
                contact.point = null
                contact.correction.zero()
                contact.release.zero()
                contact.swinging = true
            }
            previous = null
            previousPhase = Double.NaN
            previousTime = Double.NaN
            previousTurn = Float.NaN
            previousWalk = Float.NaN
            age = 0.0
            cached = null
            quietUntil = Double.NEGATIVE_INFINITY
        }

        /** Capture native toe contact in stance; swing only releases the last additive offset. */
        fun update(
            root: Root,
            view: CartShoppingTurn.View,
            actor: SkinningData,
            poses: Array<out Matrix4f?>,
            now: Double = System.nanoTime() / 1e9,
        ): Frame? {
            if (
                !root.x.isFinite() ||
                    !root.y.isFinite() ||
                    !root.angle.isFinite() ||
                    !now.isFinite() ||
                    !view.phase.isFinite() ||
                    view.phase !in 0f..1f ||
                    !view.turn.isFinite() ||
                    abs(view.turn) > 1f ||
                    !view.walk.isFinite() ||
                    view.walk > 1f ||
                    view.walk < .001f ||
                    abs(view.turn) < .001f
            ) {
                clear()
                return null
            }
            val old = previous
            if (
                old == root &&
                    previousPhase == view.phase.toDouble() &&
                    previousTurn == view.turn &&
                    previousWalk == view.walk
            )
                return cached
            val elapsed = now - previousTime
            val seconds = if (elapsed.isFinite()) elapsed.coerceIn(0.0, .1) else 0.0
            val advance = (view.phase.toDouble() - previousPhase + 1.0) % 1.0
            // A remote snapshot correction or teleport is not a step. Wait for stable roots
            // before capturing another native contact, rather than dragging an old anchor.
            if (
                old != null &&
                    (elapsed < 0 ||
                        kotlin.math.hypot(root.x - old.x, root.y - old.y) > .5 ||
                        abs(wrap(root.angle - old.angle)) > maxOf(.1, 6 * seconds) ||
                        advance > .3)
            ) {
                clear()
                quietUntil = now + .5
            } else if (old != null && previousTurn * view.turn < 0f) {
                clear()
            } else if (old != null && seconds.isFinite()) {
                age += seconds
            }
            previous = root
            previousPhase = view.phase.toDouble()
            previousTime = now
            previousTurn = view.turn
            previousWalk = view.walk
            if (now < quietUntil) return null.also { cached = null }

            val weight = abs(view.turn) * view.walk * smooth(0.0, .16, age)
            val targets = arrayOfNulls<Matrix4f>(2)
            for ((i, side) in listOf("L", "R").withIndex()) {
                val foot = actor.getBone("Bip01_${side}_Foot") ?: continue
                val toe = actor.getBone("Bip01_${side}_Toe0") ?: continue
                val native = poses.getOrNull(foot.index) ?: continue
                val toePose = poses.getOrNull(toe.index) ?: continue
                val contact = contacts[i]
                val p = (view.phase.toDouble() + (if (i == 1) .5 else 0.0)) % 1.0
                val swinging = p < .53 || p >= .98
                if (swinging) {
                    if (!contact.swinging) contact.release.set(contact.correction)
                    contact.point = null
                    // Native animation supplies every swing position and rotation. Only decay
                    // the previous stance correction through the first .18 of the cycle.
                    contact.correction
                        .set(contact.release)
                        .mul((1 - smooth(0.0, .18, (p + .02) % 1.0)).toFloat())
                } else {
                    val source = toePose.getTranslation(Vector3f())
                    if (contact.point == null) {
                        contact.point = root.world(source)
                        contact.correction.zero()
                    }
                    val residual = root.local(contact.point!!).sub(source)
                    residual.y = 0f
                    val distance = residual.length()
                    if (distance > MAX_CORRECTION) residual.mul(MAX_CORRECTION / distance)
                    val blend = (1 - kotlin.math.exp(-seconds / .035)).toFloat()
                    contact.correction.lerp(residual, blend)
                }
                contact.swinging = swinging
                val correction = Vector3f(contact.correction).mul(weight.toFloat())
                targets[i] =
                    Matrix4f(native)
                        .setTranslation(
                            native.m30() + correction.x,
                            native.m31(),
                            native.m32() + correction.z,
                        )
            }
            if (age < 1e-6) return null.also { cached = null }
            return Frame(targets, weight.toFloat()).also { cached = it }
        }
    }

    /** Both legs commit together, with a continuous reach limit instead of a snapped fallback. */
    fun apply(poses: Array<out Matrix4f?>, actor: SkinningData, frame: Frame?): Boolean {
        if (frame == null) return true
        val count = actor.numBones()
        if (count > 64 || poses.size < count) return false
        val original = Array(count) { i -> poses[i]?.let(::Matrix4f) ?: return false }
        val working = Array<Matrix4f?>(count) { Matrix4f(original[it]) }
        val caps = DoubleArray(2) { 1.0 }
        for ((i, side) in listOf("L", "R").withIndex()) {
            val target = frame.targets[i] ?: continue
            val ids =
                listOf("Thigh", "Calf", "Foot").map {
                    actor.getBone("Bip01_${side}_$it")?.index ?: return false
                }
            val hip = original[ids[0]].getTranslation(Vector3f())
            val knee = original[ids[1]].getTranslation(Vector3f())
            val foot = original[ids[2]].getTranslation(Vector3f())
            val reach = hip.distance(knee) + knee.distance(foot) - .0005f
            val offset = Vector3f(foot).sub(hip)
            val delta = target.getTranslation(Vector3f()).sub(foot)
            val a = delta.lengthSquared().toDouble()
            val b = 2.0 * offset.dot(delta)
            val c = (offset.lengthSquared() - reach * reach).toDouble()
            if (a > 1e-12 && a + b + c > 0) {
                val disc = b * b - 4 * a * c
                caps[i] =
                    if (disc > 0) ((-b + kotlin.math.sqrt(disc)) / (2 * a)).coerceIn(0.0, 1.0)
                    else 0.0
            }
        }
        fun solve(weight: Double): Boolean {
            for (i in 0 until count) working[i]!!.set(original[i])
            for ((i, side) in listOf("L", "R").withIndex()) {
                val goal = frame.targets[i] ?: continue
                val index = actor.getBone("Bip01_${side}_Foot")?.index ?: return false
                if (
                    goal
                        .getTranslation(Vector3f())
                        .distanceSquared(original[index].getTranslation(Vector3f())) < 1e-12f
                )
                    continue
                val target = Matrix4f()
                if (
                    !CartTransitionMath.blend(original[index], goal, weight * caps[i], target) ||
                        !CartGrip.fitFoot(working, actor, side, target)
                )
                    return false
            }
            // Near full extension a small ankle delta can amplify into a large knee move.
            // Limit that independently and retain the native bend plane chosen by fitFoot.
            for (side in listOf("L", "R")) {
                val knee = actor.getBone("Bip01_${side}_Calf")?.index ?: return false
                if (
                    working[knee]!!
                        .getTranslation(Vector3f())
                        .distance(original[knee].getTranslation(Vector3f())) > MAX_CORRECTION
                )
                    return false
            }
            return separated(working, actor)
        }
        var cap = 1.0
        if (!solve(cap)) {
            var low = 0.0
            var high = cap
            repeat(8) {
                val mid = (low + high) / 2
                if (solve(mid)) low = mid else high = mid
            }
            cap = low
            if (cap < .001 || !solve(cap)) return false
        }
        for (i in 0 until count) poses[i]!!.set(working[i])
        return true
    }

    private fun separated(poses: Array<out Matrix4f?>, actor: SkinningData): Boolean {
        fun at(side: String, part: String): Vector3f? =
            actor.getBone("Bip01_${side}_$part")?.let {
                poses[it.index]?.getTranslation(Vector3f())
            }
        val left = listOf("Thigh", "Calf", "Foot").map { at("L", it) ?: return false }
        val right = listOf("Thigh", "Calf", "Foot").map { at("R", it) ?: return false }
        val lateral = Vector3f(left[0]).sub(right[0]).normalize()
        if (Vector3f(left[2]).sub(right[2]).dot(lateral) < .10f) return false
        for (i in 0..1) for (j in 0..1) if (
            segmentDistance(left[i], left[i + 1], right[j], right[j + 1]) < .095f
        )
            return false
        return true
    }

    private fun segmentDistance(a: Vector3f, b: Vector3f, c: Vector3f, d: Vector3f): Float {
        val u = Vector3f(b).sub(a)
        val v = Vector3f(d).sub(c)
        val w = Vector3f(a).sub(c)
        val aa = u.dot(u)
        val bb = u.dot(v)
        val cc = v.dot(v)
        val dd = u.dot(w)
        val ee = v.dot(w)
        fun point(p: Vector3f, start: Vector3f, direction: Vector3f, length: Float): Float =
            Vector3f(start)
                .fma((Vector3f(p).sub(start).dot(direction) / length).coerceIn(0f, 1f), direction)
                .distance(p)
        var result =
            minOf(point(a, c, v, cc), point(b, c, v, cc), point(c, a, u, aa), point(d, a, u, aa))
        val determinant = aa * cc - bb * bb
        if (determinant > 1e-12f) {
            val s = (bb * ee - cc * dd) / determinant
            val t = (aa * ee - bb * dd) / determinant
            if (s in 0f..1f && t in 0f..1f)
                result = minOf(result, Vector3f(w).fma(s, u).fma(-t, v).length())
        }
        return result
    }

    private fun wrap(angle: Double) = Math.IEEEremainder(angle, 2 * Math.PI)

    private fun smooth(a: Double, b: Double, value: Double): Double {
        val u = ((value - a) / (b - a)).coerceIn(0.0, 1.0)
        return u * u * u * (10 + u * (-15 + 6 * u))
    }
}
