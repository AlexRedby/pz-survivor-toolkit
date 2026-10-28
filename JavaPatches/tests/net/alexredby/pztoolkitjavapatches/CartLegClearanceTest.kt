package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import java.util.Arrays
import java.util.HashMap
import java.util.Locale
import java.util.Objects
import org.joml.Matrix4f

/** Analytic geometry and captured-pose source-cage replay; no game or render context. */
object CartLegClearanceTest {
    private const val EPS = 1e-6
    private val TETRA = doubleArrayOf(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
    private val INSIDE = doubleArrayOf(0.2, 0.1, 0.1, 0.2, 0.2, 0.1, 0.2, 0.1, 0.2)
    private val XY = doubleArrayOf(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0)
    private val TRI_ORDERS =
        arrayOf(
            intArrayOf(0, 1, 2),
            intArrayOf(0, 2, 1),
            intArrayOf(1, 0, 2),
            intArrayOf(1, 2, 0),
            intArrayOf(2, 0, 1),
            intArrayOf(2, 1, 0),
        )

    private fun check(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun close(actual: Number, expected: Number, tolerance: Double, message: String) {
        check(
            java.lang.Double.isFinite(actual.toDouble()) &&
                Math.abs(actual.toDouble() - expected.toDouble()) <= tolerance,
            "$message: actual=$actual expected=$expected",
        )
    }

    private fun translated(points: DoubleArray, x: Number, y: Number, z: Number): DoubleArray {
        val out = points.clone()
        for (i in out.indices step 3) {
            out[i] += x.toDouble()
            out[i + 1] += y.toDouble()
            out[i + 2] += z.toDouble()
        }
        return out
    }

    private fun scaled(points: DoubleArray, scale: Number): DoubleArray {
        val out = points.clone()
        for (i in out.indices) out[i] *= scale.toDouble()
        return out
    }

    private fun ordered(points: DoubleArray, vararg order: Int): DoubleArray {
        val out = DoubleArray(order.size * 3)
        for (i in order.indices) System.arraycopy(points, order[i] * 3, out, i * 3, 3)
        return out
    }

    private fun range(
        body: DoubleArray,
        cart: DoubleArray,
        margin: Double,
        message: String,
    ): DoubleArray {
        val bodyBefore = body.clone()
        val cartBefore = cart.clone()
        val out = DoubleArray(2)
        check(CartLegClearance.interval(body, cart, margin, out), "$message: interval missing")
        check(
            java.lang.Double.isFinite(out[0]) &&
                java.lang.Double.isFinite(out[1]) &&
                out[0] <= out[1],
            "$message: invalid interval",
        )
        check(
            body.contentEquals(bodyBefore) && cart.contentEquals(cartBefore),
            "$message: input geometry mutated",
        )
        return out
    }

    private fun expectedRange(
        body: DoubleArray,
        cart: DoubleArray,
        low: Number,
        high: Number,
        message: String,
    ) {
        val out = range(body, cart, 0.0, message)
        close(out[0], low, 1e-8, "$message lower")
        close(out[1], high, 1e-8, "$message upper")
    }

    private fun separated(body: DoubleArray, cart: DoubleArray, message: String) {
        check(!CartLegClearance.interval(body, cart, 0.0, DoubleArray(2)), message)
    }

    private fun tetrahedra() {
        // The body triangle is wholly inside a solid tetrahedron, with no surface
        // edge crossing. Body x=.2-d and minimum y+z=.2 give -.6 <= d <= .2.
        expectedRange(INSIDE, TETRA, -0.6, 0.2, "solid containment, cart+X/body-X sign")
        expectedRange(
            translated(INSIDE, 2, 0, 0),
            TETRA,
            1.4,
            2.2,
            "far positive sweep is not capped by the runtime corridor",
        )
        expectedRange(translated(INSIDE, -2, 0, 0), TETRA, -2.6, -1.8, "far negative sweep")
        // All three vertices lie outside, but an edge crosses the tetra interior.
        expectedRange(
            doubleArrayOf(0.2, -0.5, 0.2, 0.2, 1.5, 0.2, 0.2, 0.5, 0.8),
            TETRA,
            -0.6,
            0.2,
            "edge/face overlap with no contained vertex",
        )
        separated(translated(INSIDE, 0, 2, 0), TETRA, "Y separation cannot be repaired by X")
        separated(translated(INSIDE, 0, 0, -2), TETRA, "Z separation cannot be repaired by X")
        for (a in 0 until 4) for (b in 0 until 4) if (b != a)
            for (c in 0 until 4) if (c != a && c != b) {
                val d = 6 - a - b - c
                for (order in TRI_ORDERS) expectedRange(
                    ordered(INSIDE, *order),
                    ordered(TETRA, a, b, c, d),
                    -0.6,
                    0.2,
                    "winding/vertex permutation invariance",
                )
            }
        for (scale in doubleArrayOf(0.1, 1.0, 10.0)) expectedRange(
            translated(scaled(INSIDE, scale), 17, -11, 4),
            translated(scaled(TETRA, scale), 17, -11, 4),
            -0.6 * scale,
            0.2 * scale,
            "common translation and uniform scale",
        )
        val reflected = INSIDE.clone()
        val reflectedCart = TETRA.clone()
        for (i in reflected.indices step 3) reflected[i] = -reflected[i]
        for (i in reflectedCart.indices step 3) reflectedCart[i] = -reflectedCart[i]
        expectedRange(
            reflected,
            reflectedCart,
            -0.2,
            0.6,
            "mirrored X reverses both interval endpoints",
        )
        val padded = range(INSIDE, TETRA, 0.001, "positive clearance margin")
        check(
            padded[0] <= -0.601 + 1e-10 && padded[1] >= 0.201 - 1e-10,
            "margin must expand both escape directions",
        )
    }

    private fun triangles() {
        expectedRange(
            XY,
            translated(XY, 2, 0, 0),
            -3,
            -1,
            "coplanar separated triangles meet under negative cart shift",
        )
        expectedRange(
            XY,
            translated(XY, -2, 0, 0),
            1,
            3,
            "coplanar separated triangles meet under positive cart shift",
        )
        expectedRange(
            XY,
            XY,
            -1,
            1,
            "coplanar overlapping triangles require in-plane separating axes",
        )
        separated(XY, translated(XY, 0, 2, 0), "coplanar disjoint Y ranges remain separated")
        separated(XY, translated(XY, 0, 0, 0.25), "parallel separated planes remain separated")
        // The vertical primitive intersects z=0 over y=[.25,1]. The body's
        // right edge x+y=2 gives the independent upper bound d=1.25.
        val vertical = doubleArrayOf(0.5, 0.25, -1.0, 0.5, 0.25, 1.0, 0.5, 1.0, 0.0)
        val wide = scaled(XY, 2)
        expectedRange(wide, vertical, -0.5, 1.25, "noncoplanar triangle/triangle intersection")
        for (bodyOrder in TRI_ORDERS) for (cartOrder in TRI_ORDERS) expectedRange(
            ordered(wide, *bodyOrder),
            ordered(vertical, *cartOrder),
            -0.5,
            1.25,
            "noncoplanar winding invariance",
        )
    }

    private fun domainWrapper() {
        val out = DoubleArray(2)
        check(
            !CartLegClearance.intervalWithinDomain(
                translated(INSIDE, 2, 0, 0),
                TETRA,
                0.0,
                -0.03,
                0.03,
                out,
            ),
            "domain broadphase skips a strictly positive distant sweep",
        )
        check(
            !CartLegClearance.intervalWithinDomain(
                translated(INSIDE, -2, 0, 0),
                TETRA,
                0.0,
                -0.03,
                0.03,
                out,
            ),
            "domain broadphase skips a strictly negative distant sweep",
        )
        val smallTetra = scaled(TETRA, 0.01)
        val smallBody = scaled(INSIDE, 0.01)
        for (offset in doubleArrayOf(0.035, -0.031)) {
            val body = translated(smallBody, offset, 0, 0)
            val generic = range(body, smallTetra, 0.0, "domain-edge interval")
            check(
                generic[0] <= 0.03 && generic[1] >= -0.03,
                "edge control actually intersects the legal corridor",
            )
            check(
                CartLegClearance.intervalWithinDomain(body, smallTetra, 0.0, -0.03, 0.03, out),
                "thin collision at either domain edge must survive the broadphase",
            )
            close(out[0], generic[0], 1e-12, "domain wrapper preserves lower endpoint")
            close(out[1], generic[1], 1e-12, "domain wrapper preserves upper endpoint")
        }
        val touching = doubleArrayOf(0.04, 0.0, 0.0, 0.04, 0.001, 0.0, 0.04, 0.0, 0.001)
        check(
            CartLegClearance.intervalWithinDomain(touching, smallTetra, 0.0, -0.03, 0.03, out),
            "exact positive-domain contact is retained",
        )
        close(out[0], 0.03, 1e-9, "exact edge contact lower endpoint")
        val marginOnly = translated(touching, 0.0005, 0, 0)
        check(
            !CartLegClearance.intervalWithinDomain(marginOnly, smallTetra, 0.0, -0.03, 0.03, out),
            "unpadded control is beyond the domain",
        )
        check(
            CartLegClearance.intervalWithinDomain(
                marginOnly,
                smallTetra,
                0.001,
                -0.03,
                0.03,
                out,
            ) && out[0] <= 0.03 && out[1] >= -0.03,
            "margin-only in-domain contact survives the broadphase",
        )
        // Compare the wrapper with the unbounded SAT oracle over both directions,
        // margins and domain boundaries; no second geometry algorithm is copied.
        var retained = 0
        for (i in -20..20) for (margin in doubleArrayOf(0.0, 0.001)) {
            val body = translated(smallBody, i * 0.0025, 0, 0)
            val generic = DoubleArray(2)
            val exists = CartLegClearance.interval(body, smallTetra, margin, generic)
            val filtered =
                CartLegClearance.intervalWithinDomain(body, smallTetra, margin, -0.03, 0.03, out)
            if (exists && generic[0] <= 0.03 && generic[1] >= -0.03) {
                retained++
                check(filtered, "domain broadphase lost an in-domain collision")
                close(out[0], generic[0], 1e-12, "filtered lower endpoint matches generic SAT")
                close(out[1], generic[1], 1e-12, "filtered upper endpoint matches generic SAT")
            }
            if (!exists) check(!filtered, "domain wrapper must not invent a generic interval")
        }
        check(retained > 20, "domain-retention controls exercise a useful sweep")
    }

    private fun choice(
        low: DoubleArray,
        high: DoubleArray,
        count: Int,
        min: Double,
        max: Double,
        message: String,
    ): Double {
        val value = CartLegClearance.choose(low, high, count, min, max)
        check(
            java.lang.Double.isFinite(value) && value >= min && value <= max,
            "$message: no bounded solution",
        )
        for (i in 0 until count) check(
            value <= low[i] - EPS + 1e-10 || value >= high[i] + EPS - 1e-10,
            "$message: selected point enters a forbidden interval or its epsilon clearance",
        )
        return value
    }

    private fun choices() {
        close(
            choice(DoubleArray(0), DoubleArray(0), 0, -0.03, 0.03, "empty union"),
            0,
            0.0,
            "neutral zero",
        )
        close(
            choice(
                doubleArrayOf(0.01, -0.03),
                doubleArrayOf(0.02, -0.02),
                2,
                -0.03,
                0.03,
                "disjoint clear intervals",
            ),
            0,
            0.0,
            "a bounding hull must not close a real free gap",
        )
        close(
            choice(
                doubleArrayOf(1.5 * EPS),
                doubleArrayOf(0.01),
                1,
                -0.03,
                0.03,
                "near but clear zero",
            ),
            0,
            0.0,
            "epsilon merging must not invent an initial zero collision",
        )
        close(
            choice(
                doubleArrayOf(-0.01),
                doubleArrayOf(0.02),
                1,
                -0.03,
                0.03,
                "shorter negative escape",
            ),
            -0.010001,
            1e-12,
            "nearest negative",
        )
        close(
            choice(
                doubleArrayOf(-0.02),
                doubleArrayOf(0.01),
                1,
                -0.03,
                0.03,
                "shorter positive escape",
            ),
            0.010001,
            1e-12,
            "nearest positive",
        )
        close(
            choice(
                doubleArrayOf(0.0),
                doubleArrayOf(0.01),
                1,
                -0.03,
                0.03,
                "zero on forbidden boundary",
            ),
            -EPS,
            1e-12,
            "closed boundary escape",
        )
        close(
            choice(
                doubleArrayOf(0.005, -0.004, 0.001),
                doubleArrayOf(0.02, 0.002, 0.006),
                3,
                -0.03,
                0.03,
                "unsorted transitive union",
            ),
            -0.004001,
            1e-12,
            "must escape the complete connected component",
        )
        close(
            choice(
                doubleArrayOf(-0.01, 0.0100015),
                doubleArrayOf(0.01, 0.03),
                2,
                -0.005,
                0.04,
                "epsilon gap between neighbours",
            ),
            0.030001,
            1e-12,
            "epsilon exit must not enter the next forbidden component",
        )
        close(
            choice(
                doubleArrayOf(-0.004),
                doubleArrayOf(0.02),
                1,
                -0.003,
                0.03,
                "negative side outside budget",
            ),
            0.020001,
            1e-12,
            "bounded positive alternative",
        )
        close(
            choice(
                doubleArrayOf(-0.02),
                doubleArrayOf(0.004),
                1,
                -0.03,
                0.003,
                "positive side outside budget",
            ),
            -0.020001,
            1e-12,
            "bounded negative alternative",
        )
        val tie =
            choice(
                doubleArrayOf(-0.01),
                doubleArrayOf(0.01),
                1,
                -0.03,
                0.03,
                "symmetric alternatives",
            )
        close(Math.abs(tie), 0.010001, 1e-12, "either nearest symmetric side is valid")
        check(
            CartLegClearance.choose(doubleArrayOf(-0.02), doubleArrayOf(0.02), 1, -0.01, 0.01)
                .isNaN(),
            "covered corridor must refuse",
        )
        check(
            CartLegClearance.choose(doubleArrayOf(-0.0299995), doubleArrayOf(0.04), 1, -0.03, 0.03)
                .isNaN(),
            "sub-epsilon boundary sliver is not a safe corridor",
        )
        close(
            choice(
                doubleArrayOf(Double.NEGATIVE_INFINITY),
                doubleArrayOf(0.01),
                1,
                -0.03,
                0.03,
                "unbounded half-axis",
            ),
            0.010001,
            1e-12,
            "finite escape from half-axis",
        )
        check(
            CartLegClearance.choose(
                    doubleArrayOf(Double.NEGATIVE_INFINITY),
                    doubleArrayOf(Double.POSITIVE_INFINITY),
                    1,
                    -0.03,
                    0.03,
                )
                .isNaN(),
            "whole-axis obstruction refuses",
        )
        close(
            CartLegClearance.choose(
                doubleArrayOf(0.02, Double.NaN),
                doubleArrayOf(0.03, Double.NaN),
                1,
                -0.03,
                0.03,
            ),
            0,
            0.0,
            "unused scratch tail does not poison the live prefix",
        )
        close(
            CartLegClearance.choose(DoubleArray(0), DoubleArray(0), 0, 0.0, 0.0),
            0,
            0.0,
            "unblocked singleton corridor",
        )
    }

    private fun guards() {
        for (body in
            arrayOf(
                null,
                DoubleArray(8),
                DoubleArray(9),
                doubleArrayOf(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 0.0, 0.0),
            )) check(
            !CartLegClearance.interval(body, TETRA, 0.0, DoubleArray(2)),
            "invalid/degenerate body rejected",
        )
        for (cart in
            arrayOf(
                null,
                DoubleArray(8),
                DoubleArray(9),
                DoubleArray(12),
                doubleArrayOf(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 0.0, 0.0),
                doubleArrayOf(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0),
            )) check(
            !CartLegClearance.interval(INSIDE, cart, 0.0, DoubleArray(2)),
            "invalid/degenerate primitive rejected",
        )
        for (out in arrayOf(null, DoubleArray(0), DoubleArray(1))) check(
            !CartLegClearance.interval(INSIDE, TETRA, 0.0, out),
            "undersized output rejected",
        )
        for (value in
            doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            for (i in INSIDE.indices) {
                val body = INSIDE.clone()
                body[i] = value
                separated(body, TETRA, "every body coordinate must be finite")
            }
            for (i in TETRA.indices) {
                val cart = TETRA.clone()
                cart[i] = value
                separated(INSIDE, cart, "every primitive coordinate must be finite")
            }
            check(
                !CartLegClearance.interval(INSIDE, TETRA, value, DoubleArray(2)),
                "nonfinite margin rejected",
            )
            check(
                CartLegClearance.choose(DoubleArray(0), DoubleArray(0), 0, value, 0.03).isNaN(),
                "nonfinite lower corridor bound rejected",
            )
            check(
                CartLegClearance.choose(DoubleArray(0), DoubleArray(0), 0, -0.03, value).isNaN(),
                "nonfinite upper corridor bound rejected",
            )
        }
        check(
            !CartLegClearance.interval(INSIDE, TETRA, -0.001, DoubleArray(2)),
            "negative margin rejected",
        )
        check(
            CartLegClearance.choose(null, DoubleArray(0), 0, -0.03, 0.03).isNaN(),
            "null lower ranges rejected",
        )
        check(
            CartLegClearance.choose(DoubleArray(0), null, 0, -0.03, 0.03).isNaN(),
            "null upper ranges rejected",
        )
        for (count in intArrayOf(-1, 2)) check(
            CartLegClearance.choose(doubleArrayOf(0.0), doubleArrayOf(0.0), count, -0.03, 0.03)
                .isNaN(),
            "invalid count rejected",
        )
        check(
            CartLegClearance.choose(doubleArrayOf(0.0), DoubleArray(0), 1, -0.03, 0.03).isNaN(),
            "mismatched live prefix rejected",
        )
        check(
            CartLegClearance.choose(doubleArrayOf(Double.NaN), doubleArrayOf(1.0), 1, -0.03, 0.03)
                .isNaN(),
            "NaN interval rejected",
        )
        check(
            CartLegClearance.choose(doubleArrayOf(1.0), doubleArrayOf(0.0), 1, -0.03, 0.03).isNaN(),
            "reversed interval rejected",
        )
        check(
            CartLegClearance.choose(DoubleArray(0), DoubleArray(0), 0, 0.01, -0.01).isNaN(),
            "reversed corridor rejected",
        )
    }

    private fun footprints() {
        val front = CartFootprint.WALK_FRONT
        for (side in doubleArrayOf(-1.0, 1.0)) {
            check(
                CartFootprint.contains(0.3, side * 0.04, front, 0.001),
                "rail centre belongs to the native envelope",
            )
            check(
                CartFootprint.contains(-0.298, side * 0.04, front, 0.001),
                "rear rounded cap keeps its interior",
            )
            check(
                !CartFootprint.contains(-0.301, side * 0.04, front, 0.001),
                "point behind the rear cap is outside",
            )
            check(
                CartFootprint.contains(0.3, side * 0.338, front, 0.001),
                "rail radius admits a point with reserve",
            )
            check(
                !CartFootprint.contains(0.3, side * 0.341, front, 0.001),
                "point beyond the outer rail radius is outside",
            )
            check(
                !CartFootprint.contains(-0.25, side * 0.29, front, 0.001),
                "rounded rear corner is not an oversized box",
            )
        }
        check(
            CartFootprint.contains(0.98, 0.0, front, 0.001),
            "tapered nose tip belongs to the envelope",
        )
        check(
            CartFootprint.contains(1.26, 0.0, front, 0.001),
            "existing forward cap contains its calibrated nose",
        )
        check(
            !CartFootprint.contains(1.281, 0.0, front, 0.001),
            "point beyond the nose cap is outside",
        )
        check(
            CartFootprint.contains(0.3, 0.3395, front, 0.0) &&
                !CartFootprint.contains(0.3, 0.3395, front, 0.001),
            "one-millimetre reserve shrinks the native envelope",
        )
        for (value in
            doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            check(
                !CartFootprint.contains(value, 0.0, front, 0.001),
                "nonfinite forward coordinate rejected",
            )
            check(
                !CartFootprint.contains(0.0, value, front, 0.001),
                "nonfinite lateral coordinate rejected",
            )
            check(
                !CartFootprint.contains(0.0, 0.0, value, 0.001),
                "nonfinite forward budget rejected",
            )
            check(!CartFootprint.contains(0.0, 0.0, front, value), "nonfinite reserve rejected")
        }
        check(!CartFootprint.contains(0.0, 0.0, 0.1, 0.001), "collapsed forward budget rejected")
        check(
            !CartFootprint.contains(0.0, 0.0, front, -0.001) &&
                !CartFootprint.contains(0.0, 0.0, front, 0.3),
            "invalid reserve rejected",
        )
    }

    private fun recordContracts() {
        val bones = arrayOf<String?>(null)
        val vertices = intArrayOf(1)
        val influences = intArrayOf(2)
        val points = floatArrayOf(3f)
        val triangles = intArrayOf(4)
        val skin =
            CartLegClearanceData.Skin(
                null,
                null,
                0L,
                bones,
                0,
                vertices,
                influences,
                points,
                triangles,
            )
        check(
            skin == skin.copy() && skin != skin.copy(influenceVertex = vertices.clone()),
            "Skin record compares live array identities",
        )
        var seed = 1
        repeat(9) { seed *= 31 }
        check(
            skin.hashCode() ==
                Objects.hash(null, null, 0L, bones, 0, vertices, influences, points, triangles) -
                    seed,
            "Skin record must use Java identity hashes for array components",
        )
        val hash = skin.hashCode()
        vertices[0] = 9
        check(
            skin.influenceVertex === vertices &&
                (skin.influenceVertex ?: throw NullPointerException())[0] == 9 &&
                skin.hashCode() == hash,
            "Skin record must expose its original mutable arrays",
        )
        val rows = arrayOf<FloatArray?>(null)
        val footprint = floatArrayOf(1f)
        val cart = CartLegClearanceData.Cart(null, null, 0L, rows, footprint)
        seed = 1
        repeat(5) { seed *= 31 }
        check(
            cart == cart.copy() &&
                cart != cart.copy(primitives = rows.clone()) &&
                cart.hashCode() == Objects.hash(null, null, 0L, rows, footprint) - seed,
            "Cart record keeps Java array equality and identity hash semantics",
        )
        check(
            CartLegClearanceData.Skin(null, null, 0L, null, 0, null, null, null, null).toString() ==
                "Skin[suffix=null, sha256=null, bytes=0, bones=null, vertexCount=0, influenceVertex=null, influenceBone=null, weightedPoints=null, triangles=null]" &&
                CartLegClearanceData.Cart(null, null, 0L, null, null).toString() ==
                    "Cart[suffix=null, sha256=null, bytes=0, primitives=null, footprintPoints=null]",
            "source records retain nullable Java construction and record formatting",
        )
    }

    private class Replay(val name: String, val female: Boolean, val expected: Double) {
        val bones = HashMap<String?, Matrix4f>()
        val points = ArrayList<DoubleArray>()
        val skins =
            arrayOf(
                CartLegClearanceData.SKINS[if (female) 1 else 0],
                CartLegClearanceData.SKINS[if (female) 3 else 2],
            )
        val triangles: Array<DoubleArray>
        val primitives: Array<DoubleArray>
        var cart: Matrix4f? = null

        init {
            var faces = 0
            for (skin in skins) {
                points.add(DoubleArray(skin.vertexCount * 3))
                faces += (skin.triangles ?: throw NullPointerException()).size / 3
            }
            triangles = Array(faces) { DoubleArray(9) }
            val source = CartLegClearanceData.WOOD.primitives ?: throw NullPointerException()
            primitives =
                Array(source.size) {
                    DoubleArray((source[it] ?: throw NullPointerException()).size)
                }
        }

        fun rebuild() {
            var face = 0
            for (s in skins.indices) {
                val skin = skins[s]
                val vertices = points[s]
                Arrays.fill(vertices, 0.0)
                val names = skin.bones ?: throw NullPointerException()
                for (bone in names.indices) {
                    val pose = bones[names[bone]]
                    check(pose != null, "$name: missing captured bone ${names[bone]}")
                    CartLegClearance.accumulate(skin, bone, pose, vertices)
                }
                val indices = skin.triangles ?: throw NullPointerException()
                for (i in indices.indices step 3) {
                    val triangle = triangles[face++]
                    for (j in 0 until 3) System.arraycopy(
                        vertices,
                        indices[i + j] * 3,
                        triangle,
                        j * 3,
                        3,
                    )
                }
            }
            val source = CartLegClearanceData.WOOD.primitives ?: throw NullPointerException()
            for (i in source.indices) {
                val row = source[i] ?: throw NullPointerException()
                for (j in row.indices step 3) {
                    val x = row[j].toDouble()
                    val y = row[j + 1].toDouble()
                    val z = row[j + 2].toDouble()
                    val p = primitives[i]
                    val transform = cart ?: throw NullPointerException()
                    p[j] =
                        transform.m00() * x +
                            transform.m10() * y +
                            transform.m20() * z +
                            transform.m30()
                    p[j + 1] =
                        transform.m01() * x +
                            transform.m11() * y +
                            transform.m21() * z +
                            transform.m31()
                    p[j + 2] =
                        transform.m02() * x +
                            transform.m12() * y +
                            transform.m22() * z +
                            transform.m32()
                }
            }
        }
    }

    private fun matrix(fields: Array<String>, start: Int): Matrix4f {
        check(fields.size == start + 16, "captured matrix has exactly 16 column-major values")
        val values = FloatArray(16)
        for (i in 0 until 16) {
            values[i] = fields[start + i].toFloat()
            check(java.lang.Float.isFinite(values[i]), "finite captured matrix")
        }
        return Matrix4f().set(values)
    }

    private fun captures(path: Path): List<Replay> {
        val cases = ArrayList<Replay>()
        var current: Replay? = null
        for (line in Files.readAllLines(path)) {
            if (line.isBlank() || line.startsWith("#")) continue
            val fields = line.split(",", ignoreCase = false, limit = 0).toTypedArray()
            when (fields[0]) {
                "case" -> {
                    check(current == null && fields.size == 4, "nested/malformed replay case")
                    check(fields[2] == "0" || fields[2] == "1", "captured sex must be exact")
                    current = Replay(fields[1], fields[2] == "1", fields[3].toDouble())
                }
                "cart" -> {
                    check(current != null && current.cart == null, "duplicate/orphan cart matrix")
                    (current ?: throw NullPointerException()).cart = matrix(fields, 1)
                }
                "bone" ->
                    check(
                        current != null &&
                            current.bones.putIfAbsent(fields[1], matrix(fields, 2)) == null,
                        "duplicate/orphan bone",
                    )
                "end" -> {
                    check(
                        current != null &&
                            current.cart != null &&
                            java.lang.Double.isFinite(current.expected),
                        "incomplete replay case",
                    )
                    cases.add(current ?: throw NullPointerException())
                    current = null
                }
                else -> throw AssertionError("Unknown replay row ${fields[0]}")
            }
        }
        check(current == null && cases.isNotEmpty(), "unterminated/empty replay")
        return cases
    }

    private class Solver {
        var low = DoubleArray(512)
        var high = DoubleArray(512)
        val out = DoubleArray(2)
        var count = 0

        fun solve(replay: Replay): Double {
            replay.rebuild()
            count = 0
            for (triangle in replay.triangles) for (primitive in replay.primitives) if (
                CartLegClearance.intervalWithinDomain(
                    triangle,
                    primitive,
                    0.001,
                    -0.030,
                    0.030,
                    out,
                )
            ) {
                if (count == low.size) {
                    low = low.copyOf(count * 2)
                    high = high.copyOf(count * 2)
                }
                low[count] = out[0]
                high[count++] = out[1]
            }
            return CartLegClearance.choose(low, high, count, -0.030, 0.030)
        }
    }

    private fun replay(path: Path) {
        val cases = captures(path)
        val solver = Solver()
        var positives = 0
        var neutrals = 0
        var maxTriangles = 0
        var maxRanges = 0
        for (capture in cases) {
            val selected = solver.solve(capture)
            maxRanges = Math.max(maxRanges, solver.count)
            maxTriangles = Math.max(maxTriangles, capture.triangles.size)
            close(
                selected,
                capture.expected,
                3e-6,
                "${capture.name}: independent captured-pose nearest shift",
            )
            if (capture.expected == 0.0) {
                neutrals++
                close(selected, 0, 0.0, "${capture.name}: clear control stays exactly neutral")
            } else {
                positives++
                check(selected != 0.0, "${capture.name}: positive contact requires a fit")
                val cart = capture.cart ?: throw NullPointerException()
                val fitted = Matrix4f(cart).m30(cart.m30() + selected.toFloat())
                check(
                    CartLegClearance.withinFootprint(fitted),
                    "${capture.name}: calibrated nonzero fit leaves the native footprint",
                )
            }
            for (shift in floatArrayOf(-0.5f, 0.5f)) {
                val cart = capture.cart ?: throw NullPointerException()
                val escaped = Matrix4f(cart).m30(cart.m30() + shift)
                check(
                    !CartLegClearance.withinFootprint(escaped),
                    "${capture.name}: huge lateral shift bypasses footprint gate",
                )
            }
            check(
                !CartLegClearance.withinFootprint(Matrix4f(capture.cart).m30(Float.NaN)),
                "${capture.name}: nonfinite fitted transform rejected",
            )
            for (i in 0 until solver.count) check(
                selected < solver.low[i] || selected > solver.high[i],
                "${capture.name}: selected fit still forbidden",
            )
            // Physically move body -X as the cart moves +X; independently check
            // the solved pose, not only membership in the precomputed ranges.
            for (triangle in capture.triangles) {
                val moved = translated(triangle, -selected, 0, 0)
                for (primitive in capture.primitives) if (
                    CartLegClearance.interval(moved, primitive, 0.001, solver.out)
                )
                    check(
                        solver.out[0] > 0 || solver.out[1] < 0,
                        "${capture.name}: post-fit body/cart margin still intersects",
                    )
            }
        }
        check(positives > 0 && neutrals > 0, "replay needs contact positives and clear controls")
        check(cases.any { it.female } && cases.any { !it.female }, "both source rigs replayed")
        repeat(40) {
            check(
                java.lang.Double.isFinite(solver.solve(cases[it % cases.size])),
                "warmup fit finite",
            )
        }
        val times = LongArray(60)
        var total = 0L
        var checksum = 0.0
        for (i in times.indices) {
            val start = System.nanoTime()
            checksum += solver.solve(cases[i % cases.size])
            times[i] = System.nanoTime() - start
            total += times[i]
        }
        Arrays.sort(times)
        check(java.lang.Double.isFinite(checksum), "benchmark work remains observable")
        System.out.printf(
            Locale.ROOT,
            "CART_LEG_CLEARANCE_REPLAY cases=%d positives=%d neutral=%d maxTriangles=%d primitives=%d maxRanges=%d warmup=40 measured=60 meanMs=%.3f p95Ms=%.3f%n",
            cases.size,
            positives,
            neutrals,
            maxTriangles,
            (CartLegClearanceData.WOOD.primitives ?: throw NullPointerException()).size,
            maxRanges,
            total / 60e6,
            times[56] / 1e6,
        )
        println(
            "Replay scope: headless source skin accumulation, cart transform and SAT/choose; excludes footprint gating, native slot guards, live IK coupling, garment GPU palettes and render upload.",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        recordContracts()
        tetrahedra()
        triangles()
        domainWrapper()
        choices()
        guards()
        footprints()
        val fixture =
            if (args.isNotEmpty()) Path.of(args[0])
            else
                Path.of(
                    System.getProperty("pz.test.project", "."),
                    "JavaPatches/tests/fixtures/cart-leg-clearance.csv",
                )
        replay(fixture)
        println("CART_LEG_CLEARANCE_PASS")
    }
}
