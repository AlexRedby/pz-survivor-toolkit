package net.alexredby.cartlab

import java.lang.ref.WeakReference
import java.lang.reflect.Field
import java.util.ArrayList
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicLong
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.ActionAdmission.ACTION_ADMISSION
import net.alexredby.cartlab.ActionAdmission.actionAdmissionFailed
import net.alexredby.cartlab.ActionAdmission.actionAdmissionKind
import net.alexredby.cartlab.ActionAdmission.actionAdmissionRegistered
import net.alexredby.cartlab.LeaseControl.LEASE_CONTROL
import net.alexredby.cartlab.LeaseControl.LeaseCommandIngress
import net.alexredby.cartlab.LeaseControl.leaseControlCurrent
import net.alexredby.cartlab.LeaseControl.leaseControlFailed
import net.alexredby.cartlab.LeaseControl.leaseControlIngresses
import net.alexredby.cartlab.LeaseControl.leaseControlOwnedClient
import net.alexredby.cartlab.Multiplayer.TIMELINE
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.Multiplayer.timelineError
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.NativeTime.nativeTimeIdentity
import net.alexredby.cartlab.NativeTime.nativeTimePeer
import net.alexredby.cartlab.NativeTime.nativeTimeProcess
import net.alexredby.cartlab.NativeTime.nativeTimeSends
import net.alexredby.cartlab.ObserverParams.observerParamsHealthy
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.ai.states.PlayerActionsState
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.characters.NetworkCharacterAI
import zombie.characters.NetworkState
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.PZNetKahluaTableImpl
import zombie.network.PacketTypes
import zombie.network.fields.character.PlayerID
import zombie.network.packets.actions.StatePacket

object ObserverAssociation {
    @JvmStatic fun initialize() = Unit

    // DIAGNOSTIC ONLY: opt-in top-level State params tag changes test wire, never animation
    // variables/effects.
    internal val OBSERVER_ASSOCIATION = "true".equals(System.getenv("PZ_CART_OBSERVER_ASSOCIATION"))
    val OBSERVER_MARKER = "__pz_cart_observer_probe"
    @Volatile private var observerAssociationFailed: Boolean = false
    internal val observerSequence = AtomicLong()
    private val observerSources = NativeWeakMap<LuaTimedActionNew, ObserverSource>()
    private val observerPackets = NativeWeakMap<StatePacket, ObserverPacket>()
    private val observerProxies = NativeWeakMap<BaseAction, ObserverProxy>()
    private val observerActors = NativeWeakMap<IsoPlayer, ObserverProxy>()
    private val observerSends = NativeWeakMap<UdpConnection, ObserverSend>()
    internal val observerApplying = ThreadLocal<ObserverApply>()
    private val observerProcessing = ThreadLocal<ObserverProcess>()
    @Volatile private var observerParamsField: Field? = null
    @Volatile private var observerCharacterField: Field? = null
    @Volatile private var observerPlayerField: Field? = null

    @JvmRecord
    data class ObserverTag(
        val life: String,
        val text: String,
        val process: String,
        val actor: Long,
        val connection: Long,
        val action: Long,
        val table: Long,
        val begin: Long,
        val state: Long,
    )

    class ObserverSource(
        action: LuaTimedActionNew,
        owner: IsoPlayer,
        connection: UdpConnection,
        val begin: Long,
    ) {
        val action = WeakReference(action)
        val table = WeakReference(action.table)
        val owner = WeakReference(owner)
        val connection = WeakReference(connection)
        val life =
            "1|$nativeTimeProcess|${nativeTimeIdentity(owner, true)}|${nativeTimeIdentity(connection, false)}|${nativeTimeIdentity(action, false)}|${nativeTimeIdentity(action.table, false)}|$begin"
        @Volatile var returned = false
        @Volatile var ended = false
    }

    class ObserverPacket(packet: StatePacket, owner: IsoPlayer, val tag: ObserverTag) {
        val epoch = observerSequence.incrementAndGet()
        val packet = WeakReference(packet)
        val owner = WeakReference(owner)
        val stage = packet.stage?.name ?: "unavailable"
        @Volatile var ingress: LeaseCommandIngress? = null
        @Volatile var receive = 0L
        @Volatile var apply = 0L
        @Volatile var sourceValidated = false
        @Volatile var processed = false
        @Volatile var applied = false
        @Volatile var discarded = false
    }

    class ObserverProxy
    @JvmOverloads
    constructor(
        proxy: BaseAction,
        owner: IsoPlayer,
        val input: ObserverPacket,
        val apply: Long,
        val associationKind: String = "packet-apply",
        val consumeGeneration: Long = 0,
        val paramsMapEpoch: Long = 0,
        val paramsRevision: Long = 0,
    ) {
        val proxy = WeakReference(proxy)
        val owner = WeakReference(owner)
        val epoch = observerSequence.incrementAndGet()
        val actionEpoch = nativeTimeIdentity(proxy, false)
        @Volatile var state = "active"
        @Volatile var reason = "state-apply"
    }

    @JvmRecord data class ObserverParse(val begin: Int, val ingress: LeaseCommandIngress?)

    @JvmRecord
    data class ObserverApply(
        val input: ObserverPacket?,
        val generation: Long,
        val previous: ObserverApply?,
    )

