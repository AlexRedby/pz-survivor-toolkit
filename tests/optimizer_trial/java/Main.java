package net.alexredby.optimizertrial;

import java.io.InputStream;
import java.lang.reflect.Method;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.Map;
import java.util.Properties;
import java.util.zip.ZipFile;
import me.zed_0xff.zombie_buddy.Patch;

/** Experimental client lifecycle adapter; optimizer algorithms remain in the user's official download. */
public final class Main {
    public static final String ARCHIVE_SHA256 = "2bcd0e01a3ac66856fae137ff1dbda66c8397375da781e7a6ed67fe2b9d6590d";
    public static final String PROFILE = "xd3i-b42.21-d1bbdcf-bounded-v1";
    private static final Properties ORIGINALS = properties("optimizer-trial-native.properties");
    private static final Properties NATIVE_LIFECYCLE = properties("optimizer-trial-native-lifecycle.properties");
    private static final Properties SELECTED = properties("optimizer-trial-selected.properties");
    private static final Properties PROFILE_PROPERTIES = properties("optimizer-trial-profile.properties");
    private static volatile boolean enabled;
    private static boolean booted;
    private static String mode = "singleplayer";
    private static boolean animationStarted, clientResetSeen, loadingStarted, worldActive, sessionEnded, drainObserved, exitingWorld;
    private static Thread gameThread;
    private static Method startAnim, joinAnim, startAnimal, drainAnimal;
    private static Field clientMode, serverMode, tileStarts, tileMerged, tileStamped;
    private static boolean tileProofNeeded, bakeProofNeeded;
    private static Field bakePlayers, bakeFrames, bakeUsed;
    private static long tileNextCheck;
    private static Class<?> telemetryLua;
    private static boolean telemetryHookReady;

    private Main() {}

    public static void main(String[] args) {
        boolean prewarm = Boolean.getBoolean("pz.optimizerTrial.prewarm");
        try {
            verifyLifecycle(Main.class.getClassLoader(), prewarm);
            telemetryHookReady = true;
        } catch (Throwable error) {
            telemetryHookReady = false;
            disable(error);
            return;
        }
        if (!prewarm) {
            System.out.println("[OptimizerTrial] bridge inactive: explicit opt-in absent");
            return;
        }
        try {
            mode = launchMode(System.getProperty("pz.optimizerTrial.mode", "singleplayer"));
            Path cache = Path.of(required("pz.optimizerTrial.cachedir")).toRealPath();
            verifyResources(Main.class.getClassLoader(), Path.of(required("pz.optimizerTrial.sourceZip")), cache);
            verifyProfile();
            for (String key : new String[]{"enabled", "worldgenPatternCache", "preloadAnimSets", "animalPreload"})
                if (!"true".equals(System.getProperty("pzopt." + key)))
                    throw new IllegalStateException("required -Dpzopt." + key + "=true");
            if (!"false".equals(System.getProperty("pzopt.instrument")))
                throw new IllegalStateException("required -Dpzopt.instrument=false");
            // The launcher must have set the game's cache before loading this Java mod.
            Class<?> fs = Class.forName("zombie.ZomboidFileSystem", false, Main.class.getClassLoader());
            Object singleton = fs.getField("instance").get(null);
            Path actual = Path.of((String) fs.getMethod("getCacheDir").invoke(singleton)).toRealPath();
            if (!cache.equals(actual)) throw new IllegalStateException("game cache differs from isolated trial cache");
            enabled = true;
            System.out.println("[OptimizerTrial] prewarm armed; awaiting OnGameBoot; mode=" + mode);
        } catch (Throwable error) { disable(error); }
    }

    static String launchMode(String value) {
        if (!"singleplayer".equals(value) && !"multiplayer".equals(value))
            throw new IllegalArgumentException("unsupported pz.optimizerTrial.mode: " + value);
        return value;
    }

    static String required(String key) {
        String value = System.getProperty(key);
        if (value == null || value.isBlank()) throw new IllegalArgumentException("missing " + key);
        return value;
    }

