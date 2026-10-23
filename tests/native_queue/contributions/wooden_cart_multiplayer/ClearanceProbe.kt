import java.io.BufferedWriter
import java.lang.instrument.Instrumentation
import java.lang.reflect.Method
import java.nio.file.*
import java.security.MessageDigest
import java.util.HexFormat
import net.bytebuddy.agent.builder.AgentBuilder
import net.bytebuddy.asm.Advice
import net.bytebuddy.matcher.ElementMatchers.*
import org.joml.Matrix4f
import org.lwjgl.BufferUtils
import org.lwjgl.opengl.GL11
import org.lwjgl.opengl.GL15
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.model.*

// Read-only final render poses for native body/handle clearance measurements.
object ClearanceProbe {
    private fun methodNamed(
        name: String,
    ): net.bytebuddy.matcher.ElementMatcher.Junction<
        net.bytebuddy.description.method.MethodDescription,
    > = named(name)

    private fun methodNames(
        vararg names: String,
    ): net.bytebuddy.matcher.ElementMatcher.Junction<
        net.bytebuddy.description.method.MethodDescription,
    > = namedOneOf(*names)

    private fun typeNamed(
        name: String,
    ): net.bytebuddy.matcher.ElementMatcher.Junction<
        net.bytebuddy.description.type.TypeDescription,
    > = named(name)

    private var output: BufferedWriter? = null
    private var solves: BufferedWriter? = null
    private var cameras: BufferedWriter? = null
    private var handoffEvents: BufferedWriter? = null
    private val INVENTORY_EQUIP = "true".equals(System.getenv("PZ_CART_INVENTORY_EQUIP"))
    private var inventoryEquip: BufferedWriter? = null
    private var inventoryFrame: Long = 0
    private var inventorySample: Long = 0
    private var nextInventoryAction: Long = 0
    private val inventoryActions =
        java.util.WeakHashMap<zombie.characters.CharacterTimedActions.LuaTimedActionNew, Long>()
    private val inventoryUpdates =
        java.util.WeakHashMap<zombie.characters.CharacterTimedActions.LuaTimedActionNew, Long>()
    private val inventoryAttachments =
        java.util.WeakHashMap<zombie.characters.IsoPlayer, InventoryAttachment>()
    private val handoffOutputLock = Any()
    private var captureSerial: Long = 0
    private val TIMELINE = "true".equals(System.getenv("PZ_CART_TIMELINE"))
    private val OBSERVER_ASSOCIATION = "true".equals(System.getenv("PZ_CART_OBSERVER_ASSOCIATION"))
    private var timelineBridge: Method? = null
    private var timelineInputBridge: Method? = null
    private var observerBridge: Method? = null
    private val hands = java.util.WeakHashMap<zombie.characters.IsoPlayer, Hands>()
    private val nativePoses = java.util.WeakHashMap<ModelSlotRenderData?, NativePose>()
    private val drawFrames = java.util.WeakHashMap<ModelSlotRenderData?, DrawFrame>()
    private val consumedCamera = ThreadLocal<ConsumedCamera>()
    private lateinit var directory: Path
    private var meshProof: Boolean = false
    private var phaseMeshProof: Boolean = false
    private var meshError: Boolean = false
    private var firstMeshPhase: Double = 0.toDouble()
    private var firstMeshHash: String? = null
    private var wheelPhase: Method? = null
    private val MESH_SHA = "0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948"
    private val solve = ThreadLocal<StringBuilder>()
    private var last: Long = 0
    private var installed: Boolean = false

    @JvmRecord
    private data class InventoryAttachment(
        val item: zombie.inventory.InventoryItem?,
        val first: Long,
    )

    private fun inventoryActor(owner: zombie.characters.IsoPlayer?): String? {
        val local = zombie.characters.IsoPlayer.getInstance()
        if (
            (!INVENTORY_EQUIP ||
                inventoryEquip == null ||
                !zombie.network.GameClient.client ||
                zombie.network.GameServer.server ||
                zombie.network.GameClient.connection == null ||
                !zombie.network.GameClient.instance.connected ||
                owner == null ||
                !"client1".equals(owner.getUsername()) ||
                owner.getOnlineID() < 0 ||
                owner.isDead() ||
                owner.getCurrentSquare() == null ||
                local == null ||
                !local.isLocalPlayer() ||
                !("client1".equals(local.getUsername()) || "client2".equals(local.getUsername())))
        )
            return null
        return local.getUsername()
    }

    private fun inventoryActionId(
        action: zombie.characters.CharacterTimedActions.LuaTimedActionNew,
    ): Long {
        return inventoryActions.computeIfAbsent(action) { ++nextInventoryAction }
    }

    private fun inventoryPrefix(
        kind: String,
        player: zombie.characters.IsoPlayer,
        actor: String?,
    ): String {
        return ("{\"producer\":\"cart-mp-inventory-equip-native-v1\",\"event\":" +
            jsonString(kind) +
            ",\"actor\":" +
            jsonString(actor) +
            ",\"ownerID\":" +
            player.getOnlineID() +
            ",\"local\":" +
            player.isLocalPlayer() +
            ",\"female\":" +
            player.isFemale() +
            ",\"wall\":" +
            System.currentTimeMillis())
    }

    private fun inventoryReadiness(player: zombie.characters.IsoPlayer): String {
        val item = player.getPrimaryHandItem()
        return ("{\"visualEnabled\":" +
            net.alexredby.pztoolkitjavapatches.CartMotionSync.visualEnabled(player) +
            ",\"steeringEnabled\":" +
            net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled(player) +
            ",\"supportedHeldCart\":" +
            net.alexredby.pztoolkitjavapatches.CartSteeringHooks.supportedCart(player) +
            ",\"IsPerformingAnAction\":" +
            player.getVariableBoolean("IsPerformingAnAction") +
            ",\"ToolkitCartMotion\":" +
            player.getVariableBoolean("ToolkitCartMotion") +
            ",\"Weapon\":" +
            jsonString(player.getVariableString("Weapon")) +
            ",\"PerformingAction\":" +
            jsonString(player.getVariableString("PerformingAction")) +
            ",\"ToolkitCartPose\":" +
            jsonString(player.getVariableString("ToolkitCartPose")) +
            ",\"RightHandMask\":" +
            jsonString(player.getVariableString("RightHandMask")) +
            ",\"LeftHandMask\":" +
            jsonString(player.getVariableString("LeftHandMask")) +
            ",\"overridePrimary\":" +
            jsonString(player.overridePrimaryHandModel) +
            ",\"overrideSecondary\":" +
            jsonString(player.overrideSecondaryHandModel) +
            ",\"forceNullOverride\":" +
            player.forceNullOverride +
            ",\"hideWeapon\":" +
            player.isHideWeaponModel() +
            ",\"inventoryOwnsPrimary\":" +
            (item != null && item.getContainer() === player.getInventory()) +
            "}")
    }

    private fun inventoryGroundPose(
        slot: ModelSlotRenderData,
        cart: ModelInstanceRenderData,
    ): String {
        val player = slot.character as zombie.characters.IsoPlayer
        val item = player.getPrimaryHandItem()
        val row =
            StringBuilder("{\"wall\":")
                .append(System.currentTimeMillis())
                .append(",\"slotToken\":")
                .append(System.identityHashCode(slot))
                .append(",\"cartDataToken\":")
                .append(System.identityHashCode(cart))
                .append(",\"id\":")
                .append(item.getID())
                .append(",\"primaryID\":")
                .append(item.getID())
                .append(",\"secondaryID\":")
                .append(
                    if (player.getSecondaryHandItem() == null) -1
                    else player.getSecondaryHandItem().getID(),
                )
                .append(",\"readiness\":")
                .append(inventoryReadiness(player))
                .append(",\"cart\":")
        matrix(row, Matrix4f(cart.xfrm).transpose())
        row.append(",\"bones\":{")
        var comma = false
        for (body in slot.modelData) if (
            (body.modelInstance === cart.modelInstance.parent &&
                body.matrixPalette != null &&
                body.modelInstance.model.tag is SkinningData)
        ) {
            val skin = body.modelInstance.model.tag as SkinningData
            for (entry in skin.boneIndices.entries) {
                val i = entry.value
                val buffer = body.matrixPalette.duplicate()
                buffer.position(i * 16)
                val raw = org.lwjgl.util.vector.Matrix4f()
                raw.load(buffer)
                val pose =
                    PZMath.convertMatrix(raw, Matrix4f())
                        .transpose()
                        .mul(
                            PZMath.convertMatrix(skin.boneOffset.get(i), Matrix4f())
                                .transpose()
                                .invert(),
                        )
                if (!pose.isFinite()) throw IllegalStateException("Nonfinite MP attachment pose")
                if (comma) row.append(',')
                comma = true
                row.append(jsonString(entry.key)).append(':')
                matrix(row, pose)
            }
            break
        }
        return row.append("}}").toString()
    }

