import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassTransform;
import java.lang.classfile.instruction.InvokeInstruction;
import java.lang.constant.ClassDesc;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import org.lwjgl.glfw.GLFW;

/** Fixture-only agent. The installed game and its class resources stay unchanged. */
public final class ToolkitWindowBootstrap {
    private static final String DISPLAY = "org/lwjglx/opengl/Display";
    // B42.21 installed Display. Reject engine updates before starting any native UI.
    private static final String DISPLAY_SHA256 = "15a0c0a3646d4340cd96c47d143a5605bfbae7543410ddaa018e83f45ae1a578";
    private static final Map<String, Integer> EXPECTED = Map.of(
        "glfwDefaultWindowHints", 1, "glfwShowWindow", 2, "glfwFocusWindow", 1,
        "glfwSetWindowPos", 1, "glfwSetWindowMonitor", 1, "glfwDestroyWindow", 2,
        "glfwPollEvents", 1);
    private static boolean agentInstalled;
    private static volatile boolean displayTransformed;
    private static long routedWindow;
    private static long pendingVisibleWindow;

    private static String sha256(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    /** Install before ZombieBuddy so both agents retain their original resource fingerprints. */
    public static void premain(String arguments, Instrumentation instrumentation) throws Exception {
        if (!enabled()) throw new IllegalStateException("Window isolation agent requires a macOS routing gate");
        gatePath();
        try (var stream = ToolkitWindowBootstrap.class.getClassLoader().getResourceAsStream(DISPLAY + ".class")) {
            if (stream == null || !DISPLAY_SHA256.equals(sha256(stream.readAllBytes()))) {
                throw new IllegalStateException("Unsupported Display resource for native window isolation");
            }
        }
        for (var loaded : instrumentation.getAllLoadedClasses()) {
            if (loaded.getName().equals("org.lwjglx.opengl.Display")) {
                throw new IllegalStateException("Display loaded before native window isolation agent");
            }
        }
        instrumentation.addTransformer(new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader, String name, Class<?> redefined,
                    ProtectionDomain domain, byte[] bytes) {
                if (!DISPLAY.equals(name)) return null;
                try {
                    byte[] patched = patchDisplay(bytes);
                    displayTransformed = true;
                    return patched;
                } catch (Throwable error) {
                    // Transformer exceptions are otherwise swallowed by Instrumentation.
                    System.err.println("[QUEUE_TEST] FAIL native window bootstrap " + error);
                    Runtime.getRuntime().halt(71);
                    throw new AssertionError(error);
                }
            }
        });
        agentInstalled = true;
    }

    /** Pure bytecode operation, also used by preparation checks without starting native UI. */
    static byte[] patchDisplay(byte[] original) throws Exception {
        if (!DISPLAY_SHA256.equals(sha256(original))) {
            throw new IllegalStateException("Unsupported Display bytecode: " + sha256(original));
        }
        var calls = new HashMap<String, Integer>();
        var classFile = ClassFile.of();
        var patched = classFile.transformClass(classFile.parse(original),
            ClassTransform.transformingMethodBodies((builder, element) -> {
                if (element instanceof InvokeInstruction call
                        && call.owner().asInternalName().equals("org/lwjgl/glfw/GLFW")
                        && EXPECTED.containsKey(call.name().stringValue())) {
                    String name = call.name().stringValue();
                    calls.merge(name, 1, Integer::sum);
                    builder.invokestatic(ClassDesc.of("ToolkitWindowBootstrap"), name, call.typeSymbol());
                } else builder.with(element);
            }));
        if (!EXPECTED.equals(calls)) throw new IllegalStateException("Unexpected Display lifecycle: " + calls);
        var errors = classFile.verify(patched);
        if (!errors.isEmpty()) throw new IllegalStateException("Invalid patched Display: " + errors);
        return patched;
    }

    /** Must run before the first GLFW initialization, and before any window can be created. */
    public static void beforeGlfwInit() throws Exception {
        if (!enabled()) return;
        if (!agentInstalled) throw new IllegalStateException("Native window isolation agent is missing");
        var gate = gatePath();
        if (Files.exists(gate, LinkOption.NOFOLLOW_LINKS)
                || Files.exists(visibleGatePath(), LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalStateException("Window routing acknowledgement already exists: " + gate);
        }
        Class.forName("org.lwjglx.opengl.Display", false, ToolkitWindowBootstrap.class.getClassLoader());
        if (!displayTransformed) throw new IllegalStateException("Native Display isolation hooks are missing");
        // AeroSpace discovers regular UI applications; focus is independently suppressed below.
        GLFW.glfwInitHint(GLFW.GLFW_COCOA_MENUBAR, GLFW.GLFW_TRUE);
        System.out.println("[QUEUE_TEST] WINDOW_BOOTSTRAP_ARMED pid=" + ProcessHandle.current().pid());
    }

    private static boolean enabled() {
        return System.getProperty("os.name").startsWith("Mac")
            && System.getProperty("toolkit.test.windowGate") != null;
    }

    private static Path gatePath() {
        var gate = Path.of(System.getProperty("toolkit.test.windowGate"));
        if (!gate.isAbsolute()) throw new IllegalArgumentException("Window gate path must be absolute");
        return gate;
    }

    private static Path visibleGatePath() {
        return gatePath().resolveSibling("test-window-visible.txt");
    }

    /** Complete recovery tokens are published atomically; malformed input never reveals a window. */
    static boolean visibleAcknowledged(Path gate, String token) throws Exception {
        if (!Files.exists(gate, LinkOption.NOFOLLOW_LINKS)) return false;
        if (!Files.isRegularFile(gate, LinkOption.NOFOLLOW_LINKS)) {
            throw new IllegalStateException("Window visibility acknowledgement must be a regular file: " + gate);
        }
        try (var stream = Files.newInputStream(gate, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
            byte[] bytes = stream.readNBytes(257);
            if (!new String(bytes, StandardCharsets.US_ASCII).equals(token + "\n")) {
                throw new IllegalStateException("Invalid owned window visibility acknowledgement: " + gate);
            }
        }
        return true;
    }

    public static void glfwDefaultWindowHints() {
        GLFW.glfwDefaultWindowHints();
        if (enabled()) {
            GLFW.glfwWindowHint(GLFW.GLFW_FOCUSED, GLFW.GLFW_FALSE);
            GLFW.glfwWindowHint(GLFW.GLFW_FOCUS_ON_SHOW, GLFW.GLFW_FALSE);
        }
    }

    public static void glfwShowWindow(long window) {
        if (!enabled()) { GLFW.glfwShowWindow(window); return; }
        if (window == routedWindow) { GLFW.glfwShowWindow(window); return; }
        try {
            Path gate = gatePath();
            if (Files.exists(visibleGatePath(), LinkOption.NOFOLLOW_LINKS)) {
                throw new IllegalStateException("Window visibility acknowledgement already exists");
            }
            Files.deleteIfExists(gate);
            GLFW.glfwSetWindowAttrib(window, GLFW.GLFW_FOCUS_ON_SHOW, GLFW.GLFW_FALSE);
            GLFW.glfwSetWindowOpacity(window, 0.0f);
            GLFW.glfwShowWindow(window);
            String token = ProcessHandle.current().pid() + ":" + window;
            System.out.println("[QUEUE_TEST] WINDOW_ROUTING_READY pid=" + ProcessHandle.current().pid() + " glfw=" + window);
            System.out.flush();
            long deadline = System.nanoTime() + 60_000_000_000L;
            String acknowledgement = "";
            while (true) {
                if (Files.exists(gate, LinkOption.NOFOLLOW_LINKS)
                        && !Files.isRegularFile(gate, LinkOption.NOFOLLOW_LINKS)) {
                    throw new IllegalStateException("Window routing acknowledgement must be a regular file");
                }
                if (Files.isRegularFile(gate, LinkOption.NOFOLLOW_LINKS)) {
                    acknowledgement = Files.readString(gate).strip();
                    if (acknowledgement.equals(token) || acknowledgement.equals(token + ":current")) break;
                }
                if (System.nanoTime() >= deadline) throw new IllegalStateException("Timed out waiting for owned window routing: " + token);
                // A waiting Cocoa event pump also services accessibility requests from AeroSpace.
                GLFW.glfwWaitEventsTimeout(0.025);
            }
            routedWindow = window;
            boolean current = acknowledgement.equals(token + ":current");
            pendingVisibleWindow = current ? window : 0;
            if (!current) GLFW.glfwSetWindowOpacity(window, 1.0f);
            System.out.println("[QUEUE_TEST] WINDOW_ROUTED pid=" + ProcessHandle.current().pid() + " glfw=" + window
                + " mode=" + (current ? "current transparent=true" : "aerospace"));
        } catch (Exception error) {
            // Never reveal a window when routing fails, even if the engine catches this exception.
            System.err.println("[QUEUE_TEST] FAIL native window routing " + error);
            Runtime.getRuntime().halt(71);
        }
    }

    public static void glfwDestroyWindow(long window) {
        if (enabled() && window == routedWindow) routedWindow = 0;
        if (enabled() && window == pendingVisibleWindow) pendingVisibleWindow = 0;
        GLFW.glfwDestroyWindow(window);
    }

    public static void glfwPollEvents() {
        GLFW.glfwPollEvents();
        if (!enabled() || pendingVisibleWindow == 0) return;
        try {
            long window = pendingVisibleWindow;
            String token = ProcessHandle.current().pid() + ":" + window;
            if (visibleAcknowledged(visibleGatePath(), token)) {
                GLFW.glfwSetWindowOpacity(window, 1.0f);
                pendingVisibleWindow = 0;
                System.out.println("[QUEUE_TEST] WINDOW_VISIBLE pid=" + ProcessHandle.current().pid() + " glfw=" + window);
            }
        } catch (Exception error) {
            System.err.println("[QUEUE_TEST] FAIL native window visibility " + error);
            Runtime.getRuntime().halt(71);
        }
    }

    public static void glfwFocusWindow(long window) {
        if (!enabled()) GLFW.glfwFocusWindow(window);
    }

    public static void glfwSetWindowPos(long window, int x, int y) {
        // AeroSpace owns the routed position; later mode updates may otherwise center it again.
        if (!enabled() || window != routedWindow) GLFW.glfwSetWindowPos(window, x, y);
    }

    public static void glfwSetWindowMonitor(long window, long monitor, int x, int y, int width, int height, int refreshRate) {
        if (enabled()) {
            if (monitor != 0) {
                System.err.println("[QUEUE_TEST] FAIL native window isolation forbids fullscreen");
                Runtime.getRuntime().halt(71);
            }
            if (window == routedWindow) {
                int[] currentX = new int[1], currentY = new int[1];
                GLFW.glfwGetWindowPos(window, currentX, currentY);
                x = currentX[0];
                y = currentY[0];
            }
        }
        GLFW.glfwSetWindowMonitor(window, monitor, x, y, width, height, refreshRate);
    }
}
