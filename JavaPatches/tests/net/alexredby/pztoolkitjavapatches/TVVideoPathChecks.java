package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.HashSet;
import me.zed_0xff.zombie_buddy.PatchEngine;
import sun.misc.Unsafe;
import zombie.ZomboidFileSystem;
import zombie.core.textures.Texture;
import zombie.core.textures.VideoTexture;
import zombie.gameStates.ChooseGameInfo;

public final class TVVideoPathChecks {
    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }

    private static Field field(Class<?> type, String name) throws Exception {
        var result = type.getDeclaredField(name); result.setAccessible(true); return result;
    }

    private static String key(String filename) {
        return ZomboidFileSystem.instance.getMediaPath("videos/" + filename);
    }

    private static VideoTexture video(Unsafe unsafe, String filename) throws Exception {
        var texture = (VideoTexture)unsafe.allocateInstance(VideoTexture.class);
        field(VideoTexture.class, "videoFilename").set(texture, filename);
        field(VideoTexture.class, "binkId").setInt(texture, -1);
        return texture;
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        var fs = ZomboidFileSystem.instance;
        fs.setCacheDir(System.getProperty("pz.test.cache")); fs.init();
        var cache = Path.of(System.getProperty("pz.test.cache"));
        var root = cache.resolve("relocated Mods/TVRadio");
        var directory = root.resolve("42/media/videos"); Files.createDirectories(directory);
        Files.createDirectories(root.resolve("common"));
        Files.writeString(root.resolve("common/mod.info"), "id=TVRadio_ReInvented\n");
        Files.writeString(root.resolve("42/mod.info"), "id=TVRadio_ReInvented\nmodversion=1.4\n");
        Files.writeString(directory.resolve("Future_Video.bik"), "fixture only; never decoded");
        fs.setModIdToDir(TVVideoPaths.MOD, root.toString());
        var mod = ChooseGameInfo.getModDetails(TVVideoPaths.MOD);
        require(mod != null && Path.of(mod.getVersionDir()).equals(root.resolve("42")),
            "native metadata did not select the fixture version directory");
        require("1.4".equals(mod.getModVersion()), "fixture metadata version was not read");
        fs.getModIDs().add(TVVideoPaths.MOD);
        require(TVVideoPaths.SUPPORTED, "native video/path bytecode is unsupported");
        String input = TVVideoPaths.PREFIX + "Future_Video.bik";
        String redirected = TVVideoPaths.redirect(input, true);
        require(!input.equals(redirected), "active relocated video was not redirected");
        require(Path.of(key(redirected)).normalize().equals(directory.resolve("Future_Video.bik")),
            "redirected native path does not reach the active mod video");
        require(TVVideoPaths.redirect(input, false).equals(input), "unsupported bytecode changed the path");
        for (String name : new String[]{"../Future_Video.bik", "nested/Future_Video.bik", "nested\\Future_Video.bik",
                "/Future_Video.bik", "Future_Video.png", "missing.bik", "", "Future_Video.bik/../other.bik"}) {
            String original = TVVideoPaths.PREFIX + name;
            require(TVVideoPaths.redirect(original, true).equals(original), "invalid/missing filename changed: " + name);
        }
        require(TVVideoPaths.redirect(null, true) == null, "null filename changed");
        require(TVVideoPaths.redirect("OtherMod/Future_Video.bik", true).equals("OtherMod/Future_Video.bik"),
            "unrelated video changed");
        var outside = cache.resolve("outside.bik"); Files.writeString(outside, "outside");
        Files.createSymbolicLink(directory.resolve("Escaped.bik"), outside);
        require(TVVideoPaths.redirect(TVVideoPaths.PREFIX + "Escaped.bik", true)
            .equals(TVVideoPaths.PREFIX + "Escaped.bik"), "symlink escaped the active video directory");

        var unsafe = (Unsafe)field(Unsafe.class, "theUnsafe").get(null);
        var successful = (HashMap<String, VideoTexture>)field(VideoTexture.class, "successfullyLoaded").get(null);
        var failed = (HashSet<String>)field(VideoTexture.class, "failedToLoad").get(null);
        String originalKey = key(input), correctedKey = key(redirected);
        var originalVideo = video(unsafe, originalKey);
        var correctedVideo = video(unsafe, correctedKey);
        successful.put(originalKey, originalVideo); successful.put(correctedKey, correctedVideo);
        require(VideoTexture.getOrCreate(input, 160, 120, false) == originalVideo,
            "baseline did not use its original native cache key");
        var originalFileMap = new HashMap<>(fs.activeFileMap);
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", TVVideoPathChecks.class.getClassLoader());
        require(VideoTexture.getOrCreate(input, 160, 120, false) == correctedVideo,
            "woven getOrCreate did not resolve before the native cache lookup");
        require(VideoTexture.getOrCreate(input, 320, 240, true) == correctedVideo,
            "native cache semantics changed with dimensions or async");
        require(field(VideoTexture.class, "videoFilename").get(correctedVideo).equals(correctedKey),
            "cached object's native filename changed after construction");
        failed.add(correctedKey);
        require(VideoTexture.getOrCreate(input, 160, 120, false) == null,
            "native failed-cache precedence did not use the corrected key");
        failed.remove(correctedKey);
        field(Texture.class, "destroyed").setBoolean(correctedVideo, true);
        require(VideoTexture.getOrCreate(input, 160, 120, false) == correctedVideo
            && !successful.containsKey(correctedKey), "native destroyed-entry eviction changed");
        successful.put(correctedKey, correctedVideo); failed.add(correctedKey);
        correctedVideo.closeAndDestroy();
        require(!successful.containsKey(correctedKey) && !failed.contains(correctedKey)
            && successful.get(originalKey) == originalVideo, "native close removed inconsistent cache keys");

        fs.getModIDs().remove(TVVideoPaths.MOD);
        require(VideoTexture.getOrCreate(input, 160, 120, false) == originalVideo,
            "inactive mod changed native lookup");
        fs.getModIDs().add(TVVideoPaths.MOD);
        String system = System.getProperty("os.name");
        try {
            System.setProperty("os.name", "non-Mac fixture");
            require(VideoTexture.getOrCreate(input, 160, 120, false) == originalVideo,
                "non-Mac path changed native lookup");
        } finally { System.setProperty("os.name", system); }
        var moved = root.resolve("another active layer"); Files.createDirectories(moved.resolve("media/videos"));
        Files.writeString(moved.resolve("media/videos/Future_Video.bik"), "moved");
        mod.versionDir = moved.toString();
        String movedName = TVVideoPaths.redirect(input, true);
        require(Path.of(key(movedName)).normalize().equals(moved.resolve("media/videos/Future_Video.bik")),
            "active version-directory change reused the previous path");
        var movedVideo = video(unsafe, key(movedName)); successful.put(key(movedName), movedVideo);
        require(VideoTexture.getOrCreate(input, 160, 120, false) == movedVideo,
            "woven lookup did not follow the changed mod directory");
        Files.delete(moved.resolve("media/videos/Future_Video.bik"));
        require(VideoTexture.getOrCreate(input, 160, 120, false) == originalVideo,
            "missing active file changed native lookup");
        require(originalFileMap.equals(fs.activeFileMap), "video correction changed global filesystem mappings");
        System.out.println("TV_VIDEO_PATH_CHECKS_PASS (native metadata, contained dynamic paths, woven successful/failed caches, eviction and close keys)");
        System.exit(0);
    }
}
