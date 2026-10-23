package net.alexredby.cartlab

import java.lang.reflect.Field
import java.nio.file.Files
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoPlayer
import zombie.core.Core
import zombie.inventory.InventoryItem
import zombie.vehicles.BaseVehicle

/** Test-only native input and read-only cart diagnostics. */
object Main {
    internal val runtime = configuredPath("PZ_CART_RUNTIME_FILE")
    private val commands = configuredPath("PZ_CART_COMMAND_FILE")
    @JvmField var drive = -1
    @JvmField var gait = 0
    private var lastCommand = 0L
    private var heldKey = -1
    private var captureUIHidden = false

    private fun captureUIWorld() =
        System.getenv("PZ_CART_TEST_PAD") == "true" &&
            zombie.iso.IsoWorld.instance != null &&
            zombie.iso.IsoWorld.instance.getWorld() == "CartTestArea" &&
            !zombie.network.GameClient.client &&
            !zombie.network.GameServer.server

    @JvmStatic
    @LuaMethod(name = "cartLabCaptureUIKeyBound", global = true)
    fun captureUIKeyBound(key: Int) =
        Core.getInstance().getKeyBinding(key) !== Core.KEYBINDING_EMPTY

    @JvmStatic
    @LuaMethod(name = "cartLabCaptureUIVisible", global = true)
    fun captureUIVisible() = zombie.ui.UIManager.visibleAllUi

    @JvmStatic
    @LuaMethod(name = "cartLabCaptureUIRender", global = true)
    fun captureUIRender(hidden: Boolean) {
        check(!hidden || captureUIWorld()) { "Disposable single-player CartTestArea pad required" }
        captureUIHidden = hidden
        zombie.ui.UIManager.uiTextureContentsValid = false
    }

    @JvmStatic
    fun hideCaptureUIRender(): Boolean {
        if (!captureUIWorld()) captureUIHidden = false
        return captureUIHidden
    }

    @Patch(className = "zombie.ui.UIManager", methodName = "render", warmUp = true)
    object CaptureUIRender {
        @JvmStatic @Patch.OnEnter(skipOn = true) fun enter() = hideCaptureUIRender()
    }

