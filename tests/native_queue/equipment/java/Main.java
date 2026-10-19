package net.alexredby.equipmentprobe;

import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.pztoolkitjavapatches.QueueManagers;
import se.krka.kahlua.vm.JavaFunction;
import zombie.Lua.LuaManager;
import zombie.core.NetTimedAction;
import zombie.core.Transaction.TransactionState;
import zombie.core.TransactionManager;
import zombie.inventory.InventoryItem;
import zombie.network.GameServer;

/** Read-only drain evidence for the isolated one-player equipment fixture. */
public final class Main {
    private static final JavaFunction pending = (frame, arguments) -> {
        int value = GameServer.server && QueueManagers.ITEM_SUPPORTED
            ? count(Accessor.tryGet(TransactionManager.class, "transactions", (ConcurrentLinkedQueue<?>)null)) : -1;
        frame.push((double)value);
        return 1;
    };
    public static int count(Iterable<?> transactions) {
        if (transactions == null) return -1;
        int pending = 0;
        for (Object transaction : transactions) {
            TransactionState state = Accessor.tryGet(transaction, "state", (TransactionState)null);
            if (state == null) return -1;
            if (state != TransactionState.Done && state != TransactionState.Reject) pending++;
        }
        return pending;
    }

    public record Sample(TransactionState state) { }
    public static void main(String[] args) {
        if (count(null) != -1 || count(List.of(new Object())) != -1 || count(List.of()) != 0)
            throw new IllegalStateException("Invalid equipment transfer probe");
        for (TransactionState state : TransactionState.values()) {
            int expected = state == TransactionState.Done || state == TransactionState.Reject ? 0 : 1;
            if (count(List.of(new Sample(state))) != expected)
                throw new IllegalStateException("Invalid equipment transfer state " + state);
        }
        System.out.println("[EQUIPMENT_TEST] TRANSFER_PROBE active=" + QueueManagers.ITEM_SUPPORTED);
    }

    public static void observe() {
        if (!GameServer.server || LuaManager.env == null) return;
        LuaManager.env.rawset("equipmentNativeTransferCount", pending);
    }

    public static void floorResult(NetTimedAction action, boolean result) {
        if (!GameServer.server || !"P4RestoreFloorAction".equals(action.type)) return;
        Object item = action.action == null ? null : action.action.rawget("item");
        int id = item instanceof InventoryItem value ? value.getID() : -1;
        System.out.println("[EQUIPMENT_TEST] FLOOR_RESTORE id=" + id + " result=" + result);
    }

    @Patch(className="zombie.core.NetTimedAction", methodName="perform", warmUp=true, strictMatch=true)
    public static class FloorCompleted {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This NetTimedAction action, @Patch.Return boolean result) {
            floorResult(action, result);
        }
    }

    @Patch(className="zombie.core.TransactionManager", methodName="update", warmUp=true, strictMatch=true)
    public static class Updated {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit() { Main.observe(); }
    }
}
