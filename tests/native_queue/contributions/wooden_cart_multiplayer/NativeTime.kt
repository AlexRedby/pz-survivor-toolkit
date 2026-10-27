package net.alexredby.cartlab

import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.HexFormat
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.Multiplayer.TIMELINE
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.Multiplayer.timelineError
import net.alexredby.cartlab.Multiplayer.timelineEvent
import net.alexredby.cartlab.Multiplayer.timelineOwner
import zombie.characters.IsoPlayer
import zombie.characters.NetworkPlayerAI
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.PacketTypes
import zombie.network.ZomboidNetData
import zombie.network.fields.character.Prediction
import zombie.network.packets.character.PlayerPacket

/** Opt-in diagnostic association. Native packets and prediction stay authoritative. */
object NativeTime {
    @JvmField val nativeTimeProcess = UUID.randomUUID().toString()
    private val nativeTimeOrdinal = AtomicLong()

    /**
     * Weak native identity, deliberately independent of equals/hashCode and bounded to 512 keys.
     */
    class NativeWeakMap<K : Any, V> {
        private val keys = ArrayList<WeakReference<K>>()
        private val values = ArrayList<V>()

        @Synchronized
        operator fun get(key: K?): V? {
            for (index in keys.lastIndex downTo 0) {
                val known = keys[index].get()
                when {
                    known == null -> {
                        keys.removeAt(index)
                        values.removeAt(index)
                    }
                    known === key -> return values[index]
                }
            }
            return null
        }

        @Synchronized
        fun put(key: K?, value: V) {
            requireNotNull(key) { "Null native identity" }
            for (index in keys.lastIndex downTo 0) {
                val known = keys[index].get()
                when {
                    known == null -> {
                        keys.removeAt(index)
                        values.removeAt(index)
                    }
                    known === key -> {
                        values[index] = value
                        return
                    }
                }
            }
            check(keys.size < 512) { "Native identity map limit" }
            keys.add(WeakReference(key))
            values.add(value)
        }

        @Synchronized
        fun remove(key: K?) {
            for (index in keys.lastIndex downTo 0) {
                val known = keys[index].get()
                if (known == null || known === key) {
                    keys.removeAt(index)
                    values.removeAt(index)
                }
            }
        }
    }

    private val nativeTimeActors = NativeWeakMap<Any, Long>()
    private val nativeTimeConnections = NativeWeakMap<Any, Long>()
    private val nativeTimeSources = NativeWeakMap<PlayerPacket, NativeSource>()
    private val nativeTimeReceipts = NativeWeakMap<PlayerPacket, NativeReceipt>()
    internal val nativeTimeSends = NativeWeakMap<ByteBufferWriter, NativeSend>()
    private val nativeTimeIngress = NativeWeakMap<ByteBufferReader, NativeIngress>()
    private val nativeTimeAccepted = NativeWeakMap<IsoPlayer, NativeAccepted>()
    private val nativeTimeServer = ThreadLocal<NativeServerScope>()
    private val nativeTimeCopy = ThreadLocal<NativeCopyScope>()
    private val nativeTimeActiveConnections = NativeWeakMap<UdpConnection, NativeActiveSend>()

    @JvmStatic fun initialize() = Unit

    @JvmStatic fun nativeTimeNext(): Long = nativeTimeOrdinal.incrementAndGet()

    @JvmStatic
    fun nativeTimeIdentity(value: Any?, actor: Boolean): Long {
        if (value == null) return 0
        val identities = if (actor) nativeTimeActors else nativeTimeConnections
        return synchronized(identities) {
            identities[value] ?: nativeTimeNext().also { identities.put(value, it) }
        }
    }

    @JvmRecord
    data class NativeBody(val hex: String, val sha: String, val bytes: Int, val order: String)

    @JvmRecord
    data class NativeSource(
        val generation: Long,
        val actor: Long,
        val begin: Long,
        val end: Long,
        val motionBegin: String?,
        val motionEnd: String?,
        val actionBegin: String?,
        val actionEnd: String?,
    )

