package net.alexredby.pztoolkitjavapatches;

import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.ActionManager;
import zombie.core.Transaction;
import zombie.core.Transaction.TransactionState;
import zombie.core.TransactionManager;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.ItemTransactionPacket;

public final class QueueManagers {
    public static final boolean ITEM_SUPPORTED = Main.supports("zombie/core/TransactionManager.class",
            "4a0f649f5e55edd13eff7d6788934fbec49e0073901609e1c12731fc47d7481d")
        && Main.supports("zombie/core/Transaction.class",
            "107b0a554cc46d1015398ff283a2e48faf02efbc44adf12854f66394ee2487b6")
        && Main.supports("zombie/network/packets/ItemTransactionPacket.class",
            "41608a6690d16cb0ac202a4a3196b2b0851dadb935bca2b1d9a0a3e501791e83")
        && Main.supports("zombie/core/raknet/UdpConnection.class",
            "9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763");
    public static final boolean ACTION_SUPPORTED = Main.supports("zombie/core/ActionManager.class",
            "3e85655f0d287837b17164d2ee4cecb7067ab419ffbe8ce1adb36bd7d54b202f")
        && Main.supports("zombie/core/Action.class",
            "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d");

    private static final ThreadLocal<RejectScope> rejectScope = new ThreadLocal<>();

    public static final class RejectScope {
        final UdpConnection connection;
        final RejectScope previous;
        RejectScope(UdpConnection connection, RejectScope previous) {
            this.connection = connection;
            this.previous = previous;
        }
    }

    public static RejectScope beginReject(ItemTransactionPacket packet, UdpConnection connection) {
        if (!ITEM_SUPPORTED || !GameServer.server || GameClient.client
            || Accessor.tryGet(packet, "state", (TransactionState)null) != TransactionState.Reject) return null;
        RejectScope scope = new RejectScope(connection, rejectScope.get());
        rejectScope.set(scope);
        return scope;
    }

    public static void endReject(RejectScope scope) {
        if (scope == null) return;
        if (scope.previous == null) rejectScope.remove();
        else rejectScope.set(scope.previous);
    }

    public static boolean removeOwned(byte id) {
        RejectScope scope = rejectScope.get();
        if (!ITEM_SUPPORTED || scope == null) return false;
        var transactions = Accessor.tryGet(TransactionManager.class, "transactions", (ConcurrentLinkedQueue<Transaction>)null);
        if (transactions != null) transactions.removeIf(transaction -> {
            Byte candidate = Accessor.tryGet(transaction, "id", (Byte)null);
            PlayerID owner = Accessor.tryGet(transaction, "playerId", (PlayerID)null);
            // Reject omits the player on the wire; only the receiving connection can establish ownership.
            return candidate != null && candidate == id && scope.connection != null && owner != null
                && scope.connection.havePlayer(owner.getPlayer());
        });
        return true;
    }

    public static boolean hasAction(PlayerID owner, byte id) {
        var actions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<?>)null);
        if (actions == null) return false;
        for (Object action : actions) {
            Byte candidate = Accessor.tryGet(action, "id", (Byte)null);
            PlayerID player = Accessor.tryGet(action, "playerId", (PlayerID)null);
            if (candidate != null && candidate == id && player != null && player.getID() == owner.getID()) return true;
        }
        return false;
    }

    @Patch(className="zombie.network.packets.ItemTransactionPacket", methodName="processServer", warmUp=true, strictMatch=true)
    public static class ItemRejectConnection {
        @Patch.OnEnter
        public static void enter(@Patch.This ItemTransactionPacket packet, @Patch.Argument(1) UdpConnection connection,
                                 @Patch.Local("toolkitItemRejectScope") RejectScope scope) {
            scope = beginReject(packet, connection);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitItemRejectScope") RejectScope scope) {
            endReject(scope);
        }
    }

    @Patch(className="zombie.core.TransactionManager", methodName="removeItemTransaction", warmUp=true, strictMatch=true)
    public static class ItemRejectOwner {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) byte id, @Patch.Argument(1) boolean cancel) {
            return removeOwned(id);
        }
    }

    @Patch(className="zombie.core.ActionManager", methodName="isDone", warmUp=true, strictMatch=true)
    public static class ActionDone {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) PlayerID owner, @Patch.Argument(1) byte id,
                                @Patch.Return(readOnly=false) boolean result) {
            if (ACTION_SUPPORTED && result) result = hasAction(owner, id);
        }
    }
}
