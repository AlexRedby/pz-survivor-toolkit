package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.SkinningData

/** Native shopping turns and fast-gait lean; female targets reuse captured male arm geometry. */
object CartShoppingGripTest {
    private val names =
        arrayOf(
            "Bip01_Spine",
            "Bip01_Spine1",
            "Bip01_L_Clavicle",
            "Bip01_R_Clavicle",
            "Bip01_L_UpperArm",
            "Bip01_L_Forearm",
            "Bip01_L_Hand",
            "Bip01_R_UpperArm",
            "Bip01_R_Forearm",
            "Bip01_R_Hand",
            "Bip01_L_Thigh",
            "Bip01_L_Calf",
            "Bip01_L_Foot",
            "Bip01_R_Thigh",
            "Bip01_R_Calf",
            "Bip01_R_Foot",
            "Bip01_Neck",
            "Bip01_Head",
        )
    private val phases =
        setOf(
            "left-held", "right-held", "pivot-left", "pivot-right",
            "reverse-left", "reverse-right", "run", "sprint",
        )

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun at(poses: Array<Matrix4f>, index: Int): Vector3f =
        poses[index].getTranslation(Vector3f())

    private fun angle(a: Vector3f, b: Vector3f): Double =
        Math.toDegrees(Math.acos(a.normalize().dot(b.normalize()).toDouble().coerceIn(-1.0, 1.0)))

    private data class Arm(val wrist: Double, val roll: Double, val flex: Double)

    private fun arm(poses: Array<Matrix4f>, upper: Int): Arm {
        val forearm = upper + 1
        val hand = upper + 2
        val upperAxis = at(poses, forearm).sub(at(poses, upper))
        val forearmAxis = at(poses, hand).sub(at(poses, forearm))
        val axis = Vector3f(forearmAxis).normalize()
        val forearmPalm = poses[forearm].transformDirection(Vector3f(0f, 0f, 1f))
        val handPalm = poses[hand].transformDirection(Vector3f(0f, 0f, 1f))
        forearmPalm.fma(-forearmPalm.dot(axis), axis)
        handPalm.fma(-handPalm.dot(axis), axis)
        return Arm(
            angle(forearmAxis, poses[hand].transformDirection(Vector3f(1f, 0f, 0f))),
            angle(forearmPalm, handPalm),
            angle(upperAxis, forearmAxis),
        )
    }

    private fun copy(poses: Array<Matrix4f>): Array<Matrix4f> =
        Array(poses.size) { Matrix4f(poses[it]) }

