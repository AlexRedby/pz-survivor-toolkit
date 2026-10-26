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
        close(motion.phase, .48, "entry anchors anatomical left swing")
        motion.update(1.0, 1.0 / 60, clock, .02, 2.0 / 3)
        close(motion.phase, .48 + 1.0 / 60 / .88, "wrap honors cadence cap")
        val beforeReplacement = motion.phase
        motion.update(1.0, 1.0 / 60, Any(), .75, 2.0 / 3)
        close(motion.phase, beforeReplacement, "track replacement cannot jump feet")
        repeat(60) { motion.update(1.0, 1.0 / 60, clock, it / 30.0, 2.0 / 3) }
        check(motion.turn > .99 && motion.walk > .99, "entry reaches walking turn")
        val paused = motion.phase
        repeat(10) { motion.update(1.0, 1.0 / 60, clock, 59 / 30.0, 2.0 / 3) }
        close(motion.phase, paused, "native pause freezes cosmetic feet")
        val before = motion.turn
        motion.update(0.0, 1.0 / 60, clock, 2.0, 2.0 / 3)
        check(motion.turn in .8..before, "turn release must fade")
        repeat(60) { motion.update(0.0, 1.0 / 60, clock, 2.0 + it / 30.0, 2.0 / 3) }
        close(motion.turn, 0.0, "turn release settles")
        check(motion.walk > .99, "straight walking survives turn release")
        repeat(120) { motion.update(-1.0, 1.0 / 60, clock, 4.0 + it / 30.0, 2.0 / 3) }
        check(motion.turn < -.99, "direction reversal")
        val beforeStop = motion.walk
        motion.update(0.0, 1.0 / 60, null, Double.NaN, Double.NaN, false)
        check(motion.walk in .8..beforeStop, "stop/reverse releases walk smoothly")
        repeat(90) { motion.update(0.0, 1.0 / 60, null, Double.NaN, Double.NaN, false) }
        close(motion.walk, 0.0, "walk release settles")
        close(motion.turn, 0.0, "stop releases turn")
        motion.update(0.0, 1.0 / 60, clock, .25, 2.0 / 3)
        close(motion.phase, .75, "new walk reanchors after full release")

        val fast = CartShoppingTurn.Blend()
        val token = Any()
        for (i in 0..120) fast.update(0.0, 1.0 / 60, token, i * .06, 2.0 / 3)
        close(
            fast.phase,
            (.5 + 2 / .88) % 1.0,
            "compensated strafe cannot accelerate cosmetic cadence",
        )
        val slow = CartShoppingTurn.Blend()
        for (i in 0..60) slow.update(0.0, 1.0 / 60, token, i * .005, 2.0 / 3)
        close(slow.phase, .8, "slower native cycle limits cosmetic clock")
        val unchanged = slow.phase
        slow.update(0.0, Double.NaN, token, .4, 2.0 / 3)
        close(slow.phase, unchanged, "invalid wall time cannot advance phase")
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
        val straight = CartShoppingTurn.View(.4f, 0f, 1f)
        CartShoppingTurn.capture(slot, source, straight)
        check(CartShoppingTurn.view(slot, owner) == straight, "straight walking owns a snapshot")
        CartShoppingTurn.capture(slot, source, straight.copy(walk = 0f))
        check(CartShoppingTurn.view(slot, owner) == null, "released walk cannot capture")
        CartShoppingTurn.capture(slot, source, straight.copy(walk = Float.NaN))
        check(CartShoppingTurn.view(slot, owner) == null, "invalid walk cannot capture")
        CartShoppingTurn.capture(slot, source, straight)
        CartShoppingTurn.release(slot)
        check(CartShoppingTurn.view(slot, owner) == null, "released slot")
    }

    /** A complete foot cycle keeps the cart fixed while preserving the arms and hand contacts. */
    private fun stableBar(actor: SkinningData, clip: AnimationClip, baseline: Array<Matrix4f?>) {
        for (female in listOf(false, true)) {
            var first: Matrix4f? = null
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
        }
    }

    /** The production composition uses the same anatomical phase at every turn strength. */
    private fun sharedWalk(
        actor: SkinningData,
        baseline: Array<Matrix4f?>,
        walk: AnimationClip,
        turn: AnimationClip,
    ) {
        for (phase in listOf(0f, .13f, .49f, .75f)) {
            val native = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                CartShoppingTurn.apply(
                    native,
                    actor,
                    walk,
                    CartShoppingTurn.View(phase, 1f),
                ),
                "native walk phase",
            )
            for (i in native.indices) {
                val bone = actor.getBoneAt(i)
                val parent = bone.parent ?: continue
                if (!bone.name.endsWith("Nub")) continue
                close(
                    native[i]
                        .getTranslation(Vector3f())
                        .distance(native[parent.index].getTranslation(Vector3f()))
                        .toDouble(),
                    baseline[i]!!
                        .getTranslation(Vector3f())
                        .distance(baseline[parent.index]!!.getTranslation(Vector3f()))
                        .toDouble(),
                    "native zero-offset marker keeps actor length ${bone.name}",
                )
            }
            val straight = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                CartShoppingTurn.apply(
                    straight,
                    actor,
                    walk,
                    null,
                    CartShoppingTurn.View(phase, 0f),
                ),
                "straight walk composition",
            )
            check(
                straight.indices.all { matrixError(straight[it], native[it]) < 2e-5 },
                "straight walk anatomical phase",
            )
            for (weight in listOf(.25f, .5f, 1f)) {
                val expected = Array(native.size) { Matrix4f(native[it]) }
                check(
                    CartShoppingTurn.apply(
                        expected,
                        actor,
                        turn,
                        CartShoppingTurn.View(phase, weight),
                    ),
                    "expected turn",
                )
                val output = Array(baseline.size) { Matrix4f(baseline[it]) }
                check(
                    CartShoppingTurn.apply(
                        output,
                        actor,
                        walk,
                        turn,
                        CartShoppingTurn.View(phase, weight),
                    ),
                    "shared phase turn composition",
                )
                check(
                    output.indices.all { matrixError(output[it], expected[it]) < 2e-5 },
                    "turn and straight use one phase",
                )
            }
            val fallback = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                CartShoppingTurn.apply(
                    fallback,
                    actor,
                    walk,
                    null,
                    CartShoppingTurn.View(phase, 1f),
                ),
                "missing turn retains straight walk",
            )
            check(
                fallback.indices.all { matrixError(fallback[it], native[it]) < 2e-5 },
                "valid native fallback",
            )
            val untouched = Array(baseline.size) { Matrix4f(baseline[it]) }
            check(
                !CartShoppingTurn.apply(
                    untouched,
                    actor,
                    null,
                    turn,
                    CartShoppingTurn.View(phase, 1f),
                ),
                "missing native walk refuses composition",
            )
            check(
                untouched.indices.all { untouched[it] == baseline[it] },
                "failed composition is transactional",
            )
            for (name in listOf("Dummy01", "Bip01", "Translation_Data")) {
                val i = actor.getBone(name).index
                check(
                    matrixError(straight[i], baseline[i]!!) < 2e-5,
                    "cosmetic walk preserves root $name",
                )
            }
        }
    }

    private fun support(
        actor: SkinningData,
        idle: AnimationClip,
        walk: AnimationClip,
        left: AnimationClip,
        right: AnimationClip,
    ) {
        val baseline = reference(actor, idle)
        val root = CartShoppingFeet.Root(10821.5, 10130.5, 2.3)
        val point = Vector3f(.1f, .06f, -.2f)
        check(
            root.local(root.world(point)).distance(point) < .001f,
            "support world/local transform",
        )
        val contactDump = System.getProperty("pz.test.shoppingFeetDump")
        val dump = StringBuilder("[")
        var changed = 0
        var fullSupport = 0
        var supportDrift = 0.0
        var nativeDrift = 0.0
        var jitterDrift = 0.0
        var jitterNative = 0.0
        var jitterDeclined = 0
        var maxAnkleCorrection = 0f
        var maxKneeCorrection = 0f
        var nativeSwingSamples = 0
        for ((turn, clip, jitter) in
            listOf(
                Triple(1f, left, false),
                Triple(-1f, right, false),
                Triple(.5f, left, false),
                Triple(-.5f, right, false),
                Triple(1f, left, true),
            )) {
            val state = CartShoppingFeet.State()
            var previous: Array<Vector3f>? = null
            var previousNative: Array<Vector3f>? = null
            val dt = 1.0 / 60
            var x = 0.0
            var y = 0.0
            var angle = 0.0
            repeat(240) { frame ->
                val phase = ((frame * dt / .88) % 1).toFloat()
                // Native render heading for this turn: 1.05 model units/s and 2.48rad/s.
                angle += turn * 2.48 * dt
                x +=
                    (-kotlin.math.cos(angle) * .77 * turn + kotlin.math.sin(angle) * .78) * 1.5 * dt
                y +=
                    (-kotlin.math.sin(angle) * .77 * turn - kotlin.math.cos(angle) * .78) * 1.5 * dt
                // A remote facing correction may arrive in short bursts while position keeps
                // moving.
                val drawAngle =
                    if (jitter) kotlin.math.floor(frame * dt / .2) * .2 * turn * 2.48 else angle
                val world = CartShoppingFeet.Root(x, y, drawAngle)
                val view = CartShoppingTurn.View(phase, turn)
                val poses = Array<Matrix4f?>(baseline.size) { Matrix4f(baseline[it]) }
                check(CartShoppingTurn.apply(poses, actor, walk, clip, view), "support source")
                val before = poses.map { Matrix4f(it) }
                val feet = state.update(world, view, actor, poses, frame * dt)
                if (jitter && frame > 60 && feet == null) jitterDeclined++
                CartShoppingFeet.apply(poses, actor, feet)
                val points =
                    Array(2) { i ->
                        world.world(
                            poses[actor.getBone("Bip01_${if(i==0)"L" else "R"}_Toe0").index]!!
                                .getTranslation(Vector3f()),
                        )
                    }
                val nativePoints =
                    Array(2) { i ->
                        world.world(
                            before[actor.getBone("Bip01_${if(i==0)"L" else "R"}_Toe0").index]
                                .getTranslation(Vector3f()),
                        )
                    }
                for ((i, side) in listOf("L", "R").withIndex()) {
                    val p = (phase + (if (i == 1) .5f else 0f)) % 1f
                    if (
                        p in 0.55f..0.95f &&
                            previous != null &&
                            frame > 60 &&
                            kotlin.math.abs(turn) == 1f
                    ) {
                        fun flat(a: Vector3f, b: Vector3f) =
                            kotlin.math.hypot((a.x - b.x).toDouble(), (a.z - b.z).toDouble())
                        if (jitter) {
                            jitterDrift += flat(points[i], previous!![i])
                            jitterNative += flat(nativePoints[i], previousNative!![i])
                        } else {
                            supportDrift += flat(points[i], previous!![i])
                            nativeDrift += flat(nativePoints[i], previousNative!![i])
                        }
                        fullSupport++
                    }
                    val foot = actor.getBone("Bip01_${side}_Foot").index
                    if (matrixError(poses[foot]!!, before[foot]) > 1e-4) changed++
                    val toe = actor.getBone("Bip01_${side}_Toe0").index
                    val knee = actor.getBone("Bip01_${side}_Calf").index
                    val delta =
                        poses[foot]!!
                            .getTranslation(Vector3f())
                            .sub(before[foot].getTranslation(Vector3f()))
                    val ankleCorrection = kotlin.math.hypot(delta.x, delta.z)
                    val kneeCorrection =
                        poses[knee]!!
                            .getTranslation(Vector3f())
                            .distance(before[knee].getTranslation(Vector3f()))
                    maxAnkleCorrection = maxOf(maxAnkleCorrection, ankleCorrection)
                    maxKneeCorrection = maxOf(maxKneeCorrection, kneeCorrection)
                    check(ankleCorrection <= .025002f, "bounded additive ankle correction")
                    check(kneeCorrection <= .025002f, "bounded native knee displacement")
                    close(delta.y.toDouble(), 0.0, "native ankle height")
                    close(
                        poses[toe]!!.m31().toDouble(),
                        before[toe].m31().toDouble(),
                        "native toe height/roll",
                    )
                    for (index in listOf(foot, toe)) {
                        check(
                            matrixError(
                                Matrix4f(poses[index]).setTranslation(0f, 0f, 0f),
                                Matrix4f(before[index]).setTranslation(0f, 0f, 0f),
                            ) < 2e-5,
                            "native foot/toe rotation",
                        )
                    }
                    val nativeToe = Matrix4f(before[foot]).invert().mul(before[toe])
                    val correctedToe = Matrix4f(poses[foot]).invert().mul(poses[toe])
                    check(
                        matrixError(nativeToe, correctedToe) < 2e-5,
                        "native toe articulation relative to ankle",
                    )
                    if (p in .20f..0.52f) {
                        nativeSwingSamples++
                        for (part in listOf("Thigh", "Calf", "Foot", "Toe0")) {
                            val index = actor.getBone("Bip01_${side}_$part").index
                            check(
                                matrixError(poses[index]!!, before[index]) < 2e-5,
                                "source swing retained after stance-offset release: $side $p $part",
                            )
                        }
                    }
                    for ((a, b) in listOf("Thigh" to "Calf", "Calf" to "Foot")) {
                        val ai = actor.getBone("Bip01_${side}_$a").index
                        val bi = actor.getBone("Bip01_${side}_$b").index
                        close(
                            poses[ai]!!
                                .getTranslation(Vector3f())
                                .distance(poses[bi]!!.getTranslation(Vector3f()))
                                .toDouble(),
                            before[ai]
                                .getTranslation(Vector3f())
                                .distance(before[bi].getTranslation(Vector3f()))
                                .toDouble(),
                            "support lengths",
                        )
                    }
                    for (name in listOf("Pelvis", "Spine", "Spine1", "Head", "L_Hand", "R_Hand")) {
                        val index = actor.getBone("Bip01_$name").index
                        check(poses[index] == before[index], "foot support leaves torso/grip $name")
                    }
                }
                previous = points
                previousNative = nativePoints
                if (contactDump != null) {
                    if (dump.length > 1) dump.append(',')
                    dump.append("{\"time\":${(if(turn>0)0 else 4)+frame*dt},\"bones\":{")
                    for (i in poses.indices) {
                        if (i > 0) dump.append(',')
                        dump.append('"').append(actor.getBoneAt(i).name).append("\":")
                        dump.append(poses[i]!!.get(FloatArray(16)).joinToString(",", "[", "]"))
                    }
                    dump.append("}}")
                }
            }
        }
        println(
            "SHOPPING_SUPPORT_DIAGNOSTIC changed=$changed measured=$fullSupport corrected=$supportDrift native=$nativeDrift jitter=$jitterDrift jitterNative=$jitterNative maxAnkle=$maxAnkleCorrection maxKnee=$maxKneeCorrection",
        )
        check(changed > 100, "support correction actually applied")
        check(nativeSwingSamples > 500, "native swing trajectory measured")
        if (contactDump != null)
            java.nio.file.Files.writeString(Path.of(contactDump), dump.append(']').toString())
        check(
            supportDrift < nativeDrift * .995,
            "small additive contacts modestly reduce world sliding: $supportDrift / $nativeDrift",
        )
        check(
            jitterDrift <= jitterNative * 1.01,
            "remote heading bursts cannot amplify foot sliding: $jitterDrift / $jitterNative",
        )
        check(jitterDeclined > 150, "bursty remote roots retain native gait until stable")
        // Entering a turn midway through a swing starts at the already rendered pose.
        for (phase in listOf(.25f, .5f)) {
            val entry = CartShoppingFeet.State()
            val first = entry.update(root, CartShoppingTurn.View(phase, 1f), actor, baseline, 0.0)
            check(first == null, "support entry has no first-frame pop at $phase")
        }
        val release = CartShoppingFeet.State()
        var last: CartShoppingFeet.Frame? = null
        var lastView = CartShoppingTurn.View(.2f, 1f)
        repeat(30) { i ->
            lastView = CartShoppingTurn.View(.2f + i / 100f, 1f)
            last = release.update(root, lastView, actor, baseline, i / 60.0)
        }
        val fading = release.update(root, lastView.copy(walk = .5f), actor, baseline, .51)
        check(
            last != null && fading != null && fading.influence < last!!.influence,
            "paused root/phase cannot reuse a stale full-weight contact during release",
        )
        check(
            release.update(root, lastView.copy(walk = 0f), actor, baseline, .52) == null,
            "fully released contact clears",
        )
        check(
            release.update(root, lastView.copy(phase = Float.NaN), actor, baseline, .53) == null,
            "invalid phase clears contact",
        )
        // Reverse, inactive and discontinuous remote roots cannot retain old stance anchors.
        for (inactive in listOf(lastView.copy(walk = -1f), lastView.copy(turn = 0f))) {
            check(
                release.update(root, inactive, actor, baseline, .54) == null,
                "reverse/inactive gait clears contacts",
            )
            check(
                release.update(root, lastView, actor, baseline, .55) == null,
                "resuming starts with native gait",
            )
        }
        for (jump in listOf(root.copy(x = root.x + 2), root.copy(angle = root.angle + .5))) {
            val reset = CartShoppingFeet.State()
            reset.update(root, lastView, actor, baseline, 0.0)
            check(
                reset.update(jump, lastView.copy(phase = .6f), actor, baseline, .02) == null,
                "teleport/yaw snapshot correction declines support",
            )
            check(
                reset.update(jump, lastView.copy(phase = .61f), actor, baseline, .2) == null,
                "discontinuous root keeps native gait while settling",
            )
        }
        // An impossible foot goal must not leave a half-solved leg or move the body.
        val unchanged = Array<Matrix4f?>(baseline.size) { Matrix4f(baseline[it]) }
        val far =
            Matrix4f(unchanged[actor.getBone("Bip01_L_Foot").index]).translateLocal(10f, 0f, 0f)
        check(!CartGrip.fitFoot(unchanged, actor, "L", far), "unreachable foot refused")
        check(
            unchanged.indices.all { unchanged[it] == baseline[it] },
            "unreachable foot transaction",
        )
        val straight =
            CartShoppingFeet.State().update(root, CartShoppingTurn.View(.7f, 0f), actor, unchanged)
        check(straight == null, "straight gait remains unchanged")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        controller()
        slots()
        val root = Path.of(System.getProperty("pz.test.project"))
        val folder = root.resolve("PZSurvivorToolkit/42/media/anims_X/Bob")
        val (actor, idle) = read(folder.resolve("Toolkit_CartPivot_Idle.x"))
        val baseline = reference(actor, idle)
        val (_, walk) = read(folder.resolve("Toolkit_ShoppingWalk.x"))
        val (_, nativeWalk) = read(folder.resolve("Toolkit_CartPivot_Walk.x"))
        support(
            actor,
            idle,
            walk,
            read(folder.resolve("Toolkit_ShoppingTurn_Left.x")).second,
            read(folder.resolve("Toolkit_ShoppingTurn_Right.x")).second,
        )
        for (side in listOf("Left", "Right")) {
            val (targetActor, clip) = read(folder.resolve("Toolkit_ShoppingTurn_$side.x"))
            check(actor.boneIndices == targetActor.boneIndices, "bone mapping")
            val expected = reference(actor, clip)
            stableBar(actor, clip, baseline)
            sharedWalk(actor, baseline, walk, clip)
            if (side == "Left") sharedWalk(actor, baseline, nativeWalk, clip)
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
                "native import/FK matches source: " +
                    full.indices
                        .sortedByDescending { matrixError(full[it], expected[it]!!) }
                        .take(3)
                        .joinToString {
                            "${actor.getBoneAt(it).name}=${matrixError(full[it], expected[it]!!)}"
                        },
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
            "CART_SHOPPING_TURN_PASS native loops, shared walking phase, cadence cap/pause/release, transactional fallback, slot ownership",
        )
    }
}