    @Synchronized
    @JvmStatic
    fun inventoryGroundBefore(slot: ModelSlotRenderData): String? {
        val player = slot.character as? zombie.characters.IsoPlayer ?: return null
        if (inventoryActor(player) == null) return null
        val item = player.getPrimaryHandItem()
        if (
            item == null ||
                item !== player.getSecondaryHandItem() ||
                !"SaucedWheelbarrow.WheelbarrowWood".equals(item.getFullType())
        )
            return null
        val now = System.nanoTime()
        var window = inventoryAttachments.get(player)
        if (window == null || window.item !== item) {
            window = InventoryAttachment(item, now)
            inventoryAttachments.put(player, window)
        }
        if (now - window.first > 750_000_000L) return null
        for (cart in slot.modelData) if (
            (cart.modelInstance != null &&
                cart.modelInstance.parent != null &&
                cart.modelInstance.modelScript != null &&
                "WheelbarrowWood".equals(cart.modelInstance.modelScript.getName()))
        )
            return inventoryGroundPose(slot, cart)
        return null
    }

    @Synchronized
    @JvmStatic
    fun inventoryGroundAfter(slot: ModelSlotRenderData?, before: String?) {
        if (before == null) return
        val player = slot!!.character as? zombie.characters.IsoPlayer ?: return
        val actor = inventoryActor(player)
        if (actor == null) return
        for (cart in slot.modelData) if (
            (cart.modelInstance != null &&
                cart.modelInstance.parent != null &&
                cart.modelInstance.modelScript != null &&
                "WheelbarrowWood".equals(cart.modelInstance.modelScript.getName()))
        ) {
            inventoryEquip!!.write(
                inventoryPrefix("grounding-pair", player, actor) +
                    ",\"before\":" +
                    before +
                    ",\"after\":" +
                    inventoryGroundPose(slot, cart) +
                    "}\n",
            )
            inventoryEquip!!.flush()
            return
        }
    }

    object InventoryGrounding {
        @Advice.OnMethodEnter(suppress = Throwable::class)
        @JvmStatic
        fun enter(@Advice.Argument(0) slot: ModelSlotRenderData): String? {
            return ClearanceProbe.inventoryGroundBefore(slot)
        }

        @Advice.OnMethodExit(suppress = Throwable::class)
        @JvmStatic
        fun exit(@Advice.Argument(0) slot: ModelSlotRenderData?, @Advice.Enter before: String?) {
            ClearanceProbe.inventoryGroundAfter(slot, before)
        }
    }

    @Synchronized
    @JvmStatic
    fun inventoryLifecycle(
        action: zombie.characters.CharacterTimedActions.LuaTimedActionNew,
        event: String?,
        stage: String?,
        thrown: Throwable?,
    ) {
        val player = action.chr as? zombie.characters.IsoPlayer ?: return
        val actor = inventoryActor(player)
        if (actor == null || !"ISCartEquipAction".equals(action.getMetaType())) return
        val now = System.nanoTime()
        if ("update".equals(event)) {
            // The server-done packet can arrive between enter and exit on the
            // final update. Never decimate that canonical completion receipt.
            val previous = inventoryUpdates.getOrDefault(action, 0L)
            if (!action.forceComplete && now - previous < 25_000_000L) return
            inventoryUpdates.put(action, now)
        }
        val table = action.getTable()
        val cartId = table.rawget("cartId")
        if (!(cartId is Number) || (cartId).toInt() <= 0)
            throw IllegalStateException("Native inventory equip has no exact cartId")
        val networkPlayer =
            stateField(action, "playerId") as zombie.network.fields.character.PlayerID
        val transaction = (stateField(action, "transactionId") as Number).toByte()
        val networkAction = zombie.core.ActionManager.getAction(transaction, networkPlayer)
        val networkExact =
            (networkAction != null &&
                networkAction.action === table &&
                "ISCartEquipAction".equals(networkAction.type) &&
                networkPlayer.getID() == player.getOnlineID())
        val networkDone =
            networkExact && zombie.core.ActionManager.isDone(networkPlayer, transaction)
        val networkRejected =
            networkExact && zombie.core.ActionManager.isRejected(networkPlayer, transaction)
        val primary = player.getPrimaryHandItem()
        val secondary = player.getSecondaryHandItem()
        val row =
            StringBuilder(inventoryPrefix("lifecycle", player, actor))
                .append(",\"actionId\":")
                .append(inventoryActionId(action))
                .append(",\"method\":")
                .append(jsonString(event))
                .append(",\"stage\":")
                .append(jsonString(stage))
                .append(",\"actionType\":")
                .append(jsonString(action.getMetaType()))
                .append(",\"sourceType\":")
                .append(jsonString(table.rawget("sourceType") as String?))
                .append(",\"id\":")
                .append((cartId).toInt())
                .append(",\"time\":")
                .append(action.getCurrentTime())
                .append(",\"maxTime\":")
                .append(action.maxTime)
                .append(",\"luaMaxTime\":")
                .append(
                    if (
                        table.rawget("maxTime") is Number &&
                            java.lang.Double.isFinite(
                                (table.rawget("maxTime") as Number).toDouble(),
                            )
                    )
                        (table.rawget("maxTime") as Number)
                    else "null",
                )
                .append(",\"luaCharacterExact\":")
                .append(table.rawget("character") === player)
                .append(",\"progress\":")
                .append(action.getJobDelta())
                .append(",\"finished\":")
                .append(action.finished())
                .append(",\"waitForFinished\":")
                .append(action.waitForFinished)
                .append(",\"transactionId\":")
                .append(transaction)
                .append(",\"networkOwnerID\":")
                .append(networkPlayer.getID())
                .append(",\"networkActionPresent\":")
                .append(networkAction != null)
                .append(",\"networkActionExact\":")
                .append(networkExact)
                .append(",\"networkActionType\":")
                .append(jsonString(if (networkAction == null) null else networkAction.type))
                .append(",\"networkDone\":")
                .append(networkDone)
                .append(",\"networkRejected\":")
                .append(networkRejected)
                .append(",\"forceStop\":")
                .append(action.forceStop)
                .append(",\"forceComplete\":")
                .append(action.forceComplete)
                .append(",\"threw\":")
                .append(thrown != null)
                .append(",\"primaryID\":")
                .append(if (primary == null) -1 else primary.getID())
                .append(",\"secondaryID\":")
                .append(if (secondary == null) -1 else secondary.getID())
                .append("}\n")
        inventoryEquip!!.write(row.toString())
        inventoryEquip!!.flush()
    }

    object InventoryLifecycle {
        @Advice.OnMethodEnter(suppress = Throwable::class)
        @JvmStatic
        fun enter(
            @Advice.This action: zombie.characters.CharacterTimedActions.LuaTimedActionNew,
            @Advice.Origin("#m") method: String?,
        ) {
            ClearanceProbe.inventoryLifecycle(action, method, "enter", null)
        }

        @Advice.OnMethodExit(onThrowable = Throwable::class, suppress = Throwable::class)
        @JvmStatic
        fun exit(
            @Advice.This action: zombie.characters.CharacterTimedActions.LuaTimedActionNew,
            @Advice.Origin("#m") method: String?,
            @Advice.Thrown thrown: Throwable?,
        ) {
            ClearanceProbe.inventoryLifecycle(action, method, "exit", thrown)
        }
    }