    @Patch(className = "zombie.iso.IsoChunkMap", methodName = "CalcChunkWidth", warmUp = true)
    object PadChunks {
        @JvmStatic
        @Patch.OnExit
        fun exit() {
            if (System.getenv("PZ_CART_TEST_PAD") != "true") return
            zombie.iso.IsoChunkMap.chunkGridWidth = maxOf(25, zombie.iso.IsoChunkMap.chunkGridWidth)
            zombie.iso.IsoChunkMap.chunkWidthInTiles = zombie.iso.IsoChunkMap.chunkGridWidth * 8
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabChunkWidth", global = true)
    fun chunkWidth() = zombie.iso.IsoChunkMap.chunkWidthInTiles

    private fun configuredPath(name: String): Path {
        val value = System.getenv(name)
        check(!value.isNullOrBlank()) { "Missing required $name" }
        return Path.of(value).also { check(it.isAbsolute) { "$name must be absolute" } }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabClipInfo", global = true)
    fun clipInfo(name: String?): String =
        zombie.core.skinnedmodel.ModelManager.instance.getAnimationClip(name)?.let {
            "duration:${it.getDuration()}"
        } ?: "missing"

    @JvmStatic
    @LuaMethod(name = "cartLabNative", global = true)
    fun nativeState(): String {
        val p = IsoPlayer.getInstance()
        val animation = p.getAnimationPlayer()
        return buildString {
            append("state:")
                .append(p.getCurrentStateName())
                .append(",action:")
                .append(p.getActionStateName())
            append(",momentum:")
                .append(p.getMomentumScalar())
                .append(",twist:")
                .append(p.getTargetTwist())
            append(",around:").append(p.isTurningAround()).append(",tracks:")
            for (track in animation.getMultiTrack().getTracks()) {
                append(track.getName()).append('@').append(track.getBlendWeight()).append('/')
                append(track.getCurrentTimeValue())
                    .append('/')
                    .append(track.getSpeedDelta())
                    .append('/')
                append(track.isPlaying).append(';')
            }
            append(",bones:")
            for (name in
                arrayOf(
                    "Bip01",
                    "Bip01_Pelvis",
                    "Bip01_Spine",
                    "Bip01_Head",
                    "Bip01_L_Thigh",
                    "Bip01_L_Calf",
                    "Bip01_L_Foot",
                    "Bip01_L_Toe0",
                    "Bip01_R_Thigh",
                    "Bip01_R_Calf",
                    "Bip01_R_Foot",
                    "Bip01_R_Toe0",
                )) {
                val index = animation.getSkinningBoneIndex(name, -1)
                if (index < 0 || index >= animation.getModelTransformsCount()) continue
                val matrix = animation.getModelTransformAt(index) ?: continue
                val world = zombie.iso.Vector3(matrix.m03, matrix.m13, matrix.m23)
                zombie.core.skinnedmodel.model.Model.vectorToWorldCoords(p, world)
                append(name)
                    .append(':')
                    .append(matrix.m03)
                    .append('/')
                    .append(matrix.m13)
                    .append('/')
                    .append(matrix.m23)
                append('|')
                    .append(world.x)
                    .append('/')
                    .append(world.y)
                    .append('/')
                    .append(world.z)
                    .append(';')
            }
        }
    }

    private fun Class<*>.readableField(name: String): Field =
        getDeclaredField(name).apply { isAccessible = true }

    private fun Any.readableField(name: String): Field = javaClass.readableField(name)

    private fun hooks() = Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks")

    private fun steeringState(player: IsoPlayer): Any? =
        (hooks().readableField("states").get(null) as Map<*, *>)[player]

    @JvmStatic
    @LuaMethod(name = "cartLabBank", global = true)
    fun bank() =
        (hooks().getMethod("lean", IsoPlayer::class.java).invoke(null, IsoPlayer.getInstance())
                as Number)
            .toDouble()

    @JvmStatic
    @LuaMethod(name = "cartLabSafety", global = true)
    fun safety(item: InventoryItem, centerX: Double, centerY: Double): String {
        val p = IsoPlayer.getInstance()
        val hooks = hooks()
        val states = hooks.readableField("states")
        val state = (states.get(null) as Map<*, *>)[p]
        val brace = state?.readableField("brace")?.getDouble(state) ?: 0.0
        val phase =
            Class.forName("net.alexredby.pztoolkitjavapatches.CartWheelSpin")
                .getDeclaredMethod("itemPhase", InventoryItem::class.java)
                .apply { isAccessible = true }
        var inventoryCount = 0
        var worldCount = 0
        var woodCount = 0
        for (entry in p.getInventory().getItems()) if (entry.getID() == item.getID())
            inventoryCount++
        val world = item.getWorldItem()
        var worldExact = false
        for (x in Math.floor(centerX).toInt() - 6..Math.floor(centerX).toInt() + 6) {
            for (y in Math.floor(centerY).toInt() - 6..Math.floor(centerY).toInt() + 6) {
                val square =
                    zombie.iso.IsoWorld.instance.currentCell.getGridSquare(x, y, p.getZ().toInt())
                checkNotNull(square) { "Impact observation pad unloaded" }
                for (candidate in square.getWorldObjects()) {
                    val entry = candidate.getItem()
                    if (entry?.getFullType() == "SaucedWheelbarrow.WheelbarrowWood") woodCount++
                    if (entry != null && entry.getID() == item.getID()) worldCount++
                    if (candidate === world && entry === item) worldExact = true
                }
            }
        }
        val cart = item as zombie.inventory.types.InventoryContainer
        val ids = ArrayList<String>()
        for (child in cart.getInventory().getItems()) ids.add(child.getID().toString())
        ids.sort()
        return "state=${p.getCurrentState().javaClass.simpleName} action=${p.getActionStateName()}" +
            " enabled=${hooks.getMethod("enabled", IsoPlayer::class.java).invoke(null, p)}" +
            " steering=${(states.get(null) as Map<*, *>).containsKey(p)}" +
            " hit=${p.hasHitReaction()} knocked=${p.isKnockedDown()} getup=${p.isGettingUp()}" +
            " ragdoll=${p.isRagdollSimulationActive()} ignore=${p.getIgnoreMovement()}" +
            " pivot=${p.getVariableBoolean("ToolkitCartPivot")} brake=${p.getVariableBoolean("ToolkitCartWoodBrake")}" +
            " stepX=${p.getVariableFloat("ToolkitCartStepX", 0f)} stepY=${p.getVariableFloat("ToolkitCartStepY", 0f)}" +
            " pace=${p.getVariableFloat("ToolkitCartLegPace", 0f)} brace=$brace" +
            " id=${item.getID()} primary=${p.getPrimaryHandItem()?.getID() ?: -1} secondary=${p.getSecondaryHandItem()?.getID() ?: -1}" +
            " cargo=${cart.getInventory().getCapacityWeight()} cargoIds=${if (ids.isEmpty()) "empty" else ids.joinToString(",")}" +
            " inventoryCount=$inventoryCount inInventory=${item.getContainer() === p.getInventory()}" +
            " worldCount=$worldCount woodCount=$woodCount worldExact=$worldExact worldId=${world?.getItem()?.getID() ?: -1}" +
            " worldPersistent=${world != null && world.isIgnoreRemoveSandbox()}" +
            " worldX=${world?.getWorldPosX() ?: 0} worldY=${world?.getWorldPosY() ?: 0} worldZ=${world?.getWorldPosZ() ?: 0}" +
            " rotation=${item.getWorldZRotation()} itemPhase=${phase.invoke(null, item)}"
    }

    private var impactWatching = false
    private var impactActor: IsoPlayer? = null
    private var naturalImpactEvents = 0L
    private var injectedImpactEvents = 0L
    private var otherImpactEvents = 0L
    private var lastImpactOrigin = "none"
    private val impactReceipts = ArrayList<String>()

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "cartLabImpactWatch", global = true)
    fun impactWatch(enabled: Boolean) {
        if (enabled) {
            val p = IsoPlayer.getInstance()
            check(p != null && p.isLocalPlayer()) { "Impact watch requires a local player" }
            impactActor = p
            naturalImpactEvents = 0
            injectedImpactEvents = 0
            otherImpactEvents = 0
            lastImpactOrigin = "none"
            impactReceipts.clear()
        }
        impactWatching = enabled
        val row = impactFields(impactActor)
        row["kind"] = "watch"
        row["origin"] = "watch-control"
        row["movingObjectSha256"] = classFingerprint(zombie.iso.IsoMovingObject::class.java)
        row["actionContextSha256"] =
            classFingerprint(zombie.characters.action.ActionContext::class.java)
        println("[CART_NATURAL_HIT] ${impactJson(row)}")
    }

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "cartLabNaturalImpact", global = true)
    fun naturalImpact(): String =
        impactFields(IsoPlayer.getInstance()).entries.joinToString(" ") {
            "${it.key}=${impactToken(it.value)}"
        }

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "cartLabImpactReceipts", global = true)
    fun impactReceipts() = impactReceipts.joinToString(",", "[", "]")

