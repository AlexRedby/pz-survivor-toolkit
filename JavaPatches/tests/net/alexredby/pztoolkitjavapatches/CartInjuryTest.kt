package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Method
import java.nio.file.Path
import java.util.HashMap
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker
import zombie.core.skinnedmodel.advancedanimation.AnimLayer
import zombie.core.skinnedmodel.advancedanimation.AnimNode
import zombie.core.skinnedmodel.advancedanimation.AnimState
import zombie.core.skinnedmodel.advancedanimation.AnimationSet
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.BoneAxis
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.model.SkinningData
import zombie.inventory.InventoryItem
import zombie.iso.Vector2

/** Uses the installed native blend topology and the actual woven blend-field boundary. */
object CartInjuryTest {
    private lateinit var unsafe: Unsafe
    private lateinit var applyField: Method
    private val nativeNodes = HashMap<String, AnimNode>()
    private val cartNodes = HashMap<String, AnimNode>()
    private val clips = HashMap<String, AnimationClip>()

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var animator: AdvancedAnimator? = null
        @JvmField var cart: InventoryItem? = null
        @JvmField var run = false
        @JvmField var sprint = false
        @JvmField var enabled = false
        @JvmField var remote = false
        @JvmField var injury = 0f
        @JvmField var speed = 0f
        @JvmField var pace = 0f

        override fun getAdvancedAnimator(): AdvancedAnimator? = animator

        override fun getPrimaryHandItem(): InventoryItem? = cart

        override fun isRunning(): Boolean = run

        override fun isSprinting(): Boolean = sprint

        override fun isLocalPlayer(): Boolean = !remote

        override fun getVariableBoolean(name: String?): Boolean =
            enabled && name == "ToolkitCartMotion"

        override fun getVariableFloat(name: String?, fallback: Float): Float =
            when (name) {
                "WalkInjury" -> injury
                "WalkSpeed" -> speed
                else -> fallback
            }