    @Synchronized
    @JvmStatic
    private fun inventorySnapshot(slot: ModelSlotRenderData) {
        val player = slot.character as? zombie.characters.IsoPlayer ?: return
        val actor = inventoryActor(player)
        val now = System.nanoTime()
        if (actor == null || now - inventorySample < 33_333_333L) return
        for (body in slot.modelData) {
            val instance = body.modelInstance
            if (
                instance == null ||
                    instance.parent != null ||
                    body.matrixPalette == null ||
                    !(instance.model.tag is SkinningData)
            )
                continue
            val skin = instance.model.tag as SkinningData
            val primary = player.getPrimaryHandItem()
            val secondary = player.getSecondaryHandItem()
            val row =
                StringBuilder(inventoryPrefix("body", player, actor))
                    .append(",\"captureId\":")
                    .append(++inventoryFrame)
                    .append(",\"primaryID\":")
                    .append(if (primary == null) -1 else primary.getID())
                    .append(",\"secondaryID\":")
                    .append(if (secondary == null) -1 else secondary.getID())
                    .append(",\"x\":")
                    .append(player.getX())
                    .append(",\"y\":")
                    .append(player.getY())
                    .append(",\"z\":")
                    .append(player.getZ())
                    .append(",\"moving\":")
                    .append(player.isPlayerMoving())
                    .append(",\"nativeActions\":")
                    .append(player.getCharacterActions().size)
                    .append(",\"readiness\":")
                    .append(inventoryReadiness(player))
                    .append(",\"models\":[")
            var comma = false
            for (data in slot.modelData) {
                val model = if (data.modelInstance == null) null else data.modelInstance.model
                if (model == null) continue
                if (comma) row.append(',')
                comma = true
                row.append(jsonString(if (model.mesh == null) model.name else model.mesh.fullPath))
            }
            row.append("],\"actions\":[")
            comma = false
            for (current in player.getCharacterActions()) {
                if (!(current is zombie.characters.CharacterTimedActions.LuaTimedActionNew))
                    continue
                if (comma) row.append(',')
                comma = true
                val id = (current).getTable().rawget("cartId")
                row.append("{\"actionId\":")
                    .append(
                        inventoryActionId(
                            (current),
                        ),
                    )
                    .append(",\"type\":")
                    .append(
                        jsonString(
                            (current).getMetaType(),
                        ),
                    )
                    .append(",\"id\":")
                    .append(if (id is Number) (id).toInt() else -1)
                    .append(",\"progress\":")
                    .append(
                        (current).getJobDelta(),
                    )
                    .append('}')
            }
            row.append("],\"bones\":{")
            comma = false
            for (entry in skin.boneIndices.entries) {
                val i = entry.value
                if ((i + 1) * 16 > body.matrixPalette.limit())
                    throw IllegalStateException("Native equip palette bounds")
                val buffer = body.matrixPalette.duplicate()
                buffer.position(i * 16)
                val raw = org.lwjgl.util.vector.Matrix4f()
                raw.load(buffer)
                val pose =
                    PZMath.convertMatrix(raw, Matrix4f())
                        .transpose()
                        .mul(
                            PZMath.convertMatrix(skin.boneOffset.get(i), Matrix4f())
                                .transpose()
                                .invert(),
                        )
                if (!pose.isFinite()) throw IllegalStateException("Native equip nonfinite pose")
                if (comma) row.append(',')
                comma = true
                row.append(jsonString(entry.key)).append(':')
                matrix(row, pose)
            }
            row.append("},\"tracks\":[")
            comma = false
            for (track in instance.animPlayer.getMultiTrack().getTracks()) {
                if (comma) row.append(',')
                comma = true
                row.append("{\"id\":")
                    .append(track.getId())
                    .append(",\"name\":")
                    .append(jsonString(track.getName()))
                    .append(",\"time\":")
                    .append(track.getCurrentTrackTime())
                    .append(",\"weight\":")
                    .append(track.getBlendWeight())
                    .append('}')
            }
            row.append("]}\n")
            inventoryEquip!!.write(row.toString())
            inventoryEquip!!.flush()
            inventorySample = now
            return
        }
    }

    // Main is installed by CartLab on server and both clients. Resolve once at
    // attachment; the probe is compiled independently from the composed Main.
    private fun timelineFrame(
        event: String?,
        slot: ModelSlotRenderData,
        frame: DrawFrame,
        part: String?,
    ) {
        if (!TIMELINE || timelineBridge == null) return
        try {
            val shared =
                (",\"captureId\":" +
                    frame.id +
                    ",\"slotToken\":" +
                    System.identityHashCode(slot) +
                    ",\"preparedPrimary\":" +
                    frame.preparedPrimary +
                    ",\"preparedSecondary\":" +
                    frame.preparedSecondary +
                    ",\"nativeMonoNs\":" +
                    frame.nativePose.mono +
                    ",\"nativeServerNs\":" +
                    frame.nativePose.server +
                    ",\"nativeClockReady\":" +
                    frame.nativePose.ready +
                    ",\"part\":" +
                    jsonString(part) +
                    frame.nativePose.inputFields)
            val owner = frame.nativePose.player
            val main = timelineBridge!!.getDeclaringClass()
            val pose = main.getMethod("timelinePose", String::class.java, String::class.java)
            for (state in
                arrayOf<Array<String?>>(
                    arrayOf<String?>("ToolkitCartPose", frame.motion),
                    arrayOf<String?>("ToolkitCartActionPose", frame.action),
                )) timelineBridge!!.invoke(
                null,
                event,
                owner,
                shared + (pose.invoke(null, state[0], state[1]) as String?),
            )
        } catch (error: Throwable) {
            System.err.println("[CART_TIMELINE] ERROR render bridge " + error)
        }
    }

    @JvmRecord
    private data class NativePose(
        val player: zombie.characters.IsoPlayer,
        val wall: Long,
        val mono: Long,
        val server: Long,
        val ready: Boolean,
        val x: Float,
        val y: Float,
        val z: Float,
        val heading: Float,
        val angle: Float,
        val inputFields: String,
    )

    @JvmRecord
    private data class Hands(val item: zombie.inventory.InventoryItem?, val changed: Long)

    @JvmStatic
    private fun rememberHands(player: zombie.characters.IsoPlayer, now: Long) {
        val item = player.getPrimaryHandItem()
        val previous = hands.get(player)
        if (previous == null || previous.item !== item) hands.put(player, Hands(item, now))
    }

    @JvmRecord
    private data class ConsumedCamera(
        val camera: zombie.core.skinnedmodel.ModelCamera,
        val wall: Long,
        val x: Float,
        val y: Float,
        val z: Float,
        val angle: Float,
        val world: Boolean,
        val vehicle: Boolean,
    )

    private class DrawFrame(
        val id: Long,
        val wall: Long,
        val nativePose: NativePose,
        val body: ModelInstance,
        val cart: ModelInstance,
    ) {
        // Ownership at preparation belongs to this frozen body/cart slot.
        val preparedPrimary: Int
        val preparedSecondary: Int
        val motion: String?
        val action: String?
        var bodyDrawn: Boolean = false
        var cartDrawn: Boolean = false

        init {
            val primary = nativePose.player.getPrimaryHandItem()
            val secondary = nativePose.player.getSecondaryHandItem()
            motion = if (TIMELINE) nativePose.player.getVariableString("ToolkitCartPose") else null
            action =
                if (TIMELINE) nativePose.player.getVariableString("ToolkitCartActionPose") else null
            preparedPrimary = if (primary == null) -1 else primary.getID()
            preparedSecondary = if (secondary == null) -1 else secondary.getID()
        }
    }

    private fun slotField(slot: ModelSlotRenderData, name: String): Float {
        val field = ModelSlotRenderData::class.java.getDeclaredField(name)
        field.setAccessible(true)
        return field.getFloat(slot)
    }

    private fun nativeInputSnapshot(player: zombie.characters.IsoPlayer?): String {
        if (!TIMELINE) return ""
        // Freeze proxy input provenance with the original native pose and body/cart
        // DrawFrame. This does not exclusively attribute blended skeletal tracks.
        try {
            return (timelineInputBridge!!.invoke(null, player) as String +
                (if (OBSERVER_ASSOCIATION) observerBridge!!.invoke(null, player) as String else ""))
        } catch (error: Throwable) {
            System.err.println("[CART_TIMELINE] ERROR native input bridge " + error)
            return ""
        }
    }

    @Synchronized
    @JvmStatic
    fun rememberNative(
        slot: ModelSlotRenderData?,
        source: zombie.core.skinnedmodel.ModelManager.ModelSlot?,
    ) {
        nativePoses.remove(slot)
        drawFrames.remove(slot)
        if (output == null || source == null) return
        val player = source.character as? zombie.characters.IsoPlayer ?: return
        rememberHands(player, System.nanoTime())
        val heading = player.getDirectionAngleRadians()
        val animation = player.getAnimationPlayer()
        val angle =
            if (animation == null) heading + (Math.PI / 2).toFloat()
            else animation.getRenderedAngle()
        val inputFields = nativeInputSnapshot(player)
        nativePoses.put(
            slot,
            NativePose(
                player,
                System.currentTimeMillis(),
                System.nanoTime(),
                zombie.GameTime.getServerTime(),
                zombie.GameTime.getServerTimeShiftIsSet(),
                player.getX(),
                player.getY(),
                player.getZ(),
                heading,
                angle,
                inputFields,
            ),
        )
    }

    @JvmStatic
    private fun prepareDraw(
        slot: ModelSlotRenderData,
        body: ModelInstance,
        cart: ModelInstance,
    ): DrawFrame {
        val pose = nativePoses.get(slot)
        if (pose == null || slot.character !== pose.player)
            throw IllegalStateException("Missing original native slot pose")
        val frame = DrawFrame(++captureSerial, System.currentTimeMillis(), pose, body, cart)
        drawFrames.put(slot, frame)
        timelineFrame("capture-prepared", slot, frame, "both")
        return frame
    }

