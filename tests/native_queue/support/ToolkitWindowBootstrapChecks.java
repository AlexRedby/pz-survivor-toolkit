import java.lang.classfile.ClassFile;
import java.lang.classfile.instruction.InvokeInstruction;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

/** No GLFW initialization or native window creation; run with JDK 25. */
public final class ToolkitWindowBootstrapChecks {
    private static void visibilityChecks() throws Exception {
        Path directory = Files.createTempDirectory("toolkit-window-visibility-");
        Path gate = directory.resolve("visible.txt");
        Path target = directory.resolve("target.txt");
        String token = "123:456";
        try {
            if (ToolkitWindowBootstrap.visibleAcknowledged(gate, token)) throw new AssertionError("Missing visibility token accepted");
            Files.writeString(gate, token + "\n");
            if (!ToolkitWindowBootstrap.visibleAcknowledged(gate, token)) throw new AssertionError("Owned visibility token rejected");
            for (String invalid : new String[] {"", "123:456", "999:456\n", "123:999\n", "123:456:current\n", "123:456\nextra", "x".repeat(300)}) {
                Files.writeString(gate, invalid);
                rejectVisibility(gate, token);
            }
            Files.delete(gate);
            Files.writeString(target, token + "\n");
            Files.createSymbolicLink(gate, target);
            rejectVisibility(gate, token);
            Files.delete(gate);
            Files.createDirectory(gate);
            rejectVisibility(gate, token);
        } finally {
            Files.deleteIfExists(gate);
            Files.deleteIfExists(target);
            Files.deleteIfExists(directory);
        }
    }

    private static void rejectVisibility(Path gate, String token) throws Exception {
        try {
            ToolkitWindowBootstrap.visibleAcknowledged(gate, token);
            throw new AssertionError("Invalid visibility acknowledgement accepted: " + gate);
        } catch (IllegalStateException expected) {
            // Files exist atomically; any unexpected content or nonregular input is fatal.
        }
    }

    public static void main(String[] args) throws Exception {
        if (!System.getProperty("os.name").startsWith("Mac")
                || System.getProperty("toolkit.test.windowGate") == null) {
            throw new IllegalStateException("Checks require macOS and toolkit.test.windowGate");
        }
        if (Arrays.asList(args).contains("--without-agent")) {
            try {
                ToolkitWindowBootstrap.beforeGlfwInit();
                throw new AssertionError("Missing agent was accepted");
            } catch (IllegalStateException expected) {
                if (!expected.getMessage().contains("agent is missing")) throw expected;
            }
            System.out.println("PASS missing agent rejected before GLFW initialization");
            return;
        }
        byte[] original;
        try (var stream = ClassLoader.getSystemResourceAsStream("org/lwjglx/opengl/Display.class")) {
            original = stream.readAllBytes();
        }
        byte[] patched = ToolkitWindowBootstrap.patchDisplay(original);
        if (Arrays.equals(original, patched)) throw new AssertionError("No bytecode change");
        var calls = new HashMap<String, Integer>();
        for (var method : ClassFile.of().parse(patched).methods()) {
            method.code().ifPresent(code -> code.forEach(element -> {
                if (element instanceof InvokeInstruction call
                        && call.owner().asInternalName().equals("ToolkitWindowBootstrap")) {
                    calls.merge(call.name().stringValue(), 1, Integer::sum);
                }
            }));
        }
        var expected = Map.of("glfwDefaultWindowHints", 1, "glfwShowWindow", 2,
            "glfwFocusWindow", 1, "glfwSetWindowPos", 1, "glfwSetWindowMonitor", 1, "glfwDestroyWindow", 2,
            "glfwPollEvents", 1);
        if (!calls.equals(expected)) throw new AssertionError("Unexpected hooks: " + calls);
        byte[] changed = original.clone();
        changed[changed.length - 1] ^= 1;
        try {
            ToolkitWindowBootstrap.patchDisplay(changed);
            throw new AssertionError("Unknown fingerprint accepted");
        } catch (IllegalStateException expectedFailure) {
            if (!expectedFailure.getMessage().contains("Unsupported Display bytecode")) throw expectedFailure;
        }
        // Definition runs the real agent transformer, without Display's static initialization.
        Class.forName("org.lwjglx.opengl.Display", false, ClassLoader.getSystemClassLoader());
        var transformed = ToolkitWindowBootstrap.class.getDeclaredField("displayTransformed");
        transformed.setAccessible(true);
        if (!transformed.getBoolean(null)) throw new AssertionError("Agent did not transform Display");
        try (var stream = ClassLoader.getSystemResourceAsStream("org/lwjglx/opengl/Display.class")) {
            if (!Arrays.equals(original, stream.readAllBytes())) throw new AssertionError("Class resource changed");
        }
        visibilityChecks();
        System.out.println("PASS exact hooks, verifier, unknown fingerprint rejection, agent definition, original resource preserved, fail-closed visibility tokens; GLFW not initialized");
    }
}