    static Properties properties(String resource) {
        try (InputStream in = Main.class.getResourceAsStream("/" + resource)) {
            if (in == null) throw new IllegalStateException("missing bridge manifest " + resource);
            Properties result = new Properties(); result.load(in); return result;
        } catch (Exception error) { throw new ExceptionInInitializerError(error); }
    }

    static void verifyProfile() {
        if (!PROFILE.equals(System.getProperty("pz.optimizerTrial.profile")))
            throw new IllegalStateException("unsupported extended optimizer profile");
        if (PROFILE_PROPERTIES.size() != 770) throw new IllegalStateException("incomplete optimizer profile");
        Properties live = System.getProperties();
        synchronized (live) {
            for (String key : PROFILE_PROPERTIES.stringPropertyNames()) {
                if (!PROFILE_PROPERTIES.getProperty(key).equals(live.getProperty("pzopt." + key)))
                    throw new IllegalStateException("optimizer profile differs: pzopt." + key);
            }
            for (Object key : live.keySet()) {
                if (key instanceof String name && name.startsWith("pzopt.") && !PROFILE_PROPERTIES.containsKey(name.substring(6)))
                    throw new IllegalStateException("optimizer profile differs: unknown " + name);
            }
        }
    }

    /** Pure byte/resource validation: no pzopt class is loaded or initialized here. */
    static void verifyResources(ClassLoader loader, Path archive, Path cache) throws Exception {
        if (Files.exists(cache.resolve("Lua/pzopt-harness.txt")) || Files.exists(cache.resolve("pzopt/benchmark/plan.properties")))
            throw new IllegalStateException("trial cache contains optimizer automation state");
        try (InputStream in = Files.newInputStream(archive)) {
            if (!ARCHIVE_SHA256.equals(sha(in))) throw new IllegalStateException("official archive hash mismatch");
        }
        verifyLifecycle(loader, true);
        int support = 0;
        try (ZipFile zip = new ZipFile(archive.toFile())) {
            for (String name : SELECTED.stringPropertyNames()) {
                var entry = zip.getEntry(name);
                if (entry == null) throw new IllegalStateException("official resource missing: " + name);
                try (InputStream actual = loader.getResourceAsStream(name); InputStream expected = zip.getInputStream(entry)) {
                    String hash = SELECTED.getProperty(name);
                    if (actual == null || !hash.equals(sha(actual)) || !hash.equals(sha(expected)))
                        throw new IllegalStateException("official resource mismatch: " + name);
                }
                support++;
            }
        }
        if (support != 888) throw new IllegalStateException("unexpected official support inventory: " + support);
    }

    /** Shared control/optimized lifecycle gate; resource reads never initialize game or optimizer classes. */
    static void verifyLifecycle(ClassLoader loader, boolean optimized) throws Exception {
        if (!NATIVE_LIFECYCLE.keySet().equals(ORIGINALS.keySet()))
            throw new IllegalStateException("native/optimized lifecycle inventories differ");
        Properties expected = optimized ? ORIGINALS : NATIVE_LIFECYCLE;
        for (String name : expected.stringPropertyNames()) {
            try (InputStream in = loader.getResourceAsStream(name)) {
                if (in == null || !expected.getProperty(name).equals(sha(in)))
                    throw new IllegalStateException("original class hash mismatch (" + (optimized ? "optimized" : "native") + "): " + name);
            }
        }
    }

