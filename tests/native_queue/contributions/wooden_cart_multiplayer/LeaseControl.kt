package net.alexredby.cartlab

import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.IdentityHashMap
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.NativeTime.nativeTimeIdentity
import net.alexredby.cartlab.NativeTime.nativeTimeProcess
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes.PacketType
import zombie.network.ZomboidNetData

/** Native command provenance; Lua owns challenge policy and this observer owns no game effects. */
object LeaseControl {
    @JvmField val LEASE_CONTROL = System.getenv("PZ_CART_LEASE_CONTROL") == "true"
    @JvmField @Volatile var leaseControlFailed = false
    private val leaseControlGeneration = AtomicLong()
    @JvmField val leaseControlIngresses = NativeWeakMap<ByteBufferReader, LeaseCommandIngress>()
    private val leaseControlConnections = NativeWeakMap<UdpConnection, LeaseTransport>()
    private val leaseControlDecode = ThreadLocal<LeaseDecodeScope>()
    @JvmField val leaseControlDispatch = ThreadLocal<LeaseDispatchScope>()
    @JvmField val leaseControlCallback = ThreadLocal<LeaseCallbackScope>()

    @JvmRecord
    data class LeaseTransport(
        val engine: WeakReference<UdpEngine>,
        val connection: WeakReference<UdpConnection>,
        val epoch: Long,
        val guid: Long,
        val type: Int,
    )

    @JvmRecord data class LeaseCommandIngress(val generation: Long, val transport: LeaseTransport)

    @JvmRecord
    data class LeaseDecodeScope(
        val reader: ByteBufferReader,
        val transport: LeaseTransport?,
        val previous: LeaseDecodeScope?,
    )

    @JvmRecord
    data class LeaseDispatchScope(
        val reader: ByteBufferReader?,
        val ingress: LeaseCommandIngress?,
        val previous: LeaseDispatchScope?,
    )

    @JvmRecord
    data class LeaseCallbackScope(
        val reader: ByteBufferReader,
        val ingress: LeaseCommandIngress?,
        val connection: UdpConnection?,
        val playerIndex: Int,
        val server: Boolean,
        val previous: LeaseCallbackScope?,
    )

    private val leaseReceiptFrames =
        ThreadLocal<IdentityHashMap<LeaseCallbackScope, LeaseReceiptFrame>>()
    private var leaseReceiptRows = 0L

    class LeaseReceiptFrame(
        val buffer: ByteBuffer,
        val begin: Int,
        val end: Int,
        val module: String,
        val command: String,
    ) {
        val order: ByteOrder = buffer.order()
        var receipt: String? = null
    }

    private fun leaseReceiptModule(module: String?) =
        module == "CartLeaseProbe" ||
            module == "CartLeaseLifetimes" ||
            module == "CartActionAdmissionProbe"

    private fun leaseReceiptCapture(scope: LeaseCallbackScope) {
        if (scope.ingress == null) return
        val buffer = scope.reader.bb ?: return
        val begin = buffer.position()
        val end = buffer.limit()
        try {
            // The pinned native reader uses a signed-short UTF-8 length.
            val duplicate = buffer.asReadOnlyBuffer().order(buffer.order())
            val reader = ByteBufferReader(duplicate)
            if (scope.server && reader.getByte().toInt() != scope.playerIndex) return
            val module = reader.getUTF()
            if (!leaseReceiptModule(module)) return
            val command = reader.getUTF()
            if (command.isNullOrEmpty() || duplicate.remaining() < 1) return
            val frames =
                leaseReceiptFrames.get()
                    ?: IdentityHashMap<LeaseCallbackScope, LeaseReceiptFrame>()
                        .also(leaseReceiptFrames::set)
            frames[scope] = LeaseReceiptFrame(buffer, begin, end, module, command)
        } catch (_: java.nio.BufferUnderflowException) {
            // The original parser remains authoritative for malformed headers.
        } catch (_: NegativeArraySizeException) {} catch (error: Throwable) {
            leaseControlError(error)
        }
    }

