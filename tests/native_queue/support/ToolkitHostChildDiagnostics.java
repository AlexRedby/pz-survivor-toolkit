import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Test-only observation of the owner's exact native CoopMaster child. Never reads stdout. */
public final class ToolkitHostChildDiagnostics {
    public static final int STDERR_LIMIT = 256 * 1024;
    public static final int METADATA_LIMIT = 64 * 1024;
    private ToolkitHostChildDiagnostics() {}

    static List<String> validatedArgv(Process process, long expectedPid, Path cache) {
        if (process == null || !process.isAlive() || expectedPid <= 0 || process.pid() != expectedPid)
            throw new IllegalArgumentException("native child is not live or differs from the proved PID");
        var child = process.toHandle();
        long owner = ProcessHandle.current().pid();
        if (expectedPid == owner || !child.parent().map(parent -> parent.pid() == owner).orElse(false))
            throw new IllegalArgumentException("native child parent differs from this owner");
        var info = child.info();
        String executable = info.command().orElseThrow(() -> new IllegalArgumentException("native child executable unavailable"));
        var arguments = Arrays.asList(info.arguments().orElseThrow(() -> new IllegalArgumentException("native child argv unavailable")));
        int main = arguments.indexOf("zombie.network.GameServer");
        String expectedCache = "-cachedir=" + cache.toAbsolutePath().normalize();
        if (main < 0 || javaMainIndex(arguments) != main || arguments.lastIndexOf("zombie.network.GameServer") != main
                || main + 1 >= arguments.size() || !arguments.get(main + 1).equals("-coop")
                || arguments.stream().filter(arg -> arg.startsWith("-cachedir=")).count() != 1
                || !arguments.contains(expectedCache))
            throw new IllegalArgumentException("native child main, coop mode or cache differs");
        var result = new ArrayList<String>();
        result.add(executable);
        result.addAll(arguments);
        return result;
    }

    private static int javaMainIndex(List<String> arguments) {
        for (int index = 0; index < arguments.size(); index++) {
            String argument = arguments.get(index);
            if (argument.equals("-cp") || argument.equals("-classpath") || argument.equals("--class-path")) { index++; continue; }
            if (argument.equals("--")) return index + 1;
            if (!argument.startsWith("-")) return index;
        }
        return -1;
    }

    /** Unavailable diagnostics are reported, never substituted for native readiness. */
    public static Capture start(Process process, long expectedPid, Path cache) {
        return start(process, expectedPid, cache, null);
    }

