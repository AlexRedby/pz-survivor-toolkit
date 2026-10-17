package net.alexredby.pztoolkitjavapatches;

import java.nio.ByteBuffer;
import me.zed_0xff.zombie_buddy.Accessor;
import zombie.core.NetTimedAction;
import zombie.core.Transaction.TransactionState;
import zombie.core.network.ByteBufferReader;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.PZNetKahluaTableImpl;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.NetTimedActionPacket;

public final class MedicalTimedActions {
    private static final ThreadLocal<Scope> current = new ThreadLocal<>();

    public static final class Scope {
        final Scope previous;
        final NetTimedAction packet;
        final ByteBufferReader reader;
        final ByteBuffer buffer;
        final PZNetKahluaTableImpl previousArgs;
        final boolean active;
        PZNetKahluaTableImpl loading;
        boolean loaded;
        Scope(Scope previous, NetTimedAction packet, ByteBufferReader reader, boolean active) {
            this.previous = previous; this.packet = packet; this.reader = reader; this.buffer = reader.bb;
            this.previousArgs = Accessor.tryGet(packet, "actionArgs", (PZNetKahluaTableImpl)null);
            this.active = active;
        }
    }

    public static final class Arguments {
        final Scope scope;
        final PZNetKahluaTableImpl previous;
        Arguments(Scope scope, PZNetKahluaTableImpl table) {
            this.scope = scope; previous = scope.loading; scope.loading = table;
        }
    }

    private static final class StalePatient extends RuntimeException {
        final Scope scope;
        StalePatient(Scope scope) { this.scope = scope; }
    }

    public static Scope begin(NetTimedAction packet, ByteBufferReader reader, boolean supported) {
        Scope previous = current.get();
        boolean active = supported && GameServer.server && packet instanceof NetTimedActionPacket;
        if (!active && previous == null) return null;
        Scope scope = new Scope(previous, packet, reader, active);
        current.set(scope);
        return scope;
    }

    private static boolean incoming(Scope scope, ByteBufferReader reader) {
        return scope != null && scope.active && GameServer.server && scope.reader == reader && scope.buffer == reader.bb
            && Accessor.tryGet(scope.packet, "state", (TransactionState)null) == TransactionState.Request;
    }

    public static Arguments beginArguments(PZNetKahluaTableImpl table, ByteBufferReader reader) {
        Scope scope = current.get();
        if (!incoming(scope, reader) || scope.loaded) return null;
        var args = Accessor.tryGet(scope.packet, "actionArgs", (PZNetKahluaTableImpl)null);
        if (scope.loading == null && (table != args || table == scope.previousArgs)) return null;
        return new Arguments(scope, table);
    }

    public static void endArguments(Arguments arguments) {
        if (arguments != null) {
            arguments.scope.loading = arguments.previous;
            if (arguments.previous == null) arguments.scope.loaded = true;
        }
    }

    public static void beforeValue(PZNetKahluaTableImpl table, ByteBufferReader reader, IConnection connection, byte type) {
        Scope scope = current.get();
        if (type != 10 || !incoming(scope, reader) || scope.loading != table) return;
        var doctor = Accessor.tryGet(scope.packet, "playerId", (PlayerID)null);
        if (doctor == null || !doctor.isConsistent(connection)) return;
        // B42.21 BodyPart is PlayerID + int index; inspect a duplicate without consuming the native decoder's input.
        var probe = new ByteBufferReader(reader.bb.duplicate().order(reader.bb.order()));
        var patient = new PlayerID(); patient.parse(probe, connection); probe.getInt();
        if (patient.getPlayer() == null) throw new StalePatient(scope);
    }

    public static boolean end(Scope scope, Throwable failure) {
        if (scope == null) return false;
        try {
            if (!(failure instanceof StalePatient stale) || stale.scope != scope) return false;
            scope.packet.action = null;
            var args = Accessor.tryGet(scope.packet, "actionArgs", (PZNetKahluaTableImpl)null);
            if (args != null && args != scope.previousArgs) args.wipe();
            // ZomboidNetData bounds this buffer to one datagram; discard it and let native processServer send Reject.
            scope.buffer.position(scope.buffer.limit());
            return true;
        } finally {
            if (scope.previous == null) current.remove(); else current.set(scope.previous);
        }
    }
}