    private fun renderFields(slot: ModelSlotRenderData, frame: DrawFrame): String {
        val nativePose = frame.nativePose
        val expected =
            zombie.iso.IsoDepthHelper.getSquareDepthData(
                    Math.floor(slotField(slot, "camCharacterX").toDouble()).toInt(),
                    Math.floor(slotField(slot, "camCharacterY").toDouble()).toInt(),
                    slot.x + slotField(slot, "fixJigglyModelsSquareX"),
                    slot.y + slotField(slot, "fixJigglyModelsSquareY"),
                    slot.z,
                )
                .depthStart
        return StringBuilder(512)
            .append(",\"renderProbeVersion\":1,\"captureId\":")
            .append(frame.id)
            .append(",\"slotToken\":")
            .append(System.identityHashCode(slot))
            .append(",\"nativeWallTimeMillis\":")
            .append(nativePose.wall)
            .append(",\"nativeX\":")
            .append(nativePose.x)
            .append(",\"nativeY\":")
            .append(nativePose.y)
            .append(",\"nativeZ\":")
            .append(nativePose.z)
            .append(",\"nativeHeading\":")
            .append(nativePose.heading)
            .append(",\"nativeRenderAngle\":")
            .append(nativePose.angle)
            .append(",\"squareDepth\":")
            .append(slot.squareDepth)
            .append(",\"expectedSquareDepth\":")
            .append(expected)
            .toString()
    }

    @JvmStatic
    fun beginCamera(camera: zombie.core.skinnedmodel.ModelCamera) {
        consumedCamera.set(
            ConsumedCamera(
                camera,
                System.currentTimeMillis(),
                camera.x,
                camera.y,
                camera.z,
                camera.useAngle,
                camera.useWorldIso,
                camera.inVehicle,
            ),
        )
    }

    @JvmStatic
    fun endCamera() {
        consumedCamera.remove()
    }

    @Synchronized
    @JvmStatic
    fun draw(slot: ModelSlotRenderData?, data: ModelInstanceRenderData?) {
        if (cameras == null || data == null) return
        val frame = drawFrames.get(slot)
        if (frame == null) return
        val body = data.modelInstance === frame.body
        val cart = data.modelInstance === frame.cart
        if (!body && !cart || body && frame.bodyDrawn || cart && frame.cartDrawn) return
        val consumed = consumedCamera.get()
        val camera = zombie.core.skinnedmodel.ModelCamera.instance
        if (
            consumed == null ||
                camera !== consumed.camera ||
                slot!!.character !== frame.nativePose.player
        )
            throw IllegalStateException("Draw lacks matching consumed native camera/actor")
        val livePrimary = frame.nativePose.player.getPrimaryHandItem()
        val liveSecondary = frame.nativePose.player.getSecondaryHandItem()
        val row =
            StringBuilder(1024)
                .append("{\"renderProbeVersion\":1,\"captureId\":")
                .append(frame.id)
                .append(",\"slotToken\":")
                .append(System.identityHashCode(slot))
                .append(",\"id\":")
                .append(frame.nativePose.player.getOnlineID())
                .append(",\"preparedPrimary\":")
                .append(frame.preparedPrimary)
                .append(",\"preparedSecondary\":")
                .append(frame.preparedSecondary)
                .append(",\"primary\":")
                .append(if (livePrimary == null) -1 else livePrimary.getID())
                .append(",\"secondary\":")
                .append(if (liveSecondary == null) -1 else liveSecondary.getID())
                .append(",\"model\":")
                .append(
                    jsonString(
                        if (data.modelInstance.modelScript == null) null
                        else data.modelInstance.modelScript.getName(),
                    ),
                )
                .append(",\"part\":")
                .append(jsonString(if (body) "body" else "cart"))
                .append(",\"captureWallTimeMillis\":")
                .append(frame.wall)
                .append(",\"cameraWallTimeMillis\":")
                .append(consumed.wall)
                .append(",\"wallTimeMillis\":")
                .append(System.currentTimeMillis())
                .append(",\"cameraX\":")
                .append(consumed.x)
                .append(",\"cameraY\":")
                .append(consumed.y)
                .append(",\"cameraZ\":")
                .append(consumed.z)
                .append(",\"cameraAngle\":")
                .append(consumed.angle)
                .append(",\"cameraWorldIso\":")
                .append(consumed.world)
                .append(",\"cameraInVehicle\":")
                .append(consumed.vehicle)
                .append(",\"currentCameraX\":")
                .append(camera.x)
                .append(",\"currentCameraY\":")
                .append(camera.y)
                .append(",\"currentCameraZ\":")
                .append(camera.z)
                .append(",\"currentCameraAngle\":")
                .append(camera.useAngle)
                .append(",\"slotX\":")
                .append(slot.x)
                .append(",\"slotY\":")
                .append(slot.y)
                .append(",\"slotZ\":")
                .append(slot.z)
                .append(",\"slotAngle\":")
                .append(slot.animPlayerAngle)
                .append(",\"squareDepth\":")
                .append(slot.squareDepth)
                .append(",\"depthBias\":")
                .append(data.depthBias)
                .append("}\n")
        cameras!!.write(row.toString())
        cameras!!.flush()
        timelineFrame("draw-consumed", slot, frame, if (body) "body" else "cart")
        if (body) frame.bodyDrawn = true else frame.cartDrawn = true
    }

    object NativeCapture {
        @Advice.OnMethodEnter
        @JvmStatic
        fun enter(
            @Advice.This slot: ModelSlotRenderData,
            @Advice.Argument(0) source: zombie.core.skinnedmodel.ModelManager.ModelSlot?,
        ) {
            ClearanceProbe.rememberNative(slot, source)
        }
    }

    object CameraBegin {
        @Advice.OnMethodEnter
        @JvmStatic
        fun enter(@Advice.This camera: zombie.core.skinnedmodel.ModelCamera) {
            ClearanceProbe.beginCamera(camera)
        }
    }

    object CameraEnd {
        @Advice.OnMethodExit
        @JvmStatic
        fun exit() {
            ClearanceProbe.endCamera()
        }
    }

    object ActualDraw {
        @Advice.OnMethodEnter
        @JvmStatic
        fun enter(
            @Advice.Argument(0) slot: ModelSlotRenderData?,
            @Advice.Argument(1) data: ModelInstanceRenderData?,
        ) {
            try {
                ClearanceProbe.draw(slot, data)
            } catch (e: Throwable) {
                System.err.println("[CLEARANCE_PROBE] ERROR " + e)
            }
        }
    }

    @JvmStatic
    private fun cartModel(name: String?): Boolean =
        when (name) {
            "WheelbarrowWood",
            "WheelbarrowMetal",
            "ShoppingCartModel",
            "ShoppingCartPartialModel",
            "ShoppingCartFullModel",
            "ShoppingCartFlashlightModel",
            "ShoppingCartFlashlightPartialModel",
            "ShoppingCartFlashlightFullModel" -> true
            else -> false
        }

    @JvmStatic
    private fun cartFamily(type: String, model: String): Boolean =
        when (type) {
            "SaucedCarts.ShoppingCart" -> model.startsWith("ShoppingCart")
            "SaucedWheelbarrow.WheelbarrowWood" -> model == "WheelbarrowWood"
            "SaucedWheelbarrow.WheelbarrowMetal" -> model == "WheelbarrowMetal"
            else -> false
        }

    @JvmStatic
    private fun captureModel(item: zombie.inventory.InventoryItem?, actual: String): Boolean {
        // Pickup presentation renders its exact cart while native hands are still empty.
        return if (item == null)
            "WheelbarrowWood".equals(actual) || "WheelbarrowMetal".equals(actual)
        else cartFamily(item.getFullType(), actual)
    }

    private fun longState(state: Any?, name: String): Long {
        val value = stateField(state, name)
        check(value is Long) { "Expected native long field: $name" }
        return value
    }

    private fun floatState(state: Any?, name: String): Float {
        val value = stateField(state, name)
        check(value is Float) { "Expected native float field: $name" }
        return value
    }

    @JvmStatic
    private fun stateField(state: Any?, name: String): Any? {
        val field = state!!.javaClass.getDeclaredField(name)
        field.setAccessible(true)
        return field.get(state)
    }

    private fun handoffFields(player: zombie.characters.IsoPlayer): String {
        synchronized(net.alexredby.pztoolkitjavapatches.CartTransition::class.java) {
            val type = net.alexredby.pztoolkitjavapatches.CartTransition::class.java
            val field = type.getDeclaredField("pickupHandoffs")
            field.setAccessible(true)
            val token = (field.get(null) as Map<*, *>).get(player)
            val statesField = type.getDeclaredField("states")
            statesField.setAccessible(true)
            val state = (statesField.get(null) as Map<*, *>).get(player)
            val flags =
                (",\"handoffPresent\":" +
                    (token != null) +
                    ",\"transitionPresent\":" +
                    (state != null) +
                    ",\"performing\":" +
                    player.getVariableBoolean("IsPerformingAnAction") +
                    ",\"performingAction\":" +
                    jsonString(player.getVariableString("PerformingAction")) +
                    ",\"nativeActionCount\":" +
                    player.getCharacterActions().size +
                    ",\"forceNullOverride\":" +
                    player.forceNullOverride)
            if (token == null) return flags
            val source = stateField(token, "source")
            return (flags +
                ",\"handoffPerformed\":" +
                stateField(token, "performed") +
                ",\"handoffReceipted\":" +
                stateField(token, "receipted") +
                ",\"handoffHeldExact\":" +
                (stateField(token, "held") === player.getPrimaryHandItem()) +
                ",\"handoffDeadlineMs\":" +
                (((longState(token, "deadline")) - System.nanoTime()) / 1_000_000L) +
                ",\"handoffRemote\":" +
                stateField(source, "remote"))
        }
    }