    @JvmRecord
    data class ObserverProcess(
        val input: ObserverPacket?,
        val server: Boolean,
        val previous: ObserverProcess?,
    )

    @JvmRecord
    data class ObserverSend(
        val input: ObserverPacket,
        val generation: Long,
        val connection: Long,
        val peer: String,
        val parent: Long,
        val begin: Int,
        val end: Int,
        val thread: Long,
    )

    @JvmRecord
    data class ObserverQueue(
        val packets: ArrayList<StatePacket>,
        val records: ArrayList<ObserverPacket?>,
    )

    private fun observerEnabled(): Boolean {
        return OBSERVER_ASSOCIATION &&
            ACTION_ADMISSION &&
            LEASE_CONTROL &&
            TIMELINE &&
            !leaseControlFailed &&
            !actionAdmissionFailed &&
            !observerAssociationFailed
    }

    private fun observerError(error: Throwable) {
        observerAssociationFailed = true
        System.err.println("[CART_OBSERVER] ERROR " + error)
        timelineError(IllegalStateException("Diagnostic observer association failed", error))
    }

    // Exact, bounded textual identity. No timestamps, action names, models or item IDs participate.
    @JvmStatic
    fun observerAssociationTag(text: String?): ObserverTag? {
        if (text == null || text.length > 240) return null
        val fields = text.split('|')
        if (fields.size != 8 || !("1" == fields[0])) return null
        try {
            if (!java.util.UUID.fromString(fields[1]).toString().equals(fields[1])) return null
            val values = LongArray(6)
            for (i in 0..5) {
                if (!fields[i + 2].matches(Regex("[1-9][0-9]{0,15}"))) return null
                values[i] = java.lang.Long.parseLong(fields[i + 2])
                if (values[i] > 9007199254740991L) return null
            }
            return ObserverTag(
                text.substring(0, text.lastIndexOf('|')),
                text,
                fields[1],
                values[0],
                values[1],
                values[2],
                values[3],
                values[4],
                values[5],
            )
        } catch (invalid: IllegalArgumentException) {
            return null
        }
    }

    @Throws(ReflectiveOperationException::class)
    internal fun observerParams(packet: StatePacket): PZNetKahluaTableImpl {
        var field = observerParamsField
        if (field == null) {
            field = StatePacket::class.java.getDeclaredField("params")
            field.setAccessible(true)
            observerParamsField = field
        }
        return field.get(packet) as PZNetKahluaTableImpl
    }

    @Throws(ReflectiveOperationException::class)
    private fun observerTag(packet: StatePacket): ObserverTag? {
        val value = observerParams(packet).rawget(OBSERVER_MARKER)
        return if (value is String) observerAssociationTag(value) else null
    }

    private fun observerRole(): String? {
        if (GameServer.server) return "server"
        val p = IsoPlayer.getInstance()
        return if (p == null) "unavailable" else p.getUsername()
    }

    private fun observerOwner(source: ObserverSource, returned: Boolean): Boolean {
        val owner = source.owner.get()
        val action = source.action.get()
        val connection = source.connection.get()
        val table = source.table.get()
        if (
            (source.ended ||
                (returned && !source.returned) ||
                !leaseControlOwnedClient() ||
                owner !== IsoPlayer.getInstance() ||
                action == null ||
                table == null ||
                action.chr !== owner ||
                action.getTable() !== table ||
                table.rawget("character") !== owner ||
                table.rawget("action") !== action ||
                GameClient.connection !== connection ||
                owner.getCharacterActions().isEmpty() ||
                owner.getCharacterActions().get(0) !== action)
        )
            return false
        val engine = GameClient.instance.udpEngine
        return connection != null &&
            engine != null &&
            engine.getActiveConnection(connection.getConnectedGUID()) === connection
    }

