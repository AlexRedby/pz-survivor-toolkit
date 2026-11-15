package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.nio.file.Files
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.PatchEngine
import sun.misc.Unsafe
import zombie.ZomboidFileSystem
import zombie.core.textures.Texture
import zombie.core.textures.VideoTexture
import zombie.gameStates.ChooseGameInfo

object TVVideoPathChecks {
    /** A failed fixture lookup must assert before the headless JVM tries to allocate a GL texture. */
    private class Cache : HashMap<String, VideoTexture>() {
        override fun containsKey(key: String): Boolean {
            if (!super.containsKey(key)) throw AssertionError("Unexpected native video cache key: $key; seeded=$keys")
            return true
        }
    }
    private fun verify(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun key(filename: String?): String =
        // The reviewed fixture has one active mod and its video in the version directory.
        // 42.22 resolves that provider before native videos and retains the path spelling as key.
        Path.of(ChooseGameInfo.getModDetails(MOD).getVersionDir(), "media/videos/$filename")
            .toAbsolutePath().toString()

    private fun rejectedPrefix(filename: String) {
        try {
            VideoTexture.getOrCreate(filename, 160, 120, false)
            throw AssertionError("native prefix guard accepted the malformed Workshop path")
        } catch (failure: IllegalArgumentException) {
            verify(failure.message?.startsWith("Invalid prefix found for:") == true,
                "unrelated native video failure: $failure")
        }
    }

    private fun video(unsafe: Unsafe, filename: String): VideoTexture =
        (unsafe.allocateInstance(VideoTexture::class.java) as VideoTexture).apply {
            field(VideoTexture::class.java, "videoFilename").set(this, filename)
            field(VideoTexture::class.java, "binkId").setInt(this, -1)
        }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val fileSystem = ZomboidFileSystem.instance
        fileSystem.setCacheDir(System.getProperty("pz.test.cache"))
        fileSystem.init()
        val cache = Path.of(System.getProperty("pz.test.cache"))
        val root = cache.resolve("relocated Mods/TVRadio")
        val directory = root.resolve("42/media/videos")
        Files.createDirectories(directory)
        Files.createDirectories(root.resolve("common"))
        Files.writeString(root.resolve("common/mod.info"), "id=TVRadio_ReInvented\n")
        Files.writeString(root.resolve("42/mod.info"), "id=TVRadio_ReInvented\nmodversion=1.4\n")
        Files.writeString(directory.resolve("Future_Video.bik"), "fixture only; never decoded")
        fileSystem.setModIdToDir(MOD, root.toString())
        val mod =
            ChooseGameInfo.getModDetails(MOD)
                ?: throw AssertionError(
                    "native metadata did not select the fixture version directory",
                )
        verify(
            Path.of(mod.getVersionDir()) == root.resolve("42"),
            "native metadata did not select the fixture version directory",
        )
        verify(mod.getModVersion() == "1.4", "fixture metadata version was not read")
        fileSystem.getModIDs().add(MOD)
        verify(SUPPORTED, "native video/path bytecode is unsupported")
        val input = PREFIX + "Future_Video.bik"
        verify(
            relative(PREFIX + "../Future_Video.bik", null, null) == PREFIX + "../Future_Video.bik",
            "invalid basename dereferenced unavailable directories",
        )
        verify(
            relative(PREFIX + "missing.bik", root.resolve("42"), null) == PREFIX + "missing.bik",
            "missing video dereferenced the native directory before checking file containment",
        )
        try {
            relative(input, null, directory)
            throw AssertionError("valid video accepted a null version directory")
        } catch (_: NullPointerException) {}
        try {
            relative(input, root.resolve("42"), null)
            throw AssertionError("existing video accepted a null native directory")
        } catch (_: NullPointerException) {}
        val redirected = redirect(input, true)
        verify(input != redirected, "active relocated video was not redirected")
        verify(
            Path.of(key(redirected)).normalize() == directory.resolve("Future_Video.bik"),
            "redirected native path does not reach the active mod video",
        )
        verify(redirect(input, false) == input, "unsupported bytecode changed the path")
        for (name in
            arrayOf(
                "../Future_Video.bik",
                "nested/Future_Video.bik",
                "nested\\Future_Video.bik",
                "/Future_Video.bik",
                "Future_Video.png",
                "missing.bik",
                "",
                "Future_Video.bik/../other.bik",
            )) {
            val original = PREFIX + name
            verify(redirect(original, true) == original, "invalid/missing filename changed: $name")
        }
        verify(redirect(null, true) == null, "null filename changed")
        verify(
            relative(null, null, null) == null,
            "relative null filename dereferenced unused directories",
        )
        verify(
            relative("OtherMod/Future_Video.bik", null, null) == "OtherMod/Future_Video.bik",
            "relative unrelated filename dereferenced unused directories",
        )
        verify(
            redirect("OtherMod/Future_Video.bik", true) == "OtherMod/Future_Video.bik",
            "unrelated video changed",
        )
        val outside = cache.resolve("outside.bik")
        Files.writeString(outside, "outside")
        Files.createSymbolicLink(directory.resolve("Escaped.bik"), outside)
        verify(
            redirect(PREFIX + "Escaped.bik", true) == PREFIX + "Escaped.bik",
            "symlink escaped the active video directory",
        )

        val unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        val cacheField = field(VideoTexture::class.java, "successfullyLoaded")
        val successful = Cache()
        successful.putAll(cacheField.get(null) as HashMap<String, VideoTexture>)
        unsafe.putObjectVolatile(unsafe.staticFieldBase(cacheField), unsafe.staticFieldOffset(cacheField), successful)
        val failed = field(VideoTexture::class.java, "failedToLoad").get(null) as HashSet<String>
        val originalKey = key(input)
        val correctedKey = key(redirected)
        val originalVideo = video(unsafe, originalKey)
        val correctedVideo = video(unsafe, correctedKey)
        successful[originalKey] = originalVideo
        successful[correctedKey] = correctedVideo
        // The new engine checks allowed roots before even consulting this cached bad path.
        rejectedPrefix(input)
        val originalFileMap = HashMap(fileSystem.activeFileMap)
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            TVVideoPathChecks::class.java.classLoader,
        )
        verify(
            VideoTexture.getOrCreate(input, 160, 120, false) === correctedVideo,
            "woven getOrCreate did not resolve before the native cache lookup",
        )
        verify(
            VideoTexture.getOrCreate(input, 320, 240, true) === correctedVideo,
            "native cache semantics changed with dimensions or async",
        )
        verify(
            field(VideoTexture::class.java, "videoFilename").get(correctedVideo) == correctedKey,
            "cached object's native filename changed after construction",
        )
        failed.add(correctedKey)
        verify(
            VideoTexture.getOrCreate(input, 160, 120, false) == null,
            "native failed-cache precedence did not use the corrected key",
        )
        failed.remove(correctedKey)
        field(Texture::class.java, "destroyed").setBoolean(correctedVideo, true)
        verify(
            VideoTexture.getOrCreate(input, 160, 120, false) === correctedVideo &&
                successful.entries.none { it.key == correctedKey },
            "native destroyed-entry eviction changed",
        )
        successful[correctedKey] = correctedVideo
        failed.add(correctedKey)
        correctedVideo.closeAndDestroy()
        verify(
            successful.entries.none { it.key == correctedKey } &&
                correctedKey !in failed &&
                successful[originalKey] === originalVideo,
            "native close removed inconsistent cache keys",
        )