    private fun leaseReceiptCleanup(scope: LeaseCallbackScope) {
        val frames = leaseReceiptFrames.get() ?: return
        frames.remove(scope)
        if (frames.isEmpty()) leaseReceiptFrames.remove()
    }

    private fun leaseReceiptNativeEvent(server: Boolean): Boolean =
        StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE).walk { frames ->
            val event =
                frames
                    .dropWhile {
                        it.declaringClass != zombie.Lua.LuaEventManager::class.java ||
                            it.methodName != "triggerEvent"
                    }
                    .limit(2)
                    .toList()
            event.size == 2 &&
                event[0].methodType.parameterCount() == (if (server) 5 else 4) &&
                event[1].declaringClass ==
                    (if (server) GameServer::class.java else GameClient::class.java) &&
                event[1].methodName == "receiveClientCommand"
        }

    @JvmStatic
    @LuaMethod(name = "cartLeaseReceipt", global = true)
    fun cartLeaseReceipt(module: String?, command: String?): String? {
        if (!LEASE_CONTROL || leaseControlFailed || !leaseReceiptModule(module) || command == null)
            return null
        return try {
            val scope = leaseControlCallback.get() ?: return null
            val frame = leaseReceiptFrames.get()?.get(scope) ?: return null
            val ingress = scope.ingress ?: return null
            if (
                frame.module != module ||
                    frame.command != command ||
                    scope.reader.bb !== frame.buffer ||
                    frame.buffer.limit() != frame.end ||
                    frame.buffer.order() !== frame.order ||
                    frame.begin < 0 ||
                    frame.begin >= frame.end ||
                    frame.buffer.position() != frame.end ||
                    !leaseControlCommand(ingress.transport.type) ||
                    leaseControlIngresses.get(scope.reader) !== ingress ||
                    !leaseControlCurrent(ingress.transport, scope.server) ||
                    !leaseReceiptNativeEvent(scope.server)
            )
                return null
            if (scope.server) {
                if (leaseControlValidatedServerScope() !== scope) return null
            } else if (cartLeaseIngress() !== scope.connection) return null
            frame.receipt?.let {
                return it
            }
            synchronized(LeaseReceiptFrame::class.java) {
                frame.receipt?.let {
                    return it
                }
                val connection = nativeTimeIdentity(scope.connection, false)
                val generation = ingress.generation
                val mono = System.nanoTime()
                check(
                    leaseReceiptRows < 1024 &&
                        connection in 1..9007199254740991L &&
                        generation in 1..9007199254740991L,
                ) {
                    "Native command receipt bounds"
                }
                val serial = ++leaseReceiptRows
                val payload = frame.end - frame.begin
                val receipt = "1|$nativeTimeProcess|$connection|$generation|$serial"
                check(receipt.length <= 160) { "Native command receipt token limit" }
                frame.receipt = receipt
                println(
                    "[CART_LEASE_BYTES] {\"process\":" +
                        mpJsonString(nativeTimeProcess) +
                        ",\"connectionEpoch\":" +
                        connection +
                        ",\"ingressGeneration\":" +
                        generation +
                        ",\"receipt\":" +
                        mpJsonString(receipt) +
                        ",\"direction\":" +
                        mpJsonString(if (scope.server) "client-to-server" else "server-to-client") +
                        ",\"module\":" +
                        mpJsonString(module) +
                        ",\"command\":" +
                        mpJsonString(command) +
                        ",\"payloadBytes\":" +
                        payload +
                        ",\"engineBytes\":" +
                        (payload.toLong() + 3) +
                        ",\"monoNs\":" +
                        mono +
                        "}",
                )
                receipt
            }
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    private fun leaseControlError(error: Throwable) {
        leaseControlFailed = true
        Multiplayer.timelineError(
            IllegalStateException("Lease command provenance observation failed", error),
        )
    }

    @JvmStatic
    fun leaseControlHeader(buffer: ByteBuffer?): Int {
        buffer ?: return -1
        val at = buffer.position()
        if (buffer.remaining() < 3 || buffer.get(at).toInt() and 255 != 134) return -1
        return buffer.getShort(at + 1).toInt() and 65535
    }

    @JvmStatic fun leaseControlCommand(type: Int) = type == PacketType.ClientCommand.getId().toInt()

    private fun leaseControlObservedPacket(type: Int): Boolean {
        if (
            System.getenv("PZ_CART_LEASE_LIFETIME") == "true" &&
                type == PacketType.Equip.getId().toInt()
        )
            return true
        return leaseControlCommand(type) ||
            System.getenv("PZ_CART_ACTION_ADMISSION") == "true" &&
                (type == PacketType.NetTimedAction.getId().toInt() ||
                    type == PacketType.GeneralAction.getId().toInt()) ||
            System.getenv("PZ_CART_OBSERVER_ASSOCIATION") == "true" &&
                type == PacketType.State.getId().toInt()
    }

    @JvmStatic
    fun leaseControlServerReceipt(
        reader: ByteBufferReader?,
        connection: UdpConnection?,
        type: Int,
    ): LeaseCommandIngress? {
        if (!LEASE_CONTROL || leaseControlFailed || reader == null || connection == null)
            return null
        val receipt = leaseControlIngresses.get(reader) ?: return null
        return receipt.takeIf {
            it.transport.type == type &&
                it.transport.connection.get() === connection &&
                leaseControlCurrent(it.transport, true)
        }
    }

    @JvmStatic
    fun leaseControlCurrent(transport: LeaseTransport?, server: Boolean): Boolean {
        if (transport == null || leaseControlFailed) return false
        val engine = transport.engine.get() ?: return false
        val connection = transport.connection.get() ?: return false
        if (
            nativeTimeIdentity(connection, false) != transport.epoch ||
                connection.getConnectedGUID() != transport.guid ||
                engine.getActiveConnection(transport.guid) !== connection
        )
            return false
        if (server)
            return GameServer.server && !GameClient.client && GameServer.udpEngine === engine
        return GameClient.client &&
            !GameServer.server &&
            GameClient.instance != null &&
            GameClient.instance.udpEngine === engine &&
            GameClient.connection === connection
    }

    private fun leaseControlRemember(transport: LeaseTransport, server: Boolean): UdpConnection? {
        if (!leaseControlCurrent(transport, server)) return null
        val connection = transport.connection.get() ?: return null
        val previous = leaseControlConnections.get(connection)
        if (
            previous != null &&
                (previous.engine.get() !== transport.engine.get() ||
                    previous.guid != transport.guid ||
                    previous.epoch != transport.epoch)
        )
            return null
        leaseControlConnections.put(connection, transport)
        return connection
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseConnectionActive", global = true)
    fun cartLeaseConnectionActive(connection: UdpConnection?): Boolean? {
        if (!LEASE_CONTROL || leaseControlFailed || connection == null) return null
        return try {
            val scope = leaseControlCallback.get() ?: return null
            val ingress = scope.ingress ?: return null
            if (
                !leaseReceiptNativeEvent(scope.server) ||
                    leaseControlIngresses.get(scope.reader) !== ingress ||
                    !leaseControlCurrent(ingress.transport, scope.server)
            )
                return null
            if (scope.server) {
                if (leaseControlValidatedServerScope() !== scope) return null
            } else if (cartLeaseIngress() !== scope.connection) return null
            val known = leaseControlConnections.get(connection) ?: return null
            val engine = ingress.transport.engine.get() ?: return null
            if (
                known.engine.get() !== engine ||
                    known.connection.get() !== connection ||
                    known.epoch != nativeTimeIdentity(connection, false) ||
                    known.guid != connection.getConnectedGUID()
            )
                return null
            engine.getActiveConnection(known.guid) === connection
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @JvmStatic
    fun leaseControlDecodeEnter(engine: UdpEngine, reader: ByteBufferReader): LeaseDecodeScope? {
        if (!LEASE_CONTROL) return null
        val previous = leaseControlDecode.get()
        var transport: LeaseTransport? = null
        try {
            if (!leaseControlFailed) {
                val type = leaseControlHeader(reader.bb)
                if (leaseControlObservedPacket(type)) {
                    val guid = engine.getPeer().getGuidOfPacket()
                    val connection = engine.getActiveConnection(guid)
                    if (connection != null) {
                        val candidate =
                            LeaseTransport(
                                WeakReference(engine),
                                WeakReference(connection),
                                nativeTimeIdentity(connection, false),
                                guid,
                                type,
                            )
                        if (leaseControlCurrent(candidate, GameServer.server)) transport = candidate
                    }
                }
            }
        } catch (error: Throwable) {
            leaseControlError(error)
        }
        return LeaseDecodeScope(reader, transport, previous).also(leaseControlDecode::set)
    }

    @JvmStatic
    fun leaseControlDecodeExit(scope: LeaseDecodeScope?) {
        scope ?: return
        try {
            if (scope.previous == null) leaseControlDecode.remove()
            else leaseControlDecode.set(scope.previous)
        } catch (error: Throwable) {
            leaseControlError(error)
        }
    }

    @JvmStatic
    fun leaseControlReadEnter(
        data: ZomboidNetData,
        type: Short,
        reader: ByteBufferReader,
        supplied: UdpConnection?,
    ): LeaseCommandIngress? {
        if (!LEASE_CONTROL) return null
        return try {
            leaseControlIngresses.remove(data.buffer)
            if (leaseControlFailed || !leaseControlObservedPacket(type.toInt())) return null
            val scope = leaseControlDecode.get() ?: return null
            val transport = scope.transport ?: return null
            if (
                scope.reader !== reader ||
                    transport.type != type.toInt() ||
                    transport.connection.get() !== supplied ||
                    !leaseControlCurrent(transport, GameServer.server)
            )
                return null
            LeaseCommandIngress(leaseControlGeneration.incrementAndGet(), transport)
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @JvmStatic
    fun leaseControlReadExit(
        data: ZomboidNetData,
        ingress: LeaseCommandIngress?,
        failure: Throwable?,
    ) {
        if (!LEASE_CONTROL) return
        try {
            leaseControlIngresses.remove(data.buffer)
            if (failure != null || ingress == null || leaseControlFailed) return
            val transport = ingress.transport
            if (
                data.type == null ||
                    data.type.getId().toInt() != transport.type ||
                    data.connection != transport.guid ||
                    !leaseControlCurrent(transport, GameServer.server)
            )
                return
            leaseControlIngresses.put(data.buffer, ingress)
        } catch (error: Throwable) {
            leaseControlError(error)
        }
    }

    @JvmStatic
    fun leaseControlReadReset(data: ZomboidNetData) {
        if (!LEASE_CONTROL) return
        try {
            leaseControlIngresses.remove(data.buffer)
        } catch (error: Throwable) {
            leaseControlError(error)
        }
    }

    @JvmStatic
    fun leaseControlDispatchEnter(data: ZomboidNetData?): LeaseDispatchScope? {
        if (!LEASE_CONTROL) return null
        val previous = leaseControlDispatch.get()
        var ingress: LeaseCommandIngress? = null
        try {
            if (
                !leaseControlFailed &&
                    data != null &&
                    (data.type === PacketType.ClientCommand ||
                        System.getenv("PZ_CART_LEASE_LIFETIME") == "true" &&
                            data.type === PacketType.Equip)
            ) {
                val candidate = leaseControlIngresses.get(data.buffer)
                if (
                    candidate != null &&
                        data.connection == candidate.transport.guid &&
                        leaseControlCurrent(candidate.transport, false)
                )
                    ingress = candidate
            }
        } catch (error: Throwable) {
            leaseControlError(error)
        }
        return LeaseDispatchScope(data?.buffer, ingress, previous).also(leaseControlDispatch::set)
    }

    @JvmStatic
    fun leaseControlDispatchExit(scope: LeaseDispatchScope?) {
        scope ?: return
        try {
            if (scope.previous == null) leaseControlDispatch.remove()
            else leaseControlDispatch.set(scope.previous)
        } catch (error: Throwable) {
            leaseControlError(error)
        }
    }

    @JvmStatic
    fun leaseControlClientEnter(reader: ByteBufferReader, type: Short): LeaseCallbackScope? {
        if (!LEASE_CONTROL) return null
        val previous = leaseControlCallback.get()
        var ingress: LeaseCommandIngress? = null
        var connection: UdpConnection? = null
        try {
            val dispatch = leaseControlDispatch.get()
            val candidate = dispatch?.ingress
            if (
                !leaseControlFailed &&
                    leaseControlCommand(type.toInt()) &&
                    dispatch != null &&
                    dispatch.reader === reader &&
                    candidate != null &&
                    leaseControlIngresses.get(reader) === candidate &&
                    leaseControlCurrent(candidate.transport, false)
            ) {
                ingress = candidate
                connection = candidate.transport.connection.get()
            }
        } catch (error: Throwable) {
            leaseControlError(error)
        }
        return LeaseCallbackScope(reader, ingress, connection, -1, false, previous).also {
            leaseControlCallback.set(it)
            leaseReceiptCapture(it)
        }
    }

    @JvmStatic
    fun leaseControlServerEnter(
        reader: ByteBufferReader,
        connection: UdpConnection?,
        type: Short,
    ): LeaseCallbackScope? {
        if (!LEASE_CONTROL) return null
        val previous = leaseControlCallback.get()
        var ingress: LeaseCommandIngress? = null
        var index = -1
        try {
            val candidate = leaseControlIngresses.get(reader)
            if (
                !leaseControlFailed &&
                    leaseControlCommand(type.toInt()) &&
                    candidate != null &&
                    candidate.transport.type == type.toInt() &&
                    candidate.transport.connection.get() === connection &&
                    leaseControlCurrent(candidate.transport, true) &&
                    reader.bb.remaining() > 0
            ) {
                val wireIndex = reader.bb.get(reader.bb.position()).toInt()
                if (wireIndex in 0..3) {
                    index = wireIndex
                    ingress = candidate
                }
            }
        } catch (error: Throwable) {
            leaseControlError(error)
        }
        return LeaseCallbackScope(
                reader,
                ingress,
                if (ingress == null) null else connection,
                index,
                true,
                previous,
            )
            .also {
                leaseControlCallback.set(it)
                leaseReceiptCapture(it)
            }
    }

    @JvmStatic
    fun leaseControlCallbackExit(scope: LeaseCallbackScope?) {
        scope ?: return
        try {
            leaseReceiptCleanup(scope)
            if (scope.previous == null) leaseControlCallback.remove()
            else leaseControlCallback.set(scope.previous)
        } catch (error: Throwable) {
            leaseControlError(error)
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseSource", global = true)
    fun cartLeaseSource(player: IsoPlayer?): UdpConnection? {
        if (!LEASE_CONTROL || leaseControlFailed || player == null) return null
        return try {
            val scope = leaseControlCallback.get() ?: return null
            val ingress = scope.ingress ?: return null
            if (
                !scope.server ||
                    scope.playerIndex !in 0..3 ||
                    leaseControlIngresses.get(scope.reader) !== ingress ||
                    !leaseControlCurrent(ingress.transport, true)
            )
                return null
            val connection = scope.connection ?: return null
            if (
                connection !== ingress.transport.connection.get() ||
                    connection.getPlayerAt(scope.playerIndex) !== player ||
                    player.getOnlineID() < 0 ||
                    GameServer.IDToPlayerMap[player.getOnlineID()] !== player ||
                    GameServer.getConnectionFromPlayer(player) !== connection
            )
                return null
            leaseControlRemember(ingress.transport, true)
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseIngress", global = true)
    fun cartLeaseIngress(): UdpConnection? {
        if (!LEASE_CONTROL || leaseControlFailed) return null
        return try {
            val callback = leaseControlCallback.get() ?: return null
            val ingress = callback.ingress ?: return null
            val dispatch = leaseControlDispatch.get() ?: return null
            if (
                callback.server ||
                    callback.reader !== dispatch.reader ||
                    ingress !== dispatch.ingress ||
                    leaseControlIngresses.get(callback.reader) !== ingress ||
                    !leaseControlCurrent(ingress.transport, false)
            )
                return null
            if (callback.connection === ingress.transport.connection.get())
                leaseControlRemember(ingress.transport, false)
            else null
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @JvmStatic
    fun leaseControlOwnedClient(): Boolean {
        if (
            !LEASE_CONTROL ||
                leaseControlFailed ||
                !GameClient.client ||
                GameServer.server ||
                GameClient.connection == null ||
                GameClient.instance == null ||
                !GameClient.instance.connected ||
                Thread.currentThread() !== zombie.GameWindow.gameThread
        )
            return false
        val player = IsoPlayer.getInstance() ?: return false
        if (
            !player.isLocalPlayer() ||
                player.getOnlineID() < 0 ||
                (player.getUsername() != "client1" && player.getUsername() != "client2") ||
                GameClient.IDToPlayerMap[player.getOnlineID()] !== player
        )
            return false
        val configured = Main.runtime.parent.parent.toAbsolutePath().normalize()
        val cache =
            java.nio.file.Path.of(zombie.ZomboidFileSystem.instance.getCacheDir())
                .toAbsolutePath()
                .normalize()
        return cache == configured
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseCurrent", global = true)
    fun cartLeaseCurrent(): UdpConnection? =
        try {
            if (!leaseControlOwnedClient()) null
            else {
                val connection = GameClient.connection
                val engine = GameClient.instance.udpEngine
                leaseControlRemember(
                    LeaseTransport(
                        WeakReference(engine),
                        WeakReference(connection),
                        nativeTimeIdentity(connection, false),
                        connection.getConnectedGUID(),
                        -1,
                    ),
                    false,
                )
            }
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }

    @JvmStatic
    @LuaMethod(name = "cartLeaseChallengeSeed", global = true)
    fun cartLeaseChallengeSeed(): String? {
        if (!LEASE_CONTROL || leaseControlFailed) return null
        return try {
            UUID.randomUUID().toString()
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseSeed", global = true)
    fun cartLeaseSeed(): String? =
        if (LEASE_CONTROL && !leaseControlFailed) nativeTimeProcess else null

    @JvmStatic
    fun leaseControlValidatedServerScope(): LeaseCallbackScope? {
        val scope = leaseControlCallback.get() ?: return null
        val connection = scope.connection ?: return null
        if (!scope.server || scope.playerIndex !in 0..3) return null
        return if (cartLeaseSource(connection.getPlayerAt(scope.playerIndex)) === connection) scope
        else null
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseTarget", global = true)
    fun cartLeaseTarget(onlineID: Int): IsoPlayer? {
        if (!LEASE_CONTROL || leaseControlFailed || onlineID !in 0..Short.MAX_VALUE) return null
        return try {
            if (leaseControlValidatedServerScope() == null) return null
            GameServer.IDToPlayerMap[onlineID.toShort()]?.takeIf {
                it.getOnlineID().toInt() == onlineID
            }
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseOwnerConnection", global = true)
    fun cartLeaseOwnerConnection(target: IsoPlayer?): UdpConnection? {
        if (!LEASE_CONTROL || leaseControlFailed || target == null) return null
        return try {
            if (
                leaseControlValidatedServerScope() == null ||
                    target.getOnlineID() < 0 ||
                    GameServer.IDToPlayerMap[target.getOnlineID()] !== target
            )
                return null
            val connection = GameServer.getConnectionFromPlayer(target) ?: return null
            val index = target.playerIndex
            if (index !in 0..3 || connection.getPlayerAt(index) !== target) return null
            val engine = GameServer.udpEngine
            leaseControlRemember(
                LeaseTransport(
                    WeakReference(engine),
                    WeakReference(connection),
                    nativeTimeIdentity(connection, false),
                    connection.getConnectedGUID(),
                    -1,
                ),
                true,
            )
        } catch (error: Throwable) {
            leaseControlError(error)
            null
        }
    }

    @Patch(className = "zombie.network.ZomboidNetData", methodName = "reset", warmUp = true)
    object LeaseControlReset {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This data: ZomboidNetData) {
            leaseControlReadReset(data)
        }
    }

    @JvmStatic fun initialize() = Unit
}
