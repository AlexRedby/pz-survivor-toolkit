package net.alexredby.pztoolkitjavapatches

import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import org.lwjgl.opengl.GL11
import org.lwjgl.opengl.GL15
import org.lwjgl.opengl.GL21
import org.lwjgl.opengl.GL30
import org.lwjgl.glfw.GLFW
import org.lwjgl.system.MemoryUtil
import org.lwjglx.opengl.Display
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.ZomboidFileSystem

/** Explicit, silent test capture. No encoder work runs on the render thread. */
object VideoRecording {
    const val FPS = 30
    private var current: Session? = null

    init {
        Runtime.getRuntime().addShutdownHook(Thread({
            val session = synchronized(VideoRecording::class.java) {
                val session = current
                if (session == null || !session.active()) return@Thread
                session.stop(null)
                session
            }
            try { session.worker!!.join(4_000) }
            catch (_: InterruptedException) { Thread.currentThread().interrupt() }
            val process = session.process
            if (process != null && process.isAlive()) process.destroyForcibly()
        }, "toolkit-video-shutdown"))
    }

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitVideoStart", global = true)
    fun start(directory: String?, ffmpeg: String?): Boolean {
        if (current?.active() == true) return false
        try {
            if (!Main.VIDEO_SUPPORTED) throw IllegalStateException("Unsupported B42.21 display bytecode")
            val root = Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath()
            var output = Path.of(directory)
            if (!output.isAbsolute() || !output.normalize().startsWith(root) || output.normalize().equals(root))
                throw IllegalArgumentException("Output must be an absolute subdirectory of this profile: $root")
            // Resolve existing parents before creating anything, including symlink escapes.
            var parent = output.normalize()
            while (!Files.exists(parent)) parent = parent.getParent()
            if (!parent.toRealPath().startsWith(root)) throw IllegalArgumentException("Output escapes profile through symlink")
            Files.createDirectories(output)
            output = output.toRealPath()
            if (!output.startsWith(root)) throw IllegalArgumentException("Output escapes profile")
            if (ffmpeg == null || !Path.of(ffmpeg).isAbsolute() || !Files.isExecutable(Path.of(ffmpeg)))
                throw IllegalArgumentException("Pass the absolute executable path to FFmpeg")
            val session = Session(output, ffmpeg)
            current = session
            session.worker!!.start()
            return true
        } catch (error: Exception) {
            val failed = Session(error.toString())
            current = failed
            System.err.println("[ToolkitVideo] " + failed.error)
            return false
        }
    }

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitVideoStop", global = true)
    fun stop(): Boolean {
        val session = current
        if (session == null || !session.active() || session.stopped != 0L) return false
        session.stop(null)
        return true
    }

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitVideoStatus", global = true)
    fun status(): KahluaTable {
        val result = LuaManager.platform.newTable()
        val session = current
        result.rawset("state", session?.state ?: "idle")
        result.rawset("fps", FPS.toDouble())
        if (session != null) {
            result.rawset("file", session.file?.toString() ?: "")
            result.rawset("log", session.log?.toString() ?: "")
            result.rawset("error", session.error)
            result.rawset("width", session.width.toDouble())
            result.rawset("height", session.height.toDouble())
            result.rawset("frames", session.frames.toDouble())
            result.rawset("captured", session.captured.toDouble())
            result.rawset("dropped", session.dropped.toDouble())
            result.rawset("seconds", session.frames / FPS.toDouble())
        }
        return result
    }

    @JvmStatic
    @Synchronized
    fun presented() {
        val session = current
        if (session == null || !session.active() || session.stopped != 0L) return
        try {
            val width = IntArray(1); val height = IntArray(1)
            GLFW.glfwGetFramebufferSize(Display.getWindow(), width, height)
            session.capture(width[0], height[0], System.nanoTime())
        } catch (error: Throwable) {
            session.stop("Capture failed: $error")
        }
    }

    @JvmStatic
    @JvmName("slot")
    internal fun slot(elapsed: Long): Long = Math.max(0L, elapsed) / 1_000_000_000L * FPS +
        Math.max(0L, elapsed) % 1_000_000_000L * FPS / 1_000_000_000L
    @JvmStatic
    @JvmName("frameCount")
    internal fun frameCount(elapsed: Long): Long = slot(elapsed) +
        if (Math.max(0L, elapsed) % 1_000_000_000L * FPS % 1_000_000_000L == 0L) 0 else 1

    @JvmRecord
    private data class Frame(val bytes: ByteArray?, val slot: Long) {
        override fun equals(other: Any?): Boolean = other is Frame && bytes === other.bytes && slot == other.slot
        override fun hashCode(): Int = 31 * System.identityHashCode(bytes) + java.lang.Long.hashCode(slot)
        override fun toString(): String = "Frame[bytes=$bytes, slot=$slot]"
    }

    private class Session {
        val file: Path?
        val log: Path?
        val executable: String?
        val free = ArrayBlockingQueue<ByteArray>(3)
        val ready = ArrayBlockingQueue<Frame>(3)
        val worker: Thread?
        val started = System.nanoTime()
        @Volatile var stopped = 0L
        @Volatile var frames = 0L
        @Volatile var captured = 0L
        @Volatile var dropped = 0L
        @Volatile var width = 0
        @Volatile var height = 0
        @Volatile var state = "starting"
        @Volatile var error = ""
        @Volatile var process: Process? = null
        var pixels: ByteBuffer? = null
        var lastSlot = -1L

