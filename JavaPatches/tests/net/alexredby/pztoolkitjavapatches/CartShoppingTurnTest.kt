package net.alexredby.pztoolkitjavapatches

import jassimp.AiPostProcessSteps
import jassimp.Jassimp
import java.nio.file.Path
import java.util.EnumSet
import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams

object CartShoppingTurnTest {
    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(a: Double, b: Double, message: String) =
        check(kotlin.math.abs(a - b) < 2e-5, "$message $a != $b")

    private fun matrixError(a: Matrix4f, b: Matrix4f): Float {
        val x = a.get(FloatArray(16))
        val y = b.get(FloatArray(16))
        return x.indices.maxOf { kotlin.math.abs(x[it] - y[it]) }
    }

    private fun field(target: Any, name: String): Any =
        target.javaClass.getDeclaredField(name).run {
            isAccessible = true
            get(target)
        }

    @Suppress("UNCHECKED_CAST")
    private fun read(path: Path): Pair<SkinningData, AnimationClip> {
        val params = ProcessedAiSceneParams.create()
        params.scene =
            Jassimp.importFile(
                path.toString(),
                EnumSet.of(
                    AiPostProcessSteps.MAKE_LEFT_HANDED,
                    AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS,
                ),
            )
        params.mode = JAssImpImporter.LoadMode.AnimationOnly
        params.animBonesScaleModifier = 1f
        params.animBonesRotateModifier = null
        val imported =
            ImportedSkeleton.process(
                ImportedSkeletonParams.create(params, params.scene.getMeshes()[0]),
            )
        val indices = field(imported, "boneIndices") as HashMap<String, Int>
        val hierarchy = field(imported, "skeletonHierarchy") as ArrayList<Int>
        val clips = field(imported, "clips") as HashMap<String, AnimationClip>
        val offsets = ArrayList<org.lwjgl.util.vector.Matrix4f>()
        repeat(indices.size) { offsets.add(org.lwjgl.util.vector.Matrix4f()) }
        return SkinningData(HashMap(), offsets, offsets, offsets, hierarchy, indices) to
            clips.values.single()
    }

    private fun reference(actor: SkinningData, clip: AnimationClip) =
        Array<Matrix4f?>(actor.numBones()) { i ->
            Matrix4f().also {
                check(
                    CartGrounding.referencePose(clip, actor, actor.getBoneAt(i).name, it),
                    "reference bone$i",
                )
            }
        }

    private fun controller() {
        close(CartShoppingTurn.amount(0f, .8f), 0.0, "straight")
        close(CartShoppingTurn.amount(-1f, 0f), 0.0, "stationary")
        close(CartShoppingTurn.amount(-1f, -.8f), 0.0, "reverse")
        close(CartShoppingTurn.amount(Float.NaN, 1f), 0.0, "invalid")
        check(CartShoppingTurn.amount(-.6f, .8f) > 0, "left sign")
        check(CartShoppingTurn.amount(.6f, .8f) < 0, "right sign")
        val motion = CartShoppingTurn.Blend()
        val clock = Any()
        motion.update(1.0, 1.0 / 60, clock, .98, 2.0 / 3)
        motion.update(1.0, 1.0 / 60, clock, .02, 2.0 / 3)
        close(motion.phase, 1.0 / 30, "phase wrap")
        motion.update(1.0, 1.0 / 60, Any(), .75, 2.0 / 3)
        close(motion.phase, 1.0 / 30, "track replacement")
        repeat(60) { motion.update(1.0, 1.0 / 60, null, Double.NaN, Double.NaN) }
        check(motion.turn > .99, "entry reaches target")
        val before = motion.turn
        motion.update(0.0, 1.0 / 60, null, Double.NaN, Double.NaN)
        check(motion.turn in .8..before, "release must fade")
        repeat(60) { motion.update(0.0, 1.0 / 60, null, Double.NaN, Double.NaN) }
        close(motion.turn, 0.0, "release settles")
        repeat(120) { motion.update(-1.0, 1.0 / 60, null, Double.NaN, Double.NaN) }
        check(motion.turn < -.99, "direction reversal")
        val secondsClock = CartShoppingTurn.Blend()
        val token = Any()
        for (i in 0..60) secondsClock.update(1.0, 1.0 / 60, token, (i / 60.0) / (2.0 / 3), 2.0 / 3)
        close(secondsClock.phase, .25, "one native source second preserves .8s loop duration")
    }

