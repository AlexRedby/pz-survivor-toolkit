import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.concurrent.TimeUnit;

/** Standalone Host failure diagnostics; no GLFW initialization or game launch. */
public final class HostStderrChecks {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class FakeProcess extends Process {
        final InputStream error;
        final boolean alive;
        boolean stderrRead;

        FakeProcess(boolean alive, InputStream error) { this.alive = alive; this.error = error; }
        FakeProcess() { this(false, new ByteArrayInputStream(new byte[70000])); }
        @Override public OutputStream getOutputStream() { throw new AssertionError("stdin touched"); }
        @Override public InputStream getInputStream() { throw new AssertionError("protocol stdout touched"); }
        @Override public InputStream getErrorStream() { stderrRead = true; return error; }
        @Override public int waitFor() { throw new AssertionError("diagnostic waited on a process"); }
        @Override public int exitValue() {
            require(!alive, "exitValue read from a live process");
            return 7;
        }
        @Override public void destroy() { throw new AssertionError("process destroyed"); }
        @Override public boolean isAlive() { return alive; }
        @Override public long pid() { return 12345L; }
    }

    private static void rejected(FakeProcess process, long pid, Path cache) {
        try {
            ToolkitSmokeLauncher.captureExitedHostStderr(process, pid, cache);
            throw new AssertionError("Unproved or live process admitted");
        } catch (IllegalStateException expected) {
            require(!process.stderrRead, "Rejected process stderr was read");
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Pass the Java binary as the only argument");
        Path cache = Files.createTempDirectory("host-stderr-owned-");
        Process child = null;
        try {
            child = new ProcessBuilder(args[0], "-XX:DefinitelyNotARealJvmOption", "-version").start();
            require(child.waitFor(10, TimeUnit.SECONDS), "JVM child did not exit");
            require(child.exitValue() != 0, "Invalid JVM option succeeded");
            String diagnostic = ToolkitSmokeLauncher.captureExitedHostStderr(child, child.pid(), cache);
            require(diagnostic.contains("exit=" + child.exitValue()) && diagnostic.contains("coop-stderr.txt"),
                    "Real child diagnostic omitted exit code or evidence path");
            require(Files.readString(cache.resolve("coop-stderr.txt")).contains("DefinitelyNotARealJvmOption"),
                    "JVM stderr not captured");

            diagnostic = ToolkitSmokeLauncher.captureExitedHostStderr(new FakeProcess(), 12345, cache);
            require(diagnostic.contains("bytes=65536") && Files.size(cache.resolve("coop-stderr.txt")) == 65536,
                    "Capture exceeded or failed to reach its 64 KiB bound");
            rejected(new FakeProcess(), 12346, cache);
            rejected(new FakeProcess(true, InputStream.nullInputStream()), 12345, cache);

            child.getErrorStream().close();
            diagnostic = ToolkitSmokeLauncher.captureExitedHostStderr(child, child.pid(), cache);
            require(diagnostic.contains("exit=" + child.exitValue()), "Closed real stderr lost exit code");
            InputStream closed = new InputStream() {
                @Override public int available() throws IOException { throw new IOException("closed fixture stream"); }
                @Override public int read() { throw new AssertionError("Unavailable stderr was drained"); }
            };
            diagnostic = ToolkitSmokeLauncher.captureExitedHostStderr(new FakeProcess(false, closed), 12345, cache);
            require(diagnostic.contains("exit=7") && diagnostic.contains("stderr=unavailable(IOException)"),
                    "Closed stderr did not preserve a bounded diagnostic");

            Files.delete(cache.resolve("coop-stderr.txt"));
            Path sentinel = cache.resolve("sentinel.txt");
            Files.writeString(sentinel, "preserve");
            Files.createSymbolicLink(cache.resolve("coop-stderr.txt"), sentinel);
            diagnostic = ToolkitSmokeLauncher.captureExitedHostStderr(new FakeProcess(), 12345, cache);
            require(diagnostic.contains("stderr=unavailable") && Files.readString(sentinel).equals("preserve"),
                    "Stderr evidence followed a symbolic link");
        } finally {
            try {
                if (child != null) {
                    if (child.isAlive()) {
                        child.destroyForcibly();
                        require(child.waitFor(10, TimeUnit.SECONDS), "Owned diagnostic child did not stop");
                    }
                    child.getInputStream().close();
                    child.getErrorStream().close();
                    child.getOutputStream().close();
                }
            } finally {
                try (var files = Files.walk(cache)) {
                    for (Path file : files.sorted(Comparator.reverseOrder()).toList()) Files.delete(file);
                }
            }
        }
        System.out.println("HOST_STDERR_CAPTURE_CHECKS_PASS");
    }
}
