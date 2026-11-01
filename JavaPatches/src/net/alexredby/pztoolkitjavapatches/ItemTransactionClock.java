package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Transaction;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoDirections;
import java.util.List;

/** Native advice adapter; local timeout accounting lives in Kotlin. */
public final class ItemTransactionClock {
    private ItemTransactionClock() { }
    public static final boolean SUPPORTED = ItemTransactionClockLogic.SUPPORTED;

    public static void allocated(Transaction transaction) {
        ItemTransactionClockLogic.allocated(transaction);
    }
    public static boolean expired(Transaction transaction, boolean nativeResult) {
        try { return ItemTransactionClockLogic.expiredAt(transaction, nativeResult, System.nanoTime()); }
        catch (Throwable ignored) { return nativeResult; }
    }
    /** Deterministic timeout seam; this never changes a transaction or its timestamps. */
    public static boolean expiredAt(Transaction transaction, boolean nativeResult, long nowNanos) {
        return ItemTransactionClockLogic.expiredAt(transaction, nativeResult, nowNanos);
    }

    @Patch(className="zombie.core.Transaction", methodName="set", warmUp=true, strictMatch=true)
    public static class Allocated {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This Transaction transaction,
                @Patch.Argument(0) IsoPlayer actor, @Patch.Argument(1) List<InventoryItem> items,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Argument(4) String extra, @Patch.Argument(5) IsoDirections direction,
                @Patch.Argument(6) float x, @Patch.Argument(7) float y, @Patch.Argument(8) float z) {
            allocated(transaction);
        }
    }

    public static synchronized boolean install(boolean supported) {
        return ItemTransactionClockLogic.install(supported);
    }
    public static byte[] weave(byte[] bytes) {
        return ItemTransactionClockLogic.weave(bytes);
    }
}
