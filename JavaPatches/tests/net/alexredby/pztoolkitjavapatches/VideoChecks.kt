package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Modifier
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.util.Comparator
import java.util.concurrent.BlockingQueue
import java.util.concurrent.TimeUnit
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaThread
import zombie.Lua.LuaManager
import zombie.ZomboidFileSystem

/** Headless public path guards, timeline and real encoder checks; no GL context. */
object VideoChecks {
    @JvmStatic
    fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    @JvmStatic
    fun field(owner: Any, name: String): Field =
        owner.javaClass.getDeclaredField(name).apply { isAccessible = true }

    @JvmStatic
    fun session(directory: Path, executable: String): Any {
        val constructor =
            Class.forName(VideoRecording::class.java.name + "\$Session")
                .getDeclaredConstructor(Path::class.java, String::class.java)
        constructor.isAccessible = true
        return constructor.newInstance(directory, executable)
    }

    @JvmStatic
    fun finish(session: Any) {
        val worker = field(session, "worker").get(session) as Thread
        worker.start()
        worker.join(15_000)
        if (worker.isAlive()) {
            val process = field(session, "process").get(session) as Process?
            process?.destroyForcibly()
            worker.interrupt()
            throw AssertionError("encoder did not finish")
        }
    }

    @JvmStatic
    fun run(vararg arguments: String): ByteArray {
        val process =
            ProcessBuilder(*arguments).redirectError(ProcessBuilder.Redirect.INHERIT).start()
        val output = process.getInputStream().readAllBytes()
        require(
            process.waitFor(10, TimeUnit.SECONDS) && process.exitValue() == 0,
            "command failed: " + arguments.contentToString(),
        )
        return output
    }

    @JvmStatic
    fun color(channel: Int): ByteArray =
        ByteArray(64 * 48 * 4).also { bytes ->
            for (pixel in bytes.indices step 4) {
                bytes[pixel + channel] = 255.toByte()
                bytes[pixel + 3] = 255.toByte()
            }
        }

    @JvmStatic
    fun executable(name: String): String {
        for (directory in (System.getenv()["PATH"] ?: "").split(java.io.File.pathSeparator)) {
            val candidate = Path.of(directory).resolve(name).toAbsolutePath()
            if (Files.isRegularFile(candidate) && Files.isExecutable(candidate))
                return candidate.toString()
        }
        throw AssertionError("Cannot find $name on PATH; set PZ_TEST_FFMPEG")
    }

    @JvmStatic
    fun refused(output: Path, executable: String, reason: String) {
        require(
            !VideoRecording.start(output.toString(), executable),
            "unsafe start accepted: $output",
        )
        val status = VideoRecording.status()
        require(
            "failed" == status.rawget("state") &&
                status.rawget("error").toString().contains(reason),
            "wrong rejection: " + status.rawget("error"),
        )
        val current = VideoRecording::class.java.getDeclaredField("current")
        current.isAccessible = true
        val failed = current.get(null)
        require(
            field(failed, "file").get(failed) == null &&
                field(failed, "worker").get(failed) == null &&
                field(failed, "process").get(failed) == null,
            "rejected start created a capture or encoder",
        )
    }

    @JvmStatic
    fun pathGuards(directory: Path, executable: String) {
        val profile = Files.createDirectory(directory.resolve("profile"))
        val outside = Files.createDirectory(directory.resolve("outside"))
        ZomboidFileSystem.instance.setCacheDir(profile.toString())
        refused(outside.resolve("videos"), executable, "absolute subdirectory")
        refused(profile, executable, "absolute subdirectory")
        refused(
            Path.of("").toRealPath().relativize(profile.resolve("relative-videos")),
            executable,
            "absolute subdirectory",
        )
        refused(profile.resolve("../outside/videos"), executable, "absolute subdirectory")
        Files.createSymbolicLink(profile.resolve("escape"), outside)
        refused(profile.resolve("escape/videos"), executable, "through symlink")
        require(!Files.exists(outside.resolve("videos")), "rejection wrote outside the profile")
        Files.walk(directory).use { files ->
            require(files.noneMatch { Files.isRegularFile(it) }, "rejected starts created files")
        }
    }

