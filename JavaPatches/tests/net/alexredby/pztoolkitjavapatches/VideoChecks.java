package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

/** Headless timeline and real encoder checks; no GL context or game profile. */
public final class VideoChecks {
    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    static Field field(Object owner, String name) throws Exception {
        Field result = owner.getClass().getDeclaredField(name);
        result.setAccessible(true);
        return result;
    }

    static Object session(Path directory, String executable) throws Exception {
        Constructor<?> constructor = Class.forName(VideoRecording.class.getName() + "$Session")
            .getDeclaredConstructor(Path.class, String.class);
        constructor.setAccessible(true);
        return constructor.newInstance(directory, executable);
    }

    static void finish(Object session) throws Exception {
        Thread worker = (Thread)field(session, "worker").get(session);
        worker.start();
        worker.join(15_000);
        if (worker.isAlive()) {
            Process process = (Process)field(session, "process").get(session);
            if (process != null) process.destroyForcibly();
            worker.interrupt();
            throw new AssertionError("encoder did not finish");
        }
    }

    static byte[] run(String... arguments) throws Exception {
        Process process = new ProcessBuilder(arguments).redirectError(ProcessBuilder.Redirect.INHERIT).start();
        byte[] output = process.getInputStream().readAllBytes();
        require(process.waitFor(10, TimeUnit.SECONDS) && process.exitValue() == 0,
            "command failed: " + Arrays.toString(arguments));
        return output;
    }

    static byte[] color(int channel) {
        byte[] bytes = new byte[64 * 48 * 4];
        for (int pixel = 0; pixel < bytes.length; pixel += 4) {
            bytes[pixel + channel] = (byte)255;
            bytes[pixel + 3] = (byte)255;
        }
        return bytes;
    }

