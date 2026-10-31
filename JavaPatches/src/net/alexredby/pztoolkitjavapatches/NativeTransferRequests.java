package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import java.util.List;
import zombie.core.Transaction;
import zombie.inventory.InventoryItem;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;

/** JVM local write-back adapter; all request logic is in Kotlin. */
public final class NativeTransferRequests {
    private NativeTransferRequests() { }
    public static final class Scope {
        final Scope previous;
        final NativeTransferRequestReceipt receipt;
        final KahluaThread thread;
        final LuaClosure observer;
        boolean notifying;
        Scope(Scope previous, NativeTransferRequestReceipt receipt, KahluaThread thread, LuaClosure observer) {
            this.previous = previous; this.receipt = receipt; this.thread = thread; this.observer = observer;
        }
    }
    public static void prepareLibrary(String file) {
        try { NativeTransferRequestsLogic.prepareLibrary(file); }
        catch (Throwable ignored) { /* Unsupported metadata must not abort native loading. */ }
    }
    public static Scope begin(IsoPlayer actor, KahluaTableImpl items, ItemContainer source, ItemContainer destination) {
        return NativeTransferRequestsLogic.begin(actor, items, source, destination);
    }
    public static void end(Scope scope, byte result, Throwable failure) {
        NativeTransferRequestsLogic.end(scope, result, failure);
    }
    @Patch(className="zombie.Lua.LuaManager$GlobalObject", methodName="createItemTransaction", warmUp=true, strictMatch=true)
    public static class RequestBoundary {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) IsoPlayer actor, @Patch.Argument(1) KahluaTableImpl items,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Local("toolkitNativeTransferRequest") Scope scope) {
            try { scope = begin(actor, items, source, destination); }
            catch (Throwable ignored) { scope = null; }
        }
        @Patch.OnExit(onThrowable=Throwable.class, suppress=Throwable.class)
        public static void exit(@Patch.Local("toolkitNativeTransferRequest") Scope scope,
                @Patch.Return byte result, @Patch.Thrown Throwable failure) {
            end(scope, result, failure);
        }
    }
    public static final class ManagerScope {
        final ManagerScope previous;
        final NativeTransferRequestReceipt receipt;
        final zombie.core.raknet.UdpConnection connection;
        Transaction transaction;
        int added;
        int allocations;
        Transaction allocated;
        boolean nested;
        ManagerScope(ManagerScope previous, NativeTransferRequestReceipt receipt) {
            this.previous=previous; this.receipt=receipt;
            this.connection=receipt == null ? null : receipt.connection;
        }
    }
    @Patch(className="zombie.core.TransactionManager", methodName="createItemTransaction", warmUp=true, strictMatch=true)
    public static class ManagerBoundary {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) IsoPlayer actor, @Patch.Argument(1) List<InventoryItem> items,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Local("toolkitNativeManagerRequest") ManagerScope scope) {
            try { scope=NativeTransferRequestsLogic.beginManager(actor, items, source, destination); }
            catch (Throwable ignored) { scope=null; }
        }
        @Patch.OnExit(onThrowable=Throwable.class, suppress=Throwable.class)
        public static void exit(@Patch.Local("toolkitNativeManagerRequest") ManagerScope scope,
                @Patch.Return byte result, @Patch.Thrown Throwable failure) {
            NativeTransferRequestsLogic.endManager(scope,result,failure);
        }
    }
    @Patch(className="zombie.core.Transaction", methodName="set", warmUp=true, strictMatch=true)
    public static class Allocated {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This Transaction transaction,
                @Patch.Argument(0) IsoPlayer actor, @Patch.Argument(1) List<InventoryItem> items,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Argument(4) String extra, @Patch.Argument(5) zombie.iso.IsoDirections direction,
                @Patch.Argument(6) float x, @Patch.Argument(7) float y, @Patch.Argument(8) float z) {
            NativeTransferRequestsLogic.allocated(transaction);
        }
    }
    @Patch(className="zombie.core.TransactionManager", methodName="add", warmUp=true, strictMatch=true)
    public static class Added {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Argument(0) Transaction transaction) {
            NativeTransferRequestsLogic.added(transaction);
        }
    }

}
