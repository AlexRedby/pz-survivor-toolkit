package net.alexredby.pztoolkitjavapatches

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.inventory.InventoryItem

/** Four-wheel movement and source-topology checks without an OpenGL context. */
object CartShoppingWheelsTest {
    private lateinit var unsafe: Unsafe

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(actual: Number, expected: Number, tolerance: Double, message: String) {
        check(
            java.lang.Double.isFinite(actual.toDouble()) &&
                Math.abs(actual.toDouble() - expected.toDouble()) <= tolerance,
            "$message: $actual expected $expected",
        )
    }

    private fun difference(a: Double, b: Double): Double = Math.IEEEremainder(a - b, Math.PI * 2)

    private fun item(): InventoryItem =
        (unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem).apply {
            setModule("SaucedCarts")
            setType("ShoppingCart")
        }

    private fun point(p: FloatArray): Vector3f = Vector3f(p[0], p[1], p[2])

    private fun follow(
        item: InventoryItem,
        x: Float,
        y: Float,
        angle: Float,
        cart: Matrix4f,
        time: Long,
    ): CartShoppingWheels.Frame {
        val frame =
            CartShoppingWheels.follow(item, x, y, angle, cart, time)
                ?: throw AssertionError("valid pose rejected")
        check(
            frame.phases!!.size == 4 && frame.casters!!.size == 2 && frame.relative!!.size == 7,
            "incomplete wheel snapshot",
        )
        for (phase in frame.phases!!) check(
            java.lang.Double.isFinite(phase),
            "nonfinite wheel phase",
        )
        for (caster in frame.casters!!) check(
            java.lang.Double.isFinite(caster),
            "nonfinite caster angle",
        )
        for (transform in frame.relative!!) check(
            transform != null && transform.isFinite,
            "nonfinite part transform",
        )
        return frame
    }

    private fun same(a: CartShoppingWheels.Frame, b: CartShoppingWheels.Frame, where: String) {
        for (i in 0 until 4) close(
            difference(a.phases!![i], b.phases!![i]),
            0,
            3e-5,
            "$where wheel $i",
        )
        for (i in 0 until 2) close(
            difference(a.casters!![i], b.casters!![i]),
            0,
            3e-5,
            "$where caster $i",
        )
    }

    private fun radius(): Double = CartShoppingWheelMesh.RADIUS * 1.5

    private fun straightAndReverse() {
        val item = item()
        val cart =
            (CartShopping.worldModel(Matrix4f())
                ?: throw AssertionError("valid world cart rejected"))
        val start = follow(item, 0f, 0f, 0f, cart, 1_000_000_000L)
        val forward = follow(item, -0.008f, 0f, 0f, cart, 1_020_000_000L)
        for (i in 0 until 4) close(
            difference(forward.phases!![i], start.phases!![i]),
            -0.008 / radius(),
            3e-5,
            "forward tire $i",
        )
        val reverse = follow(item, 0f, 0f, 0f, cart, 1_040_000_000L)
        for (i in 0 until 2) close(
            difference(reverse.phases!![i], forward.phases!![i]),
            0.008 / radius(),
            3e-5,
            "rear reverse tire $i",
        )
        for (i in 2 until 4) check(
            difference(reverse.phases!![i], forward.phases!![i]) > 0,
            "front reverse tire did not roll backwards",
        )
        for (i in 0 until 2) check(
            Math.abs(difference(reverse.casters!![i], forward.casters!![i])) <= 0.20001,
            "reverse caster snapped",
        )
        val stopped = follow(item, 0f, 0f, 0f, cart, 1_060_000_000L)
        same(reverse, stopped, "stopped")
        for (i in 0 until 7) check(
            reverse.relative!![i]!!.equals(stopped.relative!![i], 2e-5f),
            "stopped part transform drifted",
        )
        // Repeated reverse samples remain bounded even while casters turn through a half turn.
        var previous = stopped
        for (step in 1..30) {
            val next =
                follow(item, 0.004f * step, 0f, 0f, cart, 1_060_000_000L + step * 20_000_000L)
            for (i in 0 until 2) check(
                Math.abs(difference(next.casters!![i], previous.casters!![i])) <= 0.20001,
                "caster reversal discontinuity",
            )
            previous = next
        }
        check(
            Math.abs(previous.casters!![0]) > 1 && Math.abs(previous.casters!![1]) > 1,
            "reverse casters never followed movement",
        )
    }

