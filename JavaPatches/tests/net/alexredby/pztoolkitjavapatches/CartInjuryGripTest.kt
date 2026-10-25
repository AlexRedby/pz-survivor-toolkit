package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.util.HashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.SkinningData

/**
 * Measured pre-IK failures from both sexes and injured sides, plus successful neighboring poses.
 */
object CartInjuryGripTest {
    private val NAMES =
        arrayOf(
            "Bip01_Spine",
            "Bip01_Spine1",
            "Bip01_L_Clavicle",
            "Bip01_L_UpperArm",
            "Bip01_L_Forearm",
            "Bip01_L_Hand",
            "Bip01_R_Clavicle",
            "Bip01_R_UpperArm",
            "Bip01_R_Forearm",
            "Bip01_R_Hand",
            "Bip01_L_Thigh",
            "Bip01_L_Calf",
            "Bip01_L_Foot",
            "Bip01_R_Thigh",
            "Bip01_R_Calf",
            "Bip01_R_Foot",
        )

    private fun skeleton(): SkinningData {
        val indices = HashMap<String, Int>()
        val offsets = ArrayList<org.lwjgl.util.vector.Matrix4f>()
        for (i in NAMES.indices) {
            indices[NAMES[i]] = i
            offsets.add(org.lwjgl.util.vector.Matrix4f())
        }
        return SkinningData(
            HashMap(),
            offsets,
            offsets,
            offsets,
            listOf(-1, 0, 1, 2, 3, 4, 1, 6, 7, 8, 0, 10, 11, 0, 13, 14),
            indices,
        )
    }

    private fun check(result: Boolean, message: String) {
        if (!result) throw AssertionError(message)
    }

    private fun close(actual: Float, expected: Float, tolerance: Float, message: String) {
        check(
            actual.isFinite() && Math.abs(actual - expected) < tolerance,
            "$message: $actual != $expected",
        )
    }

    private fun copy(source: Array<Matrix4f>): Array<Matrix4f> =
        Array(source.size) { Matrix4f(source[it]) }

    private fun matrix(values: List<String>, offset: Int): Matrix4f =
        Matrix4f().set(FloatArray(16) { values[offset + it].toFloat() })

    private fun link(poses: Array<Matrix4f>, a: Int, b: Int): Float =
        poses[a].getTranslation(Vector3f()).distance(poses[b].getTranslation(Vector3f()))

    private fun lengths(actual: Array<Matrix4f>, expected: Array<Matrix4f>, label: String) {
        for (pair in
            arrayOf(
                intArrayOf(2, 3),
                intArrayOf(3, 4),
                intArrayOf(4, 5),
                intArrayOf(6, 7),
                intArrayOf(7, 8),
                intArrayOf(8, 9),
            )) close(
            link(actual, pair[0], pair[1]),
            link(expected, pair[0], pair[1]),
            .00001f,
            "$label stretched arm/clavicle",
        )
    }

    private fun unchanged(actual: Array<Matrix4f>, expected: Array<Matrix4f>, label: String) {
        for (i in actual.indices) check(actual[i] == expected[i], "$label changed ${NAMES[i]}")
    }

