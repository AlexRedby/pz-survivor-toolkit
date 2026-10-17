package net.alexredby.pztoolkitjavapatches;

import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;

public final class ActionCompletion {
    private static final ThreadLocal<Scope> current = new ThreadLocal<>();

    public static final class Scope {
        final Scope previous;
        final KahluaTable action;
        final Object callback, finish;
        final String phase;
        boolean failed;
        Scope(Scope previous, KahluaTable action, Object callback, Object finish, String phase) {
            this.previous = previous; this.action = action; this.callback = callback;
            this.finish = finish; this.phase = phase;
        }
    }

    public static Scope begin(LuaTimedActionNew nativeAction, String phase, boolean supported) {
        if (!supported || LuaManager.env == null) return null;
        Object toolkit = LuaManager.env.rawget("PZSurvivorToolkit");
        Object lifecycle = toolkit instanceof KahluaTable table ? table.rawget("ActionQueueLifecycle") : null;
        if (!(lifecycle instanceof KahluaTable hooks)) return null;
        Object begin = hooks.rawget("begin"), finish = hooks.rawget("finish");
        if (begin == null || finish == null) return null;
        KahluaTable action = nativeAction.getTable();
        Object[] result = LuaManager.caller.pcall(LuaManager.thread, begin, action, phase);
        if (result.length < 2 || !Boolean.TRUE.equals(result[0]) || !Boolean.TRUE.equals(result[1])) return null;
        Scope scope = new Scope(current.get(), action, action.rawget(phase), finish, phase);
        current.set(scope);
        return scope;
    }

    public static void observe(Object callback, Object argument, Object[] result) {
        Scope scope = current.get();
        if (scope != null && scope.callback != null && scope.callback == callback && scope.action == argument
                && (result == null || result.length == 0 || !Boolean.TRUE.equals(result[0])
                    || "complete".equals(scope.phase) && result.length > 1 && Boolean.FALSE.equals(result[1]))) scope.failed = true;
    }

    public static void end(Scope scope, Throwable failure) {
        if (scope == null) return;
        if (scope.previous == null) current.remove(); else current.set(scope.previous);
        LuaManager.caller.pcall(LuaManager.thread, scope.finish, scope.action, scope.phase,
            failure == null && !scope.failed);
    }
}
