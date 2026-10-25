package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.raknet.UdpConnection;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.ItemTransactionPacket;

public final class QueueManagers {
    public static final boolean ITEM_SUPPORTED = QueueManagersLogic.ITEM_SUPPORTED;
    public static final boolean ACTION_SUPPORTED = QueueManagersLogic.ACTION_SUPPORTED;

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
        return QueueManagersLogic.beginReject(packet, connection, rejectScope);
    }

    public static void endReject(RejectScope scope) {
        QueueManagersLogic.endReject(scope, rejectScope);
    }

    public static boolean removeOwned(byte id) {
        return QueueManagersLogic.removeOwned(id, rejectScope);
    }

    public static boolean hasAction(PlayerID owner, byte id) {
        return QueueManagersLogic.hasAction(owner, id);
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