    // Exact method boundaries; getters/reflection only, never a render or production gateway call.
    @JvmStatic
    fun pickupBoundary(method: String?, stage: String?, args: Array<Any?>?, thrown: Throwable?) {
        try {
            if (handoffEvents == null) return
            val actualArgs = args!!
            val player: zombie.characters.IsoPlayer?
            var state: Any? = null
            var scope: Any? = null
            var performed: zombie.characters.CharacterTimedActions.LuaTimedActionNew? = null
            if ("pickupPerformed".equals(method)) {
                performed =
                    actualArgs[0] as zombie.characters.CharacterTimedActions.LuaTimedActionNew
                val actor = performed.chr as? zombie.characters.IsoPlayer ?: return
                player = actor
                scope = actualArgs[1]
            } else {
                player = actualArgs[0] as zombie.characters.IsoPlayer?
                if ("rememberPickup".equals(method)) state = actualArgs[1]
            }
            if (player == null) return
            val row: String?
            synchronized(net.alexredby.pztoolkitjavapatches.CartTransition::class.java) {
                val type = net.alexredby.pztoolkitjavapatches.CartTransition::class.java
                val field = type.getDeclaredField("pickupHandoffs")
                field.setAccessible(true)
                val token = (field.get(null) as Map<*, *>).get(player)
                val statesField = type.getDeclaredField("states")
                statesField.setAccessible(true)
                val current = (statesField.get(null) as Map<*, *>).get(player)
                if (state == null)
                    state =
                        if (current != null) current
                        else if (token == null) null else stateField(token, "source")
                val primary = player.getPrimaryHandItem()
                val secondary = player.getSecondaryHandItem()
                val network = player.getNetworkCharacterAI()
                val networkAction = if (network == null) null else network.getAction()
                val actions = player.getCharacterActions()
                val out =
                    StringBuilder(3000)
                        .append("{\"wallTimeMillis\":")
                        .append(System.currentTimeMillis())
                        .append(",\"event\":")
                        .append(jsonString(method))
                        .append(",\"stage\":")
                        .append(jsonString(stage))
                        .append(",\"id\":")
                        .append(player.getOnlineID())
                        .append(",\"local\":")
                        .append(player.isLocalPlayer())
                        .append(",\"methodThrew\":")
                        .append(thrown != null)
                        .append(",\"scopePresent\":")
                        .append(scope != null)
                        .append(",\"primary\":")
                        .append(if (primary == null) -1 else primary.getID())
                        .append(",\"secondary\":")
                        .append(if (secondary == null) -1 else secondary.getID())
                        .append(",\"primaryIdentity\":")
                        .append(System.identityHashCode(primary))
                        .append(",\"secondaryExact\":")
                        .append(primary != null && primary === secondary)
                        .append(",\"primaryOwned\":")
                        .append(
                            primary != null &&
                                primary.getContainer() === player.getInventory() &&
                                primary.getWorldItem() == null,
                        )
                        .append(",\"overridePrimary\":")
                        .append(jsonString(player.overridePrimaryHandModel))
                        .append(",\"overrideSecondary\":")
                        .append(jsonString(player.overrideSecondaryHandModel))
                        .append(",\"hideWeapon\":")
                        .append(player.isHideWeaponModel())
                        .append(",\"hideHandR\":")
                        .append(player.isHideEquippedHandR())
                        .append(",\"npc\":")
                        .append(player.isNpc())
                        .append(",\"sneaking\":")
                        .append(player.isSneaking())
                        .append(",\"walkInjury\":")
                        .append(player.getVariableFloat("WalkInjury", 0f))
                        .append(",\"unsafe\":")
                        .append(
                            (player.isDead() ||
                                player.isAiming() ||
                                player.hasHitReaction() ||
                                player.isKnockedDown() ||
                                player.isGettingUp() ||
                                player.getVehicle() != null ||
                                player.isCurrentState(
                                    zombie.ai.states.CollideWithWallState.instance(),
                                ) ||
                                player.isGrappling() ||
                                player.isBeingGrappled() ||
                                player.isRagdollSimulationActive()),
                        )
                        .append(",\"client\":")
                        .append(zombie.network.GameClient.client)
                        .append(",\"connected\":")
                        .append(
                            zombie.network.GameClient.client &&
                                zombie.network.GameClient.connection != null &&
                                zombie.network.GameClient.instance.connected,
                        )
                        .append(",\"onlineExact\":")
                        .append(
                            zombie.network.GameClient.IDToPlayerMap.get(player.getOnlineID()) ===
                                player,
                        )
                        .append(",\"receiptConnectionExact\":")
                        .append(
                            "pickupEquipped".equals(method) &&
                                actualArgs[1] === zombie.network.GameClient.connection,
                        )
                        .append(",\"statePresent\":")
                        .append(state != null)
                        .append(",\"stateIsCurrent\":")
                        .append(state != null && state === current)
                        .append(",\"networkActionIdentity\":")
                        .append(System.identityHashCode(networkAction))
                        .append(handoffFields(player))
                if (scope != null)
                    out.append(",\"scopeFailed\":")
                        .append(stateField(scope, "failed"))
                        .append(",\"scopeActionExact\":")
                        .append(
                            performed != null &&
                                stateField(scope, "action") === performed.getTable(),
                        )
                        .append(",\"scopeCallbackExact\":")
                        .append(
                            performed != null &&
                                stateField(scope, "callback") ===
                                    performed.getTable().rawget("perform"),
                        )
                if (state != null) {
                    val item = stateField(state, "item") as zombie.inventory.InventoryItem?
                    val owner =
                        stateField(state, "actionOwner")
                            as zombie.characters.CharacterTimedActions.BaseAction?
                    val nativeLua =
                        owner as? zombie.characters.CharacterTimedActions.LuaTimedActionNew
                    val table = if (nativeLua == null) null else nativeLua.getTable()
                    val model =
                        if (item == null) null
                        else
                            zombie.scripting.ScriptManager.instance.getModelScript(
                                item.getStaticModel(),
                            )
                    val override =
                        if (player.overridePrimaryHandModel == null) null
                        else
                            zombie.scripting.ScriptManager.instance.getModelScript(
                                player.overridePrimaryHandModel,
                            )
                    val now = System.nanoTime()
                    out.append(",\"stateIdentity\":")
                        .append(System.identityHashCode(state))
                        .append(",\"sourceID\":")
                        .append(if (item == null) -1 else item.getID())
                        .append(",\"sourceIdentity\":")
                        .append(System.identityHashCode(item))
                        .append(",\"sourceType\":")
                        .append(jsonString(if (item == null) null else item.getFullType()))
                        .append(",\"sourceStaticModel\":")
                        .append(jsonString(if (item == null) null else item.getStaticModel()))
                        .append(",\"sourceModelName\":")
                        .append(jsonString(if (model == null) null else model.getName()))
                        .append(",\"sourceModelModule\":")
                        .append(
                            jsonString(
                                if (model == null || model.getModule() == null) null
                                else model.getModule().name,
                            ),
                        )
                        .append(",\"sourceOverrideModelExact\":")
                        .append(model != null && model === override)
                        .append(",\"sourceRemote\":")
                        .append(stateField(state, "remote"))
                        .append(",\"sourcePickup\":")
                        .append(stateField(state, "pickup"))
                        .append(",\"sourceRecovering\":")
                        .append(stateField(state, "recovering"))
                        .append(",\"sourceRendered\":")
                        .append(stateField(state, "rendered"))
                        .append(",\"sourceHandoffRemembered\":")
                        .append(stateField(state, "handoffRemembered"))
                        .append(",\"sourceWorldPresent\":")
                        .append(stateField(state, "world") != null)
                        .append(",\"sourceRenderAgeMs\":")
                        .append((now - (longState(state, "lastRender"))) / 1_000_000.0)
                        .append(",\"sourceUpdateAgeMs\":")
                        .append((now - (longState(state, "updated"))) / 1_000_000.0)
                        .append(",\"sourceConnectionExact\":")
                        .append(
                            stateField(state, "connection") ===
                                zombie.network.GameClient.connection,
                        )
                        .append(",\"ownerPresent\":")
                        .append(owner != null)
                        .append(",\"ownerIdentity\":")
                        .append(System.identityHashCode(owner))
                        .append(",\"ownerClass\":")
                        .append(jsonString(if (owner == null) null else owner.javaClass.getName()))
                        .append(",\"ownerChrExact\":")
                        .append(owner != null && owner.chr === player)
                        .append(",\"ownerLocalActionExact\":")
                        .append(owner != null && actions.size == 1 && actions.get(0) === owner)
                        .append(",\"ownerNetworkExact\":")
                        .append(owner != null && networkAction === owner)
                        .append(",\"ownerPerformedExact\":")
                        .append(owner != null && performed === owner)
                        .append(",\"ownerMetaType\":")
                        .append(
                            jsonString(if (nativeLua == null) null else nativeLua.getMetaType()),
                        )
                        .append(",\"ownerTableCharacterExact\":")
                        .append(table != null && table.rawget("character") === player)
                        .append(",\"ownerTableItemID\":")
                        .append(
                            jsonString(
                                if (table == null) null
                                else java.lang.String.valueOf(table.rawget("itemId")),
                            ),
                        )
                }
                row = out.append("}\n").toString()
            }
            synchronized(handoffOutputLock) {
                if (handoffEvents != null) {
                    handoffEvents!!.write(row)
                    handoffEvents!!.flush()
                }
            }
        } catch (error: Throwable) {
            System.err.println("[CLEARANCE_PROBE] ERROR pickup boundary " + error)
            error.printStackTrace()
        }
    }

