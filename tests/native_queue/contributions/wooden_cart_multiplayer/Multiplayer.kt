package net.alexredby.cartlab

import java.io.BufferedWriter
import java.io.IOException
import java.lang.ref.WeakReference
import java.lang.reflect.Field
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.util.ArrayDeque
import java.util.WeakHashMap
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.LongAdder
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.ClockTime.timelineClockRequestFields
import net.alexredby.cartlab.ClockTime.timelineFlushRequests
import net.alexredby.cartlab.ClockTime.timelineRequestsPending
import net.alexredby.cartlab.NativeTime.timelineNativeSnapshot
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.network.fields.character.Prediction
import zombie.network.packets.VariableSyncPacket

/** Opt-in multiplayer diagnostics. These observations never alter packet or equipment authority. */
object Multiplayer {
    @JvmStatic
    private fun mpBraceOwner(player: IsoPlayer?, cartId: Int): Boolean {
        val item = player?.getPrimaryHandItem()
        return zombie.network.GameClient.client &&
            !zombie.network.GameServer.server &&
            zombie.network.GameClient.connection != null &&
            zombie.network.GameClient.instance.connected &&
            player != null &&
            player === IsoPlayer.getInstance() &&
            player.isLocalPlayer() &&
            !player.isDead() &&
            player.getUsername() == "client1" &&
            player.getOnlineID() >= 0 &&
            player.getCurrentSquare() != null &&
            item != null &&
            item.getID() == cartId &&
            item === player.getSecondaryHandItem() &&
            item.getFullType() == "SaucedWheelbarrow.WheelbarrowWood" &&
            player.getInventory() != null &&
            item.getContainer() === player.getInventory()
    }

    @JvmStatic
    @LuaMethod(name = "cartMPBrace", global = true)
    fun mpBrace(player: IsoPlayer?, cartId: Int, wallX: Double, y: Double): String {
        check(mpBraceOwner(player, cartId)) {
            "Live native MP fixture owner and exact held cart required"
        }
        val p = player!!
        val z = Math.floor(p.getZ().toDouble()).toInt()
        val x = wallX.toFloat()
        val fy = y.toFloat()
        require(
            (x + fy).isFinite() &&
                z > 0 &&
                Math.abs(x - p.getX()) <= 16 &&
                Math.abs(fy - p.getY()) <= 16,
        ) {
            "Loaded local upper-pad wall query required"
        }
        val cell = p.getCell()
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
        val hooks = Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks")
        val states = hooks.getDeclaredField("states").apply { isAccessible = true }
        val state = checkNotNull((states.get(null) as Map<*, *>)[p]) { "Cart state required" }
        val amount = state.javaClass.getDeclaredField("brace").apply { isAccessible = true }
        val intent = state.javaClass.getDeclaredField("wantsMove").apply { isAccessible = true }
        val value = amount.getDouble(state)
        check(value.isFinite() && value in 0.0..1.0) { "Invalid brace amount" }
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
        return "brace=$value nativeBlocked=$blocked wantsMove=${intent.getBoolean(state)}"
    }

