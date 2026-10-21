package zombie.characters.CharacterTimedActions;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import net.alexredby.pztoolkitjavapatches.ActionCompletion;
import net.alexredby.pztoolkitjavapatches.Main;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import sun.misc.Unsafe;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameClient;

public final class ActionCompletionChecks {
    static Unsafe unsafe;
    static final List<String> events = new ArrayList<>();
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message + ": " + events); }
    static Field field(Class<?> owner, String name) throws Exception {
        Field field = owner.getDeclaredField(name); field.setAccessible(true); return field;
    }
    static KahluaTable table() { return LuaManager.platform.newTable(); }
    static LuaTimedActionNew action(boolean complete) throws Exception {
        LuaTimedActionNew action = (LuaTimedActionNew)unsafe.allocateInstance(LuaTimedActionNew.class);
        action.table = table(); action.table.rawset("Type", "LifecycleProbe");
        action.table.rawset("perform", (JavaFunction)(frame, count) -> {
            events.add("perform"); events.add("callback-tail"); return 0;
        });
        if (complete) action.table.rawset("complete", (JavaFunction)(frame, count) -> { events.add("effects"); return 0; });
        action.chr = (IsoPlayer)unsafe.allocateInstance(IsoPlayer.class);
        action.loopAction = true;
        action.useCustomRemoteTimedActionSync = true;
        return action;
    }
    static void installHooks() {
        KahluaTable toolkit = table(), lifecycle = table();
        lifecycle.rawset("begin", (JavaFunction)(frame, count) -> {
            events.add("begin:" + frame.get(1)); frame.push(Boolean.TRUE); return 1;
        });
        lifecycle.rawset("finish", (JavaFunction)(frame, count) -> {
            events.add("finish:" + frame.get(1) + ":" + frame.get(2)); return 0;
        });
        toolkit.rawset("ActionQueueLifecycle", lifecycle); LuaManager.env.rawset("PZSurvivorToolkit", toolkit);
    }
    static void observerScopes() throws Exception {
        events.clear();installHooks();
        LuaTimedActionNew outer=action(true),inner=action(true);
        ActionCompletion.Scope owned=ActionCompletion.begin(outer,"perform",true);
        KahluaTable toolkit=(KahluaTable)LuaManager.env.rawget("PZSurvivorToolkit");
        KahluaTable lifecycle=(KahluaTable)toolkit.rawget("ActionQueueLifecycle");
        lifecycle.rawset("begin",(JavaFunction)(frame,count)->{events.add("declined:"+frame.get(1));frame.push(Boolean.FALSE);return 1;});
        inner.table.rawset("perform",(JavaFunction)(frame,count)->{throw new IllegalStateException("expected observed-only failure");});
        require(ActionCompletion.begin(inner,"perform",true)==null,"declined Lua lifecycle acquired queue ownership");
        ActionCompletion.Scope observing=ActionCompletion.observeOnly(inner,"perform");
        inner.perform();
        require(field(ActionCompletion.Scope.class,"failed").getBoolean(observing),"observer-only native protected failure became success");
        require(!field(ActionCompletion.Scope.class,"failed").getBoolean(owned),"observer-only failure poisoned outer queue scope");
        ActionCompletion.end(observing,null);
        require(((ThreadLocal<?>)field(ActionCompletion.class,"current").get(null)).get()==owned,"observer-only scope failed to restore outer scope");
        require(events.stream().noneMatch(event->event.startsWith("finish:")),"observer-only scope notified Lua queue finish");
        ActionCompletion.end(owned,null);clean();
        require(events.get(events.size()-1).equals("finish:perform:true"),"outer queue callback lost its original finish boundary");
        events.clear();
        LuaTimedActionNew foreign=action(true);foreign.perform();clean();
        require(events.equals(List.of("declined:perform","perform","callback-tail")),"declined unrelated native action acquired a fallback scope");
        events.clear();installHooks();
    }
    static void clean() throws Exception {
        require(((ThreadLocal<?>)field(ActionCompletion.class, "current").get(null)).get() == null, "native completion scope leaked");
    }
    static void run(boolean client) throws Exception {
        GameClient.client = client;
        LuaTimedActionNew action = action(true);
        action.perform();
        if (!client) action.complete();
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        unsafe = (Unsafe)field(Unsafe.class, "theUnsafe").get(null);
        LuaManager.platform = new J2SEPlatform(); LuaManager.env = table();
        LuaManager.thread = new se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        installHooks(); run(false);
        require(events.equals(List.of("perform", "callback-tail", "effects")), "original native callback order changed");
        events.clear();
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ActionCompletionChecks.class.getClassLoader());
        Main.main(new String[0]);
        run(false);
        require(events.equals(List.of("begin:perform", "perform", "callback-tail", "finish:perform:true",
            "begin:complete", "effects", "finish:complete:true")), "woven SP phase boundary did not surround actual native callbacks");
        clean(); events.clear(); run(true);
        require(events.equals(List.of("begin:perform", "perform", "callback-tail", "finish:perform:true")), "woven MP boundary lost callback tail");
        clean(); events.clear(); GameClient.client = false;
        LuaTimedActionNew absent = action(false); absent.perform(); absent.complete();
        require(events.contains("finish:complete:true"), "absent optional complete treated as action failure");
        clean(); events.clear();
        LuaTimedActionNew rejected = action(true);
        rejected.table.rawset("complete", (JavaFunction)(frame, count) -> { frame.push(Boolean.FALSE); return 1; });
        rejected.perform(); rejected.complete();
        require(events.contains("finish:complete:false"), "explicit native effect rejection became success");
        clean(); events.clear();
        LuaTimedActionNew failure = action(true);
        failure.table.rawset("perform", (JavaFunction)(frame, count) -> { throw new IllegalStateException("expected completion failure"); });
        failure.perform();
        require(events.contains("finish:perform:false"), "native protected Lua failure became a success");
        clean(); events.clear();
        LuaTimedActionNew nested = action(true), outer = action(true);
        nested.table.rawset("perform", (JavaFunction)(frame, count) -> { throw new IllegalStateException("expected nested failure"); });
        outer.table.rawset("perform", (JavaFunction)(frame, count) -> { nested.perform(); return 0; });
        outer.perform();
        require(events.equals(List.of("begin:perform", "begin:perform", "finish:perform:false", "finish:perform:true")),
            "nested callback failure poisoned its caller");
        clean(); events.clear();
        LuaTimedActionNew broken = action(true); broken.chr = null;
        try { broken.perform(); throw new AssertionError("native Java exception swallowed"); }
        catch (NullPointerException expected) { }
        require(events.equals(List.of("begin:perform", "finish:perform:false")), "native Java exception did not settle failure");
        clean(); events.clear();
        observerScopes();
        require(ActionCompletion.begin(action(true), "perform", false) == null, "unsupported engine acquired completion scope");
        require(events.isEmpty(), "unsupported engine notified Lua");
        System.out.println("ACTION_COMPLETION_CHECKS_PASS (original/woven SP/MP callbacks, optional complete, nested protected errors, Java exception, observer-only failure/isolation, unsupported guard)");
    }
}
