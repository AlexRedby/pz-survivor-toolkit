package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
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
}