        constructor(directory: Path?, executable: String?) {
            file = Files.createTempFile(directory, "capture-", ".mp4")
            log = Path.of("$file.ffmpeg.log")
            this.executable = executable
            worker = Thread(::encode, "toolkit-video-encoder").apply { isDaemon = true }
        }
        constructor(error: String) {
            this.error = error; state = "failed"; file = null; log = null; executable = ""; worker = null
        }
        fun active(): Boolean = state.equals("starting") || state.equals("recording") || state.equals("stopping")

        fun stop(reason: String?) {
            if (reason != null) error = reason
            if (stopped != 0L) return
            stopped = System.nanoTime()
            state = "stopping"
            val watchdog = Thread({
                try {
                    worker!!.join(15_000)
                    if (worker.isAlive()) {
                        error = "FFmpeg did not finish within 15 seconds of stop; see $log"
                        process?.destroyForcibly()
                        worker.interrupt()
                    }
                } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
            }, "toolkit-video-stop")
            watchdog.isDaemon = true
            watchdog.start()
        }

        fun capture(w: Int, h: Int, now: Long) {
            if (w <= 0 || h <= 0) return
            if (width != 0 && (w != width || h != height)) { stop("Framebuffer resized during recording"); return }
            val index = slot(now - started)
            if (index <= lastSlot) return
            lastSlot = index
            if (pixels == null) {
                // shortcut: bounded to 4K (four RGBA buffers), revisit for larger test windows.
                if (w.toLong() * h > 3840L * 2160 || w > 4096 || h > 4096)
                    throw IllegalArgumentException("Framebuffer exceeds 4K capture limit: ${w}x$h")
                width = w; height = h
                val bytes = Math.multiplyExact(Math.multiplyExact(w, h), 4)
                pixels = MemoryUtil.memAlloc(bytes)
                repeat(3) { free.add(ByteArray(bytes)) }
            }
            val data = free.poll()
            if (data == null) { dropped++; return }
            val framebuffer = GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING)
            val packBuffer = GL11.glGetInteger(GL21.GL_PIXEL_PACK_BUFFER_BINDING)
            val alignment = GL11.glGetInteger(GL11.GL_PACK_ALIGNMENT)
            val rowLength = GL11.glGetInteger(GL11.GL_PACK_ROW_LENGTH)
            val skipRows = GL11.glGetInteger(GL11.GL_PACK_SKIP_ROWS)
            val skipPixels = GL11.glGetInteger(GL11.GL_PACK_SKIP_PIXELS)
            GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, 0)
            val readBuffer = GL11.glGetInteger(GL11.GL_READ_BUFFER)
            try {
                GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, 0)
                GL11.glReadBuffer(GL11.GL_FRONT)
                GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, 1)
                GL11.glPixelStorei(GL11.GL_PACK_ROW_LENGTH, 0)
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_ROWS, 0)
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_PIXELS, 0)
                pixels!!.clear()
                GL11.glReadPixels(0, 0, w, h, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, pixels!!)
                pixels!!.get(data)
            } finally {
                GL11.glReadBuffer(readBuffer)
                GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, framebuffer)
                GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, packBuffer)
                GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, alignment)
                GL11.glPixelStorei(GL11.GL_PACK_ROW_LENGTH, rowLength)
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_ROWS, skipRows)
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_PIXELS, skipPixels)
            }
            ready.add(Frame(data, index))
            captured++
        }

        fun write(pipe: OutputStream?, bytes: ByteArray?) {
            (pipe ?: throw NullPointerException()).write(bytes)
            frames++
        }

        fun encode() {
            try {
                var previous: Frame? = null
                var pipe: OutputStream? = null
                try {
                    while (stopped == 0L || !ready.isEmpty()) {
                        val next = ready.poll(100, TimeUnit.MILLISECONDS) ?: continue
                        if (pipe == null) {
                            process = ProcessBuilder(executable, "-hide_banner", "-loglevel", "warning", "-y",
                                "-f", "rawvideo", "-pixel_format", "rgba", "-video_size", "${width}x$height",
                                "-framerate", "30", "-i", "pipe:0", "-an", "-vf", "vflip,pad=ceil(iw/2)*2:ceil(ih/2)*2",
                                "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
                                "-movflags", "+faststart", (file ?: throw NullPointerException()).toString())
                                .redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(log!!.toFile()).start()
                            pipe = process!!.getOutputStream()
                            synchronized(VideoRecording::class.java) {
                                if (stopped == 0L) state = "recording"
                            }
                        }
                        while (frames < next.slot) write(pipe, if (previous == null) next.bytes else previous.bytes)
                        if (previous != null) free.add(previous.bytes)
                        previous = next
                        write(pipe, next.bytes)
                    }
                    if (previous == null) throw IllegalStateException("Stopped before any presented frame")
                    while (frames < frameCount(stopped - started)) write(pipe, previous.bytes)
                } finally { pipe?.close() }
                if (!process!!.waitFor(10, TimeUnit.SECONDS)) throw IllegalStateException("FFmpeg exit timeout")
                if (process!!.exitValue() != 0) throw IllegalStateException("FFmpeg exit " + process!!.exitValue() + "; see " + log)
            } catch (failure: Exception) {
                error = (if (error.isEmpty()) "" else "$error; ") + failure
            } finally {
                val encoder = process
                if (encoder != null && encoder.isAlive()) encoder.destroyForcibly()
                synchronized(VideoRecording::class.java) {
                    if (pixels != null) MemoryUtil.memFree(pixels)
                    pixels = null; free.clear(); ready.clear()
                    state = if (error.isEmpty()) "completed" else "failed"
                }
                println("[ToolkitVideo] $state file=$file frames=$frames error=$error")
            }
        }
    }
}