    private fun centerWorld(
        cart: Matrix4f,
        wheel: Int,
        x: Float,
        y: Float,
        angle: Float,
    ): DoubleArray {
        val point = cart.transformPosition(point(CartShoppingWheelMesh.CENTERS[wheel]), Vector3f())
        val c = Math.cos(angle.toDouble())
        val s = Math.sin(angle.toDouble())
        return doubleArrayOf(
            x - 1.5 * (c * point.x + s * point.z),
            y + 1.5 * (-s * point.x + c * point.z),
        )
    }

    private fun turns() {
        val cart =
            (CartShopping.worldModel(Matrix4f())
                ?: throw AssertionError("valid world cart rejected"))
        for (angle in floatArrayOf(0.04f, -0.04f)) {
            val item = item()
            val before = follow(item, 0f, 0f, 0f, cart, 2_000_000_000L)
            val x = (-0.02 * Math.cos(angle * 0.5)).toFloat()
            val y = (-0.02 * Math.sin(angle * 0.5)).toFloat()
            val after = follow(item, x, y, angle, cart, 2_020_000_000L)
            for (i in 0 until 2) {
                val a = centerWorld(cart, i, 0f, 0f, 0f)
                val b = centerWorld(cart, i, x, y, angle)
                val accepted =
                    -(b[0] - a[0]) * Math.cos(angle * 0.5) - (b[1] - a[1]) * Math.sin(angle * 0.5)
                close(
                    difference(after.phases!![i], before.phases!![i]),
                    -accepted / radius(),
                    3e-5,
                    "independent rear center arc $i",
                )
            }
            val outer = Math.abs(after.phases!![if (angle > 0) 0 else 1])
            val inner = Math.abs(after.phases!![if (angle > 0) 1 else 0])
            check(outer > inner + 0.2, "inside and outside rear tires shared a phase")
        }
    }

    private fun continuityAndInvalid() {
        val item = item()
        val cart =
            (CartShopping.worldModel(Matrix4f())
                ?: throw AssertionError("valid world cart rejected"))
        follow(item, 0f, 0f, 0f, cart, 3_000_000_000L)
        val before = follow(item, -0.01f, 0f, 0f, cart, 3_020_000_000L)
        // Equivalent global geometry represented by different actor/attachment coordinates.
        val attached = Matrix4f().translation(0.12f, 0f, -0.08f).mul(cart)
        val attachedBefore = Matrix4f(attached)
        val handoff = follow(item, 0.17f, 0.12f, 0f, attached, 3_040_000_000L)
        same(before, handoff, "equipped/world coordinate handoff")
        check(attached == attachedBefore, "follow mutated caller attachment")
        val other = follow(item(), 0f, 0f, 0f, cart, 3_040_000_000L)
        for (phase in other.phases!!) close(phase, 0, 1e-9, "phase leaked between cart items")
        val invalid = Matrix4f(cart).m00(Float.NaN)
        check(
            CartShoppingWheels.follow(item, Float.NaN, 0f, 0f, cart, 3_050_000_000L) == null,
            "NaN position accepted",
        )
        check(
            CartShoppingWheels.follow(
                item,
                0f,
                Float.POSITIVE_INFINITY,
                0f,
                cart,
                3_050_000_000L,
            ) == null,
            "infinite position accepted",
        )
        check(
            CartShoppingWheels.follow(item, 0f, 0f, Float.NaN, cart, 3_050_000_000L) == null,
            "NaN heading accepted",
        )
        check(
            CartShoppingWheels.follow(item, 0f, 0f, 0f, invalid, 3_050_000_000L) == null,
            "NaN matrix accepted",
        )
        check(
            CartShoppingWheels.follow(item, 0f, 0f, 0f, null, 3_050_000_000L) == null,
            "null matrix accepted",
        )
        check(
            CartShoppingWheels.follow(item, 0f, 0f, 0f, Matrix4f(cart).scale(0f), 3_050_000_000L) ==
                null,
            "singular matrix accepted",
        )
        check(
            CartShoppingWheels.follow(
                item,
                0f,
                0f,
                0f,
                Matrix4f(cart).scale(-1f, 1f, 1f),
                3_050_000_000L,
            ) == null,
            "reflection accepted",
        )
        check(
            CartShoppingWheels.follow(item, 0f, 0f, 0f, cart, -1) == null,
            "invalid sample time accepted",
        )
        check(
            CartShoppingWheels.follow(null, 0f, 0f, 0f, cart, 3_050_000_000L) == null,
            "null item accepted",
        )
        val unsupported = item()
        unsupported.setType("Other")
        check(
            CartShoppingWheels.follow(unsupported, 0f, 0f, 0f, cart, 3_050_000_000L) == null,
            "unsupported item accepted",
        )
        same(
            handoff,
            follow(item, 0.17f, 0.12f, 0f, attached, 3_060_000_000L),
            "invalid pose poisoned ledger",
        )
        val teleport = follow(item, 50f, 50f, 0f, attached, 3_080_000_000L)
        same(handoff, teleport, "teleport")
        val resumed = follow(item, 49.992f, 50f, 0f, attached, 3_100_000_000L)
        close(
            difference(resumed.phases!![0], teleport.phases!![0]),
            -0.008 / radius(),
            1e-4,
            "travel after teleport",
        )
        same(
            resumed,
            follow(item, 49.992f, 50f, 0f, attached, 3_120_000_000L),
            "stopped after teleport",
        )
    }

