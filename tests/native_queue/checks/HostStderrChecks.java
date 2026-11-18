import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

/** Exercise the real owning Host reader and failure summary without game/GLFW initialization. */
public final class HostStderrChecks {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Pass the Java binary as the only argument");
        Path root = Files.createTempDirectory("host-stderr-owned-");
        try {
            for (boolean captureAvailable : List.of(true, false)) {
                Path cache = Files.createDirectory(root.resolve(captureAvailable ? "capture" : "fallback"));
                var command = new ArrayList<>(List.of(args[0], "-cp", System.getProperty("java.class.path"),
                    "zombie.network.GameServer", "-coop", "-cachedir=" + cache, "--exit=7"));
                var builder = new ProcessBuilder(command);
                for (String name : List.of("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS")) builder.environment().remove(name);
                Process child = builder.start();
                try {
                    if (!captureAvailable) Files.writeString(cache.resolve("host-child-stderr.log"), "preserve");
                    var log = new ByteArrayOutputStream();
                    var target = new PrintStream(log);
                    var capture = ToolkitHostChildDiagnostics.start(child, child.pid(), cache, target);
                    require((capture != null) == captureAvailable, "Unexpected owning capture availability");
                    var fallback = capture == null ? ToolkitHostOutput.start(child, child.toHandle(), target) : null;
                    try {
                        ToolkitSmokeLauncher.exitedHostDiagnostic(child, child.pid(), cache, capture != null);
                        throw new AssertionError("Live child admitted");
                    } catch (IllegalStateException expected) {}
                    child.getOutputStream().write("go\nowner-input\n".getBytes(StandardCharsets.UTF_8));
                    child.getOutputStream().flush();
                    require(child.waitFor(10, TimeUnit.SECONDS), "Owned child did not exit after stderr drain");
                    if (capture != null) {
                        capture.finish(Duration.ofSeconds(5));
                        require(capture.await(Duration.ZERO), "Owning capture did not finish");
                    } else fallback.await(5000);
                    String diagnostic = ToolkitSmokeLauncher.exitedHostDiagnostic(child, child.pid(), cache, capture != null);
                    require(diagnostic.contains("exit=7") && diagnostic.contains(capture != null ? "host-child-stderr.log" : "owner-log"),
                        "Failure omitted actual exit code or owning reader evidence");
                    require(log.size() == 3 * ToolkitHostChildDiagnostics.STDERR_LIMIT, "Owner log lost stderr beyond evidence cap");
                    require(new String(child.getInputStream().readAllBytes(), StandardCharsets.UTF_8).equals("READY\nECHO owner-input\n"),
                        "Owning reader consumed protocol stdout");
                    if (capture != null) {
                        require(Files.size(cache.resolve("host-child-stderr.log")) == ToolkitHostChildDiagnostics.STDERR_LIMIT,
                            "Owning reader did not enforce evidence cap");
                        require(Files.readString(cache.resolve("host-child-diagnostics.json")).contains("\"exitCode\":7"),
                            "Failure metadata omitted actual exit code");
                    } else require(Files.readString(cache.resolve("host-child-stderr.log")).equals("preserve"), "Fallback overwrote evidence");
                    try {
                        ToolkitSmokeLauncher.exitedHostDiagnostic(child, child.pid() + 1, cache, capture != null);
                        throw new AssertionError("Unproved PID admitted");
                    } catch (IllegalStateException expected) {}
                } finally {
                    if (child.isAlive()) { child.destroyForcibly(); child.waitFor(10, TimeUnit.SECONDS); }
                    child.getInputStream().close(); child.getErrorStream().close(); child.getOutputStream().close();
                }
            }
        } finally {
            try (var paths = Files.walk(root)) {
                for (Path path : paths.sorted(java.util.Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
        System.out.println("HOST_STDERR_CAPTURE_CHECKS_PASS");
    }
}
