package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import zombie.ZomboidFileSystem;
import zombie.gameStates.ChooseGameInfo;

/** Repair the upstream workshop-relative path before native video caching and construction. */
public final class TVVideoPaths {
    static final String MOD = "TVRadio_ReInvented";
    static final String PREFIX = "../../../../workshop/content/108600/3420581050/mods/TVRadio Reinvented/42/media/videos/";
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/core/textures/VideoTexture.class",
        "5e25be5f6eb70d7be385c2c732b87eacc2a7032e34deef67297382d2edc7e3b4")
        && BytecodeSupport.supports("zombie/ZomboidFileSystem.class",
            "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo.class",
            "8c4b47ba966f071120feeec090202967e414246e28b5b6fd6a622a6a266af651")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo$Mod.class",
            "c91e48400b77015c450a696f2d7c5665fa872f1a76fc05d2c38e72ba2928dc69");

    public static String redirect(String filename, boolean supported) {
        if (!supported || filename == null || !filename.startsWith(PREFIX)
            || !System.getProperty("os.name", "").contains("OS X")) return filename;
        var fs = ZomboidFileSystem.instance;
        if (!fs.getModIDs().contains(MOD)) return filename;
        try {
            var mod = ChooseGameInfo.getModDetails(MOD);
            if (mod == null || mod.getVersionDir() == null) return filename;
            return relative(filename, Path.of(mod.getVersionDir()), Path.of(fs.getMediaPath("videos")));
        } catch (RuntimeException error) {
            return filename;
        }
    }

    static String relative(String filename, Path versionDirectory, Path nativeVideos) {
        if (filename == null || !filename.startsWith(PREFIX)) return filename;
        String basename = filename.substring(PREFIX.length());
        if (!basename.matches("[A-Za-z0-9_-]+\\.bik")) return filename;
        try {
            var directory = versionDirectory.resolve("media/videos").toAbsolutePath().normalize();
            var target = directory.resolve(basename);
            if (!Files.isRegularFile(target) || !target.toRealPath().startsWith(directory.toRealPath())) return filename;
            return nativeVideos.toAbsolutePath().normalize().relativize(target).toString();
        } catch (IOException | IllegalArgumentException | SecurityException error) {
            return filename;
        }
    }

    private TVVideoPaths() {}
}