    private fun circularGeometry() {
        for (cart in
            arrayOf(
                (CartShopping.worldModel(Matrix4f())
                    ?: throw AssertionError("valid world cart rejected")),
                (CartShopping.held(Matrix4f()) ?: throw AssertionError("valid held cart rejected")),
            )) {
            val item = item()
            val original = Matrix4f(cart)
            val axle = cart.transformDirection(Vector3f(0f, 0f, 1f)).normalize()
            val forward = Vector3f(0f, 1f, 0f).cross(axle).normalize()
            for (step in 0 until 12) {
                val travel = 0.012f * step
                val frame =
                    follow(
                        item,
                        -1.5f * forward.x * travel,
                        1.5f * forward.z * travel,
                        0f,
                        cart,
                        4_000_000_000L + step * 20_000_000L,
                    )
                check(
                    CartShoppingWheels.transform(cart, frame, 0, false, Matrix4f())
                        .equals(cart, 2e-5f),
                    "body moved with tire animation",
                )
                for (part in 5..6) check(
                    CartShoppingWheels.transform(cart, frame, part, false, Matrix4f())
                        .equals(cart, 2e-5f),
                    "straight support spun with tire",
                )
                for (i in 0 until 4) {
                    val center =
                        cart.transformPosition(point(CartShoppingWheelMesh.CENTERS[i]), Vector3f())
                    val transform =
                        CartShoppingWheels.transform(cart, frame, i + 1, false, Matrix4f())
                    val transposed =
                        CartShoppingWheels.transform(
                                Matrix4f(cart).transpose(),
                                frame,
                                i + 1,
                                true,
                                Matrix4f(),
                            )
                            .transpose()
                    check(
                        transform.equals(transposed, 3e-5f),
                        "native transpose path changed tire pose",
                    )
                    check(
                        transform
                            .transformPosition(point(CartShoppingWheelMesh.CENTERS[i]), Vector3f())
                            .distance(center) < 2e-5,
                        "tire axle moved during roll",
                    )
                    var minimum = Float.POSITIVE_INFINITY
                    for (raw in CartShoppingWheelMesh.PART_POINTS[i]) {
                        val p = transform.transformPosition(point(raw), Vector3f())
                        minimum = Math.min(minimum, p.y)
                        val radial = Vector3f(p).sub(center)
                        radial.fma(-radial.dot(axle), axle)
                        close(
                            radial.length(),
                            CartShoppingWheelMesh.RADIUS,
                            3e-6,
                            "tire did not remain a physical circle",
                        )
                    }
                    check(
                        minimum >= 0.00797f && minimum <= 0.00818f,
                        "rotated tire lost floor support: $minimum",
                    )
                }
            }
            check(cart == original, "wheel animation mutated source cart matrix")
        }
    }

    private fun fan(faces: Array<IntArray>): List<IntArray> {
        val result = ArrayList<IntArray>()
        for (face in faces) for (i in 1 until face.size - 1) result.add(
            intArrayOf(face[0], face[i], face[i + 1]),
        )
        return result
    }

