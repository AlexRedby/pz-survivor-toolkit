package net.alexredby.pztoolkitjavapatches;

import java.util.Iterator;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Transaction;
import zombie.inventory.ItemContainer;
import zombie.network.packets.ItemTransactionPacket;

/** Adds an incoming batch's checked prefix to native Request admission, without publishing it. */
public final class ItemBatchAdmission {
    public static final boolean SUPPORTED = ItemBatchAdmissionLogic.SUPPORTED;
    private static final ThreadLocal<RequestScope> requests = new ThreadLocal<>();
    private static final ThreadLocal<CheckScope> checks = new ThreadLocal<>();

    private ItemBatchAdmission() { }

    public static synchronized boolean install(boolean supported) {
        return ItemBatchAdmissionLogic.install(supported);
    }

    public static final class RequestScope {
        final RequestScope previous;
        final ItemTransactionPacket packet;
        final List<?> entries;
        final ItemBatchAdmissionLogic.Shadow prefix;
        int index;
        boolean checking;
        RequestScope(RequestScope previous, ItemTransactionPacket packet, List<?> entries) {
            this.previous = previous;
            this.packet = packet;
            this.entries = entries;
            this.prefix = new ItemBatchAdmissionLogic.Shadow(packet);
        }
    }

    public static RequestScope beginRequest(ItemTransactionPacket packet) {
        return ItemBatchAdmissionLogic.beginRequest(packet, requests);
    }

    public static void endRequest(RequestScope scope) {
        ItemBatchAdmissionLogic.endRequest(scope, requests);
    }

    public static final class CheckScope {
        final CheckScope previous;
        final RequestScope request;
        final Object entry;
        CheckScope(CheckScope previous, RequestScope request, Object entry) {
            this.previous = previous;
            this.request = request;
            this.entry = entry;
        }
    }

    public static CheckScope beginCheck(ItemTransactionPacket packet, int itemId,
                                        ItemContainer source, ItemContainer destination) {
        return ItemBatchAdmissionLogic.beginCheck(packet, itemId, source, destination, requests, checks);
    }

    public static void endCheck(CheckScope scope, byte result, Throwable failure) {
        ItemBatchAdmissionLogic.endCheck(scope, result, failure, checks);
    }

    /** Called only at the native isConsistent reservation-iteration site. No queue mutation. */
    public static Iterator<Transaction> reservations(ConcurrentLinkedQueue<Transaction> real) {
        return ItemBatchAdmissionLogic.reservations(real, checks);
    }

    /** Testable transformation seam. Unsupported or already changed native bytecode stays untouched. */
    public static byte[] weave(byte[] bytes) {
        return ItemBatchAdmissionLogic.weave(bytes);
    }

    @Patch(className="zombie.network.packets.ItemTransactionPacket", methodName="processServer", warmUp=true, strictMatch=true)
    public static class RequestAdmission {
        @Patch.OnEnter
        public static void enter(@Patch.This ItemTransactionPacket packet,
                                 @Patch.Argument(1) zombie.core.raknet.UdpConnection connection,
                                 @Patch.Local("toolkitItemBatchRequest") RequestScope scope) {
            scope = beginRequest(packet);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitItemBatchRequest") RequestScope scope) {
            endRequest(scope);
        }
    }

    @Patch(className="zombie.core.TransactionManager", methodName="isConsistent", warmUp=true, strictMatch=true)
    public static class EntryAdmission {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) int itemId, @Patch.Argument(2) ItemContainer source,
                                 @Patch.Argument(3) ItemContainer destination, @Patch.Argument(5) ItemTransactionPacket packet,
                                 @Patch.Local("toolkitItemBatchCheck") CheckScope scope) {
            scope = beginCheck(packet, itemId, source, destination);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitItemBatchCheck") CheckScope scope,
                                @Patch.Return byte result, @Patch.Thrown Throwable failure) {
            endCheck(scope, result, failure);
        }
    }
}
