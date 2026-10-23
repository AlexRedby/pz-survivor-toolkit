package net.alexredby.pztoolkitjavapatches

import java.nio.ByteBuffer
import me.zed_0xff.zombie_buddy.Accessor
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.core.network.ByteBufferReader
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.PZNetKahluaTableImpl
import zombie.network.fields.character.PlayerID
import zombie.network.packets.NetTimedActionPacket

object MedicalTimedActions {
    private val current = ThreadLocal<Scope>()

    class Scope(
        previous: Scope?,
        packet: NetTimedAction?,
        reader: ByteBufferReader?,
        active: Boolean,
    ) {
        @JvmField val previous = previous
        @JvmField val packet = packet
        @JvmField val reader = reader
        @JvmField val buffer: ByteBuffer? = (reader ?: throw NullPointerException()).bb
        @JvmField
        val previousArgs = Accessor.tryGet<PZNetKahluaTableImpl>(packet, "actionArgs", null)
        @JvmField val active = active
        @JvmField var loading: PZNetKahluaTableImpl? = null
        @JvmField var loaded = false
    }

    class Arguments(scope: Scope, table: PZNetKahluaTableImpl?) {
        @JvmField val scope = scope
        @JvmField val previous = scope.loading

        init {
            scope.loading = table
        }
    }

    private class StalePatient(val scope: Scope) : RuntimeException()

    @JvmStatic
    fun begin(packet: NetTimedAction?, reader: ByteBufferReader?, supported: Boolean): Scope? {
        val previous = current.get()
        val active = supported && GameServer.server && packet is NetTimedActionPacket
        if (!active && previous == null) return null
        val scope = Scope(previous, packet, reader, active)
        current.set(scope)
        return scope
    }

    private fun incoming(scope: Scope?, reader: ByteBufferReader?): Boolean =
        scope != null &&
            scope.active &&
            GameServer.server &&
            scope.reader === reader &&
            scope.buffer === (reader ?: throw NullPointerException()).bb &&
            Accessor.tryGet<TransactionState>(scope.packet, "state", null) ===
                TransactionState.Request

    @JvmStatic
    fun beginArguments(table: PZNetKahluaTableImpl?, reader: ByteBufferReader?): Arguments? {
        val scope = current.get() ?: return null
        if (!incoming(scope, reader) || scope.loaded) return null
        val args = Accessor.tryGet<PZNetKahluaTableImpl>(scope.packet, "actionArgs", null)
        if (scope.loading == null && (table !== args || table === scope.previousArgs)) return null
        return Arguments(scope, table)
    }

    @JvmStatic
    fun endArguments(arguments: Arguments?) {
        if (arguments != null) {
            arguments.scope.loading = arguments.previous
            if (arguments.previous == null) arguments.scope.loaded = true
        }
    }

    @JvmStatic
    fun beforeValue(
        table: PZNetKahluaTableImpl?,
        reader: ByteBufferReader?,
        connection: IConnection?,
        type: Byte,
    ) {
        val scope = current.get()
        if (
            type.toInt() != 10 ||
                !incoming(scope, reader) ||
                (scope ?: throw NullPointerException()).loading !== table
        )
            return
        val doctor = Accessor.tryGet<PlayerID>(scope.packet, "playerId", null)
        if (doctor == null || !doctor.isConsistent(connection)) return
        // B42.21 BodyPart is PlayerID + int index; inspect a duplicate without consuming the native
        // decoder's input.
        val bytes = (reader ?: throw NullPointerException()).bb
        val probe = ByteBufferReader(bytes.duplicate().order(bytes.order()))
        val patient = PlayerID()
        patient.parse(probe, connection)
        probe.getInt()
        if (patient.getPlayer() == null) throw StalePatient(scope)
    }

    @JvmStatic
    fun end(scope: Scope?, failure: Throwable?): Boolean {
        if (scope == null) return false
        try {
            if (failure !is StalePatient || failure.scope !== scope) return false
            val packet = scope.packet ?: throw NullPointerException()
            packet.action = null
            val args = Accessor.tryGet<PZNetKahluaTableImpl>(packet, "actionArgs", null)
            if (args != null && args !== scope.previousArgs) args.wipe()
            // ZomboidNetData bounds this buffer to one datagram; discard it and let native
            // processServer send Reject.
            val buffer = scope.buffer ?: throw NullPointerException()
            buffer.position(buffer.limit())
            return true
        } finally {
            if (scope.previous == null) current.remove() else current.set(scope.previous)
        }
    }
}