    private fun topology() {
        for (part in 0 until 6) {
            val triangles = fan(CartShoppingWheelMesh.PART_FACES[part])
            check(
                CartShoppingWheels.topology(
                    CartShoppingWheelMesh.PART_POINTS[part],
                    CartShoppingWheelMesh.PART_FACES[part],
                    triangles,
                ),
                "calibrated convex source polygons rejected",
            )
            val duplicate = ArrayList(triangles)
            duplicate[1] = duplicate[0]
            check(
                !CartShoppingWheels.topology(
                    CartShoppingWheelMesh.PART_POINTS[part],
                    CartShoppingWheelMesh.PART_FACES[part],
                    duplicate,
                ),
                "duplicate source triangle accepted",
            )
        }
        val square =
            arrayOf(
                floatArrayOf(0f, 0f, 0f),
                floatArrayOf(1f, 0f, 0f),
                floatArrayOf(1f, 1f, 0f),
                floatArrayOf(0f, 1f, 0f),
            )
        val faces = arrayOf(intArrayOf(0, 1, 2, 3))
        check(
            CartShoppingWheels.topology(
                square,
                faces,
                listOf(intArrayOf(0, 1, 3), intArrayOf(1, 2, 3)),
            ),
            "alternative valid diagonal rejected",
        )
        for (invalid in
            listOf(
                listOf(intArrayOf(0, 1, 2)),
                listOf(intArrayOf(0, 1, 2), intArrayOf(0, 1, 2)),
                listOf(intArrayOf(0, 0, 1), intArrayOf(0, 2, 3)),
                listOf(intArrayOf(0, 1, 7), intArrayOf(0, 2, 3)),
                listOf(intArrayOf(-1, 1, 2), intArrayOf(0, 2, 3)),
            )) check(
            !CartShoppingWheels.topology(square, faces, invalid),
            "invalid or duplicate topology accepted",
        )
        val split =
            arrayOf(
                floatArrayOf(0f, 0f, 0f),
                floatArrayOf(1f, 0f, 0f),
                floatArrayOf(1f, 1f, 0f),
                floatArrayOf(0f, 1f, 0f),
                floatArrayOf(2f, 0f, 0f),
                floatArrayOf(3f, 0f, 0f),
                floatArrayOf(3f, 1f, 0f),
                floatArrayOf(2f, 1f, 0f),
            )
        check(
            !CartShoppingWheels.topology(
                split,
                arrayOf(intArrayOf(0, 1, 2, 3), intArrayOf(4, 5, 6, 7)),
                listOf(intArrayOf(0, 1, 4)),
            ),
            "mixed source faces accepted",
        )
        for (value in floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY)) {
            val bad =
                arrayOf(
                    floatArrayOf(value, 0f, 0f),
                    floatArrayOf(1f, 0f, 0f),
                    floatArrayOf(1f, 1f, 0f),
                    floatArrayOf(0f, 1f, 0f),
                )
            check(
                !CartShoppingWheels.topology(bad, faces, fan(faces)),
                "nonfinite topology accepted",
            )
        }
        check(
            !CartShoppingWheels.topology(
                arrayOf(
                    floatArrayOf(0f, 0f, 0f),
                    floatArrayOf(1f, 0f, 0f),
                    floatArrayOf(2f, 0f, 0f),
                ),
                arrayOf(intArrayOf(0, 1, 2)),
                listOf(intArrayOf(0, 1, 2)),
            ),
            "zero-area triangle accepted",
        )
        val tire = FloatArray(64 * 3)
        for (i in 0 until 64) System.arraycopy(
            CartShoppingWheelMesh.PART_POINTS[0][i],
            0,
            tire,
            i * 3,
            3,
        )
        check(
            CartShoppingWheels.pointHash(tire) ==
                "1c543017d267f985c4d2b97f1ce60a791db29fa72413c24fc8edee0efd962f4f",
            "float-bit signature differs from independent source audit",
        )
        val expanded = FloatArray(tire.size * 2)
        for (i in 0 until 64) for (j in 0 until 2) System.arraycopy(
            tire,
            (63 - i) * 3,
            expanded,
            (i * 2 + j) * 3,
            3,
        )
        check(
            CartShoppingWheels.pointHash(tire) == CartShoppingWheels.pointHash(expanded),
            "UV/normal position duplication or vertex order changed signature",
        )
        check(
            CartShoppingWheels.partition(null, IntArray(0)) == null &&
                CartShoppingWheels.partition(tire, null) == null &&
                CartShoppingWheels.partition(FloatArray(1), IntArray(0)) == null &&
                CartShoppingWheels.partition(tire, intArrayOf(0, 1)) == null &&
                CartShoppingWheels.partition(tire, intArrayOf(0, 1, 2)) == null,
            "uncalibrated/malformed mesh accepted",
        )
    }

    // Optional offline full-model fixtures: packed xyz float32 LE, then native or source-derived
    // triangle int32 LE.
    private fun fullMesh(positions: Path, indices: Path) {
        val p = ByteBuffer.wrap(Files.readAllBytes(positions)).order(ByteOrder.LITTLE_ENDIAN)
        val e = ByteBuffer.wrap(Files.readAllBytes(indices)).order(ByteOrder.LITTLE_ENDIAN)
        check(p.remaining() % 12 == 0 && e.remaining() % 12 == 0, "malformed offline fixture")
        val xyz = FloatArray(p.remaining() / 4)
        val elements = IntArray(e.remaining() / 4)
        for (i in xyz.indices) xyz[i] = p.float
        for (i in elements.indices) elements[i] = e.int
        val original = elements.clone()
        val runs =
            CartShoppingWheels.partition(xyz, elements)
                ?: throw AssertionError("calibrated full mesh rejected")
        check(elements.contentEquals(original), "partition changed native EBO")
        var offset = 0
        val counts = IntArray(7)
        for (run in runs) {
            check(run[0] == offset && run[1] > 0 && run[1] % 3 == 0, "index run gap/overlap")
            offset += run[1]
            counts[run[2]] += run[1] / 3
        }
        check(offset == elements.size, "partition omitted original triangles")
        for (i in 1 until 7) check(
            counts[i] == CartShoppingWheelMesh.PART_TRIANGLES[i - 1],
            "wrong moving triangle count",
        )
        val corrupt = elements.clone()
        corrupt[0] = xyz.size / 3
        check(
            CartShoppingWheels.partition(xyz, corrupt) == null,
            "out-of-range native index accepted",
        )
        val mixed = elements.clone()
        val tireRun = runs.first { it[2] == 1 }
        val otherRun = runs.first { it[2] == 2 }
        mixed[tireRun[0]] = elements[otherRun[0]]
        check(
            CartShoppingWheels.partition(xyz, mixed) == null,
            "cross-wheel native triangle accepted",
        )
        val duplicate = elements.clone()
        System.arraycopy(elements, tireRun[0], duplicate, tireRun[0] + 3, 3)
        check(
            CartShoppingWheels.partition(xyz, duplicate) == null,
            "duplicate native tire triangle accepted",
        )
        val nonfinite = xyz.clone()
        nonfinite[0] = Float.NaN
        check(
            CartShoppingWheels.partition(nonfinite, elements) == null,
            "nonfinite native mesh accepted",
        )
    }

    private fun boundaryOrder() {
        val cart = Matrix4f().translation(.2f, -.3f, .7f).rotateX(.4f)
        for (transpose in booleanArrayOf(false, true)) {
            val out = Matrix4f().zero()
            try {
                CartShoppingWheels.transform(cart, null, 0, transpose, out)
                throw AssertionError("null frame accepted")
            } catch (expected: NullPointerException) {
                val written = Matrix4f(cart)
                if (transpose) written.transpose()
                check(out == written, "frame validation changed native output mutation order")
            }
        }
        val slot = zombie.core.skinnedmodel.model.ModelSlotRenderData()
        val data = zombie.core.skinnedmodel.model.ModelInstanceRenderData()
        CartShoppingWheels.prepare(slot, item(), data, CartShopping.worldModel(Matrix4f()))
        check(CartShoppingWheels.frame(data) != null, "valid render snapshot rejected")
        try {
            CartShoppingWheels.prepare(null, item(), data, cart)
            throw AssertionError("null render slot accepted")
        } catch (expected: NullPointerException) {
            check(
                CartShoppingWheels.frame(data) == null,
                "failed prepare retained a recycled frame",
            )
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        unsafe = field.get(null) as Unsafe
        boundaryOrder()
        straightAndReverse()
        turns()
        continuityAndInvalid()
        circularGeometry()
        topology()
        if (args.size == 2) fullMesh(Path.of(args[0]), Path.of(args[1]))
        else check(args.isEmpty(), "expected optional xyz-f32le and elements-i32le paths")
        println(
            "CART_SHOPPING_WHEELS_PASS (signed center travel, independent turn phases, bounded casters, item/handoff continuity, circular floor support, source topology)",
        )
    }
}