    object PickupBoundary {
        @Advice.OnMethodEnter
        @JvmStatic
        fun enter(@Advice.Origin("#m") method: String?, @Advice.AllArguments args: Array<Any?>?) {
            ClearanceProbe.pickupBoundary(method, "enter", args, null)
        }

        @Advice.OnMethodExit(onThrowable = Throwable::class)
        @JvmStatic
        fun exit(
            @Advice.Origin("#m") method: String?,
            @Advice.AllArguments args: Array<Any?>?,
            @Advice.Thrown thrown: Throwable?,
        ) {
            ClearanceProbe.pickupBoundary(method, "exit", args, thrown)
        }
    }

    @JvmStatic
    private fun transitionItem(
        player: zombie.characters.IsoPlayer,
    ): zombie.inventory.InventoryItem? {
        // A shopping attachment with empty hands is not identity evidence by itself.
        // Read the exact, already-rendered pickup state owned by this native player.
        if (player.getPrimaryHandItem() != null || player.getSecondaryHandItem() != null)
            return null
        synchronized(net.alexredby.pztoolkitjavapatches.CartTransition::class.java) {
            val field =
                net.alexredby.pztoolkitjavapatches.CartTransition::class
                    .java
                    .getDeclaredField("states")
            field.setAccessible(true)
            val state = (field.get(null) as Map<*, *>).get(player)
            if (
                state == null ||
                    !((stateField(state, "pickup") as? Boolean) == true) ||
                    !((stateField(state, "rendered") as? Boolean) == true)
            )
                return null
            val updated = longState(state, "updated")
            val age = System.nanoTime() - updated
            if (age < 0 || age > 1_000_000_000L) return null
            val item = stateField(state, "item") as zombie.inventory.InventoryItem?
            val world = stateField(state, "world")
            if (
                (item == null ||
                    item.getID() < 0 ||
                    world == null ||
                    item.getWorldItem() !== world ||
                    (world).getItem() !== item)
            )
                return null
            return item
        }
    }

    @JvmStatic
    private fun captureDue(
        player: zombie.characters.IsoPlayer,
        item: zombie.inventory.InventoryItem?,
        now: Long,
    ): Boolean {
        if (now - last >= 33_333_333L) return true
        val seen = hands[player]
        if (
            item != null &&
                seen != null &&
                seen.item === item &&
                now - seen.changed >= 0 &&
                now - seen.changed <= 500_000_000L
        )
            return true
        synchronized(net.alexredby.pztoolkitjavapatches.CartTransition::class.java) {
            val field =
                net.alexredby.pztoolkitjavapatches.CartTransition::class
                    .java
                    .getDeclaredField("states")
                    .apply { isAccessible = true }
            val state = (field.get(null) as Map<*, *>)[player]
            if (
                state == null ||
                    item == null ||
                    stateField(state, "item") !== item ||
                    (stateField(state, "rendered") as? Boolean) != true ||
                    (stateField(state, "ik") as? Boolean) != true ||
                    (stateField(state, "recovering") as? Boolean) == true ||
                    !(floatState(state, "progress") > 0)
            )
                return false
            val age = now - longState(state, "updated")
            if (age < 0 || age > 1_000_000_000L) return false
            if ((stateField(state, "pickup") as? Boolean) == true) {
                val world = stateField(state, "world")
                return player.getPrimaryHandItem() == null &&
                    player.getSecondaryHandItem() == null &&
                    item.getID() >= 0 &&
                    world != null &&
                    item.getWorldItem() === world &&
                    (world).getItem() === item
            }
            return player.getPrimaryHandItem() === item && player.getSecondaryHandItem() === item
        }
    }

    @JvmStatic
    private fun jsonString(value: String?): String {
        if (value == null) return "null"
        val out = StringBuilder("\"")
        for (c in value.toCharArray()) {
            if (c == '\\' || c == '\"') out.append('\\').append(c)
            else if (c.code < 32) out.append(String.format("\\u%04x", c.code)) else out.append(c)
        }
        return out.append('"').toString()
    }

    private fun matrix(row: StringBuilder, value: Matrix4f) {
        val v = value.get(FloatArray(16))
        row.append('[')
        for (i in 0..15) {
            if (i > 0) row.append(',')
            row.append(v[i])
        }
        row.append(']')
    }

    @Synchronized
    @JvmStatic
    fun snapshot(slot: ModelSlotRenderData?) {
        if (INVENTORY_EQUIP) inventorySnapshot(slot!!)
        if (output == null) return
        val player = slot!!.character as? zombie.characters.IsoPlayer ?: return
        if (!nativePoses.containsKey(slot) || drawFrames.containsKey(slot)) return
        for (cart in slot.modelData) {
            val instance = cart.modelInstance
            if (
                (instance == null ||
                    instance.parent == null ||
                    instance.modelScript == null ||
                    !cartModel(instance.modelScript.getName()))
            )
                continue
            var item: zombie.inventory.InventoryItem? = player.getPrimaryHandItem()
            val held = if (item == null) null else item.getStaticModel()
            val actual = instance.modelScript.getName()
            val transition = item == null
            if (transition) item = transitionItem(player)
            if (item == null) continue
            if (!captureModel(item, actual) || !captureDue(player, item, System.nanoTime()))
                continue
            for (body in slot.modelData) {
                if (
                    (body.modelInstance !== instance.parent ||
                        body.matrixPalette == null ||
                        !(body.modelInstance.model.tag is SkinningData))
                )
                    continue
                val skin = body.modelInstance.model.tag as SkinningData
                var modelCount = 0
                for (candidate in slot.modelData) if (
                    (candidate.modelInstance != null &&
                        candidate.modelInstance.parent != null &&
                        candidate.modelInstance.modelScript != null &&
                        cartModel(candidate.modelInstance.modelScript.getName()))
                )
                    modelCount++
                val frame = prepareDraw(slot, body.modelInstance, instance)
                val row =
                    StringBuilder(8192)
                        .append("{\"wallTimeMillis\":")
                        .append(frame.wall)
                        .append(renderFields(slot, frame))
                        .append(",\"id\":")
                        .append(player.getOnlineID())
                        .append(",\"local\":")
                        .append(player.isLocalPlayer())
                        .append(",\"enabled\":")
                        .append(
                            net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled(player),
                        )
                        .append(",\"female\":")
                        .append(slot.character.isFemale())
                        .append(",\"visualEnabled\":")
                        .append(
                            net.alexredby.pztoolkitjavapatches.CartMotionSync.visualEnabled(player),
                        )
                        .append(",\"cartModelCount\":")
                        .append(modelCount)
                        .append(handoffFields(player))
                        .append(",\"slotX\":")
                        .append(slot.x)
                        .append(",\"slotY\":")
                        .append(slot.y)
                        .append(",\"slotZ\":")
                        .append(slot.z)
                        .append(",\"slotAngle\":")
                        .append(slot.animPlayerAngle)
                        .append(",\"primary\":")
                        .append(frame.preparedPrimary)
                        .append(",\"secondary\":")
                        .append(frame.preparedSecondary)
                        .append(",\"modelProbeVersion\":1,\"model\":")
                        .append(jsonString(actual))
                        .append(",\"cartItemId\":")
                        .append(item.getID())
                        .append(",\"cartItemSource\":")
                        .append(jsonString(if (transition) "transition" else "hands"))
                        .append(",\"cartItemModel\":")
                        .append(jsonString(item.getStaticModel()))
                        .append(",\"heldModel\":")
                        .append(jsonString(held))
                        .append(",\"overridePrimary\":")
                        .append(jsonString(player.overridePrimaryHandModel))
                        .append(",\"overrideSecondary\":")
                        .append(jsonString(player.overrideSecondaryHandModel))
                        .append(",\"cart\":")
                matrix(row, Matrix4f(cart.xfrm).transpose())
                row.append(",\"bones\":{")
                var comma = false
                for (entry in skin.boneIndices.entries) {
                    val i = entry.value
                    if ((i + 1) * 16 > body.matrixPalette.limit())
                        throw AssertionError("palette bounds")
                    val buffer = body.matrixPalette.duplicate()
                    buffer.position(i * 16)
                    val raw = org.lwjgl.util.vector.Matrix4f()
                    raw.load(buffer)
                    val pose =
                        PZMath.convertMatrix(raw, Matrix4f())
                            .transpose()
                            .mul(
                                PZMath.convertMatrix(skin.boneOffset.get(i), Matrix4f())
                                    .transpose()
                                    .invert(),
                            )
                    if (!pose.isFinite()) throw AssertionError("nonfinite pose")
                    if (comma) row.append(',')
                    comma = true
                    row.append('"').append(entry.key).append("\":")
                    matrix(row, pose)
                }
                row.append("}}\n")
                output!!.write(row.toString())
                output!!.flush()
                last = System.nanoTime()
                return
            }
        }
    }

