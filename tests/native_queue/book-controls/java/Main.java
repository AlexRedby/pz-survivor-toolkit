package net.alexredby.bookcontrolsprobe;

import java.util.ArrayDeque;
import java.util.Collections;
import java.util.IdentityHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.stdlib.BaseLib;
import se.krka.kahlua.stdlib.TableLib;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.LuaClosure;
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

    private static Object own(Object value, String key) {
        return value instanceof KahluaTableImpl table ? table.delegate.get(key) : null;
    }
    private static String source(LuaClosure closure) {
        String name = closure.prototype.filename;
        if (name == null) return "";
        name = name.replace('\\', '/');
        return name.substring(name.lastIndexOf('/') + 1).replaceFirst("^@", "");
    }
    /** Read only the small, source-owned upvalue graph; never execute a guard. */
    private static int factories(Object entry, String filename) {
        if (!(entry instanceof LuaClosure first)) return -1;
        var seen = Collections.newSetFromMap(new IdentityHashMap<LuaClosure, Boolean>());
        var prototypes = Collections.newSetFromMap(new IdentityHashMap<se.krka.kahlua.vm.Prototype, Boolean>());
        var pending = new ArrayDeque<LuaClosure>(); pending.add(first);
        int count = 0;
        while (!pending.isEmpty()) {
            LuaClosure closure = pending.remove();
            if (!seen.add(closure) || !source(closure).equals(filename)) continue;
            if (seen.size() > 256) return -2;
            if (prototypes.add(closure.prototype)) for (Object value : closure.prototype.constants) {
                if (value instanceof JavaFunction && value.getClass().getName().startsWith(
                        "net.alexredby.pztoolkitjavapatches.QueueBindingCompiler")) count++;
            }
            for (var upvalue : closure.upvalues) {
                Object value = upvalue == null ? null : upvalue.getValue();
                if (value instanceof LuaClosure child) pending.add(child);
            }
        }
        return count;
    }
    public static void bindings() {
        if (!(LuaManager.env instanceof KahluaTableImpl env)) return;
        var platform = new J2SEPlatform();
        KahluaTable result = platform.newTable();
        try {
            Object toolkit = env.delegate.get("PZSurvivorToolkit");
            result.rawset("compatFactories", (double) factories(own(own(toolkit, "ActionQueueCompat"), "isTransferPerform"), "ActionQueueCompat.lua"));
            result.rawset("cartFactories", (double) factories(own(own(toolkit, "ActionQueueCarts"), "status"), "ActionQueueCarts.lua"));
            result.rawset("policyFactories", (double) factories(own(own(toolkit, "ActionQueuePolicy"), "matchesNative"), "ActionQueuePolicy.lua"));
            Object radio = own(own(own(own(toolkit, "ActionQueueDefinitions"), "entries"), "native.ISRadioAction"), "behavior");
            result.rawset("radioFactories", (double) factories(own(radio, "inspect"), "ActionQueuePolicy.lua"));
            KahluaTable canonical = platform.newTable(); TableLib.register(platform, canonical);
            Object pairs = ((KahluaTable) canonical.rawget("table")).rawget("pairs");
            result.rawset("canonicalPairs", env.delegate.get("pairs") == pairs);
            result.rawset("canonicalIpairs", env.delegate.get("ipairs") == ((KahluaTable) canonical.rawget("table")).rawget("ipairs"));
            KahluaTable base = platform.newTable(); BaseLib.register(base);
            result.rawset("canonicalGetmetatable", env.delegate.get("getmetatable") == base.rawget("getmetatable"));
            result.rawset("plainEnvironment", env.getMetatable() == null && env.getRewriteTable() == null
                    && env.delegate.get("_G") == env);
            result.rawset("debugDisabled", !zombie.core.Core.debug);
            result.rawset("readOnly", true);
            result.rawset("scope", "source-owned-upvalues-no-guard-calls");
        } catch (RuntimeException failure) {
            result.rawset("error", failure.getClass().getName());
        }
        env.rawset("bookControlsNativeBindings", result);
    }
    @Patch(className="zombie.gameStates.GameLoadingState", methodName="exit", warmUp=true, strictMatch=true)
    public static class BindingObservation {
        @Patch.OnExit
        public static void exit() { Main.bindings(); }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="stop", warmUp=true, strictMatch=true)
    public static class Stopped {
        @Patch.OnExit(onThrowable=Throwable.class, suppress=Throwable.class)
        public static void exit(@Patch.This LuaTimedActionNew action, @Patch.Thrown Throwable failure) {
            Main.stopped(action, failure);
        }
    }
}
