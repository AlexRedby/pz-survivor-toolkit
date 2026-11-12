import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStreamReader;
import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

/** Offline child-process checks only. The classpath contains a stub GameServer, no game JAR. */
public final class ToolkitHostChildDiagnosticsChecks {
    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }

    private static final class OwnerLog extends ByteArrayOutputStream {
        boolean closed;
        @Override public void close() { closed = true; }
    }

    private static void completeChild(Process child) throws Exception {
        input(child, "go"); input(child, "owner-input");
        var stdout = new BufferedReader(new InputStreamReader(child.getInputStream(), StandardCharsets.UTF_8));
        require("READY".equals(line(stdout)) && "ECHO owner-input".equals(line(stdout)), "drain blocked child or changed owner streams");
        require(child.waitFor(8, TimeUnit.SECONDS), "child did not exit after stderr drain");
        require(line(stdout) == null, "unexpected stdout data");
    }

    private static void forwarded(OwnerLog log, PrintStream target) {
        byte[] bytes = log.toByteArray();
        require(bytes.length == 3 * ToolkitHostChildDiagnostics.STDERR_LIMIT, "owner log lost stderr beyond diagnostic cap");
        for (byte value : bytes) require(value == 'E', "owner stderr bytes changed");
        require(!log.closed, "drain closed its owner's log");
        target.write('!'); target.flush();
        require(log.size() == bytes.length + 1 && !target.checkError(), "owner log no longer writable");
    }

    private static Process launch(Path cache, String main, String... extra) throws Exception {
        var command = new ArrayList<>(List.of(Path.of(System.getProperty("java.home"), "bin", "java").toString(),
            "-cp", System.getProperty("java.class.path"), main, "-coop", "-cachedir=" + cache));
        command.addAll(List.of(extra));
        var builder = new ProcessBuilder(command);
        for (String key : List.of("JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS")) builder.environment().remove(key);
        return builder.start();
    }

    private static void stop(Process child) throws Exception {
        if (child.isAlive()) { child.destroy(); if (!child.waitFor(2, TimeUnit.SECONDS)) child.destroyForcibly(); }
    }

    private static void input(Process child, String text) throws Exception {
        child.getOutputStream().write((text + "\n").getBytes(StandardCharsets.UTF_8)); child.getOutputStream().flush();
    }

    private static String line(BufferedReader reader) throws Exception {
        return CompletableFuture.supplyAsync(() -> {
            try { return reader.readLine(); } catch (Exception error) { throw new RuntimeException(error); }
        }).get(8, TimeUnit.SECONDS);
    }

    public static final class OtherMain {
        public static void main(String[] args) throws Exception { Thread.sleep(60000); }
    }

    private static void ownershipChecks(Path root) throws Exception {
        Path cache = Files.createDirectory(root.resolve("wrong-main"));
        // A foreign main with a convincing GameServer-looking application argument must fail.
        var child = launch(cache, OtherMain.class.getName(), "zombie.network.GameServer", "-coop");
        try {
            require(ToolkitHostChildDiagnostics.start(child, child.pid(), cache) == null, "foreign Java main accepted");
            require(!Files.exists(cache.resolve("host-child-stderr.log")), "foreign child stream consumed");
        } finally { stop(child); }
    }

    private static void drainChecks(Path root) throws Exception {
        Path cache = Files.createDirectory(root.resolve("owned"));
        var child = launch(cache, "zombie.network.GameServer", "-adminpassword", "private-password", "--token=private-token");
        try {
            require(ToolkitHostChildDiagnostics.start(child, child.pid() + 1, cache) == null, "wrong PID accepted");
            Path foreign = Files.createDirectory(root.resolve("wrong-cache"));
            require(ToolkitHostChildDiagnostics.start(child, child.pid(), foreign) == null, "wrong cache accepted");
            require(!Files.exists(foreign.resolve("host-child-stderr.log")), "wrong-cache output created");
            var log = new OwnerLog();
            var target = new PrintStream(log);
            var capture = ToolkitHostChildDiagnostics.start(child, child.pid(), cache, target);
            require(capture != null, "owned diagnostics unavailable");
            String initial = Files.readString(cache.resolve("host-child-diagnostics.json"));
            require(initial.contains("\"stderrEof\":false") && initial.contains("\"readinessEvidence\":false"), "incomplete observation became readiness");
            input(child, "go");
            var stdout = new BufferedReader(new InputStreamReader(child.getInputStream(), StandardCharsets.UTF_8));
            require("READY".equals(line(stdout)), "stderr drain stole or merged stdout / child blocked before readiness");
            input(child, "owner-input");
            require("ECHO owner-input".equals(line(stdout)), "owner stdin changed");
            require(child.waitFor(8, TimeUnit.SECONDS), "child did not finish after oversized stderr");
            require(capture.await(Duration.ofSeconds(5)), "diagnostic callbacks did not finish");
            forwarded(log, target);
            require(line(stdout) == null, "unexpected stdout data");
            byte[] stderr = Files.readAllBytes(cache.resolve("host-child-stderr.log"));
            require(stderr.length == ToolkitHostChildDiagnostics.STDERR_LIMIT, "stderr file exceeded or missed cap");
            for (byte value : stderr) require(value == 'E', "stderr payload changed");
            Path meta = cache.resolve("host-child-diagnostics.json"); String data = Files.readString(meta);
            require(Files.size(meta) <= ToolkitHostChildDiagnostics.METADATA_LIMIT, "metadata exceeded cap");
            for (String expected : List.of("\"argvComplete\":true", "\"credentialsRedacted\":true", "\"stderrEof\":true",
                "\"stderrTruncated\":true", "\"stderrError\":null", "\"diagnosticsError\":null", "\"processExited\":true",
                "\"exitCode\":0", "\"stdoutUntouched\":true", "\"stdinUntouched\":true", "\"readinessEvidence\":false",
                "\"stderrBytes\":" + (3L * ToolkitHostChildDiagnostics.STDERR_LIMIT)))
                require(data.contains(expected), "missing exact diagnostic receipt " + expected);
            require(!data.contains("private-password") && !data.contains("private-token") && data.contains("[REDACTED]"), "argv credential leaked");
        } finally { stop(child); }
    }

    private static void unavailableChecks(Path root) throws Exception {
        Path cache = Files.createDirectory(root.resolve("unavailable"));
        Files.writeString(cache.resolve("host-child-stderr.log"), "owned-existing-content");
        var child = launch(cache, "zombie.network.GameServer");
        try {
            var log = new OwnerLog();
            var target = new PrintStream(log);
            var capture = ToolkitHostChildDiagnostics.start(child, child.pid(), cache, target);
            require(capture == null, "existing diagnostic output overwritten");
            var fallback = ToolkitHostOutput.start(child, child.toHandle(), target);
            completeChild(child);
            fallback.await(5000);
            forwarded(log, target);
            require(Files.readString(cache.resolve("host-child-stderr.log")).equals("owned-existing-content"), "existing file changed");
            require(!Files.exists(cache.resolve("host-child-diagnostics.json")), "unavailable capture claimed metadata");
        } finally { stop(child); }
    }

    private static void destinationFailureChecks(Path root) throws Exception {
        Path cache = Files.createDirectory(root.resolve("broken-destinations"));
        var child = launch(cache, "zombie.network.GameServer");
        var target = new PrintStream(new OutputStream() {
            @Override public void write(int value) throws IOException { throw new IOException("unwritable owner log"); }
            @Override public void close() { throw new AssertionError("drain closed owner log after write failure"); }
        });
        try {
            var capture = ToolkitHostChildDiagnostics.start(child, child.pid(), cache, target);
            require(capture != null, "failure-test diagnostics unavailable");
            var sink = ToolkitHostChildDiagnostics.Capture.class.getDeclaredField("sink");
            sink.setAccessible(true);
            ((OutputStream)sink.get(capture)).close();
            completeChild(child);
            require(capture.await(Duration.ofSeconds(5)), "broken destinations stopped stderr draining");
            String data = Files.readString(cache.resolve("host-child-diagnostics.json"));
            require(data.contains("capture write: ") && data.contains("; stderr forward: IOException"), "destination failures were not both retained: " + data);
            require(data.contains("\"stderrEof\":true") && data.contains("\"stderrBytes\":" + (3L * ToolkitHostChildDiagnostics.STDERR_LIMIT)), "destination failures lost drain/byte accounting");
            require(data.contains("\"stderrCapturedBytes\":0") && data.contains("\"processExited\":true"), "failed capture/exit receipts changed");
        } finally { stop(child); }
    }

    private static void metadataAndExitChecks(Path root) throws Exception {
        Path cache = Files.createDirectory(root.resolve("bounded-metadata"));
        var child = launch(cache, "zombie.network.GameServer", "--small-stderr", "--exit=7", "--opaque=" + "X".repeat(70000));
        try {
            var capture = ToolkitHostChildDiagnostics.start(child, child.pid(), cache);
            require(capture != null, "large-argv diagnostics unavailable");
            input(child, "go"); input(child, "owner-input");
            var stdout = new BufferedReader(new InputStreamReader(child.getInputStream(), StandardCharsets.UTF_8));
            require("READY".equals(line(stdout)) && "ECHO owner-input".equals(line(stdout)), "small stderr changed owner streams");
            require(child.waitFor(8, TimeUnit.SECONDS), "nonzero child did not exit");
            capture.finish(Duration.ofSeconds(5));
            Path meta = cache.resolve("host-child-diagnostics.json"); String data = Files.readString(meta);
            require(Files.size(meta) <= ToolkitHostChildDiagnostics.METADATA_LIMIT, "oversized argv exceeded metadata cap");
            require(data.contains("\"argvComplete\":false") && data.contains("\"argv\":null"), "oversized argv silently declared complete");
            require(data.contains("\"processExited\":true") && data.contains("\"exitCode\":7"), "nonzero exit not recorded");
            require(data.contains("\"stderrEof\":true") && data.contains("\"stderrTruncated\":false") && data.contains("\"stderrBytes\":1"), "small stderr observation differs");
        } finally { stop(child); }
    }

    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]).toAbsolutePath();
        ownershipChecks(root); drainChecks(root); unavailableChecks(root); destinationFailureChecks(root); metadataAndExitChecks(root);
        System.out.println("PASS ToolkitHostChildDiagnosticsChecks");
    }
}
