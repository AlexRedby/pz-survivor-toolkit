package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import java.util.HashMap
import java.util.Objects
import org.joml.Matrix4f
import org.joml.Vector3d
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.SkinningData

/**
 * Closed native hand shape, finite-shaft contact and bounded coarse-skin residuals. This numerical
 * gate does not establish a natural-looking grasp; native visual review is separate.
 */
object CartMetalGripSurfaceChecks {
    private const val SCALE = 0.0091743395
    private const val ZMIN = 52.2465
    private const val ZMAX = 85.63253

    @JvmRecord
    private data class Contact(val part: String?, val source: IntArray?, val bary: DoubleArray?) {
        override fun hashCode(): Int =
            (Objects.hashCode(part) * 31 + Objects.hashCode(source)) * 31 + Objects.hashCode(bary)

        override fun toString(): String = "Contact[part=$part, source=$source, bary=$bary]"
    }

    @JvmRecord
    private data class Weight(val bone: String?, val weight: Float, val point: Vector3f?) {
        override fun toString(): String = "Weight[bone=$bone, weight=$weight, point=$point]"
    }

    @JvmRecord
    private data class Vertex(
        val source: Int,
        val fixed: Vector3f?,
        val weights: MutableList<Weight>?,
    ) {
        override fun toString(): String = "Vertex[source=$source, fixed=$fixed, weights=$weights]"
    }

    private class Rig {
        var female = false
        var left = false
        val bones = HashMap<String, Matrix4f>()
        val vertices = ArrayList<Vertex>()
        val faces = ArrayList<IntArray>()
        val ring = ArrayList<DoubleArray>()
        val contacts = ArrayList<Contact>()
    }

    private fun <T : Any> required(value: T?): T = value ?: throw NullPointerException()

