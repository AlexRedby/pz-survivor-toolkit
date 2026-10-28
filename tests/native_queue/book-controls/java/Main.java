package net.alexredby.bookcontrolsprobe;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;

/** Observe the unchanged native stop after its Lua cleanup, before engine removal. */
public final class Main {
    public static void stopped(LuaTimedActionNew nativeAction, Throwable failure) {
        if (LuaManager.env == null || nativeAction == null) return;
        var action = nativeAction.getTable();
        if (action == null || !"ISReadABook".equals(action.rawget("Type"))) return;
        Object observer = LuaManager.env.rawget("bookControlsNativeStopped");
        if (observer == null) return;
        Object[] result = LuaManager.caller.pcall(LuaManager.thread, observer, action, nativeAction, failure == null);
        if (result.length == 0 || !Boolean.TRUE.equals(result[0]))
            System.err.println("[QUEUE_TEST] FAIL book-controls-stop-observer rejected native stop evidence");
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="stop", warmUp=true, strictMatch=true)
    public static class Stopped {
        @Patch.OnExit(onThrowable=Throwable.class, suppress=Throwable.class)
        public static void exit(@Patch.This LuaTimedActionNew action, @Patch.Thrown Throwable failure) {
            Main.stopped(action, failure);
        }
    }
}