    @JvmStatic
    private fun impactFields(p: IsoPlayer?): LinkedHashMap<String, Any?> =
        linkedMapOf(
            "timeMs" to System.currentTimeMillis(),
            "watch" to impactWatching,
            "actor" to (p != null && p === impactActor),
            "local" to (p != null && p.isLocalPlayer()),
            "state" to (p?.getCurrentState()?.javaClass?.simpleName ?: "none"),
            "action" to (p?.getActionStateName() ?: "none"),
            "run" to (p != null && p.isRunning()),
            "sprint" to (p != null && p.isSprinting()),
            "ignore" to (p != null && p.getIgnoreMovement()),
            "getup" to (p != null && p.isGettingUp()),
            "hit" to (p != null && p.hasHitReaction()),
            "knocked" to (p != null && p.isKnockedDown()),
            "ragdoll" to (p != null && p.isRagdollSimulationActive()),
            "primary" to (p?.getPrimaryHandItem()?.getID() ?: -1),
            "secondary" to (p?.getSecondaryHandItem()?.getID() ?: -1),
            "dir" to (p?.getDir()?.name ?: "none"),
            "wallType" to (p?.getCurrentSquare()?.getWallType() ?: -1),
            "collidedN" to (p != null && p.isCollidedN()),
            "collidedS" to (p != null && p.isCollidedS()),
            "collidedE" to (p != null && p.isCollidedE()),
            "collidedW" to (p != null && p.isCollidedW()),
            "collidedDoor" to (p != null && p.isCollidedWithDoor()),
            "collideType" to (p?.getCollideType() ?: "none"),
            "naturalEvents" to naturalImpactEvents,
            "injectedEvents" to injectedImpactEvents,
            "otherEvents" to otherImpactEvents,
            "origin" to lastImpactOrigin,
        )

