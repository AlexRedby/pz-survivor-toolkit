import java.io.BufferedReader;
import java.io.InputStreamReader;
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
            var capture = ToolkitHostChildDiagnostics.start(child, child.pid(), cache);
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
            require(ToolkitHostChildDiagnostics.start(child, child.pid(), cache) == null, "existing diagnostic output overwritten");
            require(Files.readString(cache.resolve("host-child-stderr.log")).equals("owned-existing-content"), "existing file changed");
            require(!Files.exists(cache.resolve("host-child-diagnostics.json")), "unavailable capture claimed metadata");
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
        ownershipChecks(root); drainChecks(root); unavailableChecks(root); metadataAndExitChecks(root);
        System.out.println("PASS ToolkitHostChildDiagnosticsChecks");
    }
}