    static String executable(String name) {
        for (String directory : System.getenv().getOrDefault("PATH", "").split(java.io.File.pathSeparator)) {
            Path candidate = Path.of(directory).resolve(name).toAbsolutePath();
            if (Files.isRegularFile(candidate) && Files.isExecutable(candidate)) return candidate.toString();
        }
        throw new AssertionError("Cannot find " + name + " on PATH; set PZ_TEST_FFMPEG");
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        require(VideoRecording.slot(-1) == 0 && VideoRecording.frameCount(-1) == 0, "negative elapsed time");
        require(VideoRecording.slot(33_333_333) == 0 && VideoRecording.slot(33_333_334) == 1, "slot boundary");
        require(VideoRecording.frameCount(0) == 0 && VideoRecording.frameCount(1) == 1, "partial first frame");
        require(VideoRecording.frameCount(33_333_333) == 1 && VideoRecording.frameCount(33_333_334) == 2, "frame ceiling");
        require(VideoRecording.slot(1_000_000_000L) == 30 && VideoRecording.frameCount(1_000_000_000L) == 30, "whole second");
        require(VideoRecording.slot(86_400_000_000_000L) == 2_592_000, "long timeline overflow");

        String ffmpeg = System.getenv("PZ_TEST_FFMPEG");
        String suffix = System.getProperty("os.name").startsWith("Windows") ? ".exe" : "";
        if (ffmpeg == null) ffmpeg = executable("ffmpeg" + suffix);
        String ffprobe = Path.of(ffmpeg).resolveSibling("ffprobe" + suffix).toString();
        require(Files.isExecutable(Path.of(ffmpeg)) && Files.isExecutable(Path.of(ffprobe)),
            "set PZ_TEST_FFMPEG to an installed FFmpeg executable with sibling ffprobe");
        Path directory = Files.createTempDirectory("pz-video-checks-");
        try {
            Object guarded = session(directory, ffmpeg);
            var capture = guarded.getClass().getDeclaredMethod("capture", int.class, int.class, long.class);
            capture.setAccessible(true);
            long guardedStarted = field(guarded, "started").getLong(guarded);
            try {
                capture.invoke(guarded, 3840, 2161, guardedStarted);
                throw new AssertionError("oversize framebuffer accepted");
            } catch (InvocationTargetException expected) {
                require(expected.getCause() instanceof IllegalArgumentException, "4K rejection must precede GL access");
            }
            require(field(guarded, "pixels").get(guarded) == null, "4K rejection allocated pixels");
            field(guarded, "width").setInt(guarded, 64);
            field(guarded, "height").setInt(guarded, 48);
            field(guarded, "pixels").set(guarded, ByteBuffer.allocate(0));
            try {
                capture.invoke(guarded, 64, 48, guardedStarted + 1_000_000_000L);
                require(field(guarded, "dropped").getLong(guarded) == 1, "exhausted free pool must drop without GL access");
                require(((BlockingQueue<?>)field(guarded, "ready").get(guarded)).isEmpty(), "dropped frame was enqueued");
                capture.invoke(guarded, 64, 48, guardedStarted + 1_000_000_000L);
                require(field(guarded, "dropped").getLong(guarded) == 1, "same slot was captured twice");
            } finally { field(guarded, "pixels").set(guarded, null); }
            capture.invoke(guarded, 65, 48, guardedStarted + 2_000_000_000L);
            require(field(guarded, "stopped").getLong(guarded) != 0 &&
                field(guarded, "error").get(guarded).equals("Framebuffer resized during recording"), "resize must stop before GL access");
            finish(guarded);

            Object stopping = session(directory, ffmpeg);
            Field current = VideoRecording.class.getDeclaredField("current");
            current.setAccessible(true);
            Object prior = current.get(null);
            try {
                current.set(null, stopping);
                require(VideoRecording.stop(), "first stop must be accepted asynchronously");
                long stopped = field(stopping, "stopped").getLong(stopping);
                require(!VideoRecording.stop() && field(stopping, "stopped").getLong(stopping) == stopped, "repeated stop must be idempotent");
            } finally { current.set(null, prior); }
            finish(stopping);

            Object session = session(directory, ffmpeg);
            field(session, "width").setInt(session, 64);
            field(session, "height").setInt(session, 48);
            long started = field(session, "started").getLong(session);
            field(session, "stopped").setLong(session, started + 1_000_000_000L);
            Constructor<?> frame = Class.forName(VideoRecording.class.getName() + "$Frame")
                .getDeclaredConstructor(byte[].class, long.class);
            frame.setAccessible(true);
            BlockingQueue<Object> ready = (BlockingQueue<Object>)field(session, "ready").get(session);
            ready.add(frame.newInstance(color(0), 3L));
            ready.add(frame.newInstance(color(2), 9L));
            ready.add(frame.newInstance(color(1), 21L));
            finish(session);
            require(field(session, "state").get(session).equals("completed"), "successful encoding state");
            require(field(session, "frames").getLong(session) == 30, "stop time must preserve one second");
            Path file = (Path)field(session, "file").get(session);
            String metadata = new String(run(ffprobe, "-v", "error", "-count_frames", "-select_streams", "v:0",
                "-show_entries", "stream=width,height,r_frame_rate,nb_read_frames,duration", "-of", "default=noprint_wrappers=1", file.toString()));
            for (String expected : new String[]{"width=64", "height=48", "r_frame_rate=30/1", "nb_read_frames=30", "duration=1.000000"})
                require(metadata.contains(expected), "unexpected video metadata: " + metadata);
            byte[] rgb = run(ffmpeg, "-v", "error", "-i", file.toString(), "-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1");
            require(rgb.length == 30 * 3, "decoded frame count");
            for (int index = 0; index < 30; index++) {
                int channel = index < 9 ? 0 : index < 21 ? 2 : 1;
                for (int c = 0; c < 3; c++) require(Math.abs((rgb[index * 3 + c] & 255) - (c == channel ? 255 : 0)) < 15,
                    "gap-fill color differs at frame " + index);
            }
            require(field(session, "pixels").get(session) == null && ready.isEmpty(), "successful session cleanup");

            Object empty = session(directory, ffmpeg);
            field(empty, "stopped").setLong(empty, System.nanoTime());
            finish(empty);
            require(field(empty, "state").get(empty).equals("failed"), "stop before first frame must fail");
            require(field(empty, "error").get(empty).toString().contains("before any presented frame"), "empty session error");

            Object failed = session(directory, directory.resolve("missing-ffmpeg").toString());
            field(failed, "width").setInt(failed, 64);
            field(failed, "height").setInt(failed, 48);
            field(failed, "stopped").setLong(failed, System.nanoTime());
            ((BlockingQueue<Object>)field(failed, "ready").get(failed)).add(frame.newInstance(color(0), 0L));
            finish(failed);
            require(field(failed, "state").get(failed).equals("failed") && !field(failed, "error").get(failed).toString().isEmpty(),
                "encoder startup error must be observable");
            require(((BlockingQueue<?>)field(failed, "ready").get(failed)).isEmpty(), "failed session cleanup");
            System.out.println("VIDEO_CHECKS_PASS");
        } finally {
            try (var files = Files.list(directory)) {
                for (Path file : files.toList()) Files.deleteIfExists(file);
            }
            Files.delete(directory);
        }
    }
}