    @Patch(
        className = "zombie.characters.action.ActionContext",
        methodName = "reportEvent",
        warmUp = true,
        strictMatch = true,
    )
    object ImpactEventReceipt {
        @JvmStatic
        @Patch.OnExit
        fun exit(
            @Patch.This context: zombie.characters.action.ActionContext,
            @Patch.Argument(0) layer: String?,
            @Patch.Argument(1) event: String?,
        ) = observeImpact(context, layer, event)
    }

    @JvmStatic
    @Synchronized
    fun observeImpact(
        context: zombie.characters.action.ActionContext?,
        layer: String?,
        event: String?,
    ) {
        val actor = impactActor
        if (
            !impactWatching ||
                event != "collideWithWall" ||
                actor == null ||
                context?.getOwner() !== actor ||
                !actor.isLocalPlayer()
        )
            return
        val stack =
            StackWalker.getInstance().walk { frames ->
                frames.map { "${it.className}.${it.methodName}" }.toList()
            }
        val origin = impactOrigin(stack)
        when (origin) {
            "native-checkHitWall" -> naturalImpactEvents++
            "injected-cartLabWallEvent" -> injectedImpactEvents++
            else -> otherImpactEvents++
        }
        lastImpactOrigin = origin
        val row = impactFields(actor)
        row["kind"] = "event"
        row["event"] = event
        row["layer"] = layer ?: "none"
        row["stack"] = stack.joinToString(";")
        val receipt = impactJson(row)
        impactReceipts.add(receipt)
        println("[CART_NATURAL_HIT] $receipt")
    }

    @JvmStatic
    fun impactOrigin(stack: List<String>): String =
        when {
            "${Main::class.java.name}.wallEvent" in stack -> "injected-cartLabWallEvent"
            "zombie.iso.IsoMovingObject.checkHitWall" in stack -> "native-checkHitWall"
            else -> "other"
        }

    private fun impactToken(value: Any?) =
        value?.toString()?.takeIf { it.isNotEmpty() }?.replace(Regex("\\s+"), "_") ?: "none"

    @JvmStatic
    private fun impactJson(row: Map<String, Any?>) =
        row.entries.joinToString(",", "{", "}") {
            impactQuote(it.key) +
                ":" +
                when (val value = it.value) {
                    is Number,
                    is Boolean -> value.toString()
                    else -> impactQuote(value?.toString() ?: "none")
                }
        }

    private fun impactQuote(value: String) = buildString {
        append('"')
        for (c in value) when {
            c == '\\' || c == '"' -> append('\\').append(c)
            c < ' ' -> append(String.format("\\u%04x", c.code))
            else -> append(c)
        }
        append('"')
    }

    @JvmStatic
    private fun classFingerprint(type: Class<*>): String =
        try {
            type.getResourceAsStream("/${type.name.replace('.', '/')}.class").use { stream ->
                if (stream == null) "missing"
                else
                    java.util.HexFormat.of()
                        .formatHex(
                            java.security.MessageDigest.getInstance("SHA-256")
                                .digest(stream.readAllBytes()),
                        )
            }
        } catch (failure: java.io.IOException) {
            "unavailable-${failure.javaClass.simpleName}"
        } catch (failure: java.security.NoSuchAlgorithmException) {
            "unavailable-${failure.javaClass.simpleName}"
        }

    @JvmStatic
    @LuaMethod(name = "cartLabWallEvent", global = true)
    fun wallEvent() {
        val p = IsoPlayer.getInstance()
        check(p.isSprinting() && p.getActionStateName() == "sprint") {
            "Native wall event requires an actual Sprint state"
        }
        p.getActionContext().reportEvent("collideWithWall")
    }

    private fun StringBuilder.fields(value: Any, names: Array<String>, prefix: String = "") {
        for (name in names) append(prefix)
            .append(name)
            .append(':')
            .append(value.readableField(name).get(value))
            .append(',')
    }