        fileSystem.getModIDs().remove(MOD)
        rejectedPrefix(input)
        fileSystem.getModIDs().add(MOD)
        val system = System.getProperty("os.name")
        try {
            System.setProperty("os.name", "non-Mac fixture")
            rejectedPrefix(input)
        } finally {
            System.setProperty("os.name", system)
        }
        val moved = root.resolve("another active layer")
        Files.createDirectories(moved.resolve("media/videos"))
        Files.writeString(moved.resolve("media/videos/Future_Video.bik"), "moved")
        mod.versionDir = moved.toString()
        val movedName = redirect(input, true)
        verify(
            Path.of(key(movedName)).normalize() == moved.resolve("media/videos/Future_Video.bik"),
            "active version-directory change reused the previous path",
        )
        val movedVideo = video(unsafe, key(movedName))
        successful[key(movedName)] = movedVideo
        verify(
            VideoTexture.getOrCreate(input, 160, 120, false) === movedVideo,
            "woven lookup did not follow the changed mod directory",
        )
        Files.delete(moved.resolve("media/videos/Future_Video.bik"))
        rejectedPrefix(input)
        verify(
            originalFileMap == fileSystem.activeFileMap,
            "video correction changed global filesystem mappings",
        )
        println(
            "TV_VIDEO_PATH_CHECKS_PASS (native metadata, contained dynamic paths, woven successful/failed caches, eviction and close keys)",
        )
        kotlin.system.exitProcess(0)
    }
}
