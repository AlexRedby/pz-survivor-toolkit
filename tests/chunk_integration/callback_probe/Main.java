package toolkit.chunkprobe;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.IdentityHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;
import zombie.Lua.Event;
import zombie.ZomboidFileSystem;

/** Test-only inclusive callback census. All advice failures disable telemetry, never original calls. */
public final class Main {
    static final String EVENT_HASH = "cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952";
    static final String CALLER_HASH = "0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b";
    static final String OPT_IN = "chunk-callback-probe.opt-in";
    static final int MAX_THREADS = 16, MAX_HANDLERS = 128, MAX_DEPTH = 64;
    static final State[] states = new State[MAX_THREADS];
    static final ThreadLocal<State> local = new ThreadLocal<>();
    static volatile boolean enabled;
    static volatile String diagnostic;
    static int stateCount;
    private static boolean started;
    private static Path ownedCache;

    static final class Stat {
        final String file;
        final int line;
        long calls, nanos, max;
        Stat(LuaClosure callback) {
            file = callback.prototype.filename;
            int[] lines = callback.prototype.lines;
            line = lines == null || lines.length == 0 ? -1 : lines[0];
        }
    }
    static final class State {
        final String[] events = new String[MAX_DEPTH];
        final boolean[] active = new boolean[MAX_DEPTH];
        final IdentityHashMap<LuaClosure, Stat> stats = new IdentityHashMap<>(MAX_HANDLERS);
        int depth;
        long eventCount;
    }