    private fun captured(values: List<String>, actor: SkinningData, bank: Float) {
        val model =
            if (values.size > 52 + 16 * NAMES.size) values[52 + 16 * NAMES.size]
            else "WheelbarrowWood"
        val label = "$model capture=${values[0]} bank=$bank"
        val female = values[1] == "1"
        val failed = values[3] == "1"
        val weight = values[2].toFloat()
        val pressure = Math.abs(bank)
        val rotation = Matrix4f().rotationZ(bank)
        val delta = rotation.mul(matrix(values, 4), Matrix4f())
        val cart = rotation.mul(matrix(values, 20), Matrix4f())
        val reference = delta.mul(matrix(values, 36), Matrix4f())
        val poses = Array(NAMES.size) { rotation.mul(matrix(values, 52 + 16 * it), Matrix4f()) }
        val before = copy(poses)
        val cartBefore = Matrix4f(cart)
        val deltaBefore = Matrix4f(delta)
        // The recorded metal success flag predates the current palm offsets/tilt. Use the
        // current solver's reachable/no-op invariant below; wood's target is unchanged.
        if (bank == 0f && model != "WheelbarrowMetal")
            check(
                CartGrip.grip(copy(poses), actor, model, female, delta, cart, pressure) != failed,
                "$label no longer reproduces its measured original reach result",
            )
        close(
            CartGrip.injuryTorso(poses, actor, female, delta, cart, pressure, 0f, reference, model),
            0f,
            .000001f,
            "$label healthy ownership",
        )
        unchanged(poses, before, "$label healthy injury correction")
        close(
            CartGrip.injuryTorso(poses, actor, female, delta, cart, pressure, weight, null, model),
            0f,
            .000001f,
            "$label missing reference",
        )
        unchanged(poses, before, "$label unavailable reference")
        close(
            CartGrip.injuryTorso(
                poses,
                actor,
                female,
                delta,
                cart,
                pressure,
                weight,
                reference,
                "ShoppingCartModel",
            ),
            0f,
            .000001f,
            "$label shopping scope",
        )
        unchanged(poses, before, "$label shopping cart correction")
        val originallyReachable =
            CartGrip.grip(copy(poses), actor, model, female, delta, cart, pressure)
        val amount =
            CartGrip.injuryTorso(
                poses,
                actor,
                female,
                delta,
                cart,
                pressure,
                weight,
                reference,
                model,
            )
        check(amount >= 0 && amount <= 1, "$label correction escaped its measured envelope")
        if (originallyReachable) {
            close(amount, 0f, .000001f, "$label corrected an already reachable pose")
            unchanged(poses, before, "$label unnecessary torso correction")
        } else check(amount > 0, "$label could not fit the measured injury torso")
        for (i in intArrayOf(0, 10, 11, 12, 13, 14, 15)) check(
            poses[i] == before[i],
            "$label moved hip/native legs ${NAMES[i]}",
        )
        check(
            poses[1].m30() == before[1].m30() &&
                poses[1].m31() == before[1].m31() &&
                poses[1].m32() == before[1].m32(),
            "$label moved chest pivot",
        )
        lengths(poses, before, "$label torso correction")
        check(cart == cartBefore && delta == deltaBefore, "$label changed grounded cart")
        check(
            CartGrip.grip(poses, actor, model, female, delta, cart, pressure),
            "$label corrected pose still cannot reach both handles",
        )
        lengths(poses, before, "$label IK")
        for (i in intArrayOf(0, 10, 11, 12, 13, 14, 15)) check(
            poses[i] == before[i],
            "$label IK changed native hip/legs",
        )
        for (side in 0 until 2) {
            val shape = CartGrip.grasp(female, model)
            val palm =
                poses[if (side == 0) 5 else 9].transformPosition(
                    Vector3f(shape.palmX, 0f, shape.palmDepth),
                )
            val handle = Vector3f()
            CartGrip.handle(model, side == 0, handle)
            cart.transformPosition(handle)
            close(palm.distance(handle), 0f, .00002f, "$label palm missed handle")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val fixture =
            if (args.isEmpty())
                Path.of(
                    System.getProperty("pz.test.project"),
                    "JavaPatches/tests/fixtures/cart-injury-grip.csv",
                )
            else Path.of(args[0])
        val actor = skeleton()
        var count = 0
        for (line in Files.readAllLines(fixture)) if (!line.startsWith("#") && line.isNotBlank()) {
            val values = line.split(",")
            check(
                values.size == 52 + 16 * NAMES.size || values.size == 53 + 16 * NAMES.size,
                "incomplete recorded injury fixture",
            )
            for (bank in
                floatArrayOf(
                    0f,
                    Math.toRadians(-3.0).toFloat(),
                    Math.toRadians(3.0).toFloat(),
                )) captured(values, actor, bank)
            count++
        }
        check(
            count == if (args.size > 1) args[1].toInt() else 26,
            "missing representative injury captures",
        )
        check(
            CartGrip.injuryTorso(
                emptyArray(),
                null,
                false,
                Matrix4f(),
                Matrix4f(),
                0f,
                1f,
                Matrix4f(),
                "WheelbarrowWood",
            ) == 0f,
            "missing actor did not preserve the native fallback",
        )
        println("CART_INJURY_GRIP_PASS")
    }
}