    private static String sha(InputStream in) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] bytes = new byte[65536];
        for (int count; (count = in.read(bytes)) != -1;) digest.update(bytes, 0, count);
        return HexFormat.of().formatHex(digest.digest());
    }

    private static void disable(Throwable error) {
        enabled = false;
        System.err.println("[OptimizerTrial] prewarm disabled: " + error);
    }

    private static boolean client() throws Exception {
        if (clientMode == null) {
            ClassLoader loader = Main.class.getClassLoader();
            clientMode = Class.forName("zombie.network.GameClient", false, loader).getField("client");
            serverMode = Class.forName("zombie.network.GameServer", false, loader).getField("server");
        }
        return clientMode.getBoolean(null);
    }

    private static void clientProcess() throws Exception {
        client();
        if (serverMode.getBoolean(null)) throw new IllegalStateException("server process is outside this trial");
    }

    private static void expectedSession() throws Exception {
        clientProcess();
        if (client() != "multiplayer".equals(mode))
            throw new IllegalStateException("loaded session differs from launch mode=" + mode);
    }

    private static IllegalStateException restartRequired() {
        return new IllegalStateException("restart required: optimizer trial supports one world session per JVM");
    }

    static boolean worldReady(Thread loading, Object cell) {
        return (loading == null || !loading.isAlive()) && cell != null;
    }

    /** The pinned override synchronizes this reset with animation-cache accesses. Never reset helper internals. */
    public static void animationReset() {
        if (!enabled) return;
        try {
            if (gameThread != null && !onGameThread()) return;
            clientProcess();
            if (exitingWorld) return;
            if (animationStarted || loadingStarted || sessionEnded) throw restartRequired();
            if (client()) clientResetSeen = true;
        } catch (Throwable error) { disable(error); }
    }

    private static boolean onGameThread() {
        if (gameThread != Thread.currentThread()) {
            disable(new IllegalStateException("unexpected lifecycle thread"));
            return false;
        }
        return true;
    }

    /** OnGameBoot is a future invocation even when GameWindow.enter is already active during mod loading. */
    public static void event(String name) {
        if (!enabled || !"OnGameBoot".equals(name)) return;
        try {
            clientProcess();
            if (gameThread == null) gameThread = Thread.currentThread();
            if (!onGameThread()) return;
            if (exitingWorld) return;
            if (animationStarted || loadingStarted || sessionEnded) throw restartRequired();
            if (!booted) arm();
            if ("multiplayer".equals(mode) && (!client() || !clientResetSeen)) {
                System.out.println("[OptimizerTrial] bridge awaiting client reset boot mode=multiplayer");
                return;
            }
            expectedSession();
            startAnim.invoke(null);
            animationStarted = true;
            System.out.println("[OptimizerTrial] official cache and preload active");
            System.out.println("[OptimizerTrial] OnGameBoot animation preload started mode=" + mode
                + " postClientReset=" + clientResetSeen);
        } catch (Throwable error) { disable(error); }
    }

    private static void arm() throws Exception {
        ClassLoader loader = Main.class.getClassLoader();
        Class<?> boot = Class.forName("pzopt.BootAsync", false, loader);
        Class<?> animals = Class.forName("pzopt.AnimalPreload", false, loader);
        startAnim = boot.getMethod("startAnimSets");
        joinAnim = boot.getMethod("joinAnimSets");
        startAnimal = animals.getMethod("start");
        drainAnimal = animals.getMethod("drain");
        Class<?> overrides = Class.forName("pzopt.Overrides", false, loader);
        if (!Boolean.TRUE.equals(overrides.getMethod("buildMatches").invoke(null))
            || !Boolean.TRUE.equals(overrides.getMethod("enabled").invoke(null)))
            throw new IllegalStateException("official optimizer build/master gate is closed");
        Class<?> config = Class.forName("pzopt.Config", false, loader);
        for (String field : new String[]{"WORLDGEN_PATTERN_CACHE", "PRELOAD_ANIM_SETS", "ANIMAL_PRELOAD"})
            if (!config.getField(field).getBoolean(null))
                throw new IllegalStateException("official optimizer feature gate is closed: " + field);
        for (String field : new String[]{"TILE_VERTEX_DEPTH", "TILE_STATE_FOLD", "BAKE_SCHEDULER", "OCCLUSION_RETAIN"})
            if (!config.getField(field).getBoolean(null))
                throw new IllegalStateException("extended feature gate closed: " + field);
        int handoff = config.getField("CHUNK_HANDOFF_DIVISOR").getInt(null);
        if (handoff != 8) throw new IllegalStateException("chunk handoff divisor differs: " + handoff);
        boolean tiles = Class.forName("pzopt.TileBatch", false, loader).getField("ON").getBoolean(null);
        if (tiles) {
            Class<?> batch = Class.forName("pzopt.TileBatch", false, loader);
            tileStarts = batch.getField("starts"); tileMerged = batch.getField("merged"); tileStamped = batch.getField("stamped");
            tileProofNeeded = true;
        }
        boolean bakes = Class.forName("pzopt.BakeScheduler", false, loader).getField("ON").getBoolean(null);
        if (!bakes) throw new IllegalStateException("bake scheduler runtime gate closed");
        Class<?> scheduler = Class.forName("pzopt.BakeScheduler", false, loader);
        bakePlayers = scheduler.getDeclaredField("players"); bakeFrames = scheduler.getDeclaredField("frames");
        bakeUsed = scheduler.getDeclaredField("grantsUsed");
        bakePlayers.setAccessible(true); bakeFrames.setAccessible(true); bakeUsed.setAccessible(true);
        bakeProofNeeded = true;
        if (!tiles && !System.getProperty("os.name", "").startsWith("Mac"))
            throw new IllegalStateException("tile batch runtime gate closed");
        System.out.println("[OptimizerTrial] extended active profile=" + PROFILE + " tileBatch=" + tiles
            + " bakeScheduler=" + bakes + " occlusionRetain=true chunkHandoffDivisor=" + handoff);
        System.out.println("[OptimizerTrial] official cache and preload armed");
        booted = true;
    }

    public static void load() {
        if (!enabled) return;
        try {
            if (!booted) throw new IllegalStateException("OnGameBoot not observed; preload gate closed");
            if (!onGameThread()) return;
            expectedSession();
            if (loadingStarted || sessionEnded) throw restartRequired();
            if (!animationStarted) throw new IllegalStateException("session animation preload not started; loading gate closed");
            joinAnim.invoke(null);
            if (Thread.currentThread().isInterrupted()) throw new IllegalStateException("animation preload join interrupted");
            startAnimal.invoke(null);
            loadingStarted = true;
            System.out.println("[OptimizerTrial] animation preload joined; animal preload started mode=" + mode);
        } catch (Throwable error) { disable(error); }
    }

    /** IngameState follows GameLoadingState.exit, which clears the native loader. */
    public static void worldEntered() {
        if (!enabled) return;
        try {
            if (!onGameThread()) return;
            expectedSession();
            if (worldActive || sessionEnded) throw restartRequired();
            if (!loadingStarted) throw new IllegalStateException("world entered without loading phase");
            ClassLoader loader = Main.class.getClassLoader();
            Thread loading = (Thread) Class.forName("zombie.gameStates.GameLoadingState", false, loader).getField("loader").get(null);
            Object world = Class.forName("zombie.iso.IsoWorld", false, loader).getField("instance").get(null);
            if (!worldReady(loading, world == null ? null : world.getClass().getField("currentCell").get(world)))
                throw new IllegalStateException("world entered before native loading completed");
            worldActive = true;
            System.out.println("[OptimizerTrial] bridge ready mode=" + mode + " client=" + client()
                + " server=false session=1");
        } catch (Throwable error) { disable(error); }
    }

    public static void worldExited() {
        flushTelemetry("WorldExit");
        if (!enabled) return;
        try {
            if (!onGameThread()) return;
            clientProcess();
            worldActive = false;
            sessionEnded = true;
            exitingWorld = true;
            System.out.println("[OptimizerTrial] session ended; restart required before another world");
        } catch (Throwable error) { disable(error); }
    }

    public static void worldExitCompleted() {
        if (!enabled) return;
        if (onGameThread()) exitingWorld = false;
    }

    /** Look up the current observer after each Lua reset. It owns client checks and duplicate suppression. */
    public static void flushTelemetry(String reason) {
        if (!telemetryHookReady) return;
        try {
            if (telemetryLua == null) telemetryLua = Class.forName("zombie.Lua.LuaManager", false, Main.class.getClassLoader());
            Object env = telemetryLua.getField("env").get(null);
            if (env == null || telemetryLua.getField("caller").get(null) == null || telemetryLua.getField("thread").get(null) == null) return;
            Object observer = env.getClass().getMethod("rawget", Object.class).invoke(env, "PZOptimizerTrialTelemetryFlush");
            if (observer == null) return;
            telemetryLua.getMethod("call", String.class, Object.class).invoke(null, "PZOptimizerTrialTelemetryFlush", reason);
        } catch (Throwable error) {
            System.err.println("[OptimizerTrial] telemetry flush failed reason=" + reason + " error=" + error);
        }
    }

    public static void disconnected() {
        flushTelemetry("Disconnect");
        if (!enabled) return;
        if (!onGameThread()) return;
        worldActive = false;
        sessionEnded = true;
        System.out.println("[OptimizerTrial] session disconnected; restart required before another world");
    }

    public static void frame() {
        if (!enabled || !booted) return;
        try {
            if (!onGameThread()) return;
            clientProcess();
            if (!worldActive || sessionEnded) return;
            expectedSession();
            // Official drain waits for the loader to finish and publishes only on this game thread.
            drainAnimal.invoke(null);
            if (!drainObserved) {
                drainObserved = true;
                System.out.println("[OptimizerTrial] animal drain invoked mode=" + mode + " client=" + client() + " server=false");
            }
            if ((tileProofNeeded || bakeProofNeeded) && System.nanoTime() >= tileNextCheck) {
                tileNextCheck = System.nanoTime() + 1_000_000_000L;
                if (tileProofNeeded) {
                    long starts = tileStarts.getLong(null), merged = tileMerged.getLong(null), stamped = tileStamped.getLong(null);
                    if (starts > 0 && merged > 0 && stamped > 0) {
                        tileProofNeeded = false;
                        System.out.println("[OptimizerTrial] tile batch used starts=" + starts + " merged=" + merged + " stamped=" + stamped);
                    }
                }
                if (bakeProofNeeded) {
                    Object[] players = (Object[]) bakePlayers.get(null);
                    if (players[0] != null) {
                        long frames = bakeFrames.getLong(players[0]), used = bakeUsed.getLong(players[0]);
                        if (frames > 0 && used > 0) {
                            bakeProofNeeded = false;
                            System.out.println("[OptimizerTrial] bake scheduler used frames=" + frames + " grants=" + used);
                        }
                    }
                }
            }
        } catch (Throwable error) { disable(error); }
    }

    @Patch(className="zombie.Lua.LuaEventManager", methodName="triggerEvent")
    public static class BootEvent {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) String name) { Main.event(name); }
    }
    @Patch(className="zombie.gameStates.GameLoadingState", methodName="enter", strictMatch=true)
    public static class Loading {
        @Patch.OnEnter public static void enter() { Main.load(); }
    }
    @Patch(className="zombie.GameWindow", methodName="frameStep", strictMatch=true)
    public static class Frame {
        @Patch.OnEnter public static void enter() { Main.frame(); }
    }
    @Patch(className="zombie.core.skinnedmodel.advancedanimation.AnimationSet", methodName="Reset", strictMatch=true)
    public static class AnimationReset {
        @Patch.OnEnter public static void enter() { Main.animationReset(); }
    }
    @Patch(className="zombie.gameStates.IngameState", methodName="enter", strictMatch=true)
    public static class WorldEnter {
        @Patch.OnEnter public static void enter() { Main.worldEntered(); }
    }
    @Patch(className="zombie.gameStates.IngameState", methodName="exit", strictMatch=true)
    public static class WorldExit {
        @Patch.OnEnter public static void enter() { Main.worldExited(); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit() { Main.worldExitCompleted(); }
    }
    @Patch(className="zombie.gameStates.ServerDisconnectState", methodName="enter", strictMatch=true)
    public static class Disconnect {
        @Patch.OnEnter public static void enter() { Main.disconnected(); }
    }
}