    @JvmRecord
    data class NativeIngress(
        val generation: Long,
        val connection: Long,
        val mono: Long,
        val type: Int,
        val typeName: String,
        val peer: String,
        val body: NativeBody,
    )

    @JvmRecord
    data class NativeReceipt(
        val generation: Long,
        val actor: Long,
        val connection: Long,
        val ingress: Long,
        val ingressMono: Long,
        val type: Int,
        val typeName: String,
        val peer: String,
        val body: NativeBody,
    )

    @JvmRecord
    data class NativeAccepted(val receipt: NativeReceipt, val prediction: WeakReference<Prediction>)

    @JvmRecord
    data class NativeServerScope(
        val packet: PlayerPacket,
        val receipt: NativeReceipt?,
        val previous: NativeServerScope?,
    )

    @JvmRecord
    data class NativeCopyScope(
        val ai: NetworkPlayerAI,
        val packet: PlayerPacket,
        val owner: IsoPlayer,
        val receipt: NativeReceipt,
        val previous: NativeCopyScope?,
    )

    @JvmRecord
    data class NativeActiveSend(val writer: WeakReference<ByteBufferWriter>, val send: NativeSend)

    class NativeSend(connection: UdpConnection?) {
        @JvmField val generation = nativeTimeNext()
        @JvmField val connection = nativeTimeIdentity(connection, false)
        @JvmField val thread = Thread.currentThread().threadId()
        @JvmField val peer = nativeTimePeer(connection, true)
        @JvmField val endpoint = WeakReference(connection)
        @JvmField var type = -1
        @JvmField var typeName = "unavailable"
        @JvmField var body: NativeBody? = null
        @JvmField var source: NativeSource? = null
        @JvmField var parent: NativeReceipt? = null
        @JvmField var owner: WeakReference<IsoPlayer>? = null
        @JvmField var motionAtWrite: String? = null
        @JvmField var actionAtWrite: String? = null
    }