        override fun setVariable(name: String?, value: Float): IAnimationVariableSlot? {
            if (name == "ToolkitCartLegPace") pace = value
            return null
        }
    }

    private class Cart : InventoryItem(null, null, null, null as String?) {
        @JvmField var type: String? = null

        override fun getFullType(): String? = type
    }

    private data class Fixture(
        val player: Player,
        val layer: AnimLayer,
        val live: LiveAnimNode,
        val source: AnimNode,
    )

    private fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(actual: Double, expected: Double, message: String) {
        check(
            actual.isFinite() && Math.abs(actual - expected) < .00003,
            "$message: $actual != $expected",
        )
    }

    private fun close(actual: Float, expected: Float, message: String) =
        close(actual.toDouble(), expected.toDouble(), message)

    private fun close(actual: Float, expected: Double, message: String) =
        close(actual.toDouble(), expected, message)

    private fun read(path: Path): AnimNode {
        val node =
            AnimNode.Parse(path.toString())
                ?: throw AssertionError("Cannot parse native animation field: $path")
        val media =
            Path.of(System.getProperty("pz.test.project"))
                .resolve("PZSurvivorToolkit/42/media/anims_X/Bob")
        for (blend in node.blends2d) clips.computeIfAbsent(blend.animName) { name ->
            val folder = if (name.startsWith("Toolkit_")) media else Path.of("media/anims_X/Bob")
            importClip(folder.resolve("$name.x"))
        }
        return node
    }

    @Suppress("UNCHECKED_CAST")
    private fun importClip(path: Path): AnimationClip {
        check(java.nio.file.Files.isRegularFile(path), "missing native animation source: $path")
        val params = zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams.create()
        params.scene =
            jassimp.Jassimp.importFile(
                path.toString(),
                java.util.EnumSet.of(
                    jassimp.AiPostProcessSteps.MAKE_LEFT_HANDED,
                    jassimp.AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS,
                ),
            )
        params.mode = zombie.core.skinnedmodel.model.jassimp.JAssImpImporter.LoadMode.AnimationOnly
        params.animBonesScaleModifier = 1f
        params.animBonesRotateModifier = null
        val skeleton =
            zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton.process(
                zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams.create(
                    params,
                    params.scene.getMeshes()[0],
                ),
            )
        val field = skeleton.javaClass.getDeclaredField("clips")
        field.isAccessible = true
        val imported = field.get(skeleton) as Map<String, AnimationClip>
        check(imported.size == 1, "native source must contain one animation: $path")
        return imported.values.single()
    }

    private fun fixture(type: String, gait: String, injury: Float, remote: Boolean): Fixture {
        val player = allocate(Player::class.java)
        player.enabled = true
        player.remote = remote
        player.injury = injury
        player.speed = if (gait == "Walk") .62f else if (gait == "Run") .55f else .78f
        player.run = gait == "Run"
        player.sprint = gait == "Sprint"
        val item = allocate(Cart::class.java)
        item.type = type
        player.cart = item
        val animator = AdvancedAnimator()
        player.animator = animator
        animator.animSet = AnimationSet()
        for (name in listOf("movement", "run", "sprint")) {
            val state = AnimState()
            state.name = name
            state.nodes.add(nativeNodes.getValue(name))
            for (node in cartNodes.values) {
                if (
                    name == "movement" && node.name.endsWith("Walk") ||
                        name == "run" && node.name.endsWith("Run") ||
                        name == "sprint" && node.name.endsWith("Sprint")
                )
                    state.nodes.add(node)
            }
            animator.animSet.states[name] = state
        }
        val source =
            CartLegPace.pivotNode(player)
                ?: throw AssertionError("cart gait selector found no node")
        val layer = AnimLayer.alloc(player, animator)
        val root = AdvancedAnimator::class.java.getDeclaredField("rootLayer")
        root.isAccessible = true
        root.set(animator, layer)
        val live = LiveAnimNode.alloc(layer, source)
        live.setActive(true)
        layer.getLiveAnimNodes().add(live)
        for (blend in source.blends2d) {
            val track = AnimationTrack.alloc()
            track.startClip(clips.getValue(blend.animName), true, 0f)
            track.advance(.27f)
            live.addMainTrack(track)
        }
        return Fixture(player, layer, live, source)
    }

    private fun picked(node: AnimNode, x: Float, y: Float): HashMap<String, Float> {
        val picked = node.blend2dPicker.Pick(x, y, Anim2DBlendPicker.PickResults())
        val result = HashMap<String, Float>()
        for (i in 0 until picked.numNodes) {
            val entry = if (i == 0) picked.node1 else if (i == 1) picked.node2 else picked.node3
            val weight = if (i == 0) picked.scale1 else if (i == 1) picked.scale2 else picked.scale3
            if (weight >= .0001f) result.merge(entry.animName, Math.min(1f, weight), Float::plus)
        }
        return result
    }

    private fun expected(f: Fixture, x: Float, y: Float): Map<String, Float> {
        val result = picked(f.source, x, y)
        val alpha = CartInjury.amount(f.player.injury)
        val forward =
            if (f.player.sprint) "Toolkit_CartPivot_Sprint"
            else if (f.player.run) "Toolkit_CartPivot_Run" else "Toolkit_CartPivot_Walk"
        val mass = result.getOrDefault(forward, 0f) * alpha
        result.merge(forward, -mass, Float::plus)
        val state = if (f.player.sprint) "sprint" else if (f.player.run) "run" else "movement"
        for ((name, weight) in
            picked(nativeNodes.getValue(state), f.player.injury, f.player.speed)) result.merge(
            name,
            mass * weight,
            Float::plus,
        )
        return result
    }

    private fun apply(f: Fixture, x: Float, y: Float) {
        applyField.invoke(f.layer, f.live, .4f, x, y)
    }

    private fun weights(f: Fixture): Map<String, Float> {
        val result = HashMap<String, Float>()
        for (track in f.live.getMainAnimationTracks()) result.merge(
            track.getName(),
            track.getBlendFieldWeight(),
            Float::plus,
        )
        return result
    }

    private fun speed(f: Fixture, cadence: Boolean): Float {
        var x = 0.0
        var y = 0.0
        for (track in f.live.getMainAnimationTracks()) {
            val root =
                track.getClip().getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2())
            var weight = track.getBlendFieldWeight() / track.getClip().getDuration()
            if (cadence) weight *= track.getSpeedDelta()
            x += weight * root.x
            y += weight * root.y
        }
        return Math.hypot(x, y).toFloat()
    }

    private fun rootSpeed(weights: Map<String, Float>): Float {
        var x = 0.0
        var y = 0.0
        for ((name, weight) in weights) {
            val clip = clips.getValue(name)
            val root = clip.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2())
            x += weight * root.x / clip.getDuration()
            y += weight * root.y / clip.getDuration()
        }
        return Math.hypot(x, y).toFloat()
    }

    private fun expectedTarget(f: Fixture, x: Float, y: Float): Float {
        val state = if (f.player.sprint) "sprint" else if (f.player.run) "run" else "movement"
        val native = nativeNodes.getValue(state)
        val nativeRoot = rootSpeed(picked(native, f.player.injury, f.player.speed))
        val amount = Math.hypot(x.toDouble(), y.toDouble()).toFloat()
        val base = native.getSpeedScale(f.player)
        if (f.player.run || f.player.sprint || y >= 0) return base * nativeRoot * amount
        // Reverse remains a separately authored maneuver, with its existing slowdown envelope.
        val reference =
            if (f.player.cart!!.getFullType() != "SaucedCarts.ShoppingCart") "Bob_WalkBwdNoAim1Hand"
            else "Bob_Walk"
        val healthyRadius = Math.max(0f, Math.min(1f, f.player.speed))
        val radius = CartInjury.walkMagnitude(f.player, healthyRadius)
        val effort = if (radius > 1e-6f) amount / radius else 0f
        val healthy = rootSpeed(mapOf(reference to 1f)) * healthyRadius * effort
        val capped = Math.min(nativeRoot, healthyRadius * rootSpeed(mapOf(reference to 1f)))
        val alpha = CartInjury.amount(f.player.injury)
        return base * ((1 - alpha) * healthy + alpha * capped * effort)
    }

    private fun steadyParity() {
        for (type in
            listOf(
                "SaucedCarts.ShoppingCart",
                "SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal",
            )) for (gait in listOf("Walk", "Run", "Sprint")) for (injury in
            floatArrayOf(-.9f, -.5f, -.15f, -.075f, 0f, .075f, .15f, .5f, .9f)) {
            val f = fixture(type, gait, injury, false)
            val state = if (gait == "Walk") "movement" else gait.lowercase()
            val native = nativeNodes.getValue(state)
            for (scalar in floatArrayOf(-.1f, 0f, .05f, .2f, .4f, .5f, .8f, 1f)) {
                f.player.speed = scalar
                // Native defaultWalk's origin is Bob_WalkSlow, not a stationary clip. Directional
                // cart intent stays full length; native field weights alone determine speed.
                val expected =
                    native.getSpeedScale(f.player) * rootSpeed(picked(native, injury, scalar))
                apply(f, 0f, 1f)
                val context = "$type/$gait/$injury/$scalar"
                close(
                    CartLegPace.targetSpeed(f.player, 0f, 1f),
                    expected,
                    "native gait oracle $context",
                )
                val cadence = CartLegPace.scale(f.player, 0f, 1f)
                close(
                    speed(f, false) * cadence,
                    expected,
                    "steady native/cart extracted-root parity $context",
                )
                CartLegPace.applySpeed(f.player, expected, 0f, 1f)
                close(
                    speed(f, true),
                    expected,
                    "requested native budget changed during cadence application $context",
                )
                close(
                    CartLegPace.targetSpeed(f.player, 0f, 0f),
                    0f,
                    "zero intent must not inherit the native slow clip $context",
                )
            }
        }
        val f = fixture("SaucedCarts.ShoppingCart", "Walk", 0f, false)
        val native = nativeNodes.getValue("movement")
        val source = clips.remove("Bob_WalkSlow")!!
        try {
            f.player.speed = 0f
            check(
                CartLegPace.targetSpeed(f.player, 0f, 1f).isNaN(),
                "missing native root source claimed a calibrated target",
            )
            close(
                CartLegPace.scale(f.player, 0f, 1f),
                1.04,
                "missing native root source poisoned fallback cadence",
            )
            close(
                CartLegPace.targetSpeed(f.player, 0f, 0f),
                0f,
                "missing native root source prevented a stop",
            )
        } finally {
            clips["Bob_WalkSlow"] = source
        }
        for ((injury, scalar, pace) in
            listOf(
                Triple(Float.NaN, .8f, 1.04f),
                Triple(0f, Float.NaN, 1.04f),
                Triple(0f, .8f, Float.NaN),
                Triple(0f, .8f, -1f),
            )) check(
            CartLegPace.nativeSpeed(native, injury, scalar, pace, clips::get).isNaN(),
            "invalid native field source acquired a speed",
        )
        check(
            CartLegPace.nativeSpeed(null, 0f, .8f, 1.04f, clips::get).isNaN(),
            "absent native field acquired a speed",
        )
        check(
            CartLegPace.nativeSpeed(native, 0f, .8f, 1.04f, null).isNaN(),
            "absent clip provider acquired a speed",
        )
        val state = f.player.animator!!.animSet.states.getValue("movement")
        state.nodes.remove(native)
        try {
            check(
                CartLegPace.targetSpeed(f.player, 0f, 1f).isNaN(),
                "missing native gait claimed a calibrated target",
            )
        } finally {
            state.nodes.add(native)
        }
    }

    private fun directions() {
        for (type in
            listOf(
                "SaucedCarts.ShoppingCart",
                "SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal",
            )) for (gait in listOf("Walk", "Run", "Sprint")) for (injury in
            floatArrayOf(-.9f, -.5f, -.075f, -.00001f, 0f, .00001f, .075f, .15f, .5f, .9f)) {
            val f = fixture(type, gait, injury, false)
            check(
                f.source.name == CartLegPace.pivotName(type, f.player.run, f.player.sprint),
                "wrong cart/gait selector",
            )
            for (degree in -180..180 step 30) {
                val radius =
                    if (gait == "Walk" && degree !in -90..90)
                        CartInjury.walkMagnitude(f.player, f.player.speed)
                    else 1f
                val x = radius * Math.sin(Math.toRadians(degree.toDouble())).toFloat()
                val y = radius * Math.cos(Math.toRadians(degree.toDouble())).toFloat()
                val expected = expected(f, x, y)
                apply(f, x, y)
                var sum = 0.0
                for (track in f.live.getMainAnimationTracks()) {
                    close(
                        track.getBlendFieldWeight(),
                        expected.getOrDefault(track.getName(), 0f),
                        "woven injury field $gait/$injury/$degree/${track.getName()}",
                    )
                    close(
                        track.getBlendWeight(),
                        .4f * track.getBlendFieldWeight(),
                        "injury changed native node fade",
                    )
                    close(
                        track.getCurrentTimeValue(),
                        .27,
                        "injury replacement sought the foot phase",
                    )
                    sum += track.getBlendFieldWeight()
                }
                close(sum, 1.0, "injury blend lost directional mass")
                close(
                    CartLegPace.blendedSpeed(
                        f.source,
                        x,
                        y,
                        clips::get,
                        CartInjury.blend(f.player, f.source),
                    ),
                    speed(f, false),
                    "prediction differs from actual blended root",
                )
                val target = CartLegPace.targetSpeed(f.player, x, y)
                close(
                    target,
                    expectedTarget(f, x, y),
                    "cart target lost native injury/gait speed $type/$gait/$injury/$degree",
                )
                CartLegPace.applySpeed(f.player, target, x, y)
                close(
                    speed(f, true),
                    Math.min(target, 2.5f * speed(f, false)),
                    "native extracted root differs from requested budget/cadence cap $gait/$injury/$degree",
                )
            }
        }
    }

    private fun lifecycle() {
        val owner = fixture("SaucedWheelbarrow.WheelbarrowWood", "Walk", -.7f, false)
        val observer = fixture("SaucedWheelbarrow.WheelbarrowWood", "Walk", -.7f, true)
        apply(owner, .25f, .75f)
        apply(observer, .25f, .75f)
        check(weights(owner) == weights(observer), "owner/observer injury fields differ")
        val retained = weights(owner)
        owner.live.setActive(false)
        owner.player.injury = .8f
        apply(owner, -.8f, -.2f)
        check(weights(owner) == retained, "outgoing node changed its retained injury/direction")
        CartLegPace.applySpeedTracks(listOf(owner.live), .2f, null, 0f, 1f)
        close(speed(owner, true), .2, "outgoing injured node lost root-speed compensation")
        owner.live.setActive(true)
        owner.player.injury = 0f
        apply(owner, .25f, .75f)
        for (track in owner.live.getMainAnimationTracks()) close(
            track.getBlendFieldWeight(),
            picked(owner.source, .25f, .75f).getOrDefault(track.getName(), 0f),
            "healing failed to restore exact healthy field",
        )
        owner.player.injury = -.7f
        owner.player.enabled = false
        apply(owner, .25f, .75f)
        for (track in owner.live.getMainAnimationTracks()) close(
            track.getBlendFieldWeight(),
            picked(owner.source, .25f, .75f).getOrDefault(track.getName(), 0f),
            "disabled actor received injured pose",
        )
        val other = read(Path.of("media/AnimSets/player/movement/defaultWalk.xml"))
        check(
            CartInjury.blend(observer.player, other) == null,
            "injury hook claimed native non-cart node",
        )
    }

    private fun readiness() {
        val f = fixture("SaucedCarts.ShoppingCart", "Walk", -.7f, false)
        val blend =
            CartInjury.blend(f.player, f.source)
                ?: throw AssertionError("fixture lacks injury blend")
        check(CartInjury.supported(f.player), "ready injured actor failed capability gate")
        val selected = blend.first!!.animName
        val removed = clips.remove(selected)!!
        try {
            check(
                CartInjury.blend(f.player, f.source) == null,
                "missing asset still enabled injury blend",
            )
            check(
                !CartInjury.supported(f.player),
                "missing asset did not restore native injury fallback",
            )
            close(
                CartInjury.walkMagnitude(f.player, .62f),
                .62,
                "missing asset expanded healthy stride",
            )
            apply(f, 0f, .62f)
            close(
                weights(f).getValue("Toolkit_CartPivot_Walk"),
                .62,
                "missing asset consumed forward mass",
            )
        } finally {
            clips[selected] = removed
        }
        for (track in f.live.getMainAnimationTracks()) if (selected == track.getName()) {
            val original = track.currentClip
            track.currentClip = null
            try {
                apply(f, 0f, .62f)
                close(
                    weights(f).getValue("Toolkit_CartPivot_Walk"),
                    .62,
                    "missing live track consumed forward mass",
                )
            } finally {
                track.currentClip = original
            }
            break
        }
        val missing = f.source.blends2d.first { it.animName == selected }
        val index = f.source.blends2d.indexOf(missing)
        f.source.blends2d.removeAt(index)
        try {
            check(
                CartInjury.blend(f.player, f.source) == null,
                "incomplete cart XML still enabled injury blend",
            )
        } finally {
            f.source.blends2d.add(index, missing)
        }
    }

    private fun heavyPoseWeights() {
        val f = fixture("SaucedWheelbarrow.WheelbarrowWood", "Walk", 1f, false)
        close(
            CartInjury.poseWeight(f.player),
            1.0,
            "current injury lost its non-limp Sprint pose guard",
        )
        f.player.injury = 0f
        close(
            CartInjury.poseWeight(f.player),
            0.0,
            "dormant clips acquired torso correction after healing",
        )
        for (track in f.live.getMainAnimationTracks()) {
            track.setBlendFieldWeight(if (track.getName() == "Bob_WalkHeavyLimpR") .75f else 0f)
            track.setBlendWeight(.4f)
        }
        close(
            CartInjury.poseWeight(f.player),
            .3,
            "heavy correction ignored effective node/field weights",
        )
        f.live.setActive(false)
        close(
            CartInjury.poseWeight(f.player),
            .3,
            "outgoing heavy pose lost torso correction during fade",
        )
        for (track in f.live.getMainAnimationTracks()) {
            track.setBlendFieldWeight(if (track.getName() == "Bob_WalkLightLimpL") .5f else 0f)
            track.setBlendWeight(.4f)
        }
        close(
            CartInjury.poseWeight(f.player),
            .2,
            "outgoing light limp lost torso correction after healing",
        )
        f.source.name = "defaultRun"
        try {
            close(
                CartInjury.poseWeight(f.player),
                0.0,
                "native outgoing clips acquired cart-owned correction after healing",
            )
            f.player.injury = -.228f
            close(
                CartInjury.poseWeight(f.player),
                1.0,
                "native catch-up fallback lost current cart injury support",
            )
        } finally {
            f.source.name = "ToolkitWoodCartPivotWalk"
        }
        close(CartInjury.poseWeight(null), 0.0, "missing actor acquired torso correction")
    }

    private fun stationaryContinuity() {
        for (type in
            listOf(
                "SaucedCarts.ShoppingCart",
                "SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal",
            )) {
            val f = fixture(type, "Walk", 0f, false)
            val healthy = CartLegPace.targetSpeed(f.player, 1f, 0f) * f.player.speed
            for (injury in floatArrayOf(-.000001f, .000001f)) {
                f.player.injury = injury
                val radius = CartInjury.walkMagnitude(f.player, f.player.speed)
                close(
                    CartLegPace.targetSpeed(f.player, 1f, 0f) * radius,
                    healthy,
                    "tiny injury changed stationary pivot speed",
                )
            }
        }
        close(CartInjury.amount(Float.NaN), 0.0, "invalid injury acquired blend ownership")
        close(CartInjury.amount(.075f), .5, "injury onset must remain continuous")
        close(CartInjury.amount(-.075f), .5, "left/right injury onset differs")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        unsafe = field.get(null) as Unsafe
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartInjuryTest::class.java.classLoader,
        )
        check(Main.CART_INJURY_SUPPORTED, "installed native injury hook fingerprint unsupported")
        val project = Path.of(System.getProperty("pz.test.project"))
        nativeNodes["movement"] = read(Path.of("media/AnimSets/player/movement/defaultWalk.xml"))
        nativeNodes["run"] = read(Path.of("media/AnimSets/player/run/defaultRun.xml"))
        nativeNodes["sprint"] = read(Path.of("media/AnimSets/player/sprint/defaultSprint.xml"))
        for (relative in
            listOf(
                "movement/toolkit_cart_pivot_walk.xml",
                "movement/toolkit_cart_wood_pivot_walk.xml",
                "run/toolkit_cart_pivot_run.xml",
                "sprint/toolkit_cart_pivot_sprint.xml",
            )) {
            val node =
                read(
                    project.resolve("PZSurvivorToolkit/42/media/AnimSets/player").resolve(relative),
                )
            cartNodes[node.name] = node
        }
        // The healthy reverse budget still uses the native reference clip; the current
        // cart XML uses a separate authored Toolkit_CartPivot_Backward asset.
        clips.computeIfAbsent("Bob_WalkBwdNoAim1Hand") {
            importClip(Path.of("media/anims_X/Bob/$it.x"))
        }
        val model = ModelManager::class.java.getDeclaredField("animModel")
        model.isAccessible = true
        val previous = model.get(ModelManager.instance)
        val mesh = allocate(ModelMesh::class.java)
        mesh.skinningData = SkinningData(clips, listOf(), listOf(), listOf(), listOf(), HashMap())
        model.set(ModelManager.instance, mesh)
        applyField =
            AnimLayer::class
                .java
                .getDeclaredMethod(
                    "applyBlendField",
                    LiveAnimNode::class.java,
                    Float::class.javaPrimitiveType,
                    Float::class.javaPrimitiveType,
                    Float::class.javaPrimitiveType,
                )
        applyField.isAccessible = true
        try {
            steadyParity()
            directions()
            lifecycle()
            readiness()
            stationaryContinuity()
            heavyPoseWeights()
        } finally {
            model.set(ModelManager.instance, previous)
        }
        println("CART_INJURY_PASS")
    }
}