    public static void main(String[] args) {
        try {
            if (!start(Path.of(ZomboidFileSystem.instance.getCacheDir())))
                System.out.println("[CHUNK_CALLBACK_PROBE] DISABLED reason=" + diagnostic);
        } catch (Throwable failure) {
            disable("startup-failure");
        }
    }
    static synchronized boolean start(Path cache) {
        if (started) return false;
        try {
            Path real = cache.toRealPath();
            if (!owned(real)) { diagnostic = "owned-cache-opt-in"; return false; }
            if (!matchesHash(Event.class.getResourceAsStream("/zombie/Lua/Event.class"), EVENT_HASH)
                    || !matchesHash(LuaCaller.class.getResourceAsStream("/se/krka/kahlua/integration/LuaCaller.class"), CALLER_HASH)) {
                diagnostic = "native-byte-mismatch";
                return false;
            }
            ownedCache = real;
            diagnostic = null;
            started = true;
            enabled = true;
            return true;
        } catch (Throwable failure) {
            diagnostic = "startup-guard-failure";
            return false;
        }
    }
    static boolean matchesHash(InputStream input, String expected) throws Exception {
        if (input == null) return false;
        try (input) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
            return expected.equals(HexFormat.of().formatHex(digest.digest()));
        }
    }
    static String expectedToken() throws Exception {
        try (InputStream input = Main.class.getResourceAsStream("probe-opt-in.txt")) {
            if (input == null) throw new IllegalStateException("missing fixture token");
            String token = new String(input.readNBytes(128), java.nio.charset.StandardCharsets.US_ASCII).trim();
            if (!token.matches("[0-9a-f]{32}")) throw new IllegalStateException("invalid fixture token");
            return token;
        }
    }
    static boolean owned(Path cache) throws Exception {
        Path marker = cache.resolve("smoke-user.txt"), optIn = cache.resolve(OPT_IN);
        return Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS) && Files.size(marker) > 0
            && Files.size(marker) <= 1024 && Files.isRegularFile(optIn, LinkOption.NOFOLLOW_LINKS)
            && Files.size(optIn) <= 128 && Files.readString(optIn).trim().equals(expectedToken());
    }
    static void disable(String reason) {
        enabled = false;
        if (diagnostic == null) diagnostic = reason;
    }
    private static State state() {
        State value = local.get();
        if (value != null) return value;
        synchronized (states) {
            if (!enabled) return null;
            if (stateCount == MAX_THREADS) { disable("thread-capacity"); return null; }
            value = new State();
            states[stateCount++] = value;
            local.set(value);
            return value;
        }
    }
    public static int eventEnter(Event event) {
        if (!enabled) return 0;
        try {
            State state = state();
            if (state == null) return 0;
            synchronized (state) {
                if (!enabled) return 0;
                if (state.depth == MAX_DEPTH) { disable("event-depth-capacity"); return 0; }
                int frame = state.depth++;
                state.events[frame] = event.name;
                state.active[frame] = false;
                if ("LoadGridsquare".equals(event.name)) {
                    if (state.eventCount == Long.MAX_VALUE) { disable("counter-overflow"); return frame + 1; }
                    state.eventCount++;
                }
                return frame + 1;
            }
        } catch (Throwable failure) { disable("event-enter-failure"); return 0; }
    }
    public static void eventExit(int token) {
        if (token == 0) return;
        try {
            State state = local.get();
            synchronized (state) {
                if (state.depth != token) { disable("event-stack-mismatch"); return; }
                int frame = --state.depth;
                if (state.active[frame]) disable("unfinished-callback");
                state.events[frame] = null;
                state.active[frame] = false;
            }
        } catch (Throwable failure) { disable("event-exit-failure"); }
    }
    public static long begin(Object function) {
        if (!enabled || !(function instanceof LuaClosure callback)) return 0;
        try {
            State state = local.get();
            if (state == null) return 0;
            synchronized (state) {
                int frame = state.depth - 1;
                if (!enabled || frame < 0 || state.active[frame] || !"LoadGridsquare".equals(state.events[frame])) return 0;
                if (!state.stats.containsKey(callback)) {
                    if (state.stats.size() == MAX_HANDLERS) { disable("handler-capacity"); return 0; }
                    state.stats.put(callback, new Stat(callback));
                }
                state.active[frame] = true;
                return System.nanoTime();
            }
        } catch (Throwable failure) { disable("callback-enter-failure"); return 0; }
    }
    public static void end(Object function, long began) {
        if (began == 0) return;
        long elapsed = System.nanoTime() - began;
        try {
            State state = local.get();
            synchronized (state) {
                int frame = state.depth - 1;
                if (frame < 0 || !state.active[frame]) { disable("callback-stack-mismatch"); return; }
                state.active[frame] = false;
                if (!enabled) return;
                Stat stat = state.stats.get(function);
                if (stat == null || elapsed < 0 || stat.calls == Long.MAX_VALUE || stat.nanos > Long.MAX_VALUE - elapsed) {
                    disable("counter-overflow"); return;
                }
                stat.calls++;
                stat.nanos += elapsed;
                stat.max = Math.max(stat.max, elapsed);
            }
        } catch (Throwable failure) { disable("callback-exit-failure"); }
    }
    @LuaMethod(name="chunkCallbackProbeFinish", global=true)
    public static void finish() {
        enabled = false;
        try {
            if (ownedCache == null || !owned(ownedCache)) { disable("finish-cache-guard"); return; }
            StringBuilder out = new StringBuilder("file\tline\tcalls\tnanos\tmax_ns\n");
            long events = 0, calls = 0;
            synchronized (states) {
                for (int i = 0; i < stateCount; i++) {
                    State state = states[i];
                    synchronized (state) {
                        for (boolean active : state.active) if (active) disable("unfinished-callback");
                        events += state.eventCount;
                        for (Stat stat : state.stats.values()) {
                            calls += stat.calls;
                            String file = String.valueOf(stat.file).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ');
                            if (file.length() > 2048) file = file.substring(0, 2048);
                            out.append(file).append('\t').append(stat.line).append('\t').append(stat.calls)
                                .append('\t').append(stat.nanos).append('\t').append(stat.max).append('\n');
                        }
                    }
                }
            }
            String status = diagnostic == null ? "complete" : "incomplete";
            Files.writeString(ownedCache.resolve("chunk-callbacks.tsv"), out);
            Files.writeString(ownedCache.resolve("chunk-callbacks-status.txt"),
                "status=" + status + "\nreason=" + String.valueOf(diagnostic) + "\nevents=" + events + "\ncalls=" + calls + "\n");
            System.out.println("[CHUNK_CALLBACK_PROBE] FINISH status=" + status + " events=" + events + " calls=" + calls);
        } catch (Throwable failure) { disable("finish-output-failure"); }
    }
    @Patch(className="zombie.Lua.Event", methodName="trigger", strictMatch=true)
    public static class EventProbe {
        @Patch.OnEnter public static void enter(@Patch.This Event self,
                @Patch.Argument(0) KahluaTable env, @Patch.Argument(1) LuaCaller caller,
                @Patch.Argument(2) Object[] args, @Patch.Local("chunkEventFrame") int frame) { frame = eventEnter(self); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(
                @Patch.Local("chunkEventFrame") int frame) { eventExit(frame); }
    }
    @Patch(className="se.krka.kahlua.integration.LuaCaller", methodName="protectedCallVoid", strictMatch=true)
    public static class CallbackProbe {
        // Object deliberately matches both three-argument Object and Object[] overloads in ZombieBuddy.
        @Patch.OnEnter public static void enter(@Patch.Argument(0) KahluaThread thread,
                @Patch.Argument(1) Object function, @Patch.Argument(2) Object args,
                @Patch.Local("chunkCallbackBegin") long began) { began = begin(function); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Argument(0) KahluaThread thread,
                @Patch.Argument(1) Object function, @Patch.Argument(2) Object args,
                @Patch.Local("chunkCallbackBegin") long began) { end(function, began); }
    }
}
