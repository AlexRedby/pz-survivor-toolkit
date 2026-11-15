package net.alexredby.wringstopprobe;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;

/** Disposable observation only: neither native nor Lua stop callbacks are replaced. */
public final class Main {
    private static final ThreadLocal<Scope> CURRENT = new ThreadLocal<>();

    public static final class Scope {
        final Scope previous;
        final LuaTimedActionNew nativeAction;
        final KahluaTable action;
        final Object callback;
        int callbackCalls;
        boolean callbackFailed;

        Scope(Scope previous, LuaTimedActionNew nativeAction, KahluaTable action, Object callback) {
            this.previous = previous;
            this.nativeAction = nativeAction;
            this.action = action;
            this.callback = callback;
        }
    }

    private static void failed() {
        System.err.println("[QUEUE_TEST] FAIL wring-clothing native-stop-probe observation failed");
    }

    private static void notify(Scope scope, String boundary, Throwable failure) {
        if (LuaManager.env == null) return;
        Object observer = LuaManager.env.rawget("wringControlsNativeStop");
        if (observer == null) return;
        boolean unchanged = scope.nativeAction.getTable() == scope.action
                && scope.callback != null && scope.action.rawget("stop") == scope.callback;
        boolean observed = scope.callbackCalls > 0;
        boolean callbackSucceeded = scope.callbackCalls == 1 && !scope.callbackFailed;
        boolean succeeded = "returned".equals(boundary) && failure == null
                && unchanged && callbackSucceeded;
        KahluaTable details = new J2SEPlatform().newTable();
        details.rawset("source", "disposable-jvm-stop");
        details.rawset("probeClass", Main.class.getName());
        details.rawset("nativeClass", scope.nativeAction.getClass().getName());
        details.rawset("callbackObserved", observed);
        details.rawset("callbackSucceeded", callbackSucceeded);
        details.rawset("callbackUnchanged", unchanged);
        Object[] result = LuaManager.caller.pcall(LuaManager.thread, observer,
                scope.action, scope.nativeAction, boundary, succeeded, details);
        if (result.length == 0 || !Boolean.TRUE.equals(result[0])) failed();
    }

    public static Scope begin(LuaTimedActionNew nativeAction) {
        if (LuaManager.env == null || nativeAction == null) return null;
        KahluaTable action = nativeAction.getTable();
        if (action == null || !"ISWringClothing".equals(action.rawget("Type"))) return null;
        Scope scope = new Scope(CURRENT.get(), nativeAction, action, action.rawget("stop"));
        CURRENT.set(scope);
        try { notify(scope, "entry", null); }
        catch (Throwable failure) { scope.callbackFailed = true; failed(); }
        return scope;
    }

    public static void callback(Object callback, Object action, Object[] result) {
        Scope scope = CURRENT.get();
        if (scope == null || callback != scope.callback || action != scope.action) return;
        scope.callbackCalls++;
        if (result == null || result.length == 0 || !Boolean.TRUE.equals(result[0])
                || result.length > 1 && Boolean.FALSE.equals(result[1])) scope.callbackFailed = true;
    }

    public static void end(Scope scope, Throwable failure) {
        if (scope == null) return;
        try {
            if (CURRENT.get() != scope) scope.callbackFailed = true;
            notify(scope, "returned", failure);
        } finally {
            if (scope.previous == null) CURRENT.remove(); else CURRENT.set(scope.previous);
        }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="stop", warmUp=true, strictMatch=true)
    public static class NativeStop {
        @Patch.OnEnter
        public static void enter(@Patch.This LuaTimedActionNew action, @Patch.Local("wringStopScope") Scope scope) {
            try { scope = Main.begin(action); }
            catch (Throwable failure) { failed(); }
        }
        @Patch.OnExit(onThrowable=Throwable.class, suppress=Throwable.class)
        public static void exit(@Patch.Local("wringStopScope") Scope scope, @Patch.Thrown Throwable failure) {
            Main.end(scope, failure);
        }
    }

    @Patch(className="se.krka.kahlua.integration.LuaCaller", methodName="pcall", warmUp=true, strictMatch=true)
    public static class CallbackResult {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Argument(1) Object callback, @Patch.Argument(2) Object action, @Patch.Return Object[] result) {
            Main.callback(callback, action, result);
        }
    }
}
