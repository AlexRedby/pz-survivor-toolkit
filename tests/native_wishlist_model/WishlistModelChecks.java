import java.lang.ref.Reference;
import java.lang.ref.WeakReference;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import org.luaj.kahluafork.compiler.FuncState;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;

/** Execute only the Wishlist model/server fixture, without starting the game. */
public final class WishlistModelChecks {
    private static final String RELEASE_ERROR = "snapshots or request buckets retained a departed player";
    private static final String PRUNE = "versions, requests = currentVersions, currentRequests";

    private static void require(boolean value, String detail) {
        if (!value) throw new AssertionError(detail);
    }

    private static LuaClosure compile(String source, String name, KahluaTable env) throws Exception {
        String previous = FuncState.currentFile, previousFull = FuncState.currentfullFile;
        try {
            FuncState.currentFile = name;
            FuncState.currentfullFile = name;
            return LuaCompiler.loadstring(source, name, env);
        } finally {
            FuncState.currentFile = previous;
            FuncState.currentfullFile = previousFull;
        }
    }

    private static final class Runtime {
        final J2SEPlatform platform = J2SEPlatform.getInstance();
        final KahluaTable env = platform.newTable();
        final KahluaThread thread;
        int cases, completions, reportedCases, witnesses;

        Runtime(Path game) throws Exception {
            env.rawset("_G", env);
            env.rawset("_VERSION", "Kahlua");
            // Installed PZ supplies stdlib.lbc; newEnvironment expects cwd/stdlib.lua.
            se.krka.kahlua.stdlib.BaseLib.register(env);
            se.krka.kahlua.j2se.MathLib.register(platform, env);
            se.krka.kahlua.stdlib.RandomLib.register(platform, env);
            se.krka.kahlua.stdlib.StringLib.register(platform, env);
            se.krka.kahlua.stdlib.CoroutineLib.register(platform, env);
            se.krka.kahlua.stdlib.OsLib.register(platform, env);
            se.krka.kahlua.stdlib.TableLib.register(platform, env);
            LuaCompiler.register(env);
            thread = new KahluaThread(System.out, platform, env);
            thread.debugOwnerThread = Thread.currentThread();
            try (var stream = Files.newInputStream(game.resolve("stdlib.lbc"))) {
                thread.call(Prototype.loadByteCode(stream, env), new Object[0]);
            }
            Object originalPrint = env.rawget("print");
            env.rawset("print", (JavaFunction) (frame, count) -> {
                if (count > 0 && frame.get(0) instanceof String line) {
                    if (line.startsWith("PASS wishlist model: ")) cases++;
                    String end = "Wishlist model/server checks passed: ";
                    if (line.startsWith(end)) {
                        completions++;
                        reportedCases = Integer.parseInt(line.substring(end.length()));
                    }
                }
                Object[] arguments = new Object[count];
                for (int i = 0; i < count; i++) arguments[i] = frame.get(i);
                thread.call(originalPrint, arguments);
                return 0;
            });
            env.rawset("NativeWeakReference", (JavaFunction) (frame, count) -> {
                require(count == 1 && frame.get(0) instanceof KahluaTable, "Expected one Lua player-table witness");
                witnesses++;
                WeakReference<Object> ref = new WeakReference<>(frame.get(0));
                // Neither return the referent to Lua nor capture the call frame.
                return frame.push((JavaFunction) (reader, size) -> {
                    require(size == 0, "Release witness takes no arguments");
                    return reader.push(ref.refersTo(null));
                });
            });
        }

        Object[] execute(String source, String name) throws Exception {
            return thread.pcall(compile(source, name, env), new Object[0]);
        }
    }

    private static void witnessControls(Path game) throws Exception {
        Runtime runtime = new Runtime(game);
        try {
            Object[] result = runtime.execute("""
                local nativeWeak = setmetatable({}, {__mode='v'})
                nativeWeak[1] = {}
                collectgarbage('collect')
                assert(nativeWeak[1] ~= nil, 'native weak-table premise changed; review harness')
                local released
                do local value = {}; released = NativeWeakReference(value) end
                collectgarbage('collect')
                assert(released(), 'native witness retained a released object')
                local retained
                do
                    local value = {}
                    retained = NativeWeakReference(value)
                    HeldPlayer = function() return value end
                end
                collectgarbage('collect')
                assert(not retained(), 'native witness missed a rooted closure')
                HeldPlayer = nil
                collectgarbage('collect')
                assert(retained(), 'native witness failed after releasing rooted closure')
                """, "wishlist-native-witness-controls.lua");
            require(Boolean.TRUE.equals(result[0]), Arrays.toString(result));
            require(runtime.witnesses == 2, "Witness controls did not run");
        } finally {
            Reference.reachabilityFence(runtime.env);
            Reference.reachabilityFence(runtime.thread);
        }
        System.out.println("WISHLIST_MODEL_NATIVE_WITNESS_PASS");
    }

    private static void suite(Path project, Path game, boolean retainDeparted) throws Exception {
        Runtime runtime = new Runtime(game);
        Path server = project.resolve("PZSurvivorToolkit/42/media/lua/server/PZSurvivorWishlist/Server.lua");
        runtime.env.rawset("ProjectRoot", project.toString());
        runtime.env.rawset("dofile", (JavaFunction) (frame, count) -> {
            require(count == 1 && frame.get(0) instanceof String, "Expected one source path");
            try {
                Path file = Path.of((String) frame.get(0)).toRealPath();
                require(file.startsWith(project), "Fixture dofile escaped project");
                String source = Files.readString(file);
                if (retainDeparted && file.equals(server)) {
                    int at = source.indexOf(PRUNE);
                    require(at >= 0 && source.indexOf(PRUNE, at + PRUNE.length()) < 0,
                            "Retention control requires the current exact server-pruning boundary");
                    // Mutate only this isolated load; production bytes stay untouched.
                    source = source.replace(PRUNE, "-- retained-player negative control");
                }
                return frame.push(runtime.thread.call(compile(source, file.toString(), runtime.env), new Object[0]));
            } catch (Exception error) {
                throw new RuntimeException(error);
            }
        });
        try {
            Path test = project.resolve("tests/test_wishlist_model.lua");
            Object[] result = runtime.execute(Files.readString(test), test.toString());
            require(runtime.witnesses > 0, "Suite omitted departed-player witness");
            if (retainDeparted) {
                require(Boolean.FALSE.equals(result[0]) && RELEASE_ERROR.equals(result[1]),
                        "Retained-player control did not fail the release assertion: " + Arrays.toString(result));
                require(runtime.completions == 0, "Retention control published a completed suite");
            } else {
                require(Boolean.TRUE.equals(result[0]), Arrays.toString(result));
                require(runtime.completions == 1 && runtime.cases > 0 && runtime.cases == runtime.reportedCases,
                        "Suite did not complete all reported model/server checks");
            }
        } finally {
            // Keep real server closures/caches rooted while the Lua assertion runs.
            Reference.reachabilityFence(runtime.env);
            Reference.reachabilityFence(runtime.thread);
        }
        System.out.println(retainDeparted ? "WISHLIST_MODEL_RETAINED_CONTROL_REJECTED" : "WISHLIST_MODEL_NATIVE_PASS");
    }

    public static void main(String[] args) throws Exception {
        require(args.length == 2, "Expected project root and installed game root");
        Path project = Path.of(args[0]).toRealPath(), game = Path.of(args[1]).toRealPath();
        witnessControls(game);
        suite(project, game, false);
        suite(project, game, true);
    }
}
