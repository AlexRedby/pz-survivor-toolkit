package net.alexredby.worldrenderfixture;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Set;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.iso.IsoCamera;
import zombie.iso.IsoChunk;
import zombie.iso.IsoWorld;
import zombie.iso.fboRenderChunk.FBORenderCutaways;

/** Test-only post-world-draw snapshots. Never edits cutaway flags, caches, dirty bits or callbacks. */
public final class Main {
    private static final String CLASS = "zombie/iso/fboRenderChunk/FBORenderCutaways.class";
    private static final Set<String> SUPPORTED = Set.of(
        "9f44080e7858af88c858235939a7bfc2b3c792ee64b69c763568f1ecc6d6ce03",
        "adf81d2ee0e30dc05a90bb61694b9049508169122d6e21ef40bc2b5fb2a9bb5a");
    private static Field invalidated;
    private static Method hasAny;
    private static String sha = "", error = "";
    private static int snapshots, observations, mismatches, asymmetric, lastFrame = -1;
    private static int firstX, firstY, firstZ;
    private static boolean firstExpected, firstCached;

    private static void require(boolean value, String message) {
        if (!value) throw new IllegalStateException(message);
    }
    private static void disposable(IsoPlayer player) {
        String cache = System.getenv("PZ_WORLD_RENDER_CACHE");
        require(cache != null && Path.of(cache).isAbsolute() && Path.of(cache).normalize().equals(
            Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize()), "Owned runner cache required");
        require(player != null && player.isLocalPlayer() && player.getSquare() != null, "Native local player required");
    }
    private static void metadata() throws Exception {
        if (invalidated != null) return;
        try (var stream = FBORenderCutaways.class.getClassLoader().getResourceAsStream(CLASS)) {
            require(stream != null, "Missing cutaways class resource");
            sha = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes()));
        }
        require(SUPPORTED.contains(sha), "Unsupported cutaways class resource: " + sha);
        Field field = FBORenderCutaways.class.getDeclaredField("invalidatedChunks");
        field.setAccessible(true);
        Method method = FBORenderCutaways.class.getDeclaredMethod("hasAnyCutawayWalls", int.class,
            IsoChunk.class, int.class, byte.class, int.class, int.class, int.class, int.class);
        method.setAccessible(true);
        hasAny = method;
        invalidated = field;
    }
    @LuaMethod(name="worldRenderCutawayObserve", global=true)
    public static void observe(IsoPlayer player) {
        if (!error.isEmpty() || snapshots >= 64 || observations >= 64) return;
        try {
            disposable(player);
            metadata();
            int frame = IsoWorld.instance.getFrameNo();
            if (frame == lastFrame) return;
            lastFrame = frame;
            require(IsoCamera.frameState.playerIndex == player.getPlayerNum(), "Cutaway camera/player index differs");
            snapshots++;
            int z = PZMath.fastfloor(IsoCamera.frameState.camCharacterZ), checked = 0;
            FBORenderCutaways owner = FBORenderCutaways.getInstance();
            // Called from OnPreUIDraw after the world's render pass, on the game thread.
            // The previous method's actual invalidated set is inspected; no target method is instrumented.
            for (Object value : (Set<?>) invalidated.get(owner)) {
                if (!(value instanceof IsoChunk chunk)) continue;
                var level = chunk.getCutawayData().getDataForLevel(z);
                if (level == null) continue;
                boolean expected = (boolean) hasAny.invoke(owner, player.getPlayerNum(), chunk, z, (byte) 2, 0, 7, 7, 7);
                boolean cached = level.hasCutawayWestWallsOnSouthEdge;
                observations++;
                if (expected != level.hasCutawayWestWallsOnNorthEdge) asymmetric++;
                if (expected != cached) {
                    if (mismatches++ == 0) {
                        firstX = chunk.wx; firstY = chunk.wy; firstZ = z;
                        firstExpected = expected; firstCached = cached;
                    }
                }
                // Spread at most two edges per discrete snapshot over the scene transitions.
                if (++checked >= 2 || observations >= 64) break;
            }
        } catch (Exception | LinkageError failure) {
            error = failure.getClass().getSimpleName() + ": " + failure.getMessage();
        }
    }
    private static String quote(String value) {
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " ") + "\"";
    }
    @LuaMethod(name="worldRenderCutawayReport", global=true)
    public static String report(IsoPlayer player) {
        disposable(player);
        return "{\"sha256\":" + quote(sha) + ",\"snapshots\":" + snapshots
            + ",\"observations\":" + observations + ",\"mismatches\":" + mismatches
            + ",\"asymmetric\":" + asymmetric + ",\"error\":" + quote(error)
            + ",\"firstMismatch\":{\"wx\":" + firstX + ",\"wy\":" + firstY + ",\"z\":" + firstZ
            + ",\"expected\":" + firstExpected + ",\"cached\":" + firstCached + "}}";
    }
}