    @JvmStatic
    fun observerBegin(action: LuaTimedActionNew): ObserverSource? {
        if (!observerEnabled()) return null
        try {
            if (
                (!leaseControlOwnedClient() ||
                    !(action.chr is IsoPlayer) ||
                    (action.chr as IsoPlayer) !== IsoPlayer.getInstance() ||
                    action.getTable() == null ||
                    !(action.getTable().rawget("Type") is String) ||
                    !actionAdmissionKind((action.getTable().rawget("Type") as String?)))
            )
                return null
            val record =
                ObserverSource(
                    action,
                    (action.chr as IsoPlayer),
                    GameClient.connection,
                    observerSequence.incrementAndGet(),
                )
            if (!observerOwner(record, false)) return null
            val previous = observerSources.get(action)
            if (previous != null && !previous.ended) {
                previous.ended = true
                observerSourceLog("source-end", previous, "source-restarted", true)
            }
            observerSources.put(action, record)
            observerSourceLog("source-begin", record, "native-start-enter", true)
            return record
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerBeginExit(source: ObserverSource?, failure: Throwable?) {
        if (source == null) return
        try {
            if (failure == null) source.returned = true
            else {
                source.ended = true
                observerSourceLog("source-end", source, "start-threw", false)
            }
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerSourceEnd(action: LuaTimedActionNew, reason: String, failure: Throwable?) {
        if (!observerEnabled()) return
        try {
            val source = observerSources.get(action)
            if (source != null && !source.ended) {
                source.ended = true
                observerSourceLog("source-end", source, reason, failure == null)
            }
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @LuaMethod(name = "cartObserverSource", global = true)
    @JvmStatic
    fun cartObserverSource(actualNative: Any?): String? {
        if (!observerEnabled() || !(actualNative is LuaTimedActionNew)) return null
        try {
            val source = observerSources.get(actualNative)
            if (source != null && observerOwner(source, true)) {
                observerSourceLog("source-capture", source, "exact-current-native", true)
                return source.life
            }
            return null
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerSet(packet: StatePacket, args: Array<Any?>, failure: Throwable?) {
        if (!observerEnabled() || failure != null) return
        try {
            observerPackets.remove(packet)
            if (
                (args.size != 3 ||
                    args[1] !== PlayerActionsState.instance() ||
                    !(args[0] is IsoPlayer) ||
                    !(args[0] as IsoPlayer).isLocalPlayer() ||
                    (args[0] as IsoPlayer).getCharacterActions().isEmpty() ||
                    !((args[0] as IsoPlayer).getCharacterActions().get(0) is LuaTimedActionNew))
            )
                return
            val source =
                observerSources.get(
                    ((args[0] as IsoPlayer).getCharacterActions().get(0) as LuaTimedActionNew),
                )
            if (
                source == null ||
                    source.owner.get() !== (args[0] as IsoPlayer) ||
                    !observerOwner(source, false)
            )
                return
            val params = observerParams(packet)
            if (params.rawget(OBSERVER_MARKER) != null)
                throw IllegalStateException("Diagnostic State marker key collision")
            val tag = observerAssociationTag(source.life + "|" + observerSequence.incrementAndGet())
            if (tag == null) throw IllegalStateException("Diagnostic State marker encoding failed")
            params.rawset(OBSERVER_MARKER, tag.text)
            val record = ObserverPacket(packet, (args[0] as IsoPlayer), tag)
            record.sourceValidated = true
            observerPackets.put(packet, record)
            observerLog("state-set", record, null, 0, "native-set-data", true, 0, 0, 0, 0, "", 0)
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerParseEnter(reader: ByteBufferReader, connection: IConnection?): ObserverParse? {
        if (!observerEnabled()) return null
        try {
            var ingress = leaseControlIngresses.get(reader)
            if (
                (ingress == null ||
                    ingress.transport.type != PacketTypes.PacketType.State.getId().toInt() ||
                    ingress.transport.connection.get() !== connection ||
                    !leaseControlCurrent(ingress.transport, GameServer.server))
            )
                ingress = null
            return ObserverParse(reader.position(), ingress)
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerParsed(
        packet: StatePacket,
        reader: ByteBufferReader,
        scope: ObserverParse?,
        failure: Throwable?,
    ) {
        if (scope == null) return
        try {
            observerPackets.remove(packet)
            if (failure != null) return
            val tag = observerTag(packet)
            if (tag == null) return
            if (
                !(packet.getCharacter() is IsoPlayer) ||
                    packet.getState() !== PlayerActionsState.instance()
            )
                return
            val record = ObserverPacket(packet, (packet.getCharacter() as IsoPlayer), tag)
            record.ingress = scope.ingress
            record.receive = observerSequence.incrementAndGet()
            observerPackets.put(packet, record)
            observerLog(
                "state-parse",
                record,
                null,
                0,
                if (record.ingress == null) "ingress-unavailable" else "native-parse",
                true,
                scope.begin,
                reader.position(),
                reader.position() - scope.begin,
                0,
                "",
                0,
            )
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    internal fun observerTransport(record: ObserverPacket?): Boolean {
        return record != null &&
            record.ingress != null &&
            leaseControlCurrent(record.ingress!!.transport, GameServer.server)
    }

    @Throws(ReflectiveOperationException::class)
    private fun observerServerActor(record: ObserverPacket, connection: UdpConnection): Boolean {
        val player = record.owner.get()
        val packet = record.packet.get()
        if (
            player == null ||
                packet == null ||
                !observerTransport(record) ||
                record.ingress!!.transport.connection.get() !== connection ||
                !actionAdmissionRegistered(player, connection)
        )
            return false
        var id = observerCharacterField
        if (id == null) {
            id = StatePacket::class.java.getDeclaredField("characterId")
            id.setAccessible(true)
            observerCharacterField = id
        }
        val character = id.get(packet)
        var slot = observerPlayerField
        if (slot == null) {
            slot =
                zombie.network.fields.character.CharacterID::class.java.getDeclaredField("playerId")
            slot.setAccessible(true)
            observerPlayerField = slot
        }
        val wire = slot.get(character) as PlayerID
        return wire.getPlayer() === player &&
            wire.getID() == player.getOnlineID() &&
            wire.getPlayerIndex().toInt() == player.playerIndex
    }

    @JvmStatic
    fun observerProcessEnter(
        packet: StatePacket,
        connection: UdpConnection,
        server: Boolean,
    ): ObserverProcess? {
        if (!observerEnabled()) return null
        val previous = observerProcessing.get()
        var record: ObserverPacket? = null
        try {
            record = observerPackets.get(packet)
            if (record != null) {
                var valid =
                    observerTransport(record) &&
                        record.ingress!!.transport.connection.get() === connection
                if (server)
                    record.sourceValidated = valid && observerServerActor(record, connection)
                else
                    valid =
                        (valid &&
                            record.owner.get() != null &&
                            !record.owner.get()!!.isLocalPlayer() &&
                            GameClient.IDToPlayerMap.get(record.owner.get()!!.getOnlineID()) ===
                                record.owner.get())
                record.processed = valid && (!server || record.sourceValidated)
            }
        } catch (error: Throwable) {
            observerError(error)
        }

        val scope = ObserverProcess(record, server, previous)
        observerProcessing.set(scope)
        return scope
    }

    @JvmStatic
    fun observerProcessExit(scope: ObserverProcess?, failure: Throwable?) {
        if (scope == null) return
        try {
            val record = scope.input
            if (record != null) {
                if (failure != null) record.processed = false
                observerLog(
                    if (scope.server) "state-process-server" else "state-process-client",
                    record,
                    null,
                    record.apply,
                    "native-process",
                    failure == null,
                    0,
                    0,
                    0,
                    0,
                    "",
                    0,
                )
                if (!scope.server && !record.applied && !observerQueued(record))
                    observerDiscard(record, "process-not-retained")
            }
        } catch (error: Throwable) {
            observerError(error)
        } finally {
            if (scope.previous == null) observerProcessing.remove()
            else observerProcessing.set(scope.previous)
        }
    }

    private fun observerQueued(record: ObserverPacket): Boolean {
        val packet = record.packet.get()
        val owner = record.owner.get()
        if (packet == null || owner == null || owner.getNetworkCharacterAI() == null) return false
        val state = owner.getNetworkCharacterAI().getState()
        val type = packet.getState()
        return state.getEnterState(type) === packet ||
            state.getEnterSubState(type) === packet ||
            state.getExitState(type) === packet ||
            state.getExitSubState(type) === packet
    }

    @JvmStatic
    fun observerWritten(
        packet: StatePacket,
        writer: ByteBufferWriter,
        begin: Int,
        failure: Throwable?,
    ) {
        if (!observerEnabled()) return
        try {
            val record = observerPackets.get(packet)
            if (record == null || failure != null) return
            val send = nativeTimeSends.get(writer)
            val endpoint = if (send == null) null else send.endpoint.get()
            val connection = if (send == null) 0 else send.connection
            val peer = if (send == null) "unavailable" else send.peer
            if (send != null && send.thread != Thread.currentThread().threadId())
                throw IllegalStateException("Foreign diagnostic State writer thread")
            if (
                begin < 3 ||
                    (writer.bb.get(begin - 3).toInt() and 255) != 134 ||
                    writer.bb.getShort(begin - 2) != PacketTypes.PacketType.State.getId()
            )
                throw IllegalStateException("Diagnostic State write header changed")
            val end = writer.bb.position()
            if (end < begin || end - begin > 2048)
                throw IllegalStateException("Diagnostic State body exceeds capacity")
            val processing = observerProcessing.get()
            val parent = if (GameServer.server) record.receive else 0
            val reason =
                if (GameServer.server)
                    (if (processing != null && processing.input === record) "native-relay"
                    else "retained-sync")
                else "native-source"
            if (endpoint != null)
                observerSends.put(
                    endpoint,
                    ObserverSend(
                        record,
                        checkNotNull(send).generation,
                        connection,
                        peer,
                        parent,
                        begin,
                        end,
                        Thread.currentThread().threadId(),
                    ),
                )
            observerLog(
                "state-write",
                record,
                null,
                0,
                reason,
                true,
                begin,
                end,
                end - begin,
                connection,
                peer,
                if (send == null) 0 else send.generation,
            )
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerSendStarted(connection: UdpConnection) {
        if (!observerEnabled()) return
        try {
            observerSends.remove(connection)
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerSendEnter(connection: UdpConnection): ObserverSend? {
        if (!observerEnabled()) return null
        try {
            val send = observerSends.get(connection)
            observerSends.remove(connection)
            if (send != null && send.thread != Thread.currentThread().threadId())
                throw IllegalStateException("Foreign diagnostic State submission")
            return send
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerSendExit(send: ObserverSend?, cancel: Boolean, failure: Throwable?) {
        if (send == null) return
        try {
            observerLog(
                if (cancel || failure != null) "state-cancel" else "state-submit",
                send.input,
                null,
                0,
                if (cancel) "native-cancel" else "native-submit",
                failure == null,
                send.begin,
                send.end,
                send.end - send.begin,
                send.connection,
                send.peer,
                send.generation,
            )
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerApplyEnter(packet: StatePacket): ObserverApply? {
        if (!observerEnabled()) return null
        val previous = observerApplying.get()
        val record = observerPackets.get(packet)
        val generation = observerSequence.incrementAndGet()
        if (record != null) record.apply = generation
        val scope = ObserverApply(record, generation, previous)
        observerApplying.set(scope)
        return scope
    }

    @JvmStatic
    fun observerApplyExit(scope: ObserverApply?, failure: Throwable?) {
        if (scope == null) return
        try {
            val record = scope.input
            if (record != null) {
                record.applied = failure == null
                val actor = record.owner.get()
                var associated = if (actor == null) null else observerActors.get(actor)
                if (
                    associated != null &&
                        (associated.input !== record || associated.apply != scope.generation)
                )
                    associated = null
                observerLog(
                    "state-apply",
                    record,
                    associated,
                    scope.generation,
                    "native-apply",
                    failure == null,
                    0,
                    0,
                    0,
                    0,
                    "",
                    0,
                )
                if (failure != null) {
                    val owner = record.owner.get()
                    val proxy = if (owner == null) null else observerActors.get(owner)
                    if (proxy != null && proxy.apply == scope.generation) {
                        proxy.state = "stopped"
                        proxy.reason = "apply-threw"
                        observerLog(
                            "proxy-stop",
                            record,
                            proxy,
                            proxy.apply,
                            proxy.reason,
                            false,
                            0,
                            0,
                            0,
                            0,
                            "",
                            0,
                        )
                    }
                }
            }
        } catch (error: Throwable) {
            observerError(error)
        } finally {
            if (scope.previous == null) observerApplying.remove()
            else observerApplying.set(scope.previous)
        }
    }

    private fun observerProxyCurrent(proxy: ObserverProxy): Boolean {
        val owner = proxy.owner.get()
        val action = proxy.proxy.get()
        return owner != null &&
            action != null &&
            owner.getNetworkCharacterAI() != null &&
            owner.getNetworkCharacterAI().getAction() === action
    }

    private fun observerProxyValid(proxy: ObserverProxy): Boolean {
        val owner = proxy.owner.get()
        return (("active" == proxy.state) &&
            (!("retained-params" == proxy.associationKind) || observerParamsHealthy()) &&
            observerProxyCurrent(proxy) &&
            proxy.input.applied &&
            proxy.input.processed &&
            observerTransport(proxy.input) &&
            owner != null &&
            !owner.isDead() &&
            !owner.isLocalPlayer() &&
            GameClient.IDToPlayerMap.get(owner.getOnlineID()) === owner)
    }

    private fun observerNativeAction(ai: NetworkCharacterAI): BaseAction? = ai.getAction()

    @JvmStatic
    fun observerAction(ai: NetworkCharacterAI, action: BaseAction?, failure: Throwable?) {
        if (!observerEnabled() || failure != null) return
        try {
            if (
                !(ai.getCharacter() is IsoPlayer) ||
                    (ai.getCharacter() as IsoPlayer).isLocalPlayer() ||
                    observerNativeAction(ai) !== action
            )
                return
            val old = observerActors.get((ai.getCharacter() as IsoPlayer))
            if (
                old != null &&
                    (action == null || old.proxy.get() !== action) &&
                    ("active" == old.state)
            ) {
                old.state = "replaced"
                old.reason = "native-replacement"
                observerReplacement(old, action)
            }
            val scope = observerApplying.get()
            val record = if (scope == null) null else scope.input
            if (
                record == null ||
                    record.owner.get() !== (ai.getCharacter() as IsoPlayer) ||
                    !("Enter" == record.stage) ||
                    !record.processed ||
                    !observerTransport(record) ||
                    action == null ||
                    action.chr !== (ai.getCharacter() as IsoPlayer)
            )
                return
            val proxy =
                ObserverProxy(action, (ai.getCharacter() as IsoPlayer), record, scope.generation)
            observerProxies.put(action, proxy)
            observerActors.put((ai.getCharacter() as IsoPlayer), proxy)
            observerLog(
                "proxy-associate",
                record,
                proxy,
                proxy.apply,
                "exact-apply-set-action",
                true,
                0,
                0,
                0,
                0,
                "",
                0,
            )
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    // Historical input association after every native consumer read completed; never a new action
    // grant.
    @JvmStatic
    fun observerParamsConsumed(
        input: ObserverPacket?,
        owner: IsoPlayer?,
        action: BaseAction?,
        applyGeneration: Long,
        consumeGeneration: Long,
        mapEpoch: Long,
        revision: Long,
    ) {
        if (!observerEnabled() || observerApplying.get() != null) return
        try {
            if (
                (input == null ||
                    input.owner.get() !== owner ||
                    !input.applied ||
                    !input.processed ||
                    !observerTransport(input) ||
                    owner == null ||
                    owner.isLocalPlayer() ||
                    owner.isDead() ||
                    GameClient.IDToPlayerMap.get(owner.getOnlineID()) !== owner ||
                    action == null ||
                    action.chr !== owner ||
                    owner.getNetworkCharacterAI() == null ||
                    owner.getNetworkCharacterAI().getAction() !== action ||
                    input.apply != applyGeneration ||
                    !("Enter" == input.stage) ||
                    consumeGeneration <= 0 ||
                    mapEpoch <= 0 ||
                    revision <= 0)
            )
                return
            val previous = observerActors.get(owner)
            if (previous != null && previous.proxy.get() === action) return
            if (previous != null && ("active" == previous.state)) {
                previous.state = "replaced"
                previous.reason = "native-replacement"
                observerReplacement(previous, action)
            }
            val proxy =
                ObserverProxy(
                    action,
                    owner,
                    input,
                    applyGeneration,
                    "retained-params",
                    consumeGeneration,
                    mapEpoch,
                    revision,
                )
            observerProxies.put(action, proxy)
            observerActors.put(owner, proxy)
            observerLog(
                "proxy-associate",
                input,
                proxy,
                applyGeneration,
                "exact-retained-params-consumer",
                true,
                0,
                0,
                0,
                0,
                "",
                0,
            )
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerStopEnter(ai: NetworkCharacterAI): ObserverProxy? {
        if (!observerEnabled()) return null
        try {
            val action = ai.getAction()
            return if (action == null) null else observerProxies.get(action)
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerStopExit(proxy: ObserverProxy?, failure: Throwable?) {
        if (proxy == null) return
        try {
            if (("active" == proxy.state)) {
                proxy.state = "stopped"
                proxy.reason = if (failure == null) "native-stop" else "stop-threw"
                observerLog(
                    "proxy-stop",
                    proxy.input,
                    proxy,
                    proxy.apply,
                    proxy.reason,
                    failure == null,
                    0,
                    0,
                    0,
                    0,
                    "",
                    0,
                )
            }
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerQueueBefore(queue: java.util.LinkedList<*>): ObserverQueue? {
        if (!observerEnabled()) return null
        try {
            if (queue.size > 256)
                throw IllegalStateException("Diagnostic State queue exceeds capacity")
            val packets = ArrayList<StatePacket>()
            val records = ArrayList<ObserverPacket?>()
            for (value in queue) if (value is StatePacket) {
                val record = observerPackets.get(value)
                if (record != null) {
                    packets.add(value)
                    records.add(record)
                }
            }
            return ObserverQueue(packets, records)
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerQueueAfter(before: ObserverQueue?, queue: java.util.LinkedList<*>, reason: String) {
        if (before == null) return
        try {
            for (i in 0 until before.records.size) if (!queue.contains(before.packets.get(i)))
                observerDiscard(before.records.get(i), reason)
        } catch (error: Throwable) {
            observerError(error)
        } finally {
            java.lang.ref.Reference.reachabilityFence(before)
        }
    }

    @JvmStatic
    fun observerDiscard(record: ObserverPacket?, reason: String) {
        if (record == null || record.applied || record.discarded) return
        record.discarded = true
        observerLog("state-discard", record, null, record.apply, reason, true, 0, 0, 0, 0, "", 0)
    }

    @JvmStatic
    fun observerRemoved(packet: StatePacket?) {
        if (!observerEnabled() || packet == null) return
        try {
            observerDiscard(observerPackets.get(packet), "native-remove")
        } catch (error: Throwable) {
            observerError(error)
        }
    }

    @JvmStatic
    fun observerResetBefore(state: NetworkState): ArrayList<ObserverQueue>? {
        if (!observerEnabled()) return null
        try {
            val before = ArrayList<ObserverQueue>()
            for (name in
                arrayOf(
                    "enterStatePackets",
                    "enterSubStatePackets",
                    "exitStatePackets",
                    "exitSubStatePackets",
                )) {
                val field = NetworkState::class.java.getDeclaredField(name)
                field.setAccessible(true)
                val pending = observerQueueBefore(field.get(state) as java.util.LinkedList<*>)
                if (pending != null) before.add(pending)
            }
            return before
        } catch (error: Throwable) {
            observerError(error)
            return null
        }
    }

    @JvmStatic
    fun observerResetAfter(before: ArrayList<ObserverQueue>?, failure: Throwable?) {
        if (before == null) return
        try {
            if (failure == null)
                for (queue in before) for (record in queue.records) observerDiscard(
                    record,
                    "native-reset",
                )
        } catch (error: Throwable) {
            observerError(error)
        } finally {
            java.lang.ref.Reference.reachabilityFence(before)
        }
    }

    private fun observerFields(
        record: ObserverPacket?,
        proxy: ObserverProxy?,
        apply: Long,
        reason: String,
        success: Boolean,
        begin: Int,
        end: Int,
        bytes: Int,
        connection: Long,
        peer: String?,
        send: Long,
    ): LinkedHashMap<String, Any?> {
        var connection = connection
        var peer = peer
        val fields = LinkedHashMap<String, Any?>()
        val tag = if (record == null) null else record.tag
        val owner = if (record == null) null else record.owner.get()
        if (connection == 0L && record != null && record.ingress != null)
            connection = record.ingress!!.transport.epoch
        if (peer == null || peer.isEmpty())
            peer =
                if (record != null && record.ingress != null)
                    nativeTimePeer(record.ingress!!.transport.connection.get(), false)
                else "unavailable"
        fields.put("protocol", 1)
        fields.put("diagnosticWire", true)
        fields.put("process", nativeTimeProcess)
        fields.put("role", observerRole())
        fields.put("owner", if (owner == null) -1 else owner.getOnlineID())
        fields.put("actorEpoch", if (owner == null) 0 else nativeTimeIdentity(owner, true))
        fields.put("connectionEpoch", connection)
        fields.put("peerRole", peer)
        fields.put("sourceLife", if (tag == null) "" else tag.life)
        fields.put("stateTag", if (tag == null) "" else tag.text)
        fields.put("sourceProcess", if (tag == null) "" else tag.process)
        fields.put("sourceActorEpoch", if (tag == null) 0 else tag.actor)
        fields.put("sourceConnectionEpoch", if (tag == null) 0 else tag.connection)
        fields.put("sourceNativeEpoch", if (tag == null) 0 else tag.action)
        fields.put("sourceTableEpoch", if (tag == null) 0 else tag.table)
        fields.put("sourceBeginGeneration", if (tag == null) 0 else tag.begin)
        fields.put("stateGeneration", if (tag == null) 0 else tag.state)
        fields.put("packetEpoch", if (record == null) 0 else record.epoch)
        fields.put(
            "ingressGeneration",
            if (record == null || record.ingress == null) 0 else record.ingress!!.generation,
        )
        fields.put("receiveGeneration", if (record == null) 0 else record.receive)
        fields.put("sendGeneration", send)
        fields.put(
            "parentReceiveGeneration",
            if (record != null && GameServer.server) record.receive else 0,
        )
        fields.put("associationKind", if (proxy == null) "unavailable" else proxy.associationKind)
        fields.put("actionEpoch", if (proxy == null) 0 else proxy.actionEpoch)
        fields.put("consumeGeneration", if (proxy == null) 0 else proxy.consumeGeneration)
        fields.put("paramsMapEpoch", if (proxy == null) 0 else proxy.paramsMapEpoch)
        fields.put("paramsRevision", if (proxy == null) 0 else proxy.paramsRevision)
        fields.put("proxyEpoch", if (proxy == null) 0 else proxy.epoch)
        fields.put("applyGeneration", apply)
        fields.put("proxyState", if (proxy == null) "unavailable" else proxy.state)
        fields.put("proxyCurrent", proxy != null && observerProxyCurrent(proxy))
        fields.put("associationValid", proxy != null && observerProxyValid(proxy))
        fields.put(
            "transportValidated",
            record != null &&
                (observerTransport(record) ||
                    (record.ingress == null &&
                        connection > 0 &&
                        connection == record.tag.connection &&
                        GameClient.connection != null &&
                        nativeTimeIdentity(GameClient.connection, false) == connection &&
                        leaseControlOwnedClient())),
        )
        fields.put("sourceValidated", record != null && record.sourceValidated)
        fields.put("stage", if (record == null) "unavailable" else record.stage)
        fields.put("reason", reason)
        fields.put("packetBytes", bytes)
        fields.put("bodyBegin", begin)
        fields.put("bodyEnd", end)
        fields.put("success", success)
        fields.put("monoNs", System.nanoTime())
        fields.put("wallMs", System.currentTimeMillis())
        return fields
    }

    private fun observerWrite(event: String, fields: Map<String, Any?>) {
        val json = StringBuilder("{\"event\":").append(mpJsonString(event))
        for (entry in fields.entries) {
            val value = entry.value
            json
                .append(',')
                .append(mpJsonString(entry.key))
                .append(':')
                .append(
                    if (value is Number || value is Boolean) value
                    else mpJsonString(value as String?),
                )
        }
        System.out.println("[CART_OBSERVER] " + json.append('}'))
    }

    // Diagnostic call provenance only. A replacement is never rebound by its stack or timing.
    private fun observerReplacement(old: ObserverProxy, replacement: BaseAction?) {
        val fields = observerFields(old.input, old, old.apply, old.reason, true, 0, 0, 0, 0, "", 0)
        val scope = observerApplying.get()
        fields.put("replacementActionEpoch", nativeTimeIdentity(replacement, false))
        fields.put("replacementApplyGeneration", if (scope == null) 0 else scope.generation)
        fields.put("replacementTaggedApply", scope != null && scope.input != null)
        fields.put(
            "replacementStack",
            StackWalker.getInstance()
                .walk(
                    { frames ->
                        frames
                            .skip(1)
                            .limit(16)
                            .map({ frame -> frame.getClassName() + "." + frame.getMethodName() })
                            .collect(java.util.stream.Collectors.joining("|"))
                    },
                ),
        )
        observerWrite("proxy-replaced", fields)
    }

    private fun observerLog(
        event: String,
        record: ObserverPacket,
        proxy: ObserverProxy?,
        apply: Long,
        reason: String,
        success: Boolean,
        begin: Int,
        end: Int,
        bytes: Int,
        connection: Long,
        peer: String,
        send: Long,
    ) {
        observerWrite(
            event,
            observerFields(
                record,
                proxy,
                apply,
                reason,
                success,
                begin,
                end,
                bytes,
                connection,
                peer,
                send,
            ),
        )
    }

    private fun observerSourceLog(
        event: String,
        source: ObserverSource,
        reason: String,
        success: Boolean,
    ) {
        val tag = observerAssociationTag(source.life + "|1")
        val owner = source.owner.get()
        val fields =
            observerFields(
                null,
                null,
                0,
                reason,
                success,
                0,
                0,
                0,
                if (source.connection.get() == null) 0
                else nativeTimeIdentity(source.connection.get(), false),
                "server",
                0,
            )
        fields.put("owner", if (owner == null) -1 else owner.getOnlineID())
        fields.put("actorEpoch", if (owner == null) 0 else nativeTimeIdentity(owner, true))
        fields.put("sourceLife", source.life)
        fields.put("sourceProcess", nativeTimeProcess)
        fields.put("sourceActorEpoch", tag!!.actor)
        fields.put("sourceConnectionEpoch", tag.connection)
        fields.put("sourceNativeEpoch", tag.action)
        fields.put("sourceTableEpoch", tag.table)
        fields.put("sourceBeginGeneration", source.begin)
        fields.put("sourceValidated", true)
        val json = StringBuilder("{\"event\":").append(mpJsonString(event))
        for (entry in fields.entries) {
            val value = entry.value
            json
                .append(',')
                .append(mpJsonString(entry.key))
                .append(':')
                .append(
                    if (value is Number || value is Boolean) value
                    else mpJsonString(value as String?),
                )
        }
        System.out.println("[CART_OBSERVER] " + json.append('}'))
    }

    // Current proxy input only. A stopped retained pointer grants no active association.
    @JvmStatic
    fun observerAssociationSnapshot(owner: IsoPlayer?): String {
        if (!OBSERVER_ASSOCIATION) return ""
        try {
            val proxy = if (observerEnabled() && owner != null) observerActors.get(owner) else null
            val record = if (proxy == null) null else proxy.input
            return (",\"observerVersion\":2,\"observerDiagnosticWire\":true,\"observerProcess\":" +
                mpJsonString(nativeTimeProcess) +
                ",\"observerSourceLife\":" +
                mpJsonString(if (record == null) "" else record.tag.life) +
                ",\"observerStateTag\":" +
                mpJsonString(if (record == null) "" else record.tag.text) +
                ",\"observerStateGeneration\":" +
                (if (record == null) 0 else record.tag.state) +
                ",\"observerPacketEpoch\":" +
                (if (record == null) 0 else record.epoch) +
                ",\"observerIngressGeneration\":" +
                (if (record == null || record.ingress == null) 0 else record.ingress!!.generation) +
                ",\"observerReceiveGeneration\":" +
                (if (record == null) 0 else record.receive) +
                ",\"observerApplyGeneration\":" +
                (if (proxy == null) 0 else proxy.apply) +
                ",\"observerProxyEpoch\":" +
                (if (proxy == null) 0 else proxy.epoch) +
                ",\"observerAssociationKind\":" +
                mpJsonString(if (proxy == null) "unavailable" else proxy.associationKind) +
                ",\"observerConsumeGeneration\":" +
                (if (proxy == null) 0 else proxy.consumeGeneration) +
                ",\"observerParamsMapEpoch\":" +
                (if (proxy == null) 0 else proxy.paramsMapEpoch) +
                ",\"observerParamsRevision\":" +
                (if (proxy == null) 0 else proxy.paramsRevision) +
                ",\"observerProxyState\":" +
                mpJsonString(if (proxy == null) "unavailable" else proxy.state) +
                ",\"observerProxyCurrent\":" +
                (proxy != null && observerProxyCurrent(proxy)) +
                ",\"observerAssociationValid\":" +
                (proxy != null && observerProxyValid(proxy)) +
                ",\"observerReason\":" +
                mpJsonString(if (proxy == null) "unavailable" else proxy.reason))
        } catch (error: Throwable) {
            observerError(error)
            return ",\"observerVersion\":2,\"observerDiagnosticWire\":true,\"observerAssociationValid\":false,\"observerReason\":\"diagnostic-failed\""
        }
    }

    @Patch(
        className = "zombie.characters.CharacterTimedActions.LuaTimedActionNew",
        methodName = "stop",
        warmUp = false,
    )
    object ObserverAssociationSourceStop {
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        @JvmStatic
        fun exit(@Patch.This action: LuaTimedActionNew, @Patch.Thrown failure: Throwable?) {
            ObserverAssociation.observerSourceEnd(action, "native-stop", failure)
        }
    }

    @Patch(
        className = "zombie.characters.CharacterTimedActions.LuaTimedActionNew",
        methodName = "perform",
        warmUp = false,
    )
    object ObserverAssociationSourcePerform {
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        @JvmStatic
        fun exit(@Patch.This action: LuaTimedActionNew, @Patch.Thrown failure: Throwable?) {
            ObserverAssociation.observerSourceEnd(action, "native-perform", failure)
        }
    }

    @Patch(
        className = "zombie.network.packets.actions.StatePacket",
        methodName = "setData",
        warmUp = false,
    )
    object ObserverAssociationSet {
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        @JvmStatic
        fun exit(
            @Patch.This packet: StatePacket,
            @Patch.Argument(0) args: Array<Any?>,
            @Patch.Thrown failure: Throwable?,
        ) {
            ObserverAssociation.observerSet(packet, args, failure)
        }
    }

    @Patch(
        className = "zombie.core.raknet.UdpConnection",
        methodName = "startPacket",
        warmUp = false,
    )
    object ObserverAssociationSendStart {
        @Patch.OnExit
        @JvmStatic
        fun exit(@Patch.This connection: UdpConnection) {
            ObserverAssociation.observerSendStarted(connection)
        }
    }

    @Patch(
        className = "zombie.characters.NetworkCharacterAI",
        methodName = "setAction",
        warmUp = false,
    )
    object ObserverAssociationProxy {
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        @JvmStatic
        fun exit(
            @Patch.This ai: NetworkCharacterAI,
            @Patch.Argument(0) action: BaseAction?,
            @Patch.Thrown failure: Throwable?,
        ) {
            ObserverAssociation.observerAction(ai, action, failure)
        }
    }

    @Patch(
        className = "zombie.characters.NetworkState",
        methodName = "removeEnterState",
        warmUp = false,
    )
    object ObserverAssociationRemoveEnter {
        @Patch.OnExit
        @JvmStatic
        fun exit(@Patch.Argument(0) packet: StatePacket) {
            ObserverAssociation.observerRemoved(packet)
        }
    }

    @Patch(
        className = "zombie.characters.NetworkState",
        methodName = "removeEnterSubState",
        warmUp = false,
    )
    object ObserverAssociationRemoveEnterSub {
        @Patch.OnExit
        @JvmStatic
        fun exit(@Patch.Argument(0) packet: StatePacket) {
            ObserverAssociation.observerRemoved(packet)
        }
    }
}
