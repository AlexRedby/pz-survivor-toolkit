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

/** Experimental SP lifecycle adapter; optimizer algorithms remain in the user's official download. */
public final class Main {
    public static final String ARCHIVE_SHA256 = "2bcd0e01a3ac66856fae137ff1dbda66c8397375da781e7a6ed67fe2b9d6590d";
    public static final String PROFILE = "xd3i-b42.21-d1bbdcf-bounded-v1";
    private static final Properties ORIGINALS = properties("optimizer-trial-native.properties");
    private static final Properties SELECTED = properties("optimizer-trial-selected.properties");
    private static final Properties PROFILE_PROPERTIES = properties("optimizer-trial-profile.properties");
    private static volatile boolean enabled;
    private static boolean booted;
    private static Thread gameThread;
    private static Method startAnim, joinAnim, startAnimal, drainAnimal;
    private static Field clientMode, serverMode, tileStarts, tileMerged, tileStamped;
    private static boolean tileProofNeeded, bakeProofNeeded;
    private static Field bakePlayers, bakeFrames, bakeUsed;
    private static long tileNextCheck;

    private Main() {}

    public static void main(String[] args) {
        if (!Boolean.getBoolean("pz.optimizerTrial.prewarm")) {
            System.out.println("[OptimizerTrial] prewarm disabled: explicit opt-in absent");
            return;
        }
        try {
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
            System.out.println("[OptimizerTrial] prewarm armed; awaiting OnGameBoot; SP trial only");
        } catch (Throwable error) { disable(error); }
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
        for (String name : ORIGINALS.stringPropertyNames()) {
            try (InputStream in = loader.getResourceAsStream(name)) {
                if (in == null || !ORIGINALS.getProperty(name).equals(sha(in)))
                    throw new IllegalStateException("original class hash mismatch: " + name);
            }
        }
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

    private static boolean singlePlayer() throws Exception {
        if (clientMode == null) {
            ClassLoader loader = Main.class.getClassLoader();
            clientMode = Class.forName("zombie.network.GameClient", false, loader).getField("client");
            serverMode = Class.forName("zombie.network.GameServer", false, loader).getField("server");
        }
        return !clientMode.getBoolean(null) && !serverMode.getBoolean(null);
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
        if (!enabled || booted || !"OnGameBoot".equals(name)) return;
        try {
            if (!singlePlayer()) throw new IllegalStateException("multiplayer is outside this trial");
            gameThread = Thread.currentThread();
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
            System.out.println("[OptimizerTrial] official cache and preload active");
            startAnim.invoke(null);
            booted = true;
            System.out.println("[OptimizerTrial] OnGameBoot animation preload started");
        } catch (Throwable error) { disable(error); }
    }

    public static void load() {
        if (!enabled) return;
        try {
            if (!booted) throw new IllegalStateException("OnGameBoot not observed; preload gate closed");
            if (!onGameThread()) return;
            if (!singlePlayer()) throw new IllegalStateException("multiplayer is outside this trial");
            joinAnim.invoke(null);
            if (Thread.currentThread().isInterrupted()) throw new IllegalStateException("animation preload join interrupted");
            startAnimal.invoke(null);
            System.out.println("[OptimizerTrial] animation preload joined; animal preload started");
        } catch (Throwable error) { disable(error); }
    }

    public static void frame() {
        if (!enabled || !booted) return;
        try {
            if (!onGameThread()) return;
            if (!singlePlayer()) throw new IllegalStateException("multiplayer is outside this trial");
            // Official drain waits for the loader to finish and publishes only on this game thread.
            drainAnimal.invoke(null);
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
}