    /** One reader keeps bounded evidence and forwards the complete stderr to its owner's log. */
    public static Capture start(Process process, long expectedPid, Path cache, PrintStream target) {
        OutputStream sink = null;
        try {
            var argv = validatedArgv(process, expectedPid, cache);
            Path root = cache.toAbsolutePath().normalize();
            if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS))
                throw new IOException("diagnostic cache is not a directory");
            Path stderr = root.resolve("host-child-stderr.log");
            Path metadata = root.resolve("host-child-diagnostics.json");
            if (Files.exists(stderr, LinkOption.NOFOLLOW_LINKS) || Files.exists(metadata, LinkOption.NOFOLLOW_LINKS))
                throw new IOException("diagnostic output already exists");
            sink = Files.newOutputStream(stderr, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS);
            var capture = new Capture(process, argv, metadata, sink, target);
            capture.persist(true);
            System.out.println("[QUEUE_TEST] HOST_CHILD_DIAGNOSTICS armed pid=" + expectedPid);
            capture.begin();
            return capture;
        } catch (Exception error) {
            if (sink != null) try { sink.close(); } catch (IOException ignored) {}
            System.err.println("[QUEUE_TEST] HOST_CHILD_DIAGNOSTICS unavailable: " + error.getClass().getSimpleName());
            return null;
        }
    }

    private static boolean secretFlag(String name) {
        String lower = name.toLowerCase(Locale.ROOT);
        return lower.startsWith("-") && (lower.contains("password") || lower.contains("token"));
    }

    static List<String> redact(List<String> argv) {
        var result = new ArrayList<String>();
        boolean nextSecret = false;
        for (String argument : argv) {
            if (nextSecret) {
                result.add("[REDACTED]"); nextSecret = false; continue;
            }
            int equal = argument.indexOf('=');
            String name = equal < 0 ? argument : argument.substring(0, equal);
            if (secretFlag(name)) {
                if (equal >= 0) result.add(name + "=[REDACTED]");
                else { result.add(argument); nextSecret = true; }
            } else result.add(argument);
        }
        return result;
    }

    private static String quote(String value) {
        if (value == null) return "null";
        var out = new StringBuilder("\"");
        for (int i = 0; i < value.length(); i++) {
            char character = value.charAt(i);
            if (character == '"' || character == '\\') out.append('\\').append(character);
            else if (character < 32) out.append(String.format("\\u%04x", (int)character));
            else out.append(character);
        }
        return out.append('"').toString();
    }

    public static final class Capture {
        private final Process process;
        private final Path metadata;
        private final OutputStream sink;
        private final PrintStream target;
        private final List<String> argv;
        private final boolean credentialsRedacted;
        private final CountDownLatch finished = new CountDownLatch(2);
        private boolean stderrCaptureStarted, stderrEof, processExited;
        private long stderrBytes, stderrCapturedBytes;
        private String stderrError, diagnosticsError;
        private Integer exitCode;

        private Capture(Process process, List<String> original, Path metadata, OutputStream sink, PrintStream target) {
            this.process = process; this.metadata = metadata; this.sink = sink; this.target = target;
            argv = redact(original); credentialsRedacted = !argv.equals(original);
        }

        private void begin() {
            process.onExit().whenComplete((child, error) -> {
                synchronized (this) {
                    try {
                        if (error != null) diagnosticsError = "exit observation: " + error.getClass().getSimpleName();
                        else { processExited = true; exitCode = child.exitValue(); }
                        persistSoft();
                    } finally { finished.countDown(); }
                }
            });
            var reader = new Thread(this::drainStderr, "toolkit-owned-host-stderr-" + process.pid());
            reader.setDaemon(true);
            reader.start();
        }

        private void drainStderr() {
            synchronized (this) { stderrCaptureStarted = true; persistSoft(); }
            long total = 0, captured = 0;
            String problem = null;
            boolean eof = false, writable = true, forwarding = target != null;
            // This stream has no native CoopMaster consumer. Stdout and stdin stay untouched.
            try (InputStream input = process.getErrorStream()) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = input.read(buffer)) != -1) {
                    total += read;
                    int retain = (int)Math.min(read, STDERR_LIMIT - captured);
                    if (writable && retain > 0) {
                        try { sink.write(buffer, 0, retain); captured += retain; }
                        catch (Exception error) { writable = false; problem = appendProblem(problem, "capture write: " + error.getClass().getSimpleName()); }
                    }
                    if (forwarding) {
                        try {
                            target.write(buffer, 0, read);
                            target.flush();
                            if (target.checkError()) throw new IOException("stderr destination failed");
                        } catch (Exception error) {
                            forwarding = false;
                            problem = appendProblem(problem, "stderr forward: " + error.getClass().getSimpleName());
                        }
                    }
                    // Keep draining after either destination fails or the evidence reaches its cap.
                }
                eof = true;
            } catch (Exception error) {
                problem = appendProblem(problem, "stderr read: " + error.getClass().getSimpleName());
            } finally {
                try { sink.close(); }
                catch (IOException error) { problem = appendProblem(problem, "capture close: " + error.getClass().getSimpleName()); }
                synchronized (this) {
                    stderrBytes = total; stderrCapturedBytes = captured; stderrEof = eof; stderrError = problem;
                    persistSoft(); finished.countDown();
                }
            }
        }

        private static String appendProblem(String previous, String problem) {
            return previous == null ? problem : previous + "; " + problem;
        }

        private synchronized String json(boolean includeArgv) {
            String arguments = includeArgv ? "[" + String.join(",", argv.stream().map(ToolkitHostChildDiagnostics::quote).toList()) + "]" : "null";
            return "{\"schema\":1,\"pid\":" + process.pid() + ",\"parent\":" + ProcessHandle.current().pid()
                + ",\"argv\":" + arguments + ",\"argvComplete\":" + includeArgv + ",\"credentialsRedacted\":" + credentialsRedacted
                + ",\"stderrCaptureStarted\":" + stderrCaptureStarted + ",\"stderrEof\":" + stderrEof
                + ",\"stderrBytes\":" + stderrBytes + ",\"stderrCapturedBytes\":" + stderrCapturedBytes
                + ",\"stderrTruncated\":" + (stderrBytes > stderrCapturedBytes) + ",\"stderrError\":" + quote(stderrError)
                + ",\"processExited\":" + processExited + ",\"exitCode\":" + exitCode
                + ",\"diagnosticsError\":" + quote(diagnosticsError)
                + ",\"stdoutUntouched\":true,\"stdinUntouched\":true,\"readinessEvidence\":false}\n";
        }

        private synchronized void persist(boolean initial) throws IOException {
            byte[] data = json(true).getBytes(StandardCharsets.UTF_8);
            if (data.length > METADATA_LIMIT) data = json(false).getBytes(StandardCharsets.UTF_8);
            if (initial) {
                Files.write(metadata, data, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS);
                return;
            }
            Path temporary = Files.createTempFile(metadata.getParent(), ".host-child-diagnostics-", ".tmp");
            try {
                Files.write(temporary, data, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING, LinkOption.NOFOLLOW_LINKS);
                try { Files.move(temporary, metadata, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }
                catch (java.nio.file.AtomicMoveNotSupportedException error) {
                    Files.move(temporary, metadata, StandardCopyOption.REPLACE_EXISTING);
                }
            } finally { Files.deleteIfExists(temporary); }
        }

        private void persistSoft() {
            try { persist(false); }
            catch (Exception error) {
                diagnosticsError = "metadata write: " + error.getClass().getSimpleName();
                System.err.println("[QUEUE_TEST] HOST_CHILD_DIAGNOSTICS metadata unavailable pid=" + process.pid());
            }
        }

        /** Bounded join for offline checks; launcher readiness never waits for diagnostics. */
        public boolean await(Duration timeout) throws InterruptedException {
            return finished.await(timeout.toMillis(), TimeUnit.MILLISECONDS);
        }

        /** Called only after native shutdown has already observed the child exit. */
        public void finish(Duration timeout) {
            String problem = null;
            if (process.isAlive()) problem = "finalization requested before child exit";
            else try {
                if (!await(timeout)) problem = "finalization incomplete";
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt(); problem = "finalization interrupted";
            }
            if (problem != null) synchronized (this) { diagnosticsError = problem; persistSoft(); }
        }
    }
}
