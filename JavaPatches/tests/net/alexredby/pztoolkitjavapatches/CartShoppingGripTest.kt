package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.model.SkinningData
import zombie.inventory.InventoryItem
import zombie.scripting.ScriptManager
import zombie.scripting.objects.ModelScript
import zombie.scripting.objects.ScriptModule

/** Native male/female shopping inputs; move the reachable cart instead of bending the torso. */
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
            "left-held",
            "right-held",
            "pivot-left",
            "pivot-right",
            "reverse-left",
            "reverse-right",
            "run",
            "sprint",
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

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var animation: AnimationPlayer? = null
        @JvmField var cart: InventoryItem? = null

        override fun hasAnimationPlayer(): Boolean = animation != null

        override fun getAnimationPlayer(): AnimationPlayer? = animation

        override fun getPrimaryHandItem(): InventoryItem? = cart
    }

    private class Cart : InventoryItem(null, null, null, null as String?) {
        override fun getFullType(): String = "SaucedCarts.ShoppingCart"

        override fun getWorldStaticModel(): String = "ShoppingGripBinding.ShoppingCartModel"
    }

    /** Exercise the native transposed palette and real model lookup, not a test solver adapter. */
    private class NativeBinding(actor: SkinningData) {
        private val player: Player
        private val transforms = AnimationPlayer::class.java.getDeclaredField("modelTransforms")
        private val held: Matrix4f

        init {
            val field = Unsafe::class.java.getDeclaredField("theUnsafe")
            field.isAccessible = true
            val unsafe = field.get(null) as Unsafe
            player = unsafe.allocateInstance(Player::class.java) as Player
            player.setDescriptor(
                unsafe.allocateInstance(zombie.characters.SurvivorDesc::class.java)
                    as zombie.characters.SurvivorDesc,
            )
            val animation = unsafe.allocateInstance(AnimationPlayer::class.java) as AnimationPlayer
            player.animation = animation
            val skinning = AnimationPlayer::class.java.getDeclaredField("skinningData")
            skinning.isAccessible = true
            skinning.set(animation, actor)
            transforms.isAccessible = true
            val item = unsafe.allocateInstance(Cart::class.java) as Cart
            item.worldScale = 1f
            player.cart = item
            val manager = ScriptManager.instance
            val module = ScriptModule()
            module.name = "ShoppingGripBinding"
            manager.moduleMap[module.name] = module
            manager.moduleList.add(module)
            val scripts = ScriptManager::class.java.getDeclaredField("models")
            scripts.isAccessible = true
            (scripts.get(manager) as zombie.scripting.ScriptBucketCollection<*>).registerModule(
                module,
            )
            val script = ModelScript()
            script.name = "ShoppingCartModel"
            script.InitLoadPP(script.name)
            script.setModule(module)
            script.scale = 1f
            script.setModelManagerKey("shopping-grip-binding")
            manager.addModelScript(script)
            val mesh = unsafe.allocateInstance(ModelMesh::class.java) as ModelMesh
            val ready = unsafe.allocateInstance(Class.forName("zombie.asset.Asset\$PRIVATE"))
            val state = ready.javaClass.getDeclaredField("currentState")
            state.isAccessible = true
            state.set(ready, zombie.asset.Asset.State.READY)
            val asset = zombie.asset.Asset::class.java.getDeclaredField("priv")
            asset.isAccessible = true
            asset.set(mesh, ready)
            mesh.transform =
                (CartShopping.worldModel(Matrix4f()) ?: error("world model")).transpose()
            val model = unsafe.allocateInstance(Model::class.java) as Model
            val modelMesh = Model::class.java.getDeclaredField("mesh")
            modelMesh.isAccessible = true
            modelMesh.set(model, mesh)
            val loaded = ModelManager::class.java.getDeclaredField("modelMap")
            loaded.isAccessible = true
            @Suppress("UNCHECKED_CAST")
            val models = loaded.get(ModelManager.instance) as MutableMap<String, Model>
            models[script.getModelManagerKey()] = model
            held =
                CartShopping.held(Matrix4f(), CartTransition.model(item), item.worldScale)
                    ?: error("native binding held model unavailable")
        }

        fun check(poses: Array<Matrix4f>, actor: SkinningData, female: Boolean, label: String) {
            player.setFemale(female)
            check(player.isFemale() == female, "native binding sex mismatch: $label")
            val native =
                Array(poses.size) {
                    PZMath.convertMatrix(
                        Matrix4f(poses[it]).transpose(),
                        org.lwjgl.util.vector.Matrix4f(),
                    )
                }
            transforms.set(player.animation, native)
            val expected = CartShoppingStance.shift(poses, actor, female, Matrix4f(), held)
            val actual = CartShoppingStance.shift(player)
            check(expected.isFinite() && expected < -.01f, "native binding has no stance: $label")
            check(
                Math.abs(actual - expected) < 1e-6f,
                "game/render stance mismatch: $label expected=$expected actual=$actual female=${player.isFemale()}",
            )
            for (i in native.indices) {
                check(
                    PZMath.convertMatrix(native[i], Matrix4f()).transpose() == poses[i],
                    "game stance changed native palette: $label/$i",
                )
            }
        }
    }

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
        val binding = NativeBinding(actor)
        val fixture =
            Path.of(System.getProperty("pz.test.project", "."))
                .resolve("JavaPatches/tests/fixtures/shopping-turning-grip.csv")
        var frames = 0
        val seen = HashSet<String>()
        val capturedRigs = HashSet<Boolean>()
        var clamped = 0
        var legacyFlex = 0.0
        var maxWrist = 0.0
        var maxRoll = 0.0
        var maxFlex = 0.0
        for (line in Files.readAllLines(fixture)) {
            if (line.isBlank() || line.startsWith("#")) continue
            val cells = line.split(",")
            val label = cells[0]
            check(cells.size == 3 + 12 * 16, "invalid native shopping fixture: $label")
            check(
                cells[1].toLong() > 0 && cells[2] in setOf("false", "true"),
                "invalid native capture identity: $label",
            )
            capturedRigs.add(cells[2].toBoolean())
            val phase = phases.single { label.startsWith("$it-") }
            seen.add(phase)
            val captured =
                Array(12) { i ->
                    Matrix4f().set(FloatArray(16) { j -> cells[3 + i * 16 + j].toFloat() })
                }
            check(captured.all { it.isFinite }, "nonfinite native shopping input: $label")
            val delta = captured[0]
            val cartBefore = captured[1]
            val deltaBefore = Matrix4f(delta)
            val original =
                Array(names.size) { i ->
                    if (i < 10) Matrix4f(captured[i + 2])
                    // Leg sentinels protect the full thigh branch, not an invented native gait.
                    else if (i < 16)
                        Matrix4f()
                            .translation(
                                if (i < 13) .06f else -.06f,
                                .5f - .12f * (i % 3),
                                .02f * i,
                            )
                    // The probe captures neither head nor legs; these only guard untouched motion.
                    else Matrix4f(captured[3]).translate(if (i == 16) .08f else .16f, 0f, 0f)
                }
            val nativeBefore = copy(original)
            binding.check(original, actor, cells[2].toBoolean(), label)
            for (femaleTarget in booleanArrayOf(false, true)) {
                val poses = copy(original)
                val cart = Matrix4f(cartBefore)
                val shift = CartShoppingStance.shift(original, actor, femaleTarget, delta, cart)
                check(shift.isFinite() && shift <= 1e-6f, "invalid shopping stance: $label")
                var preferred = 0f
                for (side in 0..1) {
                    val beforeTarget = Matrix4f()
                    check(
                        CartGrip.target(
                            "ShoppingCartModel",
                            side == 0,
                            femaleTarget,
                            delta,
                            cart,
                            beforeTarget,
                        ),
                        "shopping target refused before fitting: $label",
                    )
                    val upper = if (side == 0) 4 else 7
                    preferred = minOf(preferred, original[upper].m32() - beforeTarget.m32() - .15f)
                }
                if (shift > preferred + 1e-5f) clamped++
                check(
                    CartShoppingStance.apply(original, actor, femaleTarget, delta, cart, 1f),
                    "native shopping stance refused: $label",
                )
                check(
                    Math.abs(cart.m32() - cartBefore.m32() - shift) < 1e-6f &&
                        Matrix4f(cart).m32(cartBefore.m32()) == cartBefore,
                    "shopping stance changed cart scale/basis/X/Y: $label",
                )
                val fitted = Matrix4f(cart)
                check(
                    CartShoppingStance.apply(original, actor, femaleTarget, delta, cart, 1f) &&
                        cart.equals(fitted, 2e-6f),
                    "shopping stance accumulated when applied twice: $label",
                )
                cart.set(fitted)
                for (i in names.indices) check(
                    original[i] == nativeBefore[i],
                    "shopping stance edited native pose: $label/${names[i]}",
                )
                if (frames == 0) {
                    val missing = Array<Matrix4f?>(original.size) { Matrix4f(original[it]) }
                    missing[9] = null
                    val invalidCart = Matrix4f(cartBefore)
                    check(
                        CartShoppingStance.shift(missing, actor, femaleTarget, delta, invalidCart)
                            .isNaN() &&
                            !CartShoppingStance.apply(
                                missing,
                                actor,
                                femaleTarget,
                                delta,
                                invalidCart,
                                1f,
                            ) &&
                            invalidCart == cartBefore,
                        "missing native hand pose must refuse stance without moving the cart",
                    )
                }
                check(
                    CartGrip.grip(poses, actor, "ShoppingCartModel", femaleTarget, delta, cart),
                    "captured shopping grip refused: $label femaleTarget=$femaleTarget",
                )
                for (i in intArrayOf(0, 1, 10, 11, 12, 13, 14, 15, 16, 17)) check(
                    poses[i] == original[i],
                    "shopping grip changed native torso/head/leg: $label/${names[i]}",
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
                            "ShoppingCartModel",
                            side == 0,
                            femaleTarget,
                            delta,
                            cart,
                            target,
                        ),
                        "shopping target refused: $label",
                    )
                    check(
                        poses[hand].equals(target, 3e-5f),
                        "shopping wrist missed fitted cart: $label",
                    )
                    val nativeLength =
                        at(original, upper).distance(at(original, upper + 1)) +
                            at(original, upper + 1).distance(at(original, hand))
                    val targetDistance =
                        at(original, upper).distance(target.getTranslation(Vector3f()))
                    check(
                        nativeLength - targetDistance >= .005f - 2e-6f,
                        "shopping stance exhausted native arm reach reserve: $label side=$side",
                    )
                    val station = Vector3f()
                    check(
                        CartGrip.handle("ShoppingCartModel", side == 0, station),
                        "missing shopping handle",
                    )
                    cart.transformPosition(station)
                    val grasp = CartGrip.grasp(femaleTarget, "ShoppingCartModel")
                    val palm =
                        poses[hand].transformPosition(Vector3f(grasp.palmX, 0f, grasp.palmDepth))
                    check(
                        palm.distance(station) < 3e-5f,
                        "shopping palm missed actual handle: $label",
                    )
                    val measured = arm(poses, upper)
                    maxWrist = Math.max(maxWrist, measured.wrist)
                    maxRoll = Math.max(maxRoll, measured.roll)
                    maxFlex = Math.max(maxFlex, measured.flex)
                    // Pure reachable stance replay, with the entire native torso unchanged:
                    // male/female maxima 38.26/0.035/115.51 degrees, including asymmetric Sprint.
                    check(
                        measured.wrist <= 40 && measured.roll <= 1 && measured.flex <= 118,
                        "unnatural shopping arm: $label femaleTarget=$femaleTarget side=$side $measured",
                    )
                    if (!femaleTarget && cells[2] == "false") {
                        val old = copy(original)
                        val oldTarget = Matrix4f()
                        check(
                            CartGrip.target(
                                "ShoppingCartModel",
                                side == 0,
                                false,
                                delta,
                                cartBefore,
                                oldTarget,
                            ) && CartGrip.reach(old, actor, names[hand], oldTarget, null, false),
                            "legacy shopping fixture unexpectedly unreachable: $label",
                        )
                        legacyFlex = Math.max(legacyFlex, arm(old, upper).flex)
                    }
                }
                val nearHeld = copy(original)
                val nearCart = Matrix4f(cart)
                check(
                    CartGrip.transitionGrip(
                        nearHeld,
                        actor,
                        femaleTarget,
                        delta,
                        nearCart,
                        .99999f,
                        1f,
                        null,
                        "ShoppingCartModel",
                    ),
                    "shopping transition lost near-held reach: $label",
                )
                for (i in names.indices) check(
                    nearHeld[i].equals(poses[i], .0001f),
                    "shopping transition snapped at full held weight: $label/${names[i]}",
                )
                val zero = copy(original)
                val zeroCart = Matrix4f(cart)
                check(
                    CartGrip.transitionGrip(
                        zero,
                        actor,
                        femaleTarget,
                        delta,
                        zeroCart,
                        0f,
                        0f,
                        null,
                        "ShoppingCartModel",
                    ),
                    "zero shopping transition refused: $label",
                )
                for (i in names.indices) check(
                    zero[i].equals(original[i], 3e-6f),
                    "zero shopping transition changed pose: $label/${names[i]}",
                )
                check(
                    delta == deltaBefore &&
                        cart == fitted &&
                        nearCart == fitted &&
                        zeroCart == fitted,
                    "pure shopping IK changed fitted cart or delta: $label",
                )
            }
            frames++
        }
        check(
            frames == 20 && seen == phases && capturedRigs == setOf(false, true),
            "missing captured shopping turn/fast-gait/rig coverage",
        )
        check(clamped > 0, "native fixtures no longer exercise the other arm's reach limit")
        check(legacyFlex >= 158, "native fixtures no longer reproduce the folded-arm defect")
        println(
            "CART_SHOPPING_GRIP_PASS (20 native turn/fast-gait inputs, unchanged torso, arm lengths, " +
                "reachable cart, native binding, transition continuity; max wrist=$maxWrist roll=$maxRoll " +
                "flex=$maxFlex legacyFlex=$legacyFlex)",
        )
    }
}