    private fun fixtures(): List<Rig> {
        val path =
            Path.of(System.getProperty("pz.test.project", "."))
                .resolve("JavaPatches/tests/fixtures/metal-hand-surfaces.csv")
        val result = ArrayList<Rig>()
        var rig: Rig? = null
        for (line in Files.readAllLines(path)) {
            if (line.isBlank() || line.startsWith("#")) continue
            val c = line.split(",".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
            when (c[0]) {
                "rig" -> {
                    rig = Rig()
                    rig.female = c[1].equals("female")
                    rig.left = c[2].equals("L")
                    result.add(rig)
                }
                "bone" -> {
                    val m = FloatArray(16)
                    for (i in 0 until 16) m[i] = java.lang.Float.parseFloat(c[i + 2])
                    required(rig).bones[c[1]] = Matrix4f().set(m)
                }
                "vertex" ->
                    required(rig)
                        .vertices
                        .add(Vertex(Integer.parseInt(c[1]), point(c, 2), ArrayList()))
                "weight" ->
                    required(required(rig).vertices[required(rig).vertices.size - 1].weights)
                        .add(Weight(c[1], java.lang.Float.parseFloat(c[2]), point(c, 3)))
                "face" ->
                    required(rig)
                        .faces
                        .add(
                            intArrayOf(
                                Integer.parseInt(c[1]),
                                Integer.parseInt(c[2]),
                                Integer.parseInt(c[3]),
                            ),
                        )
                "contact" ->
                    required(rig)
                        .contacts
                        .add(
                            Contact(
                                c[1],
                                intArrayOf(
                                    Integer.parseInt(c[2]),
                                    Integer.parseInt(c[3]),
                                    Integer.parseInt(c[4]),
                                ),
                                doubleArrayOf(
                                    java.lang.Double.parseDouble(c[5]),
                                    java.lang.Double.parseDouble(c[6]),
                                    java.lang.Double.parseDouble(c[7]),
                                ),
                            ),
                        )
                "ring" ->
                    required(rig)
                        .ring
                        .add(
                            doubleArrayOf(
                                java.lang.Double.parseDouble(c[1]),
                                java.lang.Double.parseDouble(c[2]),
                            ),
                        )
                else -> throw AssertionError("Unknown mesh fixture row: " + c[0])
            }
        }
        if (
            result.size != 4 ||
                result.any {
                    it.vertices.size != 34 ||
                        it.faces.size != 42 ||
                        it.ring.size < 30 ||
                        it.contacts.size != 3
                }
        )
            throw AssertionError("Incomplete native hand/shaft fixtures")
        return result
    }

    private fun point(c: Array<String>, i: Int): Vector3f =
        Vector3f(
            java.lang.Float.parseFloat(c[i]),
            java.lang.Float.parseFloat(c[i + 1]),
            java.lang.Float.parseFloat(c[i + 2]),
        )

    private fun actor(side: String): SkinningData {
        val ids = HashMap<String, Int>()
        val offsets = ArrayList<org.lwjgl.util.vector.Matrix4f>()
        val names =
            arrayOf(
                "Bip01_Spine",
                "Bip01_" + side + "_Hand",
                "Bip01_" + side + "_Finger0",
                "Bip01_" + side + "_Finger1",
            )
        for (i in names.indices) {
            ids[names[i]] = i
            offsets.add(org.lwjgl.util.vector.Matrix4f())
        }
        return SkinningData(
            HashMap(),
            offsets,
            offsets,
            offsets,
            java.util.List.of(-1, 0, 1, 1),
            ids,
        )
    }

    private fun planes(rig: Rig): List<DoubleArray> {
        val result = ArrayList<DoubleArray>()
        for (i in rig.ring.indices) {
            val a = rig.ring[i]
            val b = rig.ring[(i + 1) % rig.ring.size]
            val dx = b[0] - a[0]
            val dy = b[1] - a[1]
            val length = Math.hypot(dx, dy)
            result.add(
                doubleArrayOf(dy / length, -dx / length, 0.0, (a[0] * dy - a[1] * dx) / length),
            )
        }
        result.add(doubleArrayOf(0.0, 0.0, -1.0, -ZMIN))
        result.add(doubleArrayOf(0.0, 0.0, 1.0, ZMAX))
        return result
    }

    private fun areaInside(triangle: Array<Vector3d>, planes: List<DoubleArray>): Double =
        areaInside(triangle, planes, 0.000001)

    private fun areaInside(
        triangle: Array<Vector3d>,
        planes: List<DoubleArray>,
        inset: Double,
    ): Double {
        var polygon = ArrayList(java.util.List.of(*triangle))
        for (plane in planes) {
            val next = ArrayList<Vector3d>()
            if (polygon.isEmpty()) return 0.0
            var previous = polygon[polygon.size - 1]
            var a = distance(previous, plane, inset)
            for (current in polygon) {
                val b = distance(current, plane, inset)
                if ((a <= 0) != (b <= 0))
                    next.add(Vector3d(current).sub(previous).mul(a / (a - b)).add(previous))
                if (b <= 0) next.add(current)
                previous = current
                a = b
            }
            polygon = next
        }
        var area = 0.0
        var i = 1
        while (i + 1 < polygon.size) {
            area +=
                Vector3d(polygon[i])
                    .sub(polygon[0])
                    .cross(Vector3d(polygon[i + 1]).sub(polygon[0]))
                    .length() * 0.5
            i++
        }
        return area * SCALE * SCALE
    }

    private fun distance(p: Vector3d, plane: DoubleArray, inset: Double): Double =
        // A1um inset distinguishes tangency; a larger inset tests the explicit residual-depth
        // budget.
        p.x * plane[0] + p.y * plane[1] + p.z * plane[2] - plane[3] + inset / SCALE

    private fun residualFaces(rig: Rig): Set<String> {
        // Measured native bridge/thumb faces only; a different intersecting surface is a
        // regression.
        if (!rig.female)
            return if (rig.left) setOf("112/114/121", "114/121/122", "120/121/122", "120/122/124")
            else setOf("418/421/427", "421/427/429", "426/427/429", "426/429/430")
        return if (rig.left)
            setOf(
                "116/118/160",
                "118/160/161",
                "121/123/160",
                "121/160/161",
                "126/150/158",
                "126/158/159",
                "158/159/164",
            )
        else
            setOf(
                "428/431/472",
                "431/472/473",
                "433/434/472",
                "433/472/473",
                "438/462/470",
                "438/470/471",
                "470/471/476",
            )
    }

    private fun legacy(rig: Rig, cart: Matrix4f): Matrix4f = legacy(rig, cart, false)

    private fun legacy(rig: Rig, cart: Matrix4f, transition: Boolean): Matrix4f {
        val axis = cart.transformDirection(Vector3f(0f, 0f, 1f)).normalize()
        val down = cart.transformDirection(Vector3f(0f, -1f, 0f)).normalize()
        val inward = down.cross(axis, Vector3f()).normalize().mul(if (rig.left) 1f else -1f)
        var radial = Math.toRadians(5.0).toFloat()
        val beta = Math.toRadians(40.0).toFloat()
        if (transition) {
            val held = CartWheelbarrow.METAL.held(Matrix4f())
            val heldAngle =
                Math.atan2(
                    held.m21().toDouble(),
                    Math.hypot(held.m20().toDouble(), held.m22().toDouble()),
                )
            val angle =
                Math.atan2(
                    cart.m21().toDouble(),
                    Math.hypot(cart.m20().toDouble(), cart.m22().toDouble()),
                )
            val lift =
                Math.max(
                    0.0,
                    Math.min(
                        1.0,
                        (angle + CartWorldSupport.pitch()) / (heldAngle + CartWorldSupport.pitch()),
                    ),
                )
            radial = Math.toRadians(-20 + 25 * lift).toFloat()
        }
        val x =
            down
                .mul(Math.cos(radial.toDouble()).toFloat(), Vector3f())
                .fma(Math.sin(radial.toDouble()).toFloat(), inward)
        var z =
            inward
                .mul(Math.cos(radial.toDouble()).toFloat(), Vector3f())
                .fma(-Math.sin(radial.toDouble()).toFloat(), down)
        x.mul(Math.cos(beta.toDouble()).toFloat())
            .fma(-Math.sin(beta.toDouble()).toFloat(), axis)
            .normalize()
        val y = z.cross(x, Vector3f()).normalize()
        z = x.cross(y, Vector3f()).normalize()
        val hand =
            Matrix4f()
                .m00(x.x)
                .m01(x.y)
                .m02(x.z)
                .m10(y.x)
                .m11(y.y)
                .m12(y.z)
                .m20(z.x)
                .m21(z.y)
                .m22(z.z)
        val point =
            cart.transformPosition(
                Vector3f(if (rig.left) -7.409948f else -39.674755f, 6.614635f, 81.45f),
            )
        val palmX = if (rig.female) 0.056f else 0.057f
        val depth = if (rig.female) 0.025f else 0.022f
        return hand.setTranslation(
            point.x - hand.m00() * palmX - hand.m20() * depth,
            point.y - hand.m01() * palmX - hand.m21() * depth,
            point.z - hand.m02() * palmX - hand.m22() * depth,
        )
    }

    private fun intersections(rig: Rig, cart: Matrix4f, old: Boolean, transition: Boolean): Int {
        val side = if (rig.left) "L" else "R"
        val hand = if (old) legacy(rig, cart) else Matrix4f()
        if (
            !old &&
                !(if (transition)
                    CartGrip.transitionTarget(
                        "WheelbarrowMetal",
                        rig.left,
                        rig.female,
                        Matrix4f(),
                        cart,
                        hand,
                    )
                else
                    CartGrip.target(
                        "WheelbarrowMetal",
                        rig.left,
                        rig.female,
                        Matrix4f(),
                        cart,
                        hand,
                    ))
        )
            throw AssertionError("Metal hand target unavailable")
        if (!old) {
            val prior = legacy(rig, cart, transition)
            // Rotating around the fixed handle intentionally arcs the wrist; bound only extra
            // seating.
            val station = Vector3f()
            CartGrip.handle("WheelbarrowMetal", rig.left, station)
            cart.transformPosition(station)
            val angleChange =
                Matrix4f(hand)
                    .setTranslation(0f, 0f, 0f)
                    .mul(Matrix4f(prior).setTranslation(0f, 0f, 0f).invert())
            val rotatedPrior =
                angleChange
                    .transformDirection(prior.getTranslation(Vector3f()).sub(station))
                    .add(station)
            if (hand.getTranslation(Vector3f()).distance(rotatedPrior) > 0.015f)
                throw AssertionError("Closed grip requires excessive extra wrist seating")
            val shaft = cart.transformDirection(Vector3f(0f, 0f, 1f)).normalize()
            val across =
                Math.toDegrees(
                    Math.acos(
                        Math.min(1f, Math.abs(shaft.dot(hand.getColumn(0, Vector3f()).normalize())))
                            .toDouble(),
                    ),
                )
            if (Math.abs(across - (if (rig.female) 65 else 70)) > 0.001)
                throw AssertionError("Closed fist lost the selected wrist/shaft angle")
            if (transition) {
                val heldAngle =
                    Math.atan2(
                        CartWheelbarrow.METAL.held(Matrix4f()).m21().toDouble(),
                        Math.hypot(
                            CartWheelbarrow.METAL.held(Matrix4f()).m20().toDouble(),
                            CartWheelbarrow.METAL.held(Matrix4f()).m22().toDouble(),
                        ),
                    )
                val angle =
                    Math.atan2(
                        cart.m21().toDouble(),
                        Math.hypot(cart.m20().toDouble(), cart.m22().toDouble()),
                    )
                if (Math.abs(angle - heldAngle) < 0.000001) {
                    val steady = Matrix4f()
                    CartGrip.target(
                        "WheelbarrowMetal",
                        rig.left,
                        rig.female,
                        Matrix4f(),
                        cart,
                        steady,
                    )
                    if (!hand.equals(steady, 0.000002f))
                        throw AssertionError("Wrist changed at held handoff")
                }
            }
        }
        val thumb = Matrix4f(hand).mul(rig.bones["Finger0"])
        val finger = Matrix4f(hand).mul(rig.bones["Finger1"])
        val poses = arrayOf<Matrix4f?>(Matrix4f(), hand, thumb, finger)
        if (old)
            finger
                .set(hand)
                .translate(required(rig.bones["Finger1"]).getTranslation(Vector3f()))
                .rotateY(if (rig.female) -1.7f else -1.5f)
        else {
            val nativeThumb = Matrix4f(thumb)
            val t = thumb.getTranslation(Vector3f())
            val f = finger.getTranslation(Vector3f())
            CartGrip.closeFingers(
                poses,
                actor(side),
                side,
                CartGrip.grasp(rig.female, "WheelbarrowMetal"),
                true,
            )
            if (
                required(poses[2]).getTranslation(Vector3f()).distance(t) > 0.000002f ||
                    required(poses[3]).getTranslation(Vector3f()).distance(f) > 0.000002f
            )
                throw AssertionError("Metal closure moved a native knuckle")
            val closed =
                Matrix4f(hand)
                    .translate(required(rig.bones["Finger1"]).getTranslation(Vector3f()))
                    .rotateY(if (rig.female) -1.7f else -1.5f)
            if (
                !required(poses[3]).equals(closed, 0.000002f) ||
                    !required(poses[2]).equals(nativeThumb, 0.000002f)
            )
                throw AssertionError(
                    "Metal clearance obtained by opening the fist or changing its thumb",
                )
        }
        val inverse = Matrix4f(hand).invert()
        val local = HashMap<String, Matrix4f>()
        local["Hand"] = Matrix4f()
        local["Finger0"] = Matrix4f(inverse).mul(poses[2])
        local["Finger1"] = Matrix4f(inverse).mul(poses[3])
        val toCart = Matrix4f(cart).invert().mul(hand)
        val points = arrayOfNulls<Vector3d>(rig.vertices.size)
        for (i in points.indices) {
            val v = rig.vertices[i]
            val p = Vector3f(v.fixed)
            for (w in required(v.weights)) p.fma(
                w.weight,
                required(local[w.bone]).transformPosition(Vector3f(w.point)),
            )
            toCart.transformPosition(p)
            points[i] = Vector3d(p.x.toDouble(), p.y.toDouble(), p.z.toDouble())
        }
        var hits = 0
        var area = 0.0
        val planes = planes(rig)
        val allowed = residualFaces(rig)
        for (face in rig.faces) {
            val triangle =
                arrayOf(
                    required(points[face[0]]),
                    required(points[face[1]]),
                    required(points[face[2]]),
                )
            val clipped = areaInside(triangle, planes)
            if (clipped > 1e-12) {
                hits++
                area += clipped
                if (!old) {
                    val ids =
                        intArrayOf(
                            rig.vertices[face[0]].source,
                            rig.vertices[face[1]].source,
                            rig.vertices[face[2]].source,
                        )
                    java.util.Arrays.sort(ids)
                    val key = ids[0].toString() + "/" + ids[1] + "/" + ids[2]
                    val depth = if (rig.female) 0.0005 else 0.0011
                    // Intersecting the inset core proves the triangle exceeds the depth budget.
                    if (
                        !allowed.contains(key) ||
                            areaInside(triangle, planes, depth + 0.000001) > 1e-12
                    )
                        throw AssertionError(
                            "Closed metal hand exceeds measured skin residual: female=" +
                                rig.female +
                                " left=" +
                                rig.left +
                                " face=" +
                                key,
                        )
                }
            }
        }
        if (!old && area > (if (rig.female) 6e-6 else 30e-6))
            throw AssertionError(
                "Closed metal skin residual area grew: female=" +
                    rig.female +
                    " left=" +
                    rig.left +
                    " mm2=" +
                    area * 1e6,
            )
        if (!old) contact(rig, points)
        return hits
    }

    private fun physicalGap(point: Vector3d, rig: Rig): Double {
        var xy = Double.POSITIVE_INFINITY
        var inside = true
        for (i in rig.ring.indices) {
            val a = rig.ring[i]
            val b = rig.ring[(i + 1) % rig.ring.size]
            val x = b[0] - a[0]
            val y = b[1] - a[1]
            val px = point.x - a[0]
            val py = point.y - a[1]
            inside = inside and (px * y - py * x <= 1e-8)
            val t = Math.max(0.0, Math.min(1.0, (px * x + py * y) / (x * x + y * y)))
            xy = Math.min(xy, Math.hypot(px - t * x, py - t * y))
        }
        if (inside) xy = 0.0
        val axial = Math.max(0.0, Math.max(ZMIN - point.z, point.z - ZMAX))
        return Math.hypot(xy, axial) * SCALE
    }

    private fun contact(rig: Rig, points: Array<Vector3d?>) {
        // These fixed real support patches check material contact, not aesthetic power-grip
        // quality.
        // A closed power grip need not put thumb and finger tips on opposite cylinder radii.
        for (patch in rig.contacts) {
            val p = Vector3d()
            var sum = 0.0
            val ids = IntArray(3)
            for (k in 0 until 3) {
                var id = -1
                for (i in rig.vertices.indices) if (
                    rig.vertices[i].source == required(patch.source)[k]
                ) {
                    id = i
                    break
                }
                if (id < 0 || required(patch.bary)[k] < 0)
                    throw AssertionError("Invalid measured contact patch")
                ids[k] = id
                sum += required(patch.bary)[k]
                p.fma(required(patch.bary)[k], points[id])
            }
            if (
                Math.abs(sum - 1) > 1e-9 ||
                    rig.faces.none { face ->
                        face.all { i -> i == ids[0] || i == ids[1] || i == ids[2] }
                    }
            )
                throw AssertionError("Contact patch is not on an actual native triangle")
            val gap = physicalGap(p, rig)
            if (gap > 0.0025 || p.z < ZMIN || p.z > ZMAX)
                throw AssertionError(
                    "Physical surface contact missed shaft: female=" +
                        rig.female +
                        " left=" +
                        rig.left +
                        " part=" +
                        patch.part +
                        " gap=" +
                        gap,
                )
        }
    }

    @JvmStatic
    fun check() {
        var checked = 0
        var oldHits = 0
        var residualPaths = 0
        for (rig in fixtures()) {
            val held = CartWheelbarrow.METAL.held(Matrix4f())
            val baseline = intersections(rig, held, true, false)
            if (baseline != (if (rig.female) 13 else 14))
                throw AssertionError("Old native hand overlap no longer reproduced: " + baseline)
            oldHits += baseline
            for (step in -1..40) {
                val heldAngle =
                    Math.atan2(
                        held.m21().toDouble(),
                        Math.hypot(held.m20().toDouble(), held.m22().toDouble()),
                    )
                val pitch =
                    (CartWorldSupport.pitch() - (heldAngle + CartWorldSupport.pitch()) * step / 40)
                        .toFloat()
                val cart =
                    if (step < 0) held
                    else
                        Matrix4f()
                            .translation(0.13f, 0.24f, -0.71f)
                            .rotateY(0.7f)
                            .rotateX(pitch)
                            .scale(SCALE.toFloat())
                val hits = intersections(rig, cart, false, step >= 0)
                if (hits > 0) residualPaths++
                checked++
            }
        }
        println(
            "CART_METAL_GRIP_SURFACE_PASS paths=" +
                checked +
                " oldIntersectingTriangles=" +
                oldHits +
                " closedFist=true residualPaths=" +
                residualPaths +
                " boundedStockResidualMm=1.1male/0.5female",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        check()
    }
}
