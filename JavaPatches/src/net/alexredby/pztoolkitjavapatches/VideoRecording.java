package net.alexredby.pztoolkitjavapatches;

import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL21;
import org.lwjgl.opengl.GL30;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.system.MemoryUtil;
import org.lwjglx.opengl.Display;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;

/** Explicit, silent test capture. No encoder work runs on the render thread. */
public final class VideoRecording {
    public static final int FPS = 30;
    private static Session current;

    static {
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            Session session;
            synchronized (VideoRecording.class) {
                session = current;
                if (session == null || !session.active()) return;
                session.stop(null);
            }
            try { session.worker.join(4_000); }
            catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
            Process p = session.process;
            if (p != null && p.isAlive()) p.destroyForcibly();
        }, "toolkit-video-shutdown"));
    }

    @LuaMethod(name="toolkitVideoStart", global=true)
    public static synchronized boolean start(String directory, String ffmpeg) {
        if (current != null && current.active()) return false;
        try {
            if (!Main.VIDEO_SUPPORTED) throw new IllegalStateException("Unsupported B42.21 display bytecode");
            Path root = Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath();
            Path output = Path.of(directory);
            if (!output.isAbsolute() || !output.normalize().startsWith(root) || output.normalize().equals(root))
                throw new IllegalArgumentException("Output must be an absolute subdirectory of this profile: " + root);
            // Resolve existing parents before creating anything, including symlink escapes.
            Path parent = output.normalize();
            while (!Files.exists(parent)) parent = parent.getParent();
            if (!parent.toRealPath().startsWith(root)) throw new IllegalArgumentException("Output escapes profile through symlink");
            Files.createDirectories(output);
            output = output.toRealPath();
            if (!output.startsWith(root)) throw new IllegalArgumentException("Output escapes profile");
            if (ffmpeg == null || !Path.of(ffmpeg).isAbsolute() || !Files.isExecutable(Path.of(ffmpeg)))
                throw new IllegalArgumentException("Pass the absolute executable path to FFmpeg");
            current = new Session(output, ffmpeg);
            current.worker.start();
            return true;
        } catch (Exception error) {
            current = new Session(error.toString());
            System.err.println("[ToolkitVideo] " + current.error);
            return false;
        }
    }

    @LuaMethod(name="toolkitVideoStop", global=true)
    public static synchronized boolean stop() {
        if (current == null || !current.active() || current.stopped != 0) return false;
        current.stop(null);
        return true;
    }

    @LuaMethod(name="toolkitVideoStatus", global=true)
    public static synchronized KahluaTable status() {
        KahluaTable result = LuaManager.platform.newTable();
        Session s = current;
        result.rawset("state", s == null ? "idle" : s.state);
        result.rawset("fps", (double)FPS);
        if (s != null) {
            result.rawset("file", s.file == null ? "" : s.file.toString());
            result.rawset("log", s.log == null ? "" : s.log.toString());
            result.rawset("error", s.error);
            result.rawset("width", (double)s.width);
            result.rawset("height", (double)s.height);
            result.rawset("frames", (double)s.frames);
            result.rawset("captured", (double)s.captured);
            result.rawset("dropped", (double)s.dropped);
            result.rawset("seconds", s.frames / (double)FPS);
        }
        return result;
    }

    public static synchronized void presented() {
        Session s = current;
        if (s == null || !s.active() || s.stopped != 0) return;
        try {
            int[] width = new int[1], height = new int[1];
            GLFW.glfwGetFramebufferSize(Display.getWindow(), width, height);
            s.capture(width[0], height[0], System.nanoTime());
        } catch (Throwable error) {
            s.stop("Capture failed: " + error);
        }
    }

    static long slot(long elapsed) { return Math.max(0, elapsed) / 1_000_000_000L * FPS
        + Math.max(0, elapsed) % 1_000_000_000L * FPS / 1_000_000_000L; }
    static long frameCount(long elapsed) { return slot(elapsed) + (Math.max(0, elapsed) % 1_000_000_000L * FPS % 1_000_000_000L == 0 ? 0 : 1); }

    private record Frame(byte[] bytes, long slot) {}

    private static final class Session {
        final Path file, log;
        final String executable;
        final ArrayBlockingQueue<byte[]> free = new ArrayBlockingQueue<>(3);
        final ArrayBlockingQueue<Frame> ready = new ArrayBlockingQueue<>(3);
        final Thread worker;
        final long started = System.nanoTime();
        volatile long stopped, frames, captured, dropped;
        volatile int width, height;
        volatile String state = "starting", error = "";
        volatile Process process;
        ByteBuffer pixels;
        long lastSlot = -1;

        Session(Path directory, String executable) throws Exception {
            file = Files.createTempFile(directory, "capture-", ".mp4");
            log = Path.of(file + ".ffmpeg.log");
            this.executable = executable;
            worker = new Thread(this::encode, "toolkit-video-encoder");
            worker.setDaemon(true);
        }
        Session(String error) { this.error = error; state = "failed"; file = log = null; executable = ""; worker = null; }
        boolean active() { return state.equals("starting") || state.equals("recording") || state.equals("stopping"); }

        void stop(String reason) {
            if (reason != null) error = reason;
            if (stopped != 0) return;
            stopped = System.nanoTime();
            state = "stopping";
            Thread watchdog = new Thread(() -> {
                try {
                    worker.join(15_000);
                    if (worker.isAlive()) {
                        error = "FFmpeg did not finish within 15 seconds of stop; see " + log;
                        Process p = process;
                        if (p != null) p.destroyForcibly();
                        worker.interrupt();
                    }
                } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
            }, "toolkit-video-stop");
            watchdog.setDaemon(true);
            watchdog.start();
        }

        void capture(int w, int h, long now) {
            if (w <= 0 || h <= 0) return;
            if (width != 0 && (w != width || h != height)) { stop("Framebuffer resized during recording"); return; }
            long index = slot(now - started);
            if (index <= lastSlot) return;
            lastSlot = index;
            if (pixels == null) {
                // shortcut: bounded to 4K (four RGBA buffers), revisit for larger test windows.
                if ((long)w * h > 3840L * 2160 || w > 4096 || h > 4096)
                    throw new IllegalArgumentException("Framebuffer exceeds 4K capture limit: " + w + "x" + h);
                width = w; height = h;
                int bytes = Math.multiplyExact(Math.multiplyExact(w, h), 4);
                pixels = MemoryUtil.memAlloc(bytes);
                for (int i = 0; i < 3; i++) free.add(new byte[bytes]);
            }
            byte[] data = free.poll();
            if (data == null) { dropped++; return; }
            int framebuffer = GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING);
            int packBuffer = GL11.glGetInteger(GL21.GL_PIXEL_PACK_BUFFER_BINDING);
            int alignment = GL11.glGetInteger(GL11.GL_PACK_ALIGNMENT);
            int rowLength = GL11.glGetInteger(GL11.GL_PACK_ROW_LENGTH);
            int skipRows = GL11.glGetInteger(GL11.GL_PACK_SKIP_ROWS);
            int skipPixels = GL11.glGetInteger(GL11.GL_PACK_SKIP_PIXELS);
            GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, 0);
            int readBuffer = GL11.glGetInteger(GL11.GL_READ_BUFFER);
            try {
                GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, 0);
                GL11.glReadBuffer(GL11.GL_FRONT);
                GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, 1);
                GL11.glPixelStorei(GL11.GL_PACK_ROW_LENGTH, 0);
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_ROWS, 0);
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_PIXELS, 0);
                pixels.clear();
                GL11.glReadPixels(0, 0, w, h, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, pixels);
                pixels.get(data);
            } finally {
                GL11.glReadBuffer(readBuffer);
                GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, framebuffer);
                GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, packBuffer);
                GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, alignment);
                GL11.glPixelStorei(GL11.GL_PACK_ROW_LENGTH, rowLength);
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_ROWS, skipRows);
                GL11.glPixelStorei(GL11.GL_PACK_SKIP_PIXELS, skipPixels);
            }
            ready.add(new Frame(data, index));
            captured++;
        }

        void write(OutputStream pipe, byte[] bytes) throws Exception {
            pipe.write(bytes);
            frames++;
        }

        void encode() {
            try {
                Frame previous = null;
                OutputStream pipe = null;
                try {
                    while (stopped == 0 || !ready.isEmpty()) {
                        Frame next = ready.poll(100, TimeUnit.MILLISECONDS);
                        if (next == null) continue;
                        if (pipe == null) {
                            process = new ProcessBuilder(executable, "-hide_banner", "-loglevel", "warning", "-y",
                                "-f", "rawvideo", "-pixel_format", "rgba", "-video_size", width + "x" + height,
                                "-framerate", "30", "-i", "pipe:0", "-an", "-vf", "vflip,pad=ceil(iw/2)*2:ceil(ih/2)*2",
                                "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
                                "-movflags", "+faststart", file.toString())
                                .redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(log.toFile()).start();
                            pipe = process.getOutputStream();
                            synchronized (VideoRecording.class) {
                                if (stopped == 0) state = "recording";
                            }
                        }
                        while (frames < next.slot) write(pipe, previous == null ? next.bytes : previous.bytes);
                        if (previous != null) free.add(previous.bytes);
                        previous = next;
                        write(pipe, next.bytes);
                    }
                    if (previous == null) throw new IllegalStateException("Stopped before any presented frame");
                    while (frames < frameCount(stopped - started)) write(pipe, previous.bytes);
                } finally { if (pipe != null) pipe.close(); }
                if (!process.waitFor(10, TimeUnit.SECONDS)) throw new IllegalStateException("FFmpeg exit timeout");
                if (process.exitValue() != 0) throw new IllegalStateException("FFmpeg exit " + process.exitValue() + "; see " + log);
            } catch (Exception failure) {
                error = (error.isEmpty() ? "" : error + "; ") + failure;
            } finally {
                Process p = process;
                if (p != null && p.isAlive()) p.destroyForcibly();
                synchronized (VideoRecording.class) {
                    if (pixels != null) MemoryUtil.memFree(pixels);
                    pixels = null; free.clear(); ready.clear();
                    state = error.isEmpty() ? "completed" : "failed";
                }
                System.out.println("[ToolkitVideo] " + state + " file=" + file + " frames=" + frames + " error=" + error);
            }
        }
    }
}
