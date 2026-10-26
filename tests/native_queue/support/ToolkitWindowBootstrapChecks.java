import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassTransform;
import java.lang.reflect.InvocationTargetException;
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

    private static void ownedCreationSizeChecks() throws Exception {
        var routed = ToolkitWindowBootstrap.class.getDeclaredField("routedWindow");
        var sizes = ToolkitWindowBootstrap.class.getDeclaredField("creationSizes");
        routed.setAccessible(true);
        sizes.setAccessible(true);
        long previous = routed.getLong(null);
        @SuppressWarnings("unchecked")
        var requests = (Map<Long, int[]>)sizes.get(null);
        if (!requests.isEmpty()) throw new AssertionError("Size checks must run before native creation");
        try {
            requests.put(123L, new int[] {1600, 900});
            requests.put(999L, new int[] {1052, 900});
            routed.setLong(null, 0L);
            if (ToolkitWindowBootstrap.routedCreationSize(123L) != null) throw new AssertionError("Unacknowledged creation accepted");
            routed.setLong(null, 123L);
            if (ToolkitWindowBootstrap.routedCreationSize(999L) != null) throw new AssertionError("Foreign handle accepted");
            if (ToolkitWindowBootstrap.routedCreationSize(0L) != null) throw new AssertionError("Zero handle accepted");
            if (!Arrays.equals(new int[] {1600, 900}, ToolkitWindowBootstrap.routedCreationSize(123L))) {
                throw new AssertionError("Prepared creation size was replaced by an observed smaller size");
            }
            ToolkitWindowBootstrap.routedCreationSize(123L)[0] = 576;
            if (ToolkitWindowBootstrap.routedCreationSize(123L)[0] != 1600) throw new AssertionError("Mutable size request escaped");
            requests.remove(123L);
            if (ToolkitWindowBootstrap.routedCreationSize(123L) != null) throw new AssertionError("Unknown creation accepted");
        } finally {
            requests.clear();
            routed.setLong(null, previous);
        }
    }

    private static void viewportChecks() {
        // Native Display exposes logical dimensions even on a larger framebuffer.
        ToolkitWindowBootstrap.validateViewport(false, 1600, 900,
            new int[] {1600, 900, 3200, 1800, 1600, 900, 1600, 900});
        // Reviewed optimizer Display exposes the actual framebuffer dimensions.
        ToolkitWindowBootstrap.validateViewport(true, 1600, 900,
            new int[] {1600, 900, 3200, 1800, 3200, 1800, 3200, 1800});
        for (boolean framebufferContract : new boolean[] {false, true}) {
            ToolkitWindowBootstrap.validateViewport(framebufferContract, 1600, 900,
                new int[] {1600, 900, 1600, 900, 1600, 900, 1600, 900});
            // Acceptance follows observed sizes; it must not assume a scale of two.
            int effectiveWidth = framebufferContract ? 2400 : 1600;
            int effectiveHeight = framebufferContract ? 1350 : 900;
            ToolkitWindowBootstrap.validateViewport(framebufferContract, 1600, 900,
                new int[] {1600, 900, 2400, 1350,
                    effectiveWidth, effectiveHeight, effectiveWidth, effectiveHeight});
            int[] valid = framebufferContract
                ? new int[] {1600, 900, 3200, 1800, 3200, 1800, 3200, 1800}
                : new int[] {1600, 900, 3200, 1800, 1600, 900, 1600, 900};
            for (int index = 0; index < valid.length; index++) {
                for (int invalid : new int[] {0, -1}) {
                    int[] changed = valid.clone();
                    changed[index] = invalid;
                    rejectViewport(framebufferContract, 1600, 900, changed);
                }
            }
            for (int index : new int[] {0, 1, 4, 5, 6, 7}) {
                int[] changed = valid.clone();
                changed[index]++;
                rejectViewport(framebufferContract, 1600, 900, changed);
            }
            for (int invalid : new int[] {0, -1}) {
                rejectViewport(framebufferContract, invalid, 900, valid);
                rejectViewport(framebufferContract, 1600, invalid, valid);
            }
            for (int length : new int[] {0, 7, 9}) {
                rejectViewport(framebufferContract, 1600, 900, Arrays.copyOf(valid, length));
            }
        }
        // A doubled cached Core value cannot stand in for a fresh 1x framebuffer.
        rejectViewport(true, 1600, 900,
            new int[] {1600, 900, 1600, 900, 3200, 1800, 3200, 1800});
        rejectViewport(true, 1600, 900,
            new int[] {1600, 900, 3200, 1800, 1600, 900, 1600, 900});
        rejectViewport(false, 1600, 900,
            new int[] {1600, 900, 3200, 1800, 3200, 1800, 3200, 1800});
        for (int index : new int[] {2, 3}) {
            int[] changed = {1600, 900, 3200, 1800, 3200, 1800, 3200, 1800};
            changed[index]++;
            rejectViewport(true, 1600, 900, changed);
        }
    }

    private static void rejectViewport(boolean framebufferContract, int expectedWidth,
            int expectedHeight, int[] values) {
        try {
            ToolkitWindowBootstrap.validateViewport(framebufferContract, expectedWidth, expectedHeight, values);
            throw new AssertionError("Invalid viewport accepted: " + Arrays.toString(values));
        } catch (IllegalStateException expected) {
            // Invalid or incoherent dimensions must fail without initializing GLFW.
        }
    }

    private static void presentationChecks() {
        var pins = Map.of("hdr", "false", "hdrAuto", "false", "macPresent", "off", "macGlCore", "false",
            "macNativeFullscreen", "false", "borderlessFullscreen", "off");
        var previous = new HashMap<String, String>();
        for (var key : pins.keySet()) previous.put(key, System.getProperty("pzopt." + key));
        try {
            pins.forEach((key, value) -> System.setProperty("pzopt." + key, value));
            ToolkitWindowBootstrap.requireOptimizedPresentation();
            for (var entry : pins.entrySet()) {
                for (var invalid : new String[] {"true", "auto", ""}) {
                    System.setProperty("pzopt." + entry.getKey(), invalid);
                    try {
                        ToolkitWindowBootstrap.requireOptimizedPresentation();
                        throw new AssertionError("Unsafe presentation accepted: " + entry.getKey() + "=" + invalid);
                    } catch (IllegalStateException expected) {
                        if (!expected.getMessage().contains("pzopt." + entry.getKey())) throw expected;
                    }
                }
                System.clearProperty("pzopt." + entry.getKey());
                try {
                    ToolkitWindowBootstrap.requireOptimizedPresentation();
                    throw new AssertionError("Unpinned presentation accepted: " + entry.getKey());
                } catch (IllegalStateException expected) {
                    if (!expected.getMessage().contains("pzopt." + entry.getKey())) throw expected;
                }
                System.setProperty("pzopt." + entry.getKey(), entry.getValue());
            }
        } finally {
            previous.forEach((key, value) -> {
                if (value == null) System.clearProperty("pzopt." + key);
                else System.setProperty("pzopt." + key, value);
            });
        }
    }

    private static void changedLifecycleChecks(byte[] original, Map<String, Integer> expected) throws Exception {
        byte[] changed = ClassFile.of().transformClass(ClassFile.of().parse(original),
            ClassTransform.transformingMethodBodies((builder, element) -> {
                if (element instanceof InvokeInstruction call
                        && call.owner().asInternalName().equals("org/lwjgl/glfw/GLFW")
                        && call.name().stringValue().equals("glfwFocusWindow")) builder.pop2();
                else builder.with(element);
            }));
        // Exercise the structural check independently of the earlier exact-hash rejection.
        // Production reaches this private helper only after a known fingerprint match.
        var transform = ToolkitWindowBootstrap.class.getDeclaredMethod("transformDisplay", byte[].class, Map.class);
        transform.setAccessible(true);
        try {
            transform.invoke(null, changed, expected);
            throw new AssertionError("Changed GLFW lifecycle count accepted");
        } catch (InvocationTargetException failure) {
            if (!(failure.getCause() instanceof IllegalStateException expectedFailure)
                    || !expectedFailure.getMessage().contains("Unexpected Display lifecycle")) throw failure;
        }
    }

    public static void main(String[] args) throws Exception {
        if (!System.getProperty("os.name").startsWith("Mac")
                || System.getProperty("toolkit.test.windowGate") == null) {
            throw new IllegalStateException("Checks require macOS and toolkit.test.windowGate");
        }
        if (Arrays.asList(args).contains("--reject-create-monitor")) {
            ToolkitWindowBootstrap.glfwCreateWindow(320, 240, "must-not-exist", 1L, 0L);
            throw new AssertionError("Fullscreen creation returned instead of halting before native GLFW");
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
        boolean official = Arrays.asList(args).contains("--official");
        var expected = Map.of("glfwDefaultWindowHints", 1, "glfwCreateWindow", official ? 2 : 1,
            "glfwShowWindow", 2, "glfwFocusWindow", 1, "glfwSetWindowPos", 1, "glfwSetWindowMonitor", 1,
            "glfwDestroyWindow", official ? 3 : 2, "glfwPollEvents", 1);
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
        changedLifecycleChecks(original, expected);
        viewportChecks();
        presentationChecks();
        ownedCreationSizeChecks();
        visibilityChecks();
        System.out.println("PASS exact hooks, verifier, unknown fingerprint and lifecycle-count rejection, agent definition, original resource preserved, fail-closed visibility tokens, pinned optimizer presentation, exact owned creation geometry, observed viewport contracts; GLFW not initialized");
    }
}
