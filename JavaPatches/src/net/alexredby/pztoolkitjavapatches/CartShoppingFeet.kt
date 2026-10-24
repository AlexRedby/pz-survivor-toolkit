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

    private class Contact {
        var point: Vector3f? = null
        var start = Vector3f()
        var landing = Vector3f()
        var angle = 0.0
        var startAngle = 0.0
        var landingAngle = 0.0
        var swinging = false
    }

    class State {
        private val contacts = Array(2) { Contact() }
        private var previous: Root? = null
        private var previousPhase = Double.NaN
        private var previousTime = Double.NaN
        private var age = 0.0
        private var cycle = .88
        private var cached: Frame? = null
        private var previousTurn = Float.NaN
        private var previousWalk = Float.NaN
        private var vx = 0.0
        private var vy = 0.0
        private var omega = 0.0

        private data class Heading(val time: Double, val angle: Double)

        private val headings = java.util.ArrayDeque<Heading>()
        private var unwrapped = 0.0
        private var quietUntil = Double.NEGATIVE_INFINITY

        fun clear() {
            for (contact in contacts) contact.point = null
            previous = null
            previousPhase = Double.NaN
            previousTime = Double.NaN
            age = 0.0
            cycle = .88
            cached = null
            vx = 0.0
            vy = 0.0
            omega = 0.0
            headings.clear()
            unwrapped = 0.0
            quietUntil = Double.NEGATIVE_INFINITY
        }

        private fun predict(root: Root, seconds: Double): Root {
            val angle = omega * seconds
            val dx: Double
            val dy: Double
            if (abs(omega) < 1e-4) {
                dx = vx * seconds
                dy = vy * seconds
            } else {
                dx = (vx * sin(angle) + vy * (cos(angle) - 1)) / omega
                dy = (vx * (1 - cos(angle)) + vy * sin(angle)) / omega
            }
            return Root(root.x + dx, root.y + dy, root.angle + angle)
        }

        /** Producer-only planner. Each swing aims at the middle of the next support interval. */
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
            previousTurn = view.turn
            previousWalk = view.walk
            val seconds = (now - previousTime).coerceIn(0.0, .1)
            val advance = (view.phase.toDouble() - previousPhase + 1.0) % 1.0
            // A snapshot yaw correction is not a human step. Native walking remains stable while
            // waiting for a half-second of reliable root motion; no extra network fields are
            // needed.
            if (
                old != null &&
                    seconds.isFinite() &&
                    seconds > 1e-5 &&
                    abs(wrap(root.angle - old.angle)) > maxOf(.1, 6 * seconds)
            ) {
                clear()
                quietUntil = now + .5
            }
            if (now < quietUntil) {
                previous = root
                previousPhase = view.phase.toDouble()
                previousTime = now
                cached = null
                return null
            }

            if (
                old != null &&
                    (kotlin.math.hypot(root.x - old.x, root.y - old.y) > .5 ||
                        abs(wrap(root.angle - old.angle)) > 1.2 ||
                        advance > .3)
            )
                clear()
            else if (old != null && seconds.isFinite() && seconds > 1e-5) {
                val dt = seconds
                age += dt
                if (advance > 1e-5) cycle += ((seconds / advance).coerceIn(.88, 2.0) - cycle) * .2
                val blend = 1.0 - kotlin.math.exp(-dt / .06)
                vx += ((root.x - old.x) / dt - vx) * blend
                vy += ((root.y - old.y) / dt - vy) * blend
                unwrapped += wrap(root.angle - old.angle)
                headings.addLast(Heading(now, unwrapped))
                while (headings.size > 2 && headings.elementAt(1).time < now - .2) headings
                    .removeFirst()
                val first = headings.first
                val span = now - first.time
                if (span > .03) {
                    val observed = ((unwrapped - first.angle) / span).coerceIn(-4.0, 4.0)
                    omega += (observed - omega) * (1.0 - kotlin.math.exp(-dt / .08))
                }
            }
            previous = root
            previousPhase = view.phase.toDouble()
            previousTime = now
            val targets = arrayOfNulls<Matrix4f>(2)
            for ((i, side) in listOf("L", "R").withIndex()) {
                val foot = actor.getBone("Bip01_${side}_Foot") ?: continue
                val toe = actor.getBone("Bip01_${side}_Toe0") ?: continue
                val hip = actor.getBone("Bip01_${side}_Thigh") ?: continue
                val native = poses.getOrNull(foot.index) ?: continue
                val toePose = poses.getOrNull(toe.index) ?: continue
                val hipPose = poses.getOrNull(hip.index) ?: continue
                val contact = contacts[i]
                val p = (view.phase.toDouble() + (if (i == 1) .5 else 0.0)) % 1.0
                val swinging = p < .53 || p >= .98
                val t = ((p + .02) % 1.0) / .55
                val sourcePoint = toePose.getTranslation(Vector3f())
                if (contact.point == null) {
                    contact.point = root.world(sourcePoint)
                    contact.start.set(contact.point!!)
                    contact.landing.set(contact.point!!)
                    contact.angle = root.angle
                    contact.startAngle = root.angle
                    contact.landingAngle = root.angle
                    contact.swinging = false
                }
                if (swinging) {
                    if (!contact.swinging) {
                        contact.start.set(contact.point!!)
                        contact.startAngle = contact.angle
                    }
                    if (!contact.swinging || t < .7) {
                        val untilLanding = (1 - t) * .55 * cycle
                        val middle = predict(root, untilLanding + .45 * cycle / 2)
                        // A wider placement beside the predicted hip, rather than turning on a
                        // forward-walk foot that has already landed at the wrong side of the arc.
                        val neutral =
                            Vector3f(
                                hipPose.m30() + (if (i == 0) .04f else -.04f),
                                sourcePoint.y,
                                -.08f,
                            )
                        val landing = middle.world(neutral)
                        contact.landing.set(landing)
                        contact.landingAngle = root.angle + omega * untilLanding
                    }
                    val ease = smooth(0.0, 1.0, t)
                    contact.point!!.set(contact.start).lerp(contact.landing, ease.toFloat())
                    val outward =
                        (.04 * sin(Math.PI * t) + .005 * sin(Math.PI * t) * sin(Math.PI * t))
                            .toFloat() * (if (i == 0) 1 else -1)
                    val offset = root.world(Vector3f(outward, 0f, 0f))
                    contact.point!!.add(
                        (offset.x - root.x).toFloat(),
                        0f,
                        (offset.z - root.y).toFloat(),
                    )
                    contact.angle =
                        contact.startAngle + wrap(contact.landingAngle - contact.startAngle) * ease
                } else if (contact.swinging) {
                    contact.point!!.set(contact.landing)
                    contact.angle = contact.landingAngle
                }
                contact.swinging = swinging
                val yaw = -wrap(root.angle - contact.angle).toFloat()
                val turned =
                    Matrix4f()
                        .rotationY(yaw)
                        .mul(Matrix4f(native).setTranslation(0f, 0f, 0f))
                        .setTranslation(native.getTranslation(Vector3f()))
                val localToe = Matrix4f(native).invert().transformPosition(sourcePoint)
                val turnedToe = turned.transformPosition(localToe)
                val goal = root.local(contact.point!!)
                val weight = abs(view.turn) * view.walk * smooth(0.0, .16, age)
                val lift = if (swinging) .015 * sin(Math.PI * t).let { it * it } else 0.0
                val target =
                    Matrix4f(turned)
                        .setTranslation(
                            native.m30() + goal.x - turnedToe.x,
                            native.m31() + lift.toFloat(),
                            native.m32() + goal.z - turnedToe.z,
                        )
                targets[i] =
                    Matrix4f().also { CartTransitionMath.blend(native, target, weight, it) }
            }
            if (age < 1e-6) return null.also { cached = null }
            return Frame(targets, (abs(view.turn) * view.walk * smooth(0.0, .16, age)).toFloat())
                .also { cached = it }
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
                val target = Matrix4f()
                if (
                    !CartTransitionMath.blend(original[index], goal, weight * caps[i], target) ||
                        !CartGrip.fitFoot(working, actor, side, target)
                )
                    return false
            }
            openKnees(working, actor, frame.influence)
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

    /** A small native-hinge swivel opens the passing calves without moving either foot. */
    private fun openKnees(poses: Array<out Matrix4f?>, actor: SkinningData, weight: Float) {
        for (side in listOf("L", "R")) {
            val thigh = actor.getBone("Bip01_${side}_Thigh") ?: continue
            val calf = actor.getBone("Bip01_${side}_Calf") ?: continue
            val foot = actor.getBone("Bip01_${side}_Foot") ?: continue
            val hip = poses[thigh.index]!!.getTranslation(Vector3f())
            val axis = poses[foot.index]!!.getTranslation(Vector3f()).sub(hip)
            if (axis.lengthSquared() < 1e-8f) continue
            val angle = (Math.toRadians(11.0) * weight * (if (side == "L") 1 else -1)).toFloat()
            val change =
                Matrix4f()
                    .translation(hip)
                    .rotate(angle, axis.normalize())
                    .translate(-hip.x, -hip.y, -hip.z)
            change.mul(poses[thigh.index], poses[thigh.index])
            change.mul(poses[calf.index], poses[calf.index])
        }
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