    @JvmStatic
    fun nativeTimeBody(buffer: ByteBuffer?, begin: Int, end: Int): NativeBody {
        require(
            buffer != null &&
                begin >= 0 &&
                end >= begin &&
                end <= buffer.limit() &&
                end - begin <= 256,
        ) {
            "Native body span exceeds bounds"
        }
        val copy = buffer.duplicate()
        copy.position(begin)
        copy.limit(end)
        val bytes = ByteArray(end - begin)
        copy.get(bytes)
        val hex = HexFormat.of()
        return NativeBody(
            hex.formatHex(bytes),
            hex.formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)),
            bytes.size,
            buffer.order().toString(),
        )
    }

    @JvmStatic
    internal fun nativeTimePeer(connection: IConnection?, outgoing: Boolean): String {
        if (connection == null) return "unavailable"
        if (!GameServer.server) return "server"
        return connection.getUserName()?.takeIf { it.isNotEmpty() } ?: "unavailable"
    }

    private fun nativeTimePlayerType(type: Int) =
        type == PacketTypes.PacketType.PlayerUpdateReliable.getId().toInt() ||
            type == PacketTypes.PacketType.PlayerUpdateUnreliable.getId().toInt()

    private fun nativeTimeFields(
        owner: IsoPlayer?,
        connection: Long,
        peer: String,
        type: Int,
        typeName: String,
        body: NativeBody?,
        source: NativeSource?,
        send: Long,
        serverReceive: Long,
        receive: Long,
        ingress: Long,
        ingressMono: Long,
    ): String =
        ",\"nativePacketVersion\":1,\"nativeProcessEpoch\":${mpJsonString(nativeTimeProcess)}" +
            ",\"actorEpoch\":${nativeTimeIdentity(owner, true)},\"connectionEpoch\":$connection,\"peerRole\":${mpJsonString(peer)}" +
            ",\"packetType\":$type,\"packetTypeName\":${mpJsonString(typeName)}" +
            ",\"packetBodyHex\":${mpJsonString(body?.hex ?: "")},\"packetSha256\":${mpJsonString(body?.sha ?: "")}" +
            ",\"packetBytes\":${body?.bytes ?: 0},\"packetByteOrder\":${mpJsonString(body?.order ?: "unavailable")}" +
            ",\"sourceSetGeneration\":${source?.generation ?: 0},\"sourceSampleBeginNs\":${source?.begin ?: 0},\"sourceSampleEndNs\":${source?.end ?: 0}" +
            ",\"sendGeneration\":$send,\"serverReceiveGeneration\":$serverReceive,\"receiveGeneration\":$receive,\"ingressGeneration\":$ingress,\"ingressMonoNs\":$ingressMono"

    private fun nativeTimeReceiptFields(owner: IsoPlayer?, receipt: NativeReceipt) =
        nativeTimeFields(
            owner,
            receipt.connection,
            receipt.peer,
            receipt.type,
            receipt.typeName,
            receipt.body,
            null,
            0,
            if (GameServer.server) receipt.generation else 0,
            receipt.generation,
            receipt.ingress,
            receipt.ingressMono,
        )

    @JvmStatic
    fun nativeTimeSourceEnter(packet: PlayerPacket, owner: IsoPlayer?): NativeSource? {
        if (
            !TIMELINE ||
                !timelineOwner(owner) ||
                owner == null ||
                !owner.isLocalPlayer() ||
                GameServer.server
        )
            return null
        return try {
            val source =
                NativeSource(
                    nativeTimeNext(),
                    nativeTimeIdentity(owner, true),
                    System.nanoTime(),
                    0,
                    owner.getVariableString("ToolkitCartPose"),
                    null,
                    owner.getVariableString("ToolkitCartActionPose"),
                    null,
                )
            nativeTimeSources.remove(packet)
            source
        } catch (error: Throwable) {
            timelineError(error)
            null
        }
    }

    @JvmStatic
    fun nativeTimeSourceExit(
        packet: PlayerPacket,
        owner: IsoPlayer,
        source: NativeSource?,
        failure: Throwable?,
    ) {
        if (source == null) return
        try {
            if (failure != null) {
                nativeTimeSources.remove(packet)
                return
            }
            val done =
                source.copy(
                    end = System.nanoTime(),
                    motionEnd = owner.getVariableString("ToolkitCartPose"),
                    actionEnd = owner.getVariableString("ToolkitCartActionPose"),
                )
            nativeTimeSources.put(packet, done)
            timelineEvent(
                "player-source-set",
                owner,
                nativeTimeFields(
                    owner,
                    0,
                    "unavailable",
                    -1,
                    "unavailable",
                    null,
                    done,
                    0,
                    0,
                    0,
                    0,
                    0,
                ) +
                    ",\"sourceMotionRawAtSetBegin\":${mpJsonString(done.motionBegin)},\"sourceMotionRawAtSetEnd\":${mpJsonString(done.motionEnd)}" +
                    ",\"sourceActionRawAtSetBegin\":${mpJsonString(done.actionBegin)},\"sourceActionRawAtSetEnd\":${mpJsonString(done.actionEnd)}",
            )
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeStart(
        connection: UdpConnection?,
        writer: ByteBufferWriter?,
        failure: Throwable?,
    ) {
        if (!TIMELINE || failure != null || writer == null) return
        try {
            nativeTimeSends.put(writer, NativeSend(connection))
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeWrite(
        packet: PlayerPacket,
        writer: ByteBufferWriter,
        begin: Int,
        failure: Throwable?,
    ) {
        if (!TIMELINE || failure != null) return
        try {
            val owner = packet.getPlayer()
            if (!timelineOwner(owner) || owner == null) return
            val body = nativeTimeBody(writer.bb, begin, writer.bb.position())
            val send = nativeTimeSends[writer]
            val source =
                nativeTimeSources[packet]?.takeIf {
                    owner.isLocalPlayer() && it.actor == nativeTimeIdentity(owner, true)
                }
            val scope = nativeTimeServer.get()
            val parent = if (scope?.packet === packet) scope.receipt else null
            check(send == null || send.thread == Thread.currentThread().threadId()) {
                "Foreign native writer thread"
            }
            if (send != null && begin >= 3) {
                val header = writer.bb.duplicate().order(writer.bb.order())
                check(header.get(begin - 3).toInt() and 255 == 134) {
                    "Native player header marker changed"
                }
                val type = header.getShort(begin - 2)
                check(nativeTimePlayerType(type.toInt())) { "Native player header type changed" }
                send.type = type.toInt()
                send.typeName = PacketTypes.packetTypes[type]?.name ?: "unavailable"
            }
            if (send != null) {
                send.body = body
                send.source = source
                send.parent = parent
                send.owner = WeakReference(owner)
                send.motionAtWrite =
                    if (owner.isLocalPlayer()) owner.getVariableString("ToolkitCartPose") else null
                send.actionAtWrite =
                    if (owner.isLocalPlayer()) owner.getVariableString("ToolkitCartActionPose")
                    else null
            }
            var fields =
                nativeTimeFields(
                    owner,
                    send?.connection ?: 0,
                    send?.peer ?: nativeTimePeer(send?.endpoint?.get(), true),
                    send?.type ?: -1,
                    send?.typeName ?: "unavailable",
                    body,
                    source,
                    send?.generation ?: 0,
                    parent?.generation ?: 0,
                    0,
                    0,
                    0,
                ) + ",\"serializedBytes\":${body.bytes}"
            if (owner.isLocalPlayer())
                fields +=
                    ",\"sourceMotionRawAtWrite\":${mpJsonString(if (send == null) owner.getVariableString("ToolkitCartPose") else send.motionAtWrite)}" +
                        ",\"sourceActionRawAtWrite\":${mpJsonString(if (send == null) owner.getVariableString("ToolkitCartActionPose") else send.actionAtWrite)}"
            timelineEvent("player-write", owner, fields)
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeFinishEnter(connection: UdpConnection): NativeActiveSend? {
        if (!TIMELINE) return null
        return try {
            val active = nativeTimeConnectionSend(connection) ?: return null
            // Detach under the original buffer lock, before another native startPacket can run.
            nativeTimeActiveConnections.remove(connection)
            active.writer.get()?.let { nativeTimeSends.remove(it) }
            active
        } catch (error: Throwable) {
            timelineError(error)
            null
        }
    }

    @JvmStatic
    fun nativeTimeFinish(
        connection: UdpConnection,
        active: NativeActiveSend?,
        cancel: Boolean,
        failure: Throwable?,
    ) {
        if (active == null) return
        try {
            val value = active.send
            val owner = value.owner?.get() ?: return
            val body = value.body ?: return
            val fields =
                nativeTimeFields(
                    owner,
                    value.connection,
                    value.peer,
                    value.type,
                    value.typeName,
                    body,
                    value.source,
                    value.generation,
                    value.parent?.generation ?: 0,
                    0,
                    0,
                    0,
                ) + ",\"submissionFailed\":${failure != null}"
            timelineEvent(
                if (cancel || failure != null) "player-cancel" else "player-submit",
                owner,
                fields,
            )
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeStartActive(
        connection: UdpConnection,
        writer: ByteBufferWriter?,
        failure: Throwable?,
    ) {
        nativeTimeStart(connection, writer, failure)
        if (!TIMELINE || failure != null || writer == null) return
        try {
            nativeTimeSends[writer]?.let {
                nativeTimeActiveConnections.put(
                    connection,
                    NativeActiveSend(WeakReference(writer), it),
                )
            }
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    private fun nativeTimeConnectionSend(connection: UdpConnection): NativeActiveSend? {
        val send = nativeTimeActiveConnections[connection]
        check(send == null || send.send.thread == Thread.currentThread().threadId()) {
            "Foreign native send completion thread"
        }
        return send
    }

    @JvmStatic
    fun nativeTimeIngressRead(
        data: ZomboidNetData,
        type: Short,
        input: ByteBufferReader,
        connection: UdpConnection,
        begin: Int,
        end: Int,
        mono: Long,
        failure: Throwable?,
    ) {
        if (!TIMELINE) return
        try {
            nativeTimeIngress.remove(data.buffer)
            if (failure != null || !nativeTimePlayerType(type.toInt())) return
            val body = nativeTimeBody(data.buffer.bb, 0, data.buffer.limit())
            val receipt =
                NativeIngress(
                    nativeTimeNext(),
                    nativeTimeIdentity(connection, false),
                    mono,
                    type.toInt(),
                    PacketTypes.packetTypes[type]?.name ?: "unavailable",
                    nativeTimePeer(connection, false),
                    body,
                )
            nativeTimeIngress.put(data.buffer, receipt)
            val duplicate = data.buffer.bb.duplicate().order(data.buffer.bb.order())
            var owner: IsoPlayer? = null
            if (duplicate.remaining() >= 3) {
                val id = duplicate.getShort()
                val index = duplicate.get().toInt()
                owner =
                    when {
                        GameServer.server && index >= 0 -> connection.getPlayerAt(index)
                        GameClient.client -> GameClient.IDToPlayerMap[id]
                        else -> GameServer.IDToPlayerMap[id]
                    }
            }
            if (timelineOwner(owner))
                timelineEvent(
                    "player-ingress",
                    owner,
                    nativeTimeFields(
                        owner,
                        receipt.connection,
                        receipt.peer,
                        receipt.type,
                        receipt.typeName,
                        body,
                        null,
                        0,
                        0,
                        0,
                        receipt.generation,
                        receipt.mono,
                    ),
                )
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeIngressReset(data: ZomboidNetData) {
        if (TIMELINE)
            try {
                nativeTimeIngress.remove(data.buffer)
            } catch (error: Throwable) {
                timelineError(error)
            }
    }

    @JvmStatic
    fun nativeTimeParse(
        packet: PlayerPacket,
        reader: ByteBufferReader,
        connection: IConnection?,
        begin: Int,
        failure: Throwable?,
    ) {
        if (!TIMELINE) return
        try {
            nativeTimeReceipts.remove(packet)
            if (failure != null) return
            val owner = packet.getPlayer()
            if (!timelineOwner(owner) || owner == null) return
            val body = nativeTimeBody(reader.bb, begin, reader.position())
            val ingress = nativeTimeIngress[reader]
            val connectionEpoch = nativeTimeIdentity(connection, false)
            check(
                ingress == null || ingress.connection == connectionEpoch && ingress.body == body,
            ) {
                "Native ingress/parse body or connection mismatch"
            }
            val receipt =
                NativeReceipt(
                    nativeTimeNext(),
                    nativeTimeIdentity(owner, true),
                    connectionEpoch,
                    ingress?.generation ?: 0,
                    ingress?.mono ?: 0,
                    ingress?.type ?: -1,
                    ingress?.typeName ?: "unavailable",
                    nativeTimePeer(connection, false),
                    body,
                )
            nativeTimeReceipts.put(packet, receipt)
            timelineEvent(
                "player-parse",
                owner,
                nativeTimeReceiptFields(owner, receipt) + ",\"serializedBytes\":-1",
            )
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeServerEnter(
        packet: PlayerPacket,
        type: PacketTypes.PacketType,
        connection: UdpConnection,
    ): NativeServerScope? {
        if (!TIMELINE) return null
        return try {
            val receipt = nativeTimeReceipts[packet]
            check(
                receipt == null ||
                    receipt.connection == nativeTimeIdentity(connection, false) &&
                        (receipt.type == -1 || receipt.type == type.getId().toInt()),
            ) {
                "Native server process route differs from parse"
            }
            NativeServerScope(packet, receipt, nativeTimeServer.get()).also {
                nativeTimeServer.set(it)
            }
        } catch (error: Throwable) {
            timelineError(error)
            null
        }
    }

    @JvmStatic
    fun nativeTimeServerExit(scope: NativeServerScope?) {
        if (scope == null) return
        try {
            if (scope.previous == null) nativeTimeServer.remove()
            else nativeTimeServer.set(scope.previous)
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeCopyEnter(ai: NetworkPlayerAI, packet: PlayerPacket): NativeCopyScope? {
        if (!TIMELINE) return null
        return try {
            val owner = packet.getPlayer()
            val receipt = nativeTimeReceipts[packet]
            if (
                !timelineOwner(owner) ||
                    owner == null ||
                    owner.getNetworkCharacterAI() !== ai ||
                    receipt == null ||
                    receipt.actor != nativeTimeIdentity(owner, true)
            )
                return null
            NativeCopyScope(ai, packet, owner, receipt, nativeTimeCopy.get()).also {
                nativeTimeCopy.set(it)
            }
        } catch (error: Throwable) {
            timelineError(error)
            null
        }
    }

    @JvmStatic
    fun nativeTimeCopyExit(scope: NativeCopyScope?) {
        if (scope == null) return
        try {
            if (scope.previous == null) nativeTimeCopy.remove()
            else nativeTimeCopy.set(scope.previous)
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun nativeTimeCopied(destination: Prediction, source: Prediction, failure: Throwable?) {
        if (!TIMELINE || failure != null) return
        try {
            val scope = nativeTimeCopy.get() ?: return
            if (destination !== scope.ai.prediction || source !== scope.packet.prediction) return
            check(nativeTimeReceipts[scope.packet] === scope.receipt) {
                "Native cached packet parse changed within copy scope"
            }
            nativeTimeAccepted.put(
                scope.owner,
                NativeAccepted(scope.receipt, WeakReference(destination)),
            )
            timelineEvent(
                "player-accepted",
                scope.owner,
                nativeTimeReceiptFields(scope.owner, scope.receipt),
            )
        } catch (error: Throwable) {
            timelineError(error)
        }
    }

    @JvmStatic
    fun timelineNativeSnapshot(owner: IsoPlayer?): String {
        if (!TIMELINE) return ""
        return try {
            val accepted =
                if (owner == null || owner.isLocalPlayer()) null else nativeTimeAccepted[owner]
            var receipt =
                if (
                    accepted == null ||
                        accepted.prediction.get() !== owner?.getNetworkCharacterAI()?.prediction
                )
                    null
                else accepted.receipt
            if (
                receipt != null &&
                    !GameServer.server &&
                    receipt.connection != nativeTimeIdentity(GameClient.connection, false)
            )
                receipt = null
            ",\"nativeInputVersion\":1,\"nativeProcessEpoch\":${mpJsonString(nativeTimeProcess)},\"nativeActorEpoch\":${nativeTimeIdentity(owner, true)}" +
                ",\"nativeReceiveGeneration\":${receipt?.generation ?: 0},\"nativeConnectionEpoch\":${receipt?.connection ?: 0},\"nativeIngressGeneration\":${receipt?.ingress ?: 0},\"nativePacketSha256\":${mpJsonString(receipt?.body?.sha ?: "")}"
        } catch (error: Throwable) {
            timelineError(error)
            ""
        }
    }

    @Patch(
        className = "zombie.core.raknet.UdpConnection",
        methodName = "startPacket",
        warmUp = true,
    )
    object NativeTimeStart {
        @JvmStatic
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        fun exit(
            @Patch.This connection: UdpConnection,
            @Patch.Return writer: ByteBufferWriter?,
            @Patch.Thrown failure: Throwable?,
        ) = nativeTimeStartActive(connection, writer, failure)
    }

    @Patch(className = "zombie.network.ZomboidNetData", methodName = "reset", warmUp = true)
    object NativeTimeIngressReset {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This data: ZomboidNetData) = nativeTimeIngressReset(data)
    }

    @Patch(
        className = "zombie.network.fields.character.Prediction",
        methodName = "copy",
        warmUp = true,
    )
    object NativeTimeCopied {
        @JvmStatic
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        fun exit(
            @Patch.This destination: Prediction,
            @Patch.Argument(0) source: Prediction,
            @Patch.Thrown failure: Throwable?,
        ) = nativeTimeCopied(destination, source, failure)
    }
}