    // Read the already drawn wooden VBO without changing it or leaving another GL binding active.
    @Synchronized
    @JvmStatic
    fun mesh(slot: ModelSlotRenderData?, data: ModelInstanceRenderData?, rendered: Boolean) {
        if (
            (output == null ||
                meshError ||
                phaseMeshProof ||
                !rendered ||
                !(slot!!.character is zombie.characters.IsoPlayer) ||
                data == null ||
                data.modelInstance == null ||
                data.modelInstance.modelScript == null ||
                !"WheelbarrowWood".equals(data.modelInstance.modelScript.getName()))
        )
            return
        try {
            if (wheelPhase == null) {
                wheelPhase =
                    Class.forName("net.alexredby.pztoolkitjavapatches.CartWheelSpin")
                        .getDeclaredMethod("phase", ModelInstanceRenderData::class.java)
                wheelPhase!!.setAccessible(true)
            }
            val value = wheelPhase!!.invoke(null, data)
            check(value is Double && value.isFinite()) { "Missing native wooden wheel phase" }
            val phase = value
            if (
                meshProof &&
                    Math.abs(Math.IEEEremainder(phase - firstMeshPhase, Math.PI * 2)) <= .25
            )
                return
            val vb = data.modelInstance.model.mesh.vb
            val field = vb.javaClass.getDeclaredField("handle")
            field.setAccessible(true)
            val handle = field.get(vb) as VertexBufferObject.Vbo
            val old = GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING)
            val raw: ByteArray
            val bytes: Int
            try {
                GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, handle.vboId)
                bytes = GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER, GL15.GL_BUFFER_SIZE)
                if (bytes != 8116 * 32 || handle.numElements != 16914)
                    throw IllegalStateException(
                        "Unexpected native wooden VBO layout: " +
                            bytes +
                            " / " +
                            handle.numElements,
                    )
                val buffer = BufferUtils.createByteBuffer(bytes)
                GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER, 0, buffer)
                raw = ByteArray(bytes)
                buffer.get(raw)
            } finally {
                GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, old)
            }
            val hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw))
            val matches = MESH_SHA.equals(hash)
            if (!meshProof)
                Files.write(
                    directory.resolve("WheelbarrowWood.bin"),
                    raw,
                    StandardOpenOption.CREATE_NEW,
                )
            val proof =
                StringBuilder("{\n  \"wallTimeMillis\": ")
                    .append(System.currentTimeMillis())
                    .append(",\n  \"id\": ")
                    .append((slot.character as zombie.characters.IsoPlayer).getOnlineID())
                    .append(",\n  \"local\": ")
                    .append((slot.character as zombie.characters.IsoPlayer).isLocalPlayer())
                    .append(",\n  \"vboId\": ")
                    .append(handle.vboId)
                    .append(",\n  \"eboId\": ")
                    .append(handle.eboId)
                    .append(",\n  \"bytes\": ")
                    .append(bytes)
                    .append(",\n  \"indices\": ")
                    .append(handle.numElements)
                    .append(",\n  \"phase\": ")
                    .append(phase)
                    .append(",\n  \"proofAfterPhaseChanged\": ")
                    .append(meshProof)
                    .append(",\n  \"sha256\": ")
                    .append(jsonString(hash))
                    .append(",\n  \"matchesOriginal\": ")
                    .append(matches)
            if (meshProof)
                proof
                    .append(",\n  \"initialPhase\": ")
                    .append(firstMeshPhase)
                    .append(",\n  \"initialSha256\": ")
                    .append(jsonString(firstMeshHash))
                    .append(",\n  \"matchesInitial\": ")
                    .append(firstMeshHash.equals(hash))
            Files.writeString(
                directory.resolve(
                    if (meshProof) "wood-wheel-mesh-phase-proof.json"
                    else "wood-wheel-mesh-proof.json",
                ),
                proof.append("\n}\n").toString(),
                StandardOpenOption.CREATE_NEW,
            )
            if (!matches || meshProof && !firstMeshHash.equals(hash))
                throw IllegalStateException("Native wooden wheel mesh changed: " + hash)
            if (meshProof) phaseMeshProof = true
            else {
                meshProof = true
                firstMeshPhase = phase
                firstMeshHash = hash
            }
        } catch (error: Throwable) {
            meshError = true
            System.err.println("[CLEARANCE_PROBE] MESH ERROR " + error)
            error.printStackTrace()
            try {
                Files.writeString(
                    directory.resolve("wood-wheel-mesh-error.json"),
                    "{\"error\":" + jsonString(error.toString()) + "}\n",
                    StandardOpenOption.CREATE_NEW,
                )
            } catch (failure: Throwable) {
                System.err.println("[CLEARANCE_PROBE] MESH ERROR OUTPUT " + failure)
            }
        }
    }

    object Drawing {
        @Advice.OnMethodExit(suppress = Throwable::class)
        @JvmStatic
        fun exit(
            @Advice.Argument(1) slot: ModelSlotRenderData?,
            @Advice.Argument(2) data: ModelInstanceRenderData?,
            @Advice.Return rendered: Boolean,
        ) {
            ClearanceProbe.mesh(slot, data, rendered)
        }
    }

    @JvmStatic
    fun beginSolve(method: String?, slot: ModelSlotRenderData?) {
        if (solves == null) return
        val player = slot!!.character as? zombie.characters.IsoPlayer ?: return
        val status = net.alexredby.pztoolkitjavapatches.CartTransition.status(player)
        val row =
            StringBuilder(2048)
                .append("{\"wallTimeMillis\":")
                .append(System.currentTimeMillis())
                .append(",\"method\":")
                .append(jsonString(method))
                .append(",\"id\":")
                .append(player.getOnlineID())
                .append(",\"local\":")
                .append(player.isLocalPlayer())
                .append(",\"x\":")
                .append(player.getX())
                .append(",\"y\":")
                .append(player.getY())
                .append(",\"progress\":")
                .append(status.rawget("progress"))
                .append(",\"pickup\":")
                .append(status.rawget("pickup"))
                .append(",\"recovering\":")
                .append(status.rawget("recovering"))
                .append(",\"failures\":[")
        solve.set(row)
    }

    @JvmStatic
    fun refusal(method: String?, detail: String?) {
        val row = solve.get()
        if (row == null) return
        if (row[row.length - 1] != '[') row.append(',')
        row.append("{\"method\":").append(jsonString(method))
        if (detail != null) row.append(',').append(detail)
        row.append('}')
    }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun reachInput(args: Array<Any?>?): String? {
        if (solve.get() == null) return null
        val actualArgs = args!!
        val poses = actualArgs[0] as Array<Matrix4f>
        val actor = actualArgs[1] as SkinningData
        val row =
            StringBuilder(2048)
                .append("\"bone\":")
                .append(jsonString(actualArgs[2] as String))
                .append(",\"wood\":")
                .append(actualArgs[5])
                .append(",\"weight\":")
                .append(actualArgs[6])
                .append(",\"target\":")
        matrix(row, actualArgs[3] as Matrix4f)
        row.append(",\"poses\":{")
        var bone = actor.getBone(actualArgs[2] as String)
        var comma = false
        var i = 0
        while (bone != null && i < 4) {
            if (comma) row.append(',')
            comma = true
            row.append(jsonString(bone.name)).append(':')
            matrix(row, poses[bone.index])
            i++
            bone = bone.parent
        }
        return row.append('}').toString()
    }

    @Synchronized
    @JvmStatic
    fun finishSolve(ok: Boolean) {
        val row = solve.get()
        solve.remove()
        if (row == null || solves == null) return
        solves!!.write(row.append("],\"ok\":").append(ok).append("}\n").toString())
        solves!!.flush()
    }

    object Solve {
        @Advice.OnMethodEnter
        @JvmStatic
        fun enter(
            @Advice.Origin("#m") method: String?,
            @Advice.Argument(0) slot: ModelSlotRenderData?,
        ) {
            ClearanceProbe.beginSolve(method, slot)
        }

        @Advice.OnMethodExit(onThrowable = Throwable::class)
        @JvmStatic
        fun exit(@Advice.Return ok: Boolean, @Advice.Thrown thrown: Throwable?) {
            try {
                if (thrown != null) ClearanceProbe.refusal("exception", null)
                ClearanceProbe.finishSolve(ok && thrown == null)
            } catch (e: Throwable) {
                System.err.println("[CLEARANCE_PROBE] ERROR " + e)
            }
        }
    }

    object Refusal {
        @Advice.OnMethodExit
        @JvmStatic
        fun exit(@Advice.Origin("#m") method: String?, @Advice.Return ok: Boolean) {
            if (!ok) ClearanceProbe.refusal(method, null)
        }
    }

    object Reach {
        @Advice.OnMethodEnter
        @JvmStatic
        fun enter(@Advice.AllArguments args: Array<Any?>?): String? {
            return ClearanceProbe.reachInput(args)
        }

        @Advice.OnMethodExit
        @JvmStatic
        fun exit(@Advice.Enter input: String?, @Advice.Return ok: Boolean) {
            if (!ok) ClearanceProbe.refusal("reach", input)
        }
    }

    object Capture {
        @Advice.OnMethodExit(suppress = Throwable::class)
        @JvmStatic
        fun exit(@Advice.Argument(0) slot: ModelSlotRenderData?) {
            try {
                ClearanceProbe.snapshot(slot)
            } catch (e: Throwable) {
                System.err.println("[CLEARANCE_PROBE] ERROR " + e)
            }
        }
    }

    @Synchronized
    @JvmStatic
    fun agentmain(args: String?, instrumentation: Instrumentation) {
        if (output != null) {
            output!!.close()
            output = null
        }
        if (solves != null) {
            solves!!.close()
            solves = null
        }
        if (cameras != null) {
            cameras!!.close()
            cameras = null
        }
        if (inventoryEquip != null) {
            inventoryEquip!!.close()
            inventoryEquip = null
        }
        inventoryActions.clear()
        inventoryUpdates.clear()
        inventoryAttachments.clear()
        nextInventoryAction = 0
        inventoryFrame = nextInventoryAction
        inventorySample = inventoryFrame
        synchronized(handoffOutputLock) {
            if (handoffEvents != null) {
                handoffEvents!!.close()
                handoffEvents = null
            }
        }
        nativePoses.clear()
        drawFrames.clear()
        consumedCamera.remove()
        if ("stop".equals(args)) {
            if (TIMELINE && timelineBridge != null)
                timelineBridge!!.getDeclaringClass().getMethod("timelineStop").invoke(null)
            System.out.println("[CLEARANCE_PROBE] stopped")
            return
        }
        if (args == null || args.isBlank() || !Path.of(args).isAbsolute())
            throw IllegalArgumentException("Agent args: absolute output directory, or stop")
        if (TIMELINE) {
            val main = Class.forName("net.alexredby.cartlab.Multiplayer")
            timelineBridge =
                main.getMethod(
                    "timelineEvent",
                    String::class.java,
                    zombie.characters.IsoPlayer::class.java,
                    String::class.java,
                )
            timelineInputBridge =
                Class.forName("net.alexredby.cartlab.NativeTime")
                    .getMethod("timelineNativeSnapshot", zombie.characters.IsoPlayer::class.java)
            if (OBSERVER_ASSOCIATION)
                observerBridge =
                    Class.forName("net.alexredby.cartlab.ObserverAssociation")
                        .getMethod(
                            "observerAssociationSnapshot",
                            zombie.characters.IsoPlayer::class.java,
                        )
        }
        directory = Path.of(args)
        if (!Files.isDirectory(directory))
            throw IllegalArgumentException("Output directory must exist")
        val file = directory.resolve("body-clearance.jsonl")
        for (name in
            arrayOf<String>(
                "body-clearance.jsonl",
                "transition-solve.jsonl",
                "render-camera.jsonl",
                "pickup-handoff-events.jsonl",
                "WheelbarrowWood.bin",
                "wood-wheel-mesh-proof.json",
                "wood-wheel-mesh-phase-proof.json",
                "wood-wheel-mesh-error.json",
            )) if (Files.exists(directory.resolve(name)))
            throw IllegalStateException("Preserve existing clearance output first: " + name)
        output = Files.newBufferedWriter(file, java.nio.file.StandardOpenOption.CREATE_NEW)
        last = 0
        solves =
            Files.newBufferedWriter(
                directory.resolve("transition-solve.jsonl"),
                java.nio.file.StandardOpenOption.CREATE_NEW,
            )
        cameras =
            Files.newBufferedWriter(
                directory.resolve("render-camera.jsonl"),
                java.nio.file.StandardOpenOption.CREATE_NEW,
            )
        captureSerial = 0
        if (INVENTORY_EQUIP)
            inventoryEquip =
                Files.newBufferedWriter(
                    directory.resolve("inventory-equip-native.jsonl"),
                    java.nio.file.StandardOpenOption.CREATE_NEW,
                )
        synchronized(handoffOutputLock) {
            handoffEvents =
                Files.newBufferedWriter(
                    directory.resolve("pickup-handoff-events.jsonl"),
                    java.nio.file.StandardOpenOption.CREATE_NEW,
                )
        }
        meshError = false
        phaseMeshProof = meshError
        meshProof = phaseMeshProof
        firstMeshHash = null
        firstMeshPhase = 0.0
        if (!installed) {
            AgentBuilder.Default()
                .disableClassFormatChanges()
                .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .with(
                    object : AgentBuilder.Listener.Adapter() {
                        override fun onError(
                            type: String,
                            loader: ClassLoader?,
                            module: net.bytebuddy.utility.JavaModule?,
                            loaded: Boolean,
                            error: Throwable,
                        ) {
                            System.err.println(
                                "[CLEARANCE_PROBE] ERROR transform " + type + " " + error,
                            )
                            error.printStackTrace()
                        }
                    },
                )
                .type(typeNamed("zombie.core.skinnedmodel.model.ModelSlotRenderData"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(
                            Advice.to(NativeCapture::class.java)
                                .on(methodNamed("initModel").and(takesArguments(1))),
                        )
                    },
                )
                .type(typeNamed("zombie.core.opengl.CharacterModelCamera"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(
                            Advice.to(CameraBegin::class.java)
                                .on(methodNamed("Begin").and(takesArguments(0))),
                        )
                    },
                )
                .type(typeNamed("zombie.core.skinnedmodel.model.Model"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(
                                Advice.to(ActualDraw::class.java)
                                    .on(methodNamed("DrawSolid").and(takesArguments(2))),
                            )
                            .visit(
                                Advice.to(CameraEnd::class.java)
                                    .on(
                                        methodNamed("CharacterModelCameraEnd")
                                            .and(takesArguments(0)),
                                    ),
                            )
                    },
                )
                .type(typeNamed("net.alexredby.pztoolkitjavapatches.CartTransition"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(
                            Advice.to(PickupBoundary::class.java)
                                .on(
                                    methodNames(
                                        "rememberPickup",
                                        "pickupPerformed",
                                        "pickupEquipped",
                                    ),
                                ),
                        )
                    },
                )
                .type(typeNamed("zombie.characters.CharacterTimedActions.LuaTimedActionNew"))
                .transform(
                    { b, d, l, m, p ->
                        if (INVENTORY_EQUIP)
                            b.visit(
                                Advice.to(InventoryLifecycle::class.java)
                                    .on(
                                        takesArguments<
                                                net.bytebuddy.description.method.MethodDescription,
                                            >(
                                                0,
                                            )
                                            .and(
                                                methodNames(
                                                    "start",
                                                    "update",
                                                    "perform",
                                                    "complete",
                                                    "stop",
                                                    "interruptWaitToStart",
                                                ),
                                            ),
                                    ),
                            )
                        else b
                    },
                )
                .type(typeNamed("net.alexredby.pztoolkitjavapatches.CartGrounding"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(Advice.to(Capture::class.java).on(methodNamed("render")))
                            .visit(
                                Advice.to(InventoryGrounding::class.java).on(methodNamed("render")),
                            )
                    },
                )
                .type(typeNamed("net.alexredby.pztoolkitjavapatches.CartWheelSpin"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(Advice.to(Drawing::class.java).on(methodNamed("render")))
                    },
                )
                .type(typeNamed("net.alexredby.pztoolkitjavapatches.CartGrip"))
                .transform(
                    { b, d, l, m, p ->
                        b.visit(
                                Advice.to(Solve::class.java)
                                    .on(
                                        methodNames(
                                            "transition",
                                            "authoredTransition",
                                            "movingRecovery",
                                        ),
                                    ),
                            )
                            .visit(
                                Advice.to(Refusal::class.java)
                                    .on(
                                        methodNames(
                                            "nativeHeight",
                                            "nativeRotation",
                                            "bendTransitionTorso",
                                            "groundFeet",
                                            "transitionGrip",
                                        ),
                                    ),
                            )
                            .visit(
                                Advice.to(Reach::class.java)
                                    .on(methodNamed("reach").and(takesArguments(7))),
                            )
                    },
                )
                .installOn(instrumentation)
            installed = true
        }
        System.out.println("[CLEARANCE_PROBE] writing " + file)
    }
}