    private fun luaBridge() {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        // Discover the owner before calling a VideoRecording method or reading its constants.
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            VideoChecks::class.java.classLoader,
        )
        val bridge =
            Exposer.getClassesWithGlobalLuaMethod().firstOrNull {
                it.name == "net.alexredby.pztoolkitjavapatches.VideoRecording"
            } ?: throw AssertionError("ZombieBuddy did not discover the video bridge")
        require(
            Path.of(bridge.protectionDomain.codeSource.location.toURI()) ==
                Path.of(System.getProperty("pz.test.patch.jar")),
            "video bridge did not come from the built JAR",
        )
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        LuaManager.exposer =
            LuaManager.Exposer(KahluaConverterManager(), LuaManager.platform, LuaManager.env)
        Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        val status = LuaManager.env.rawget("toolkitVideoStatus")
        val stop = LuaManager.env.rawget("toolkitVideoStop")
        val start = LuaManager.env.rawget("toolkitVideoStart")
        require(
            status != null && stop != null && start != null,
            "ZombieBuddy did not register the video Lua globals",
        )
        val result = thread.call(status, emptyArray<Any?>()) as se.krka.kahlua.vm.KahluaTable
        require(
            result.rawget("state") == "idle" && thread.call(stop, emptyArray<Any?>()) == false,
            "real Kahlua video bridge did not preserve idle status/stop",
        )
        require(
            thread.call(start, arrayOf<Any?>(null, null)) == false &&
                (thread.call(status, emptyArray<Any?>()) as se.krka.kahlua.vm.KahluaTable)
                    .rawget("error")
                    .toString()
                    .contains("NullPointerException"),
            "Kahlua nil directory must reach the guarded failure without creating an encoder",
        )
        for (name in arrayOf("start", "stop", "status", "presented")) {
            val method = bridge.declaredMethods.single { it.name == name }
            require(
                Modifier.isStatic(method.modifiers) && Modifier.isSynchronized(method.modifiers),
                "video entrypoint lost the class monitor: $name",
            )
        }
    }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun main(args: Array<String>) {
        luaBridge()
        require(
            VideoRecording.slot(-1) == 0L && VideoRecording.frameCount(-1) == 0L,
            "negative elapsed time",
        )
        require(
            VideoRecording.slot(33_333_333) == 0L && VideoRecording.slot(33_333_334) == 1L,
            "slot boundary",
        )
        require(
            VideoRecording.frameCount(0) == 0L && VideoRecording.frameCount(1) == 1L,
            "partial first frame",
        )
        require(
            VideoRecording.frameCount(33_333_333) == 1L &&
                VideoRecording.frameCount(33_333_334) == 2L,
            "frame ceiling",
        )
        require(
            VideoRecording.slot(1_000_000_000L) == 30L &&
                VideoRecording.frameCount(1_000_000_000L) == 30L,
            "whole second",
        )
        require(VideoRecording.slot(86_400_000_000_000L) == 2_592_000L, "long timeline overflow")
        val suffix = if (System.getProperty("os.name").startsWith("Windows")) ".exe" else ""
        val ffmpeg = System.getenv("PZ_TEST_FFMPEG") ?: executable("ffmpeg$suffix")
        val ffprobe = Path.of(ffmpeg).resolveSibling("ffprobe$suffix").toString()
        require(
            Files.isExecutable(Path.of(ffmpeg)) && Files.isExecutable(Path.of(ffprobe)),
            "set PZ_TEST_FFMPEG to an installed FFmpeg executable with sibling ffprobe",
        )
        val directory = Files.createTempDirectory("pz-video-checks-").toRealPath()
        try {
            pathGuards(directory, ffmpeg)
            val guarded = session(directory, ffmpeg)
            val capture =
                guarded.javaClass.getDeclaredMethod(
                    "capture",
                    Int::class.javaPrimitiveType,
                    Int::class.javaPrimitiveType,
                    Long::class.javaPrimitiveType,
                )
            capture.isAccessible = true
            val guardedStarted = field(guarded, "started").getLong(guarded)
            try {
                capture.invoke(guarded, 3840, 2161, guardedStarted)
                throw AssertionError("oversize framebuffer accepted")
            } catch (expected: InvocationTargetException) {
                require(
                    expected.cause is IllegalArgumentException,
                    "4K rejection must precede GL access",
                )
            }
            require(field(guarded, "pixels").get(guarded) == null, "4K rejection allocated pixels")
            field(guarded, "width").setInt(guarded, 64)
            field(guarded, "height").setInt(guarded, 48)
            field(guarded, "pixels").set(guarded, ByteBuffer.allocate(0))
            try {
                capture.invoke(guarded, 64, 48, guardedStarted + 1_000_000_000L)
                require(
                    field(guarded, "dropped").getLong(guarded) == 1L,
                    "exhausted free pool must drop without GL access",
                )
                require(
                    (field(guarded, "ready").get(guarded) as BlockingQueue<*>).isEmpty(),
                    "dropped frame was enqueued",
                )
                capture.invoke(guarded, 64, 48, guardedStarted + 1_000_000_000L)
                require(
                    field(guarded, "dropped").getLong(guarded) == 1L,
                    "same slot was captured twice",
                )
            } finally {
                field(guarded, "pixels").set(guarded, null)
            }
            capture.invoke(guarded, 65, 48, guardedStarted + 2_000_000_000L)
            require(
                field(guarded, "stopped").getLong(guarded) != 0L &&
                    field(guarded, "error").get(guarded) == "Framebuffer resized during recording",
                "resize must stop before GL access",
            )
            finish(guarded)

            val stopping = session(directory, ffmpeg)
            val current = VideoRecording::class.java.getDeclaredField("current")
            current.isAccessible = true
            val prior = current.get(null)
            try {
                current.set(null, stopping)
                require(VideoRecording.stop(), "first stop must be accepted asynchronously")
                val stopped = field(stopping, "stopped").getLong(stopping)
                require(
                    !VideoRecording.stop() &&
                        field(stopping, "stopped").getLong(stopping) == stopped,
                    "repeated stop must be idempotent",
                )
            } finally {
                current.set(null, prior)
            }
            finish(stopping)

            val session = session(directory, ffmpeg)
            field(session, "width").setInt(session, 64)
            field(session, "height").setInt(session, 48)
            val started = field(session, "started").getLong(session)
            field(session, "stopped").setLong(session, started + 1_000_000_000L)
            val frame =
                Class.forName(VideoRecording::class.java.name + "\$Frame")
                    .getDeclaredConstructor(ByteArray::class.java, Long::class.javaPrimitiveType)
            frame.isAccessible = true
            val ready = field(session, "ready").get(session) as BlockingQueue<Any>
            ready.add(frame.newInstance(color(0), 3L))
            ready.add(frame.newInstance(color(2), 9L))
            ready.add(frame.newInstance(color(1), 21L))
            finish(session)
            require(
                field(session, "state").get(session) == "completed",
                "successful encoding state",
            )
            require(
                field(session, "frames").getLong(session) == 30L,
                "stop time must preserve one second",
            )
            val file = field(session, "file").get(session) as Path
            val metadata =
                String(
                    run(
                        ffprobe,
                        "-v",
                        "error",
                        "-count_frames",
                        "-select_streams",
                        "v:0",
                        "-show_entries",
                        "stream=width,height,r_frame_rate,nb_read_frames,duration",
                        "-of",
                        "default=noprint_wrappers=1",
                        file.toString(),
                    ),
                )
            for (expected in
                arrayOf(
                    "width=64",
                    "height=48",
                    "r_frame_rate=30/1",
                    "nb_read_frames=30",
                    "duration=1.000000",
                )) require(metadata.contains(expected), "unexpected video metadata: $metadata")
            val rgb =
                run(
                    ffmpeg,
                    "-v",
                    "error",
                    "-i",
                    file.toString(),
                    "-vf",
                    "scale=1:1",
                    "-f",
                    "rawvideo",
                    "-pix_fmt",
                    "rgb24",
                    "pipe:1",
                )
            require(rgb.size == 30 * 3, "decoded frame count")
            for (index in 0 until 30) {
                val channel = if (index < 9) 0 else if (index < 21) 2 else 1
                for (c in 0 until 3) require(
                    Math.abs((rgb[index * 3 + c].toInt() and 255) - if (c == channel) 255 else 0) <
                        15,
                    "gap-fill color differs at frame $index",
                )
            }
            require(
                field(session, "pixels").get(session) == null && ready.isEmpty(),
                "successful session cleanup",
            )

            val empty = session(directory, ffmpeg)
            field(empty, "stopped").setLong(empty, System.nanoTime())
            finish(empty)
            require(
                field(empty, "state").get(empty) == "failed",
                "stop before first frame must fail",
            )
            require(
                field(empty, "error").get(empty).toString().contains("before any presented frame"),
                "empty session error",
            )

            val failed = session(directory, directory.resolve("missing-ffmpeg").toString())
            field(failed, "width").setInt(failed, 64)
            field(failed, "height").setInt(failed, 48)
            field(failed, "stopped").setLong(failed, System.nanoTime())
            (field(failed, "ready").get(failed) as BlockingQueue<Any>).add(
                frame.newInstance(color(0), 0L),
            )
            finish(failed)
            require(
                field(failed, "state").get(failed) == "failed" &&
                    field(failed, "error").get(failed).toString().isNotEmpty(),
                "encoder startup error must be observable",
            )
            require(
                (field(failed, "ready").get(failed) as BlockingQueue<*>).isEmpty(),
                "failed session cleanup",
            )
            println("VIDEO_CHECKS_PASS")
        } finally {
            Files.walk(directory).use { files ->
                for (file in files.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(
                    file,
                )
            }
        }
    }
}