    @JvmStatic
    fun mpJsonString(value: String?): String {
        if (value == null) return "null"
        return buildString {
            append('"')
            for (c in value) when {
                c == '\\' || c == '"' -> append('\\').append(c)
                c < ' ' -> append(String.format("\\u%04x", c.code))
                else -> append(c)
            }
            append('"')
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartMPSeedSprinting", global = true)
    fun seedSprinting(p: IsoPlayer?): Int {
        check(
            zombie.network.GameServer.server &&
                !zombie.network.GameClient.client &&
                p != null &&
                p.getUsername() == "client1" &&
                !p.isDead() &&
                p.isExistInTheWorld() &&
                zombie.network.GameServer.getConnectionFromPlayer(p) != null,
        ) {
            "Connected fixture owner on the native server required"
        }
        val perk = zombie.characters.skills.PerkFactory.Perks.Sprinting
        p.setPerkLevelDebug(perk, 10)
        p.getXp().setXPToLevel(perk, 10)
        p.getNetworkCharacterAI().updateXpChecker()
        zombie.network.packets.INetworkPacket.send(
            p,
            zombie.network.PacketTypes.PacketType.PlayerXp,
            p,
        )
        return p.getPerkLevel(perk)
    }

    @JvmStatic
    @LuaMethod(name = "cartMPPadHost", global = true)
    fun padHost(): Boolean {
        if (
            !zombie.network.GameServer.server ||
                zombie.network.GameClient.client ||
                zombie.network.CoopSlave.instance == null ||
                zombie.network.GameServer.serverName != "queue-smoke"
        )
            return false
        return try {
            !zombie.network.GameServer::class
                .java
                .getDeclaredField("worldExistedAtStartup")
                .apply { isAccessible = true }
                .getBoolean(null)
        } catch (_: ReflectiveOperationException) {
            false
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartMPInjurySync", global = true)
    fun injurySync(p: IsoPlayer?, cartId: Int): Float {
        val item = p?.getPrimaryHandItem()
        check(
            padHost() &&
                p != null &&
                p.getUsername() == "client1" &&
                !p.isDead() &&
                !p.isGodMod() &&
                p.isExistInTheWorld() &&
                zombie.network.GameServer.getConnectionFromPlayer(p) != null &&
                item != null &&
                item.getID() == cartId &&
                p.getSecondaryHandItem() === item &&
                item.getContainer() === p.getInventory() &&
                net.alexredby.pztoolkitjavapatches.CartSteeringHooks.supportedCart(p),
        ) {
            "Connected exact native Host injury owner/cart required"
        }
        // Native B42 derives injury/rates on the server and sends PlayerInjuries plus
        // full PlayerDamage to the owner. Movement packets relay it to observers.
        p!!.getNetworkCharacterAI().syncDamage()
        return p.getVariableFloat("WalkInjury", 0f)
    }

    @JvmStatic
    @LuaMethod(name = "cartMPState", global = true)
    fun mpState(p: IsoPlayer): String {
        timelineStats(p)
        val a = p.getPrimaryHandItem()
        val b = p.getSecondaryHandItem()
        val network = p.getNetworkCharacterAI()
        val cargo = (a as? zombie.inventory.types.InventoryContainer)?.getInventory()
        val cargoCount = cargo?.getItems()?.size ?: 0
        var inventoryCount = 0
        if (a != null)
            for (item in p.getInventory().getItems()) if (item.getID() == a.getID())
                inventoryCount++
        val world = a?.getWorldItem()
        val leftFoot =
            p.getBodyDamage().getBodyPart(zombie.characters.BodyDamage.BodyPartType.Foot_L)
        val rightFoot =
            p.getBodyDamage().getBodyPart(zombie.characters.BodyDamage.BodyPartType.Foot_R)
        return buildString {
            append("{\"wall\":")
                .append(System.currentTimeMillis())
                .append(",\"id\":")
                .append(p.getOnlineID())
            append(",\"user\":\"")
                .append(p.getUsername())
                .append("\",\"local\":")
                .append(p.isLocalPlayer())
            append(",\"enabled\":")
                .append(net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled(p))
            append(",\"x\":")
                .append(p.getX())
                .append(",\"y\":")
                .append(p.getY())
                .append(",\"z\":")
                .append(p.getZ())
            append(",\"realX\":").append(p.realx).append(",\"realY\":").append(p.realy)
            append(",\"targetX\":")
                .append(network?.targetX ?: 0f)
                .append(",\"targetY\":")
                .append(network?.targetY ?: 0f)
            append(",\"predictionType\":").append(network?.predictionType ?: -1)
            append(",\"female\":")
                .append(p.isFemale())
                .append(",\"hasPath\":")
                .append(p.hasPath())
                .append(",\"nativeMoving\":")
                .append(p.isPlayerMoving())
            append(",\"deferredLength\":")
                .append(p.getDeferredMovement(zombie.iso.Vector2()).getLength())
            append(",\"heading\":")
                .append(p.getDirectionAngleRadians())
                .append(",\"run\":")
                .append(p.isRunning())
                .append(",\"sprint\":")
                .append(p.isSprinting())
            append(",\"canSprint\":")
                .append(p.canSprint())
                .append(",\"sprintLevel\":")
                .append(p.getPerkLevel(zombie.characters.skills.PerkFactory.Perks.Sprinting))
            append(",\"sprintButtonDown\":")
                .append(p.getCharacterInputComponent().isSprintButtonDown())
                .append(",\"justMoved\":")
                .append(p.isJustMoved())
            append(",\"inTrees\":")
                .append(p.isInTrees())
                .append(",\"inTreesNoBush\":")
                .append(p.isInTreesNoBush())
            append(",\"collapsedFence\":")
                .append(
                    p.getCurrentSquare() != null &&
                        zombie.iso.BentFences.getInstance()
                            .getCollapsedFence(p.getCurrentSquare()) != null,
                )
            append(",\"walkSpeed\":")
                .append(p.getVariableFloat("WalkSpeed", -1f))
                .append(",\"walkInjury\":")
                .append(p.getVariableFloat("WalkInjury", -1f))
            append(",\"injuryProbeVersion\":1,\"god\":")
                .append(p.isGodMod())
                .append(",\"dead\":")
                .append(p.isDead())
                .append(",\"leftScratch\":")
                .append(leftFoot.getScratchTime())
                .append(",\"rightScratch\":")
                .append(rightFoot.getScratchTime())
                .append(",\"leftFracture\":")
                .append(leftFoot.getFractureTime())
                .append(",\"rightFracture\":")
                .append(rightFoot.getFractureTime())
            append(",\"endurance\":")
                .append(p.getStats().get(zombie.characters.CharacterStat.ENDURANCE))
                .append(",\"enduranceMoodle\":")
                .append(
                    p.getMoodles().getMoodleLevel(zombie.scripting.objects.MoodleType.ENDURANCE),
                )
            append(",\"primary\":")
                .append(a?.getID() ?: -1)
                .append(",\"secondary\":")
                .append(b?.getID() ?: -1)
                .append(",\"item\":\"")
                .append(a?.getFullType() ?: "none")
                .append('"')
            append(",\"modelProbeVersion\":1,\"heldModel\":")
                .append(mpJsonString(a?.getStaticModel()))
                .append(",\"overridePrimary\":")
                .append(mpJsonString(p.overridePrimaryHandModel))
            append(",\"overrideSecondary\":")
                .append(mpJsonString(p.overrideSecondaryHandModel))
                .append(",\"performing\":")
                .append(p.getVariableBoolean("IsPerformingAnAction"))
            append(",\"action\":")
                .append(mpJsonString(p.getVariableString("PerformingAction")))
                .append(",\"inventoryCount\":")
                .append(inventoryCount)
            append(",\"inventoryScope\":")
                .append(
                    mpJsonString(
                        if (p.isLocalPlayer() || zombie.network.GameServer.server) "owner-inventory"
                        else "remote-hand-snapshot",
                    ),
                )
            append(",\"worldID\":")
                .append(world?.getItem()?.getID() ?: -1)
                .append(",\"primaryInInventory\":")
                .append(a != null && a.getContainer() === p.getInventory())
            append(",\"characterActions\":")
                .append(p.getCharacterActions().size)
                .append(",\"cargoCount\":")
                .append(cargoCount)
            append(",\"cargoID\":")
                .append(if (cargoCount == 1) cargo!!.getItems()[0].getID() else -1)
                .append(",\"cargoWeight\":")
                .append(cargo?.getCapacityWeight() ?: 0f)
            append(",\"brace\":")
                .append(p.getVariableBoolean("ToolkitCartBrace"))
                .append(",\"motion\":")
                .append(p.getVariableBoolean("ToolkitCartMotion"))
            append(",\"visualEnabled\":")
                .append(net.alexredby.pztoolkitjavapatches.CartMotionSync.visualEnabled(p))
            append(",\"poseRegistered\":")
                .append(VariableSyncPacket.syncedVariables.contains("ToolkitCartPose"))
                .append(",\"actionPoseRegistered\":")
                .append(VariableSyncPacket.syncedVariables.contains("ToolkitCartActionPose"))
            append(",\"fullyConnected\":")
                .append(
                    zombie.network.GameClient.connection != null &&
                        zombie.network.GameClient.connection.isFullyConnected(),
                )
            append(",\"pose\":\"")
                .append(p.getVariableString("ToolkitCartPose"))
                .append('"')
                .append(",\"actionPose\":\"")
                .append(p.getVariableString("ToolkitCartActionPose"))
                .append('"')
            append(",\"pivot\":")
                .append(p.getVariableBoolean("ToolkitCartPivot"))
                .append(",\"stepX\":")
                .append(p.getVariableFloat("ToolkitCartStepX", 0f))
                .append(",\"stepY\":")
                .append(p.getVariableFloat("ToolkitCartStepY", 0f))
            append(",\"pace\":")
                .append(p.getVariableFloat("ToolkitCartLegPace", 0f))
                .append(",\"bank\":")
                .append(net.alexredby.pztoolkitjavapatches.CartSteeringHooks.lean(p))
                .append(",\"tracks\":\"")
            if (p.getAnimationPlayer() != null && p.getAnimationPlayer().getMultiTrack() != null)
                for (t in p.getAnimationPlayer().getMultiTrack().getTracks()) append(t.getName())
                    .append('=')
                    .append(t.getSpeedDelta())
                    .append('@')
                    .append(t.getBlendWeight())
                    .append(';')
            append("\",\"trackProgress\":[")
            var comma = false
            if (p.getAnimationPlayer() != null && p.getAnimationPlayer().getMultiTrack() != null)
                for (t in p.getAnimationPlayer().getMultiTrack().getTracks()) {
                    if (comma) append(',')
                    comma = true
                    append("{\"name\":")
                        .append(mpJsonString(t.getName()))
                        .append(",\"time\":")
                        .append(t.getCurrentTrackTime())
                        .append(",\"duration\":")
                        .append(t.getDuration())
                        .append(",\"weight\":")
                        .append(t.getBlendWeight())
                        .append('}')
                }
            append("]}")
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartMPCamera", global = true)
    fun camera(p: IsoPlayer) {
        val self = IsoPlayer.getInstance()
        if (
            TIMELINE &&
                System.getenv("PZ_CART_INVENTORY_EQUIP") == "true" &&
                self != null &&
                self.isLocalPlayer() &&
                self.getUsername() == "client2" &&
                p !== self &&
                p.getUsername() == "client1"
        ) {
            if (timelineCameraOwner?.get() !== p) timelineCameraOwner = WeakReference(p)
            timelinePan(zombie.iso.IsoCamera.cameras[0])
            zoom(false)
        }
        val x = p.getX() - self.getX()
        val y = p.getY() - self.getY()
        val length = Math.hypot(x.toDouble(), y.toDouble()).toFloat()
        if (length > 1e-5f) {
            self.setTargetAndCurrentDirection(x / length, y / length)
            self.getAnimationPlayer().setTargetAndCurrentDirection(x / length, y / length)
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartMPZoom", global = true)
    fun zoom(observer: Boolean): Float {
        val core = zombie.core.Core.getInstance()
        core.setAutoZoom(0, false)
        core.offscreenBuffer.setZoomAndTargetZoom(0, if (observer) 1f else .25f)
        return core.getZoom(0)
    }

    @JvmStatic
    @LuaMethod(name = "cartMPHideUI", global = true)
    fun hideUI() {
        zombie.ui.UIManager.setVisibleAllUI(false)
        for (ui in zombie.ui.UIManager.getUI()) if (ui is zombie.ui.UIElement) ui.setVisible(false)
    }

    private val posePackets = LongAdder()
    private val poseBytes = LongAdder()

    @JvmStatic
    fun recordPoseTraffic(key: String?, bytes: Int) {
        if (key == "ToolkitCartPose" || key == "ToolkitCartActionPose") {
            posePackets.increment()
            poseBytes.add(bytes.toLong())
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartMPTraffic", global = true)
    fun traffic() =
        "{\"wall\":${System.currentTimeMillis()},\"packets\":${posePackets.sum()},\"serializedBytes\":${poseBytes.sum()}}"

    internal val TIMELINE = System.getenv("PZ_CART_TIMELINE") == "true"
    private val timelineRows = ArrayBlockingQueue<String>(8192)
    private var timelineOutput: BufferedWriter? = null
    private var timelineThread: Thread? = null
    private var timelineSequence = 0L
    private var timelineBytes = 0L
    private var nextTimelineStats = 0L
    @Volatile internal var timelineFailed = false
    @Volatile internal var timelineClosing = false
    private var timelineLastOwnerID = 0
    private var timelineActor: String? = null
    internal var timelineBoundOwner: WeakReference<IsoPlayer>? = null
    internal var timelineBoundConnectionToken = 0
    private const val TIMELINE_MAX_BYTES = 64L * 1024 * 1024

    private fun timelineRole(): String? =
        if (zombie.network.GameServer.server) "server"
        else IsoPlayer.getInstance()?.getUsername() ?: "unbound"

    @JvmStatic
    fun timelineOwner(p: IsoPlayer?) =
        TIMELINE &&
            p != null &&
            p.getOnlineID() >= 0 &&
            p.getUsername() == "client1" &&
            (zombie.network.GameServer.server || zombie.network.GameClient.client)

    @JvmStatic
    fun timelineError(error: Throwable) {
        if (!timelineFailed) System.err.println("[CART_TIMELINE] ERROR $error")
        timelineFailed = true
    }

    private fun timelineStart() {
        if (timelineThread != null) return
        val configured = Main.runtime.parent.parent.toAbsolutePath().normalize()
        val cache =
            Path.of(zombie.ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize()
        check(cache == configured) { "Timeline cache does not match the owned fixture root" }
        val path =
            cache.resolve(
                if (zombie.network.GameServer.server) "cart-timeline-server.jsonl"
                else "cart-timeline.jsonl",
            )
        val output = Files.newBufferedWriter(path, StandardOpenOption.CREATE_NEW)
        timelineOutput = output
        val writer =
            Thread(
                {
                    try {
                        while (!timelineClosing || !timelineRows.isEmpty()) {
                            val row = timelineRows.poll(100, TimeUnit.MILLISECONDS)
                            if (row != null) {
                                val bytes = row.toByteArray(StandardCharsets.UTF_8).size + 1L
                                if (timelineBytes + bytes > TIMELINE_MAX_BYTES)
                                    throw IOException("64MiB trace limit")
                                output.write(row)
                                output.newLine()
                                timelineBytes += bytes
                            }
                            if (row == null || timelineRows.isEmpty()) output.flush()
                        }
                        output.close()
                    } catch (error: Throwable) {
                        timelineError(error)
                        try {
                            output.close()
                        } catch (_: Exception) {}
                    }
                },
                "CartTimelineWriter",
            )
        timelineThread = writer
        writer.isDaemon = true
        writer.start()
        Runtime.getRuntime()
            .addShutdownHook(
                Thread(
                    {
                        timelineStop()
                        try {
                            writer.join(1500)
                        } catch (_: InterruptedException) {
                            Thread.currentThread().interrupt()
                        }
                        if (writer.isAlive)
                            timelineError(IOException("Writer did not drain at shutdown"))
                    },
                    "CartTimelineClose",
                ),
            )
    }

    @JvmStatic
    fun timelineEvent(event: String?, owner: IsoPlayer?, fields: String?) {
        synchronized(Main::class.java) {
            if (!timelineOwner(owner) || timelineFailed || timelineClosing) return
            try {
                timelineStart()
                timelineLastOwnerID = owner!!.getOnlineID().toInt()
                timelineActor = timelineRole()
                if (timelineBoundOwner?.get() !== owner) timelineBoundOwner = WeakReference(owner)
                if (
                    !zombie.network.GameServer.server &&
                        zombie.network.GameClient.connection != null
                )
                    timelineBoundConnectionToken =
                        System.identityHashCode(zombie.network.GameClient.connection)
                timelineFlushClock(owner)
                val mono = System.nanoTime()
                val server = zombie.GameTime.getServerTime()
                val ready =
                    zombie.network.GameServer.server || zombie.GameTime.getServerTimeShiftIsSet()
                val row =
                    "{\"schema\":1,\"event\":${mpJsonString(event)},\"actor\":${mpJsonString(timelineActor)},\"seq\":${++timelineSequence},\"monoNs\":$mono,\"serverNs\":$server,\"clockReady\":$ready,\"wallMs\":${System.currentTimeMillis()},\"ownerID\":${owner.getOnlineID()}$fields}"
                if (!timelineRows.offer(row)) throw IOException("8192-row trace queue overflow")
            } catch (error: Throwable) {
                timelineError(error)
            }
        }
    }

    @JvmStatic
    fun timelineStop() {
        synchronized(Main::class.java) {
            if (!TIMELINE || timelineClosing) return
            if (timelineThread != null && !timelineFailed) {
                val server = zombie.GameTime.getServerTime()
                val end =
                    "{\"schema\":1,\"event\":\"trace-end\",\"actor\":${mpJsonString(timelineActor)},\"seq\":${++timelineSequence},\"monoNs\":${System.nanoTime()},\"serverNs\":$server,\"clockReady\":${server != 0L},\"wallMs\":${System.currentTimeMillis()},\"ownerID\":$timelineLastOwnerID,\"failed\":false}"
                if (!timelineRows.offer(end)) timelineError(IOException("Trace end queue overflow"))
            }
            timelineClosing = true
        }
    }

    @JvmStatic
    fun timelinePose(key: String?, value: String?): String? {
        if (key != "ToolkitCartPose" && key != "ToolkitCartActionPose") return null
        var identity = ",\"key\":${mpJsonString(key)}"
        if (value != null && value.length > 300) return "$identity,\"shapeError\":true"
        identity += ",\"raw\":${mpJsonString(value)}"
        if (value.isNullOrEmpty()) return "$identity,\"clear\":true"
        val parts = value.split(',')
        val motion = key == "ToolkitCartPose"
        return try {
            require(parts.size == if (motion) 13 else 14) { "pose shape" }
            require(parts[0] == "1") { "pose shape" }
            val cart = parts[if (motion) 1 else 2].toInt()
            val serial = parts[if (motion) 2 else 1].toLong()
            require(serial > 0) { "pose serial" }
            "$identity,\"cartID\":$cart,\"serial\":$serial" +
                if (motion) "" else ",\"actionGeneration\":${parts[3].toLong()}"
        } catch (_: RuntimeException) {
            "$identity,\"shapeError\":true"
        }
    }

    @JvmStatic
    fun timelineVariable(player: IsoPlayer?, event: String?, key: String?, value: String?) {
        if (!timelineOwner(player)) return
        timelinePose(key, value)?.let { timelineEvent(event, player, it) }
    }

    @JvmStatic
    fun timelinePacket(packet: VariableSyncPacket?, event: String?, bytes: Int) {
        try {
            if (!TIMELINE || packet?.player == null) return
            timelinePose(packet.key, packet.value)?.let {
                timelineEvent(event, packet.player.getPlayer(), "$it,\"serializedBytes\":$bytes")
            }
            if (event == "variable-process-server-exit") timelineStats(packet.player.getPlayer())
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun timelineNative(prediction: Prediction) =
        ",\"predictionType\":${prediction.type},\"predictionX\":${prediction.x},\"predictionY\":${prediction.y},\"predictionZ\":${prediction.z},\"predictionDirection\":${prediction.direction},\"predictionMoveDirection\":${prediction.moveDirection},\"predictionSpeed\":${prediction.speed},\"predictionTimeRemaining\":${prediction.predictionTimeRemaining}"

    @JvmStatic
    fun timelineRemote(player: IsoPlayer?, event: String?) {
        try {
            if (!timelineOwner(player) || player!!.isLocalPlayer()) return
            val ai = player.getNetworkCharacterAI()
            val fields =
                ",\"x\":${player.getX()},\"y\":${player.getY()},\"heading\":${player.getDirectionAngleRadians()},\"targetX\":${ai.targetX},\"targetY\":${ai.targetY}${timelineNative(ai.prediction)}${timelineNativeSnapshot(player)}"
            for (key in arrayOf("ToolkitCartPose", "ToolkitCartActionPose")) timelineEvent(
                event,
                player,
                fields + timelinePose(key, player.getVariableString(key)),
            )
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun timelineStats(owner: IsoPlayer?) {
        if (!timelineOwner(owner) || timelineFailed) return
        val now = System.nanoTime()
        if (now < nextTimelineStats) return
        nextTimelineStats = now + 1_000_000_000L
        try {
            if (zombie.network.GameServer.server) {
                for (connection in zombie.network.GameServer.udpEngine.connections) if (
                    connection.hasPlayer("client1") || connection.hasPlayer("client2")
                )
                    timelineConnection(owner!!, connection)
            } else zombie.network.GameClient.connection?.let { timelineConnection(owner!!, it) }
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    private fun timelineConnection(owner: IsoPlayer, connection: UdpConnection) {
        val stats = connection.getStatistics()
        var fields =
            ",\"connectionGUID\":${mpJsonString(java.lang.Long.toUnsignedString(connection.getConnectedGUID()))},\"endpoint\":${mpJsonString(if (zombie.network.GameServer.server) connection.getUserName() else "server")},\"connectionType\":${mpJsonString(connection.getConnectionType().toString())},\"scope\":\"owned-connection-all-native-traffic\",\"headerCoverage\":\"unverified\",\"available\":${stats != null}"
        if (stats != null)
            fields +=
                ",\"nativeActualBytesSent\":${stats.totalActualBytesSent},\"nativeActualBytesReceived\":${stats.totalActualBytesReceived},\"userBytesResent\":${stats.totalUserMessageBytesResent},\"resendBufferBytes\":${stats.bytesInResendBuffer},\"resendBufferMessages\":${stats.messagesInResendBuffer}"
        timelineEvent("transport-stats", owner, fields)
    }

    @Patch(
        className = "zombie.characters.IsoGameCharacter",
        methodName = "setVariable",
        warmUp = true,
    )
    object TimelinePublish {
        @JvmStatic
        @Patch.OnEnter
        fun enter(
            @Patch.This character: zombie.characters.IsoGameCharacter?,
            @Patch.Argument(0) key: String?,
            @Patch.Argument(1) value: String?,
        ) {
            try {
                if (character is IsoPlayer && character.isLocalPlayer())
                    timelineVariable(character, "publish", key, value)
            } catch (error: Throwable) {
                timelineError(error)
            }
        }
    }

    @Patch(
        className = "zombie.network.packets.VariableSyncPacket",
        methodName = "parse",
        warmUp = true,
    )
    object TimelineVariableParse {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This packet: VariableSyncPacket?) =
            timelinePacket(packet, "variable-parse", -1)
    }

    @Patch(
        className = "zombie.network.packets.VariableSyncPacket",
        methodName = "processClient",
        warmUp = true,
    )
    object TimelineVariableProcess {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This packet: VariableSyncPacket?) =
            timelinePacket(packet, "variable-process-client", -1)
    }

    @Patch(
        className = "zombie.network.packets.VariableSyncPacket",
        methodName = "processServer",
        warmUp = true,
    )
    object TimelineVariableServer {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This packet: VariableSyncPacket?) =
            timelinePacket(packet, "variable-process-server-enter", -1)

        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This packet: VariableSyncPacket?) =
            timelinePacket(packet, "variable-process-server-exit", -1)
    }

    private val timelinePredictionOwners = WeakHashMap<Prediction, WeakReference<IsoPlayer>>()

    @JvmStatic
    fun timelineBindPrediction(player: IsoPlayer?) {
        synchronized(Main::class.java) {
            if (!timelineOwner(player) || player!!.isLocalPlayer()) return
            try {
                val prediction = player.getNetworkCharacterAI().prediction
                if (timelinePredictionOwners[prediction]?.get() !== player)
                    timelinePredictionOwners[prediction] = WeakReference(player)
            } catch (error: Throwable) {
                timelineError(error)
            }
        }
    }

    @JvmStatic
    fun timelinePredictionUpdated(prediction: Prediction?) {
        synchronized(Main::class.java) {
            if (!TIMELINE) return
            try {
                val player = timelinePredictionOwners[prediction]?.get()
                if (player != null && player.getNetworkCharacterAI().prediction === prediction)
                    timelineRemote(player, "prediction-update")
            } catch (error: Throwable) {
                timelineError(error)
            }
        }
    }

    @Patch(
        className = "zombie.characters.IsoPlayer",
        methodName = "updateRemotePlayer",
        warmUp = true,
    )
    object TimelinePredictionOwner {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This player: IsoPlayer?) = timelineBindPrediction(player)
    }

    @Patch(
        className = "zombie.network.fields.character.Prediction",
        methodName = "update",
        warmUp = true,
    )
    object TimelinePrediction {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This prediction: Prediction) = timelinePredictionUpdated(prediction)
    }

    @Patch(
        className = "net.alexredby.pztoolkitjavapatches.CartMotionSync",
        methodName = "update",
        warmUp = true,
    )
    object TimelineAnimation {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.Argument(0) player: IsoPlayer?) = timelineRemote(player, "animation-update")
    }

    private data class TimelineClock(
        val sent: Long,
        val server: Long,
        val processed: Long,
        val observed: Long,
        val before: Long,
        val after: Long,
        val readyBefore: Boolean,
        val readyAfter: Boolean,
        val guid: String,
        val connectionToken: Int,
        val pending: Boolean,
        val requestFields: String,
    ) {
        fun fields() =
            ",\"clientSendNs\":$sent,\"serverPreparedNs\":$server,\"clientProcessNs\":$processed,\"observedMonoNs\":$observed,\"offsetBeforeNs\":$before,\"offsetAfterNs\":$after,\"readyBefore\":$readyBefore,\"readyAfter\":$readyAfter,\"connectionGUID\":${mpJsonString(guid)},\"connectionToken\":$connectionToken,\"pendingBeforeOwner\":$pending$requestFields"
    }

    private val timelinePendingClock = ArrayDeque<TimelineClock>()
    internal val timelineClockConnection = ThreadLocal<UdpConnection>()
    private var timelinePendingDropped = 0
    private var timelineFlushingClock = false
    private var timelineShiftField: Field? = null

    @JvmStatic
    fun timelineAppliedOffset(): Long {
        if (!TIMELINE) return 0
        return try {
            val field =
                timelineShiftField
                    ?: zombie.GameTime::class.java.getDeclaredField("serverTimeShift").apply {
                        isAccessible = true
                        timelineShiftField = this
                    }
            field.getLong(null)
        } catch (error: Throwable) {
            timelineError(error)
            0
        }
    }

    @JvmStatic
    fun timelineClockEnter(connection: UdpConnection?) {
        try {
            if (TIMELINE) timelineClockConnection.set(connection)
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun timelineClockExit() {
        try {
            if (TIMELINE) timelineClockConnection.remove()
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun timelineClock(t0: Long, server: Long, t1: Long, before: Long, readyBefore: Boolean) {
        synchronized(Main::class.java) {
            if (!TIMELINE || timelineClosing || timelineFailed) return
            try {
                val connection = timelineClockConnection.get()
                if (
                    connection == null ||
                        connection !== zombie.network.GameClient.connection ||
                        zombie.network.GameServer.server
                )
                    return
                val owner = timelineBoundOwner?.get()
                val bound =
                    owner != null &&
                        timelineBoundConnectionToken == System.identityHashCode(connection)
                val receipt =
                    TimelineClock(
                        t0,
                        server,
                        t1,
                        System.nanoTime(),
                        before,
                        timelineAppliedOffset(),
                        readyBefore,
                        zombie.GameTime.getServerTimeShiftIsSet(),
                        java.lang.Long.toUnsignedString(connection.getConnectedGUID()),
                        System.identityHashCode(connection),
                        !bound,
                        timelineClockRequestFields(connection, t0),
                    )
                if (timelinePendingClock.size == 256) {
                    timelinePendingClock.removeFirst()
                    timelinePendingDropped++
                }
                timelinePendingClock.addLast(receipt)
                if (bound) timelineFlushClock(owner!!)
            } catch (error: Throwable) {
                timelineError(error)
            }
        }
    }

    @JvmStatic
    fun timelineFlushClock(owner: IsoPlayer) {
        if (
            timelineFlushingClock ||
                zombie.network.GameServer.server ||
                timelinePendingClock.isEmpty() && !timelineRequestsPending()
        )
            return
        timelineFlushingClock = true
        try {
            timelineFlushRequests(owner)
            while (!timelinePendingClock.isEmpty()) timelineEvent(
                "clock-sync",
                owner,
                timelinePendingClock.removeFirst().fields() +
                    ",\"pendingDroppedCount\":$timelinePendingDropped",
            )
        } finally {
            timelineFlushingClock = false
        }
    }

    @Patch(
        className = "zombie.network.packets.service.TimeSyncPacket",
        methodName = "processClient",
        warmUp = true,
    )
    object TimelineTimeSyncScope {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.Argument(0) connection: UdpConnection?) = timelineClockEnter(connection)

        @JvmStatic
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        fun exit() = timelineClockExit()
    }

    private var timelineCameraOwner: WeakReference<IsoPlayer>? = null

    private fun timelineCloseCamera() =
        TIMELINE && System.getenv("PZ_CART_INVENTORY_EQUIP") == "true"

    @JvmStatic
    fun timelinePan(camera: zombie.iso.PlayerCamera?) {
        if (!timelineCloseCamera()) return
        try {
            val self = IsoPlayer.getInstance()
            val owner = timelineCameraOwner?.get()
            if (
                self == null ||
                    !self.isLocalPlayer() ||
                    self.getUsername() != "client2" ||
                    owner == null ||
                    owner === self ||
                    owner.getUsername() != "client1" ||
                    camera !== zombie.iso.IsoCamera.cameras[0]
            )
                return
            check(zombie.iso.IsoCamera.getCameraCharacter() === self) {
                "Observer camera identity changed"
            }
            val dx =
                zombie.iso.IsoUtils.XToScreen(owner.getX(), owner.getY(), owner.getZ(), 0) -
                    zombie.iso.IsoUtils.XToScreen(self.getX(), self.getY(), self.getZ(), 0)
            val dy =
                zombie.iso.IsoUtils.YToScreen(owner.getX(), owner.getY(), owner.getZ(), 0) -
                    zombie.iso.IsoUtils.YToScreen(self.getX(), self.getY(), self.getZ(), 0)
            check(
                (dx + dy).isFinite() &&
                    Math.hypot(
                        (owner.getX() - self.getX()).toDouble(),
                        (owner.getY() - self.getY()).toDouble(),
                    ) <= 16 &&
                    Math.abs(owner.getZ() - self.getZ()) <= .25f,
            ) {
                "Framing target left owned fixture pad"
            }
            camera!!.rightClickTargetX = dx
            camera.rightClickX = dx
            camera.rightClickTargetY = dy
            camera.rightClickY = dy
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @Patch(className = "zombie.iso.PlayerCamera", methodName = "update", warmUp = true)
    object TimelineCameraPan {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun exit(@Patch.This camera: zombie.iso.PlayerCamera?) = timelinePan(camera)
    }

    @JvmStatic
    fun startup() {
        NativeTime.initialize()
        ClockTime.initialize()
        LeaseControl.initialize()
        EquipmentLifetime.initialize()
        ActionAdmission.initialize()
        ActionInvalidation.initialize()
        ObserverAssociation.initialize()
        ObserverParams.initialize()
        ObserverParamsBootstrap.install()
    }
}