    private fun slots() {
        val unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").run {
                isAccessible = true
                get(null) as Unsafe
            }
        fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))
        val player = allocate(IsoPlayer::class.java)
        val owner = allocate(ModelInstance::class.java)
        owner.`object` = player
        owner.model = allocate(Model::class.java)
        owner.animPlayer = allocate(AnimationPlayer::class.java)
        val source = allocate(ModelManager.ModelSlot::class.java)
        source.character = player
        source.model = owner
        val slot = ModelSlotRenderData()
        slot.character = player
        slot.`object` = player
        val view = CartShoppingTurn.View(.3f, .8f)
        CartShoppingTurn.capture(slot, source, view)
        check(CartShoppingTurn.view(slot, owner) == view, "slot owns immutable phase")
        check(CartShoppingTurn.view(ModelSlotRenderData(), owner) == null, "other slot")
        val model = owner.model
        owner.model = allocate(Model::class.java)
        check(CartShoppingTurn.view(slot, owner) == null, "replacement model rejected")
        owner.model = model
        CartShoppingTurn.release(slot)
        check(CartShoppingTurn.view(slot, owner) == null, "released slot")
    }

    /** A complete foot cycle must bend the arms rather than shuttle the cart with the shoulders. */
    private fun stableBar(actor: SkinningData, clip: AnimationClip, baseline: Array<Matrix4f?>) {
        for (female in listOf(false, true)) {
            var first: Matrix4f? = null
            var minFlex = 180.0
            var maxFlex = 0.0
            for (phase in 0..48) {
                val poses = Array(baseline.size) { Matrix4f(baseline[it]) }
                check(
                    CartShoppingTurn.apply(
                        poses,
                        actor,
                        clip,
                        CartShoppingTurn.View(phase / 48f, 1f),
                    ),
                    "turn cycle sample",
                )
                val before = Array(poses.size) { Matrix4f(poses[it]) }
                val cart = CartShopping.held(Matrix4f()) ?: error("held cart")
                check(
                    CartShoppingStance.apply(poses, actor, female, Matrix4f(), cart, 1f),
                    "turn stance",
                )
                if (first == null) first = Matrix4f(cart)
                check(cart.equals(first, 2e-6f), "step moved shopping cart: $female/$phase")
                check(
                    CartGrip.grip(poses, actor, "ShoppingCartModel", female, Matrix4f(), cart),
                    "turn grip",
                )
                for (side in listOf("L", "R")) {
                    val ids =
                        listOf("UpperArm", "Forearm", "Hand").map {
                            actor.getBone("Bip01_${side}_$it").index
                        }
                    val a = poses[ids[0]].getTranslation(Vector3f())
                    val b = poses[ids[1]].getTranslation(Vector3f())
                    val c = poses[ids[2]].getTranslation(Vector3f())
                    val flex =
                        Math.toDegrees(
                            kotlin.math.acos(
                                b.sub(a, Vector3f())
                                    .normalize()
                                    .dot(c.sub(b, Vector3f()).normalize())
                                    .toDouble()
                                    .coerceIn(-1.0, 1.0),
                            ),
                        )
                    minFlex = minOf(minFlex, flex)
                    maxFlex = maxOf(maxFlex, flex)
                    check(flex <= 118, "turn arm folded: $female/$phase/$side $flex")
                    val target = Matrix4f()
                    check(
                        CartGrip.target(
                            "ShoppingCartModel",
                            side == "L",
                            female,
                            Matrix4f(),
                            cart,
                            target,
                        ),
                        "turn target",
                    )
                    check(poses[ids[2]].equals(target, 3e-5f), "turn hand left the bar")
                    for (link in 0..1) {
                        val i = ids[link]
                        val j = ids[link + 1]
                        close(
                            poses[i]
                                .getTranslation(Vector3f())
                                .distance(poses[j].getTranslation(Vector3f()))
                                .toDouble(),
                            before[i]
                                .getTranslation(Vector3f())
                                .distance(before[j].getTranslation(Vector3f()))
                                .toDouble(),
                            "turn arm length",
                        )
                    }
                }
                for (name in
                    listOf(
                        "Bip01_Pelvis",
                        "Bip01_Spine",
                        "Bip01_Spine1",
                        "Bip01_L_Thigh",
                        "Bip01_R_Thigh",
                    )) {
                    val i = actor.getBone(name).index
                    check(poses[i] == before[i], "stable bar changed body: $name")
                }
            }
            check(maxFlex - minFlex > 20, "turn elbows stopped absorbing body motion")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        controller()
        slots()
        val root = Path.of(System.getProperty("pz.test.project"))
        val folder = root.resolve("PZSurvivorToolkit/42/media/anims_X/Bob")
        val (actor, idle) = read(folder.resolve("Toolkit_CartPivot_Idle.x"))
        val baseline = reference(actor, idle)
        for (side in listOf("Left", "Right")) {
            val (targetActor, clip) = read(folder.resolve("Toolkit_ShoppingTurn_$side.x"))
            check(actor.boneIndices == targetActor.boneIndices, "bone mapping")
            val expected = reference(actor, clip)
            stableBar(actor, clip, baseline)
            val zero = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                CartShoppingTurn.apply(zero, actor, clip, CartShoppingTurn.View(0f, 0f)),
                "zero blend",
            )
            check(
                zero.indices.all { matrixError(zero[it], baseline[it]!!) < 2e-5 },
                "zero is native gait",
            )
            val full = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                CartShoppingTurn.apply(full, actor, clip, CartShoppingTurn.View(0f, 1f)),
                "native full pose",
            )
            check(
                full.indices.all { matrixError(full[it], expected[it]!!) < 2e-5 },
                "native import/FK matches accepted pose",
            )
            for (phase in 0..48) for (weight in listOf(.15f, .5f, 1f)) {
                val output = Array(baseline.size) { Matrix4f(baseline[it]) }
                check(
                    CartShoppingTurn.apply(
                        output,
                        actor,
                        clip,
                        CartShoppingTurn.View(phase / 48f, weight),
                    ),
                    "blend $side/$phase/$weight",
                )
                for (leg in listOf("L", "R")) for ((a, b) in
                    listOf("Thigh" to "Calf", "Calf" to "Foot")) {
                    val i = actor.getBone("Bip01_${leg}_$a").index
                    val j = actor.getBone("Bip01_${leg}_$b").index
                    val before =
                        baseline[i]!!
                            .getTranslation(Vector3f())
                            .distance(baseline[j]!!.getTranslation(Vector3f()))
                    val after =
                        output[i]
                            .getTranslation(Vector3f())
                            .distance(output[j].getTranslation(Vector3f()))
                    close(after.toDouble(), before.toDouble(), "real leg length")
                }
                check(output.all { it.isFinite }, "finite output")
            }
            val unchanged = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                !CartShoppingTurn.apply(unchanged, actor, null, CartShoppingTurn.View(0f, 1f)),
                "missing clip fallback",
            )
            check(
                unchanged.indices.all { unchanged[it] == baseline[it] },
                "failed sample cannot mutate live palette",
            )
        }
        println(
            "CART_SHOPPING_TURN_PASS native loops, local length-preserving blends, phase wrap/release, slot ownership",
        )
    }
}