    @JvmStatic
    @LuaMethod(name = "cartLabRamp", global = true)
    fun ramp(): String {
        val state = steeringState(IsoPlayer.getInstance()) ?: return "none"
        return buildString {
            for (key in arrayOf("pace", "sprintMomentum", "load", "heading")) {
                val value = state.readableField(key).get(state)
                if (key == "pace") fields(value, arrayOf("speed", "velocity"))
                else append(key).append(':').append(value).append(',')
            }
            val p = IsoPlayer.getInstance()
            val pace = Class.forName("net.alexredby.pztoolkitjavapatches.CartLegPace")
            val target =
                pace
                    .getMethod(
                        "targetSpeed",
                        IsoPlayer::class.java,
                        Float::class.javaPrimitiveType,
                        Float::class.javaPrimitiveType,
                    )
                    .invoke(
                        null,
                        p,
                        p.getVariableFloat("ToolkitCartStepX", 0f),
                        p.getVariableFloat("ToolkitCartStepY", 0f),
                    )
            append("target:").append(target).append(',')
            for (node in p.getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) if (
                node.getName() == "ToolkitCartPivotSprint"
            )
                append("fade:").append(node.getBlendOutTime()).append(',')
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabReversal", global = true)
    fun reversal(): String {
        val state = steeringState(IsoPlayer.getInstance()) ?: return "none"
        val reversal = state.readableField("reversal").get(state)
        return buildString {
            fields(reversal, arrayOf("direction", "requested", "active", "braking", "neutral"))
            fields(state, arrayOf("actualDistance", "brakeTarget"))
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabBrake", global = true)
    fun brake(): String {
        val state = steeringState(IsoPlayer.getInstance()) ?: return "none"
        return buildString {
            fields(
                state,
                arrayOf("braking", "brakeSeen", "nativeSpeed", "brakeLimit", "brakeWait"),
                "stop_",
            )
            val player = IsoPlayer.getInstance()
            val animation = player.getAnimationPlayer()
            val raw =
                animation.getModelTransformAt(animation.getSkinningBoneIndex("Bip01_Spine", -1))
            val shift =
                Class.forName("net.alexredby.pztoolkitjavapatches.CartLegPace")
                    .getMethod("woodenGaitShift", IsoPlayer::class.java)
                    .invoke(null, player)
            append("tickDt:")
                .append(zombie.GameTime.getInstance().getRealworldSecondsSinceLastUpdate())
                .append(',')
            append("bodyShift:")
                .append(shift)
                .append(",rawX:")
                .append(raw.m03)
                .append(",rawZ:")
                .append(raw.m23)
                .append(',')
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabStationary", global = true)
    fun stationary(): String {
        val player = IsoPlayer.getInstance()
        val state = steeringState(player) ?: return "none"
        return buildString {
            fields(
                state,
                arrayOf("heading", "target", "stationary", "stationaryRoot", "actualDistance"),
            )
            val axle =
                hooks().getDeclaredMethod("axle", IsoPlayer::class.java).apply {
                    isAccessible = true
                }
            append("axle:").append(axle.invoke(null, player)).append(",rootTracks:")
            for (track in player.getAnimationPlayer().getMultiTrack().getTracks()) if (
                track.getLayerIdx().toInt() == 0
            ) {
                append(track.getName())
                    .append('@')
                    .append(track.getBlendWeight())
                    .append('/')
                    .append(track.getCurrentTimeValue())
                append('/').append(track.getSpeedDelta()).append(';')
            }
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabPoseHeading", global = true)
    fun poseHeading(angle: Double) {
        require(angle.isFinite()) { "finite heading required" }
        val player = IsoPlayer.getInstance()
        val x = Math.cos(angle).toFloat()
        val y = Math.sin(angle).toFloat()
        player.setTargetAndCurrentDirection(x, y)
        player.getAnimationPlayer().setTargetAndCurrentDirection(x, y)
        hooks().getMethod("reset", IsoPlayer::class.java).invoke(null, player)
    }

    @JvmStatic
    @LuaMethod(name = "cartLabGait", global = true)
    fun gait(value: Int) {
        require(value in 0..2) { "gait must be 0, 1 or 2" }
        gait = value
    }

    @JvmStatic
    @LuaMethod(name = "cartLabHeading", global = true)
    fun heading(): Double =
        IsoPlayer.getInstance().getAnimForwardDirection(zombie.iso.Vector2()).let {
            Math.atan2(it.y.toDouble(), it.x.toDouble())
        }

    @JvmStatic
    @LuaMethod(name = "cartLabSteeringHeading", global = true)
    fun steeringHeading(): Double {
        val accepted =
            net.alexredby.pztoolkitjavapatches.CartSteeringHooks.networkHeading(
                IsoPlayer.getInstance(),
            )
        return if (accepted.isFinite()) accepted.toDouble() else heading()
    }

    @JvmStatic
    @LuaMethod(name = "cartLabFrame", global = true)
    fun frame() = zombie.iso.IsoWorld.instance.getFrameNo()

    @JvmStatic
    @LuaMethod(name = "cartLabWheelPhase", global = true)
    fun wheelPhase() =
        (hooks()
                .getMethod("wheelPhase", IsoPlayer::class.java)
                .invoke(null, IsoPlayer.getInstance()) as Number)
            .toDouble()

    @JvmStatic
    @LuaMethod(name = "cartLabFootprint", global = true)
    fun footprint(): String {
        val player = IsoPlayer.getInstance()
        val state = checkNotNull(steeringState(player)) { "Cart state required" }
        val front = state.readableField("footprintFront")
        val heading = state.readableField("heading")
        val shape = Class.forName("net.alexredby.pztoolkitjavapatches.CartFootprint")
        val world =
            shape.getDeclaredMethod("world", IsoPlayer::class.java).apply { isAccessible = true }
        val clear =
            shape
                .getDeclaredMethod(
                    "clear",
                    Class.forName("${shape.name}\$Query"),
                    Double::class.javaPrimitiveType,
                    Double::class.javaPrimitiveType,
                    Double::class.javaPrimitiveType,
                    Double::class.javaPrimitiveType,
                )
                .apply { isAccessible = true }
        return buildString {
            append("front=").append(front.getDouble(state))
            for (key in arrayOf("cartBlocked", "recovering")) append(' ')
                .append(if (key == "cartBlocked") "blocked" else key)
                .append('=')
                .append(state.readableField(key).getBoolean(state))
            append(" clear=")
                .append(
                    clear.invoke(
                        null,
                        world.invoke(null, player),
                        player.getX(),
                        player.getY(),
                        heading.getDouble(state),
                        front.getDouble(state),
                    ),
                )
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabBrace", global = true)
    fun brace(wallX: Double, y: Double): String {
        vehicleGuard()
        val player = IsoPlayer.getInstance()
        val z = Math.floor(player.getZ().toDouble()).toInt()
        val x = wallX.toFloat()
        val fy = y.toFloat()
        require(
            (x + fy).isFinite() &&
                z > 0 &&
                Math.abs(x - player.getX()) <= 16 &&
                Math.abs(fy - player.getY()) <= 16,
        ) {
            "Loaded local upper-pad wall query required"
        }
        val cell = player.getCell()
        check(
            cell.getGridSquare(Math.floor(x - .5).toInt(), Math.floor(fy.toDouble()).toInt(), z) !=
                null &&
                cell.getGridSquare(
                    Math.floor(x + .5).toInt(),
                    Math.floor(fy.toDouble()).toInt(),
                    z,
                ) != null,
        ) {
            "Wall query squares must remain loaded"
        }
        val state = checkNotNull(steeringState(player)) { "Cart state required" }
        val amount = state.readableField("brace").getDouble(state)
        check(amount.isFinite() && amount in 0.0..1.0) { "Invalid brace amount" }
        val blocked =
            zombie.pathfind.PolygonalMap2.instance.lineClearCollide(
                x + .5f,
                fy,
                x - .5f,
                fy,
                z,
                null,
                zombie.pathfind.PolygonalMap2.LCC_ZERO,
            )
        return "brace=$amount nativeBlocked=$blocked wantsMove=${state.readableField("wantsMove").getBoolean(state)}"
    }

    private var fixtureVehicle: BaseVehicle? = null
    private var fixtureHull: FloatArray? = null
    private var fixtureZ = 0f

    private fun vehicleGuard() {
        check(
            System.getenv("PZ_CART_TEST_PAD") == "true" &&
                zombie.iso.IsoWorld.instance.getWorld() == "CartTestArea" &&
                !zombie.network.GameClient.client &&
                !zombie.network.GameServer.server,
        ) {
            "Disposable single-player CartTestArea pad required"
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabVehicleCreate", global = true)
    fun vehicleCreate(x: Double, y: Double, z: Int, yaw: Double): BaseVehicle {
        vehicleGuard()
        require(fixtureVehicle == null && (x + y + yaw).isFinite() && z > 0) {
            "Empty fixture slot and finite upper-pad pose required"
        }
        val cell = zombie.iso.IsoWorld.instance.currentCell
        val square = cell.getGridSquare(Math.floor(x).toInt(), Math.floor(y).toInt(), z)
        check(square != null && square.getFloor() != null && square.TreatAsSolidFloor()) {
            "Loaded fixture floor required"
        }
        val vehicle = BaseVehicle(cell)
        vehicle.keySpawned = 1
        fixtureVehicle = vehicle
        try {
            vehicle.setScriptName("Base.CarNormal")
            vehicle.setScript()
            checkNotNull(vehicle.getScript()) { "Native CarNormal script missing" }
            vehicle.setX(x.toFloat())
            vehicle.setY(y.toFloat())
            vehicle.setZ(z.toFloat())
            vehicle.savedRot.setAngleAxis(yaw.toFloat(), 0f, 1f, 0f)
            vehicle.jniTransform.setRotation(vehicle.savedRot)
            vehicle.setSquare(square)
            vehicle.chunk = square.getChunk()
            vehicle.chunk.vehicles.add(vehicle)
            vehicle.addToWorld()
            vehicle.setPhysicsActive(false)
            vehicle.polyDirty = true
            fixtureZ = vehicle.getZ()
            fixtureHull = vehicleHull(vehicle)
            vehicleState()
            return vehicle
        } catch (failure: RuntimeException) {
            vehicleRemove()
            throw failure
        }
    }

    private fun vehicleHull(vehicle: BaseVehicle): FloatArray =
        vehicle.getPoly().let {
            floatArrayOf(it.x1, it.y1, it.x2, it.y2, it.x3, it.y3, it.x4, it.y4)
        }

    private fun checkedVehicle(): BaseVehicle {
        vehicleGuard()
        val vehicle = fixtureVehicle
        check(
            vehicle != null &&
                vehicle.addedToWorld &&
                vehicle.getId() >= 0 &&
                vehicle.isStatic &&
                !vehicle.isActive &&
                !vehicle.isPhysicsActive() &&
                vehicle.getZ() == fixtureZ &&
                vehicle.getPoly().z == fixtureZ &&
                vehicle.chunk != null &&
                vehicle.chunk.vehicles.contains(vehicle),
        ) {
            "Owned static native vehicle identity/level changed"
        }
        val hull = vehicleHull(vehicle)
        for (i in hull.indices) check(
            hull[i].isFinite() && Math.abs(hull[i] - fixtureHull!![i]) <= .002,
        ) {
            "Owned native vehicle hull moved"
        }
        return vehicle
    }

    @JvmStatic
    @LuaMethod(name = "cartLabVehicleCheck", global = true)
    fun vehicleCheck(): Boolean {
        checkedVehicle()
        return true
    }

    @JvmStatic
    @LuaMethod(name = "cartLabVehicleState", global = true)
    fun vehicleState(): String {
        val v = checkedVehicle()
        val hull = vehicleHull(v)
        val player = IsoPlayer.getInstance()
        val map = zombie.pathfind.PolygonalMap2.instance
        var cx = 0f
        var cy = 0f
        for (i in 0 until 8 step 2) {
            cx += hull[i] / 4
            cy += hull[i + 1] / 4
        }
        return buildString {
            append("id=")
                .append(v.getId())
                .append(" z=")
                .append(v.getZ())
                .append(" static=")
                .append(v.isStatic)
                .append(" active=")
                .append(v.isActive)
            append(" bodyBlocked=")
                .append(!map.canStandAt(cx, cy, fixtureZ.toInt(), player, false, false))
            append(" crossBlocked=")
                .append(
                    map.lineClearCollide(
                        cx - 8,
                        cy,
                        cx + 8,
                        cy,
                        fixtureZ.toInt(),
                        player,
                        zombie.pathfind.PolygonalMap2.LCC_ZERO,
                    ),
                )
                .append(" hull=")
            for (i in 0 until 8) {
                if (i > 0) append(',')
                append(hull[i])
            }
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabVehicleSquareAllowed", global = true)
    fun vehicleSquareAllowed(x: Int, y: Int, z: Int): Boolean {
        vehicleGuard()
        if (fixtureVehicle == null) return false
        checkedVehicle()
        var owned = false
        val cell = zombie.iso.IsoWorld.instance.currentCell
        val seen = HashSet<BaseVehicle>(cell.getVehicles())
        seen.addAll(cell.addVehicles)
        for (cx in x - 16..x + 16 step 8) for (cy in y - 16..y + 16 step 8) cell
            .getChunkForGridSquare(cx, cy, 0)
            ?.let { seen.addAll(it.vehicles) }
        for (vehicle in seen) if (vehicle.isIntersectingSquare(x, y, z)) {
            if (vehicle !== fixtureVehicle) return false
            owned = true
        }
        return owned
    }

    @JvmStatic
    @LuaMethod(name = "cartLabVehicleRemove", global = true)
    fun vehicleRemove() {
        vehicleGuard()
        val vehicle = fixtureVehicle ?: return
        if (vehicle.addedToWorld) vehicle.permanentlyRemove()
        vehicle.chunk?.vehicles?.remove(vehicle)
        fixtureVehicle = null
        fixtureHull = null
    }

    @JvmStatic
    @LuaMethod(name = "cartLabMillis", global = true)
    fun millis() = System.nanoTime() / 1_000_000.0

    @JvmStatic
    @LuaMethod(name = "cartLabDrive", global = true)
    fun drive(value: Int) {
        require(value in -1..8) { "drive must be -1..8" }
        drive = value
    }

    @JvmStatic
    @LuaMethod(name = "cartLabTracks", global = true)
    fun tracks() = buildString {
        for (track in
            IsoPlayer.getInstance().getAnimationPlayer().getMultiTrack().getTracks()) append(
                track.getName(),
            )
            .append('=')
            .append(track.getSpeedDelta())
            .append('@')
            .append(track.getBlendWeight())
            .append(';')
    }

    @JvmStatic
    @LuaMethod(name = "cartLabReload", global = true)
    fun reload() {
        check(Files.isRegularFile(runtime)) { "Missing configured runtime Lua: $runtime" }
        zombie.Lua.LuaManager.loaded.remove(runtime.toString())
        zombie.Lua.LuaManager.RunLua(runtime.toString(), false)
    }

    @JvmStatic
    @LuaMethod(name = "cartLabPoll", global = true)
    fun poll() {
        if (!Files.exists(commands)) return
        val changed = Files.getLastModifiedTime(commands).toMillis()
        if (changed == lastCommand) return
        lastCommand = changed
        when (Files.readString(commands).trim()) {
            "reload" -> reload()
            "screenshot" -> Core.getInstance().TakeFullScreenshot("cart-lab-live.png")
            else -> throw IllegalArgumentException("Unknown cart lab command")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        // CART_LAB_STARTUP
        println("[CART_LAB] LOADED")
    }

    @JvmStatic
    @LuaMethod(name = "cartLabKeyState", global = true)
    fun keyState(key: Int, down: Boolean) {
        check(drive >= 0 && key in 1 until 256) {
            "Key fixture requires isolated drive and a keyboard key"
        }
        if (down) {
            if (heldKey == key) return
            check(heldKey < 0) { "Release the previous fixture key first" }
            heldKey = key
            zombie.Lua.LuaEventManager.triggerEvent("OnKeyStartPressed", key)
            zombie.Lua.LuaEventManager.triggerEvent("OnCustomUIKeyPressed", key)
        } else {
            if (heldKey < 0) return
            check(heldKey == key) { "Wrong fixture key release" }
            heldKey = -1
            for (event in arrayOf("OnKeyPressed", "OnCustomUIKey", "OnCustomUIKeyReleased")) zombie
                .Lua
                .LuaEventManager
                .triggerEvent(event, key)
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLabContextSeconds", global = true)
    fun contextSeconds() = IsoPlayer.getInstance().timePressedContext

    @JvmStatic
    fun fixtureKey(key: Int): Boolean {
        if (heldKey == key) return true
        if (drive < 0) return false
        if (gait > 0 && key == Core.getInstance().getKey(if (gait == 1) "Run" else "Sprint"))
            return true
        if (drive == 0) return false
        val first =
            when (drive) {
                1,
                5 -> "Forward"
                2,
                6 -> "Left"
                3,
                8 -> "Right"
                else -> "Backward"
            }
        val second =
            when (drive) {
                5 -> "Left"
                6 -> "Backward"
                7 -> "Right"
                8 -> "Forward"
                else -> null
            }
        return key == Core.getInstance().getKey(first) ||
            second != null && key == Core.getInstance().getKey(second)
    }
}
