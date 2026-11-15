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
        "f2e8095e7cff8a5a1fe35d7fc1b18c06a8eca15777a44a58408b791469246157",
    ) &&
        BytecodeSupport.supports(
            "zombie/ZomboidFileSystem.class",
            "9f902cc912c7802a08f80614f5f8d3b74f249fc5f2c0204eb759f2e74dda175e",
        ) &&
        BytecodeSupport.supports(
            "zombie/gameStates/ChooseGameInfo.class",
            "5b124fe4e6f8525ed431e8c1ef62238597a7981276c13c3ddaa39c1ca1cee4b0",
        ) &&
        BytecodeSupport.supports(
            "zombie/gameStates/ChooseGameInfo\$Mod.class",
            "9f304e567f306ff43db87e85927b794be2727f5d5cb6bafbe9c6c3802de08224",
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