    @JvmStatic
    fun main(args: Array<String>) {
        val offsets = names.map { org.lwjgl.util.vector.Matrix4f() }
        val actor =
            SkinningData(
                HashMap(),
                offsets,
                offsets,
                offsets,
                listOf(-1, 0, 1, 1, 2, 4, 5, 3, 7, 8, 0, 10, 11, 0, 13, 14, 1, 16),
                HashMap<String, Int>().apply { names.forEachIndexed { i, name -> put(name, i) } },
            )
        val fixture =
            Path.of(System.getProperty("pz.test.project", "."))
                .resolve("JavaPatches/tests/fixtures/shopping-turning-grip.csv")
        var frames = 0
        val seen = HashSet<String>()
        var legacyFlex = 0.0
        var maxWrist = 0.0
        var maxRoll = 0.0
        var maxFlex = 0.0
        for (line in Files.readAllLines(fixture)) {
            if (line.isBlank() || line.startsWith("#")) continue
            val cells = line.split(",")
            val label = cells[0]
            check(cells.size == 3 + 12 * 16, "invalid native shopping fixture: $label")
            check(cells[1].toLong() > 0 && cells[2] == "false", "unexpected native rig: $label")
            val phase = phases.single { label.startsWith("$it-") }
            seen.add(phase)
            val captured =
                Array(12) { i ->
                    Matrix4f().set(FloatArray(16) { j -> cells[3 + i * 16 + j].toFloat() })
                }
            check(captured.all { it.isFinite }, "nonfinite native shopping input: $label")
            val delta = captured[0]
            val cart = captured[1]
            val deltaBefore = Matrix4f(delta)
            val cartBefore = Matrix4f(cart)
            val original =
                Array(names.size) { i ->
                    if (i < 10) Matrix4f(captured[i + 2])
                    // Leg sentinels protect the full thigh branch, not an invented native gait.
                    else if (i < 16)
                        Matrix4f().translation(
                            if (i < 13) .06f else -.06f,
                            .5f - .12f * (i % 3),
                            .02f * i,
                        )
                    // The probe captures neither head nor legs; these only guard untouched motion.
                    else Matrix4f(captured[3]).translate(if (i == 16) .08f else .16f, 0f, 0f)
                }
            for (femaleTarget in booleanArrayOf(false, true)) {
                val poses = copy(original)
                check(
                    CartGrip.grip(poses, actor, "ShoppingCartModel", femaleTarget, delta, cart),
                    "captured shopping grip refused: $label femaleTarget=$femaleTarget",
                )
                check(poses[0] == original[0], "shopping posture moved anchored Spine: $label")
                for (i in 10 until 16) check(
                    poses[i] == original[i], "shopping posture changed leg sentinel: $label/${names[i]}",
                )
                val pivot = at(original, 0)
                val posture = Matrix4f(poses[1]).mul(Matrix4f(original[1]).invert())
                val pitch = Math.atan2(posture.m12().toDouble(), posture.m11().toDouble())
                check(
                    pitch >= -1e-5 && pitch <= Math.toRadians(70.0) + 1e-5,
                    "unbounded shopping posture: $label",
                )
                val rigid =
                    Matrix4f()
                        .translation(pivot)
                        .rotateX(pitch.toFloat())
                        .translate(-pivot.x, -pivot.y, -pivot.z)
                check(posture.equals(rigid, 3e-5f), "shopping posture changed torso length/yaw: $label")
                check(
                    at(poses, 1).distance(pivot) - at(original, 1).distance(pivot) in -3e-6f..3e-6f,
                    "shopping posture stretched torso: $label",
                )
                val neck = at(poses, 16)
                val expectedNeck = rigid.transformPosition(at(original, 16))
                check(neck.distance(expectedNeck) < 3e-6f, "shopping neck detached from chest: $label")
                val neckShift = neck.sub(at(original, 16), Vector3f())
                for (i in 16..17) check(
                    poses[i].equals(Matrix4f(original[i]).translateLocal(neckShift), 3e-6f),
                    "shopping posture changed native neck/head orientation or link: $label/${names[i]}",
                )
                for (side in 0..1) {
                    val upper = if (side == 0) 4 else 7
                    val hand = upper + 2
                    for (i in upper until hand) check(
                        Math.abs(
                            at(poses, i).distance(at(poses, i + 1)) -
                                at(original, i).distance(at(original, i + 1)),
                        ) < 3e-6f,
                        "shopping grip stretched arm link: $label/${names[i]}",
                    )
                    val target = Matrix4f()
                    check(
                        CartGrip.target(
                            "ShoppingCartModel", side == 0, femaleTarget, delta, cart, target,
                        ),
                        "shopping target refused: $label",
                    )
                    check(poses[hand].equals(target, 3e-5f), "shopping wrist missed fixed target: $label")
                    val station = Vector3f()
                    check(
                        CartGrip.handle("ShoppingCartModel", side == 0, station),
                        "missing shopping handle",
                    )
                    cart.transformPosition(station)
                    val grasp = CartGrip.grasp(femaleTarget, "ShoppingCartModel")
                    val palm =
                        poses[hand].transformPosition(Vector3f(grasp.palmX, 0f, grasp.palmDepth))
                    check(palm.distance(station) < 3e-5f, "shopping palm missed actual handle: $label")
                    val measured = arm(poses, upper)
                    maxWrist = Math.max(maxWrist, measured.wrist)
                    maxRoll = Math.max(maxRoll, measured.roll)
                    maxFlex = Math.max(maxFlex, measured.flex)
                    // Full native replay maxima were 34.81/0.035/108.91 degrees, including
                    // straight Run/Sprint and both target parameter sets on this male rig.
                    check(
                        measured.wrist <= 36 && measured.roll <= 1 && measured.flex <= 112,
                        "unnatural shopping arm: $label femaleTarget=$femaleTarget side=$side $measured",
                    )
                    if (!femaleTarget) {
                        val old = copy(original)
                        check(
                            CartGrip.reach(old, actor, names[hand], target, null, false),
                            "legacy shopping fixture unexpectedly unreachable: $label",
                        )
                        legacyFlex = Math.max(legacyFlex, arm(old, upper).flex)
                    }
                }
                val nearHeld = copy(original)
                check(
                    CartGrip.transitionGrip(
                        nearHeld, actor, femaleTarget, delta, cart,
                        .99999f, 1f, null, "ShoppingCartModel",
                    ),
                    "shopping transition lost near-held reach: $label",
                )
                for (i in names.indices) check(
                    nearHeld[i].equals(poses[i], .0001f),
                    "shopping transition snapped at full held weight: $label/${names[i]}",
                )
                val zero = copy(original)
                check(
                    CartGrip.transitionGrip(
                        zero, actor, femaleTarget, delta, cart,
                        0f, 0f, null, "ShoppingCartModel",
                    ),
                    "zero shopping transition refused: $label",
                )
                for (i in names.indices) check(
                    zero[i].equals(original[i], 3e-6f),
                    "zero shopping transition changed pose: $label/${names[i]}",
                )
                check(
                    delta == deltaBefore && cart == cartBefore,
                    "shopping grip changed input transform: $label",
                )
            }
            frames++
        }
        check(frames == 16 && seen == phases, "missing captured shopping turn/fast-gait coverage")
        check(legacyFlex >= 158, "native fixtures no longer reproduce the folded-arm defect")
        println(
            "CART_SHOPPING_GRIP_PASS (16 native turn/fast-gait inputs, anchored torso, arm lengths, " +
                "fixed handles, transition continuity; max wrist=$maxWrist roll=$maxRoll " +
                "flex=$maxFlex legacyFlex=$legacyFlex)",
        )
    }
}
