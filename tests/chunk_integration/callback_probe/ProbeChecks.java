package toolkit.chunkprobe;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;
import zombie.Lua.Event;
import zombie.Lua.LuaManager;

/** Calls actual woven native methods, rather than invoking advice as a substitute for the engine. */
public final class ProbeChecks {
    private static LuaClosure closure(String source, String name, KahluaTable env) throws Exception {
        return LuaCompiler.loadis(new StringReader(source), name, env);
    }
    private static Event event(String name, LuaClosure... callbacks) {
        Event event = new Event(name, 0);
        java.util.Collections.addAll(event.callbacks, callbacks);
        return event;
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        PatchEngine.applyPatches("toolkit.chunkprobe", ProbeChecks.class.getClassLoader());
        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newTable(); env.rawset("n", 0.0);
        KahluaThread thread = new KahluaThread(platform, env); thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        LuaCaller caller = new LuaCaller(new KahluaConverterManager());
        LuaClosure callback = closure("n=n+1", "probe-callback.lua", env);
        Event event = event("LoadGridsquare", callback);
        Path cache = Files.createTempDirectory("chunk-probe-check-cache-");
        check(!Main.start(cache), "missing owned marker must refuse capture");
        check(event.trigger(env, caller, new Object[0]), "disabled event return changed");
        check(Double.valueOf(1.0).equals(env.rawget("n")), "disabled callback did not run");
        check(Main.local.get() == null, "disabled advice allocated state");
        Files.writeString(cache.resolve("smoke-user.txt"), "explicitly-owned-headless-test\n");
        check(!Main.start(cache), "missing opt-in must refuse capture");
        Files.writeString(cache.resolve(Main.OPT_IN), "wrong-token\n");
        check(!Main.start(cache), "foreign opt-in must refuse capture");
        Files.writeString(cache.resolve(Main.OPT_IN), Main.expectedToken() + "\n");
        check(!Main.matchesHash(new ByteArrayInputStream(new byte[]{1}), Main.EVENT_HASH), "mismatched bytes accepted");
        check(Main.start(cache), "valid native/owned-cache gates refused capture: " + Main.diagnostic);
        check(!event("LoadGridsquare").trigger(env, caller, new Object[0]), "empty event return changed");
        ByteArrayOutputStream capture = new ByteArrayOutputStream();
        PrintStream stdout = System.out, stderr = System.err;
        try (PrintStream quiet = new PrintStream(capture)) {
            System.setOut(quiet); System.setErr(quiet);
            check(event.trigger(env, caller, new Object[0]), "event return changed");
            Main.State state = Main.local.get();
            check(state.stats.get(callback).calls == 1 && state.depth == 0, "woven callback not measured once");
            check(state.stats.get(callback).nanos > 0 && state.stats.get(callback).max > 0, "missing inclusive timing");
            caller.protectedCallVoid(thread, callback, new Object[0]);
            caller.protectedCallVoid(thread, callback, (Object) null);
            event("OtherEvent", callback).trigger(env, caller, new Object[0]);
            check(state.stats.get(callback).calls == 1, "foreign invocation counted");

            LuaClosure inside = closure("n=n+1", "inner.lua", env);
            Event nested = event("LoadGridsquare", inside);
            LuaClosure indirect = closure("n=n+1", "indirect.lua", env);
            env.rawset("nested", (JavaFunction)(frame, count) -> {
                caller.protectedCallVoid(thread, indirect, new Object[0]);
                nested.trigger(env, caller, new Object[0]);
                return 0;
            });
            LuaClosure outer = closure("nested(); n=n+1", "outer.lua", env);
            event("LoadGridsquare", outer).trigger(env, caller, new Object[0]);
            check(state.stats.get(outer).calls == 1 && state.stats.get(inside).calls == 1,
                "nested direct handlers were lost/doubled");
            check(!state.stats.containsKey(indirect), "indirect LuaCaller invocation counted");
            check(state.stats.get(outer).nanos >= state.stats.get(inside).nanos, "nested time subtracted from parent");

            AssertionError sentinel = new AssertionError("expected callback sentinel");
            LuaCaller throwing = new LuaCaller(new KahluaConverterManager()) {
                @Override public void pcallvoid(KahluaThread t, Object function, Object[] arguments) { throw sentinel; }
            };
            try { event.trigger(env, throwing, new Object[0]); throw new AssertionError("original error swallowed"); }
            catch (AssertionError failure) { check(failure == sentinel, "original error replaced"); }
            check(state.stats.get(callback).calls == 2 && state.depth == 0, "throw exit lost timing/event cleanup");
            check(Main.enabled, "normal nesting/error disabled capture: " + Main.diagnostic);
            check(!Files.exists(cache.resolve("chunk-callbacks.tsv")), "capture wrote telemetry before finish");

            Event crowded = event("LoadGridsquare");
            for (int i = 0; i <= Main.MAX_HANDLERS; i++)
                crowded.callbacks.add(closure("n=n+1", "capacity-" + i + ".lua", env));
            double before = (Double)env.rawget("n");
            check(crowded.trigger(env, caller, new Object[0]), "capacity changed native event return");
            check((Double)env.rawget("n") == before + crowded.callbacks.size(), "capacity skipped game callbacks");
            check(!Main.enabled && "handler-capacity".equals(Main.diagnostic), "capacity did not disable with diagnostic");
            check(state.stats.size() == Main.MAX_HANDLERS && state.depth == 0, "telemetry exceeded bounds/misnested");
            before = (Double)env.rawget("n");
            event.trigger(env, caller, new Object[0]);
            check((Double)env.rawget("n") == before + 1, "disabled callback changed");
        } finally { System.setOut(stdout); System.setErr(stderr); }
        check(capture.size() == 0, "probe emitted output during capture: " + capture);
        Main.finish();
        String status = Files.readString(cache.resolve("chunk-callbacks-status.txt"));
        check(status.contains("status=incomplete") && status.contains("reason=handler-capacity"), "diagnostic not recorded");
        check(Files.readString(cache.resolve("chunk-callbacks.tsv")).startsWith("file\tline\tcalls\tnanos\tmax_ns\n"),
            "unexpected aggregate output");
        try (var files = Files.list(cache)) { for (Path file : files.toList()) Files.delete(file); }
        Files.delete(cache);
        System.out.println("CHUNK_CALLBACK_PROBE_CHECK_PASS");
        System.exit(0);
    }
}
