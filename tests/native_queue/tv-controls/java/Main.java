package net.alexredby.tvspatialprobe;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;

/** Disposable timing/counter observer; production Lua function identities stay intact. */
public final class Main {
    private static final long ORIGIN = System.nanoTime();
    private static Thread owner;
    private static boolean active;
    private static long gameReads, modReads, spatialReads, checks;

    public static synchronized void hit(int kind) {
        if (!active || owner != Thread.currentThread()) return;
        switch (kind) {
            case 0 -> gameReads++;
            case 1 -> modReads++;
            case 2 -> spatialReads++;
            case 3 -> checks++;
            default -> throw new IllegalArgumentException();
        }
    }

    private static synchronized KahluaTable state() {
        var result = new J2SEPlatform().newTable();
        result.rawset("active", active);
        result.rawset("gameSourceReads", (double) gameReads);
        result.rawset("modSourceReads", (double) modReads);
        result.rawset("spatialReads", (double) spatialReads);
        result.rawset("apiChecks", (double) checks);
        return result;
    }

    private static final JavaFunction PROBE = (frame, arguments) -> {
        Object command = arguments == 1 ? frame.get(0) : null;
        if ("clock".equals(command)) return frame.push((System.nanoTime() - ORIGIN) / 1_000_000.0);
        synchronized (Main.class) {
            if ("begin".equals(command)) {
                if (active) throw new IllegalStateException("nested TV timing scope");
                owner = Thread.currentThread();gameReads = modReads = spatialReads = checks = 0;active = true;
                return frame.push(true);
            }
            if ("end".equals(command)) {
                if (!active || owner != Thread.currentThread()) throw new IllegalStateException("unowned TV timing scope");
                active = false;owner = null;
                return frame.push(state());
            }
            if ("status".equals(command)) return frame.push(state());
        }
        throw new IllegalArgumentException("unknown TV timing probe command");
    };

    public static void install() {
        if (LuaManager.env != null) LuaManager.env.rawset("tvSpatialProbe", PROBE);
    }

    @Patch(className="zombie.gameStates.GameLoadingState", methodName="exit", warmUp=true, strictMatch=true)
    public static class Install {
        @Patch.OnExit public static void exit() { Main.install(); }
    }
    @Patch(className="zombie.Lua.LuaManager$GlobalObject", methodName="getGameFilesInput", warmUp=true, strictMatch=true)
    public static class GameReader {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) String path) { hit(0); }
    }
    @Patch(className="zombie.Lua.LuaManager$GlobalObject", methodName="getModFileReader", warmUp=true, strictMatch=true)
    public static class ModReader {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) String mod, @Patch.Argument(1) String path,
                @Patch.Argument(2) boolean create) { hit(1); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.QueueSpatialFacts", methodName="noMovement", warmUp=true, strictMatch=true)
    public static class SpatialReader {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object actor, @Patch.Argument(1) Object target,
                @Patch.Argument(2) Object exclusions, @Patch.Argument(3) Object object) { hit(2); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.QueueSpatialFacts", methodName="apiMatches", warmUp=true, strictMatch=true)
    public static class ApiChecker {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object callback) { hit(3); }
    }
}
