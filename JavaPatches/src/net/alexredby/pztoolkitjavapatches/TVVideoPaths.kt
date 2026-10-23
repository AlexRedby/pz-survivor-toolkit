@file:JvmName("TVVideoPaths")

package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import zombie.ZomboidFileSystem
import zombie.gameStates.ChooseGameInfo

/** Repair the upstream workshop-relative path before native video caching and construction. */
internal const val MOD = "TVRadio_ReInvented"
internal const val PREFIX =
    "../../../../workshop/content/108600/3420581050/mods/TVRadio Reinvented/42/media/videos/"

@JvmField
val SUPPORTED =
    BytecodeSupport.supports(
        "zombie/core/textures/VideoTexture.class",
        "5e25be5f6eb70d7be385c2c732b87eacc2a7032e34deef67297382d2edc7e3b4",
    ) &&
        BytecodeSupport.supports(
            "zombie/ZomboidFileSystem.class",
            "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750",
        ) &&
        BytecodeSupport.supports(
            "zombie/gameStates/ChooseGameInfo.class",
            "8c4b47ba966f071120feeec090202967e414246e28b5b6fd6a622a6a266af651",
        ) &&
        BytecodeSupport.supports(
            "zombie/gameStates/ChooseGameInfo\$Mod.class",
            "c91e48400b77015c450a696f2d7c5665fa872f1a76fc05d2c38e72ba2928dc69",
        )

fun redirect(filename: String?, supported: Boolean): String? {
    if (
        !supported ||
            filename == null ||
            !filename.startsWith(PREFIX) ||
            !System.getProperty("os.name", "").contains("OS X")
    )
        return filename
    val fileSystem = ZomboidFileSystem.instance
    if (MOD !in fileSystem.getModIDs()) return filename
    return try {
        val mod = ChooseGameInfo.getModDetails(MOD) ?: return filename
        if (mod.getVersionDir() == null) return filename
        relative(filename, Path.of(mod.getVersionDir()), Path.of(fileSystem.getMediaPath("videos")))
    } catch (_: RuntimeException) {
        filename
    }
}

@JvmName("relative")
internal fun relative(filename: String?, versionDirectory: Path?, nativeVideos: Path?): String? {
    if (filename == null || !filename.startsWith(PREFIX)) return filename
    val basename = filename.substring(PREFIX.length)
    if (!basename.matches(Regex("[A-Za-z0-9_-]+\\.bik"))) return filename
    return try {
        // Validate nullable Java inputs only when reached, preserving the original guard order.
        val version = versionDirectory ?: throw NullPointerException()
        val target = containedVideo(version, basename) ?: return filename
        val videos = nativeVideos ?: throw NullPointerException()
        videos.toAbsolutePath().normalize().relativize(target).toString()
    } catch (_: IOException) {
        filename
    } catch (_: IllegalArgumentException) {
        filename
    } catch (_: SecurityException) {
        filename
    }
}

private fun containedVideo(versionDirectory: Path, basename: String): Path? {
    val directory = versionDirectory.resolve("media/videos").toAbsolutePath().normalize()
    return directory.resolve(basename).takeIf { target ->
        Files.isRegularFile(target) && target.toRealPath().startsWith(directory.toRealPath())
    }
}
