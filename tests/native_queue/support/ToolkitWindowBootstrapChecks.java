import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassTransform;
import java.lang.classfile.CodeBuilder;
import java.lang.classfile.CodeElement;
import java.lang.classfile.CodeTransform;
import java.lang.classfile.Instruction;
import java.lang.classfile.Opcode;
import java.lang.classfile.instruction.FieldInstruction;
import java.lang.constant.ClassDesc;
import java.lang.constant.MethodTypeDesc;
import java.lang.reflect.InvocationTargetException;
import java.lang.classfile.instruction.InvokeInstruction;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
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

    private static void creationGuardChecks() throws Exception {
        var fields = new HashMap<String, java.lang.reflect.Field>();
        var previous = new HashMap<String, Object>();
        for (var name : List.of("agentInstalled", "displayTransformed", "glfwOwnerThread", "routedWindow")) {
            var field = ToolkitWindowBootstrap.class.getDeclaredField(name);
            field.setAccessible(true);
            fields.put(name, field);
            previous.put(name, field.get(null));
        }
        var sizes = ToolkitWindowBootstrap.class.getDeclaredField("creationSizes");
        sizes.setAccessible(true);
        @SuppressWarnings("unchecked")
        var requests = (Map<Long, int[]>)sizes.get(null);
        if (!requests.isEmpty()) throw new AssertionError("Guard checks must precede native creation");
        String gate = System.getProperty("toolkit.test.windowGate");
        try {
            fields.get("agentInstalled").setBoolean(null, true);
            fields.get("displayTransformed").setBoolean(null, true);
            fields.get("glfwOwnerThread").set(null, Thread.currentThread());
            fields.get("routedWindow").setLong(null, 123L);
            requests.put(123L, new int[] {1600, 900});
            requests.put(999L, new int[] {1600, 900});
            System.clearProperty("toolkit.test.windowGate");
            rejectCreationGuard(123L);
            System.setProperty("toolkit.test.windowGate", gate);
            for (var name : List.of("agentInstalled", "displayTransformed")) {
                fields.get(name).setBoolean(null, false);
                rejectCreationGuard(123L);
                fields.get(name).setBoolean(null, true);
            }
            fields.get("glfwOwnerThread").set(null, new Thread());
            rejectCreationGuard(123L);
            fields.get("glfwOwnerThread").set(null, Thread.currentThread());
            rejectCreationGuard(0L);
            rejectCreationGuard(999L);
            requests.remove(123L);
            rejectCreationGuard(123L);
        } finally {
            System.setProperty("toolkit.test.windowGate", gate);
            requests.clear();
            for (var entry : fields.entrySet()) entry.getValue().set(null, previous.get(entry.getKey()));
        }
    }

    private static void rejectCreationGuard(long window) {
        try {
            ToolkitWindowBootstrap.creationViewport(window);
            throw new AssertionError("Unowned creation observation accepted");
        } catch (IllegalStateException expected) {
            if (!"Creation viewport requires the owned routed GLFW thread/window".equals(expected.getMessage())) throw expected;
        }
    }

    private static void creationObservationChecks() {
        int[] requested = {1600, 900};
        for (var observed : new int[][] {{1600, 900, 1600, 900}, {1600, 900, 3200, 1800},
                {1600, 900, 2400, 1350}, {1600, 900, 1600, 1800}}) {
            ToolkitWindowBootstrap.validateCreationViewport(requested, observed);
            for (int index = 0; index < observed.length; index++) {
                for (int invalid : new int[] {0, -1}) {
                    var changed = observed.clone();
                    changed[index] = invalid;
                    rejectCreationObservation(requested, changed);
                }
            }
            for (int index : new int[] {0, 1}) {
                var changed = observed.clone();
                changed[index]++;
                rejectCreationObservation(requested, changed);
            }
        }
        for (int[] invalid : new int[][] {null, {}, {1600}, {1600, 900, 1}, {0, 900}, {1600, -1}}) {
            rejectCreationObservation(invalid, new int[] {1600, 900, 3200, 1800});
        }
        for (int[] invalid : new int[][] {null, {}, {1600, 900, 3200}, {1600, 900, 3200, 1800, 1}}) {
            rejectCreationObservation(requested, invalid);
        }
    }

    private static void rejectCreationObservation(int[] requested, int[] observed) {
        try {
            ToolkitWindowBootstrap.validateCreationViewport(requested, observed);
            throw new AssertionError("Invalid creation observation accepted: " + Arrays.toString(observed));
        } catch (IllegalStateException expected) {
            // Bad observations must be rejected before any dimension cache is initialized.
        }
    }

    private static Class<?> creationFixture;
    private static int[] fixtureObservation;
    private static int[] fixtureLateFramebuffer;
    private static boolean fixtureReject;
    private static int fixtureQueries;

    /** Script only the native observation; execute the production cache-copy bytecode unchanged. */
    public static int[] fixtureViewport(long window) throws Exception {
        if (window != 123L || creationFixture.getField("displayCreated").getBoolean(null)) {
            throw new AssertionError("Creation observation ran after publication or with another handle");
        }
        fixtureQueries++;
        if (fixtureReject) throw new IllegalStateException("Scripted observation rejection");
        if (fixtureLateFramebuffer != null) {
            creationFixture.getField("displayFramebufferWidth").setInt(null, fixtureLateFramebuffer[0]);
            creationFixture.getField("displayFramebufferHeight").setInt(null, fixtureLateFramebuffer[1]);
        }
        return fixtureObservation.clone();
    }

    private static void copyFixtureInstruction(CodeBuilder builder, CodeElement element, ClassDesc fixture) {
        if (element instanceof FieldInstruction field
                && field.owner().asInternalName().equals("org/lwjglx/opengl/Display")) {
            builder.fieldAccess(field.opcode(), fixture, field.name().stringValue(), field.typeSymbol());
        } else builder.with(element);
    }

    private static void creationCacheChecks(byte[] patched, boolean framebufferContract) throws Exception {
        var model = ClassFile.of().parse(patched);
        var create = model.methods().stream().filter(method -> method.methodName().equalsString("create")
            && method.methodType().equalsString("()V")).findFirst().orElseThrow();
        var instructions = new ArrayList<CodeElement>();
        create.code().orElseThrow().forEach(element -> {
            if (element instanceof Instruction) instructions.add(element);
        });
        int query = -1, publish = -1;
        var copiedFields = new HashMap<String, Integer>();
        for (int index = 0; index < instructions.size(); index++) {
            var element = instructions.get(index);
            if (element instanceof InvokeInstruction call
                    && call.owner().asInternalName().equals("ToolkitWindowBootstrap")
                    && call.name().equalsString("creationViewport")) {
                if (query >= 0) throw new AssertionError("Duplicate creation observation");
                query = index;
            }
            if (element instanceof FieldInstruction field && field.opcode() == Opcode.PUTSTATIC
                    && field.owner().asInternalName().equals("org/lwjglx/opengl/Display")
                    && field.name().equalsString("displayCreated")) {
                if (publish >= 0) throw new AssertionError("Duplicate creation publication");
                publish = index;
            }
        }
        if (query < 1 || publish <= query) throw new AssertionError("Observation does not precede publication");
        if (!(instructions.get(query - 1) instanceof InvokeInstruction handle)
                || !handle.owner().asInternalName().equals("org/lwjglx/opengl/Display")
                || !handle.name().equalsString("getWindow")) {
            throw new AssertionError("Creation observation does not use Display's actual handle");
        }
        var required = Set.of("latestWidth", "latestHeight", "displayWidth", "displayHeight",
            "displayFramebufferWidth", "displayFramebufferHeight");
        for (int index = query + 1; index < publish; index++) {
            if (instructions.get(index) instanceof FieldInstruction field && field.opcode() == Opcode.PUTSTATIC) {
                if (!field.owner().asInternalName().equals("org/lwjglx/opengl/Display")
                        || !required.contains(field.name().stringValue())) {
                    throw new AssertionError("Creation synchronization writes outside dimension caches");
                }
                copiedFields.merge(field.name().stringValue(), 1, Integer::sum);
            }
        }
        if (!copiedFields.keySet().equals(required) || copiedFields.values().stream().anyMatch(count -> count != 1)) {
            throw new AssertionError("Incomplete or duplicate cache initialization: " + copiedFields);
        }
        // A separate name avoids the live agent's intentional rejection of unknown Display bytes.
        var fixture = ClassDesc.of("ToolkitCreationViewportFixture");
        int begin = query, end = publish;
        byte[] bytes = ClassFile.of().build(fixture, builder -> {
            builder.withFlags(ClassFile.ACC_PUBLIC);
            for (var field : required) builder.withField(field, ClassDesc.ofDescriptor("I"), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC);
            builder.withField("displayCreated", ClassDesc.ofDescriptor("Z"), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC);
            builder.withMethodBody("initialize", MethodTypeDesc.ofDescriptor("()V"), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, code -> {
                // The original true value is already on stack at the intercepted publication instruction.
                code.iconst_1().ldc(123L).invokestatic(ClassDesc.of("ToolkitWindowBootstrapChecks"),
                    "fixtureViewport", MethodTypeDesc.ofDescriptor("(J)[I"));
                for (int index = begin + 1; index <= end; index++) copyFixtureInstruction(code, instructions.get(index), fixture);
                code.return_();
            });
            for (var method : model.methods()) {
                if (!Set.of("getWidth", "getHeight", "getFramebufferWidth", "getFramebufferHeight").contains(method.methodName().stringValue())) continue;
                builder.withMethodBody(method.methodName(), method.methodType(), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC,
                    code -> code.transform(method.code().orElseThrow(), (CodeTransform)(target, element) -> copyFixtureInstruction(target, element, fixture)));
            }
        });
        var errors = ClassFile.of().verify(bytes);
        if (!errors.isEmpty()) throw new AssertionError("Invalid creation fixture: " + errors);
        creationFixture = new ClassLoader(ToolkitWindowBootstrapChecks.class.getClassLoader()) {
            Class<?> define() { return defineClass(fixture.displayName(), bytes, 0, bytes.length); }
        }.define();
        // Old cache, final framebuffer, and optional pending callback observed while draining events.
        int[][] cases = {{3200, 1800, 1600, 900, 3200, 1800}, {3200, 1800, 1600, 900, 0, 0},
            {1600, 900, 3200, 1800, 0, 0}, {3200, 1800, 3200, 1800, 0, 0},
            {1600, 900, 2400, 1350, 0, 0}};
        for (var vector : cases) {
            seedCreationFixture(vector[0], vector[1]);
            fixtureObservation = new int[] {1600, 900, vector[2], vector[3]};
            fixtureLateFramebuffer = vector[4] == 0 ? null : new int[] {vector[4], vector[5]};
            creationFixture.getMethod("initialize").invoke(null);
            if (fixtureQueries != 1 || !creationFixture.getField("displayCreated").getBoolean(null)) {
                throw new AssertionError("Creation was not observed exactly once before publication");
            }
            for (var field : new String[] {"latestWidth", "displayWidth"}) requireFixtureField(field, 1600);
            for (var field : new String[] {"latestHeight", "displayHeight"}) requireFixtureField(field, 900);
            requireFixtureField("displayFramebufferWidth", vector[2]);
            requireFixtureField("displayFramebufferHeight", vector[3]);
            requireFixtureGetter("getWidth", framebufferContract ? vector[2] : 1600);
            requireFixtureGetter("getHeight", framebufferContract ? vector[3] : 900);
            requireFixtureGetter("getFramebufferWidth", vector[2]);
            requireFixtureGetter("getFramebufferHeight", vector[3]);
        }
        seedCreationFixture(3200, 1800);
        fixtureReject = true;
        try {
            creationFixture.getMethod("initialize").invoke(null);
            throw new AssertionError("Rejected observation still published creation");
        } catch (InvocationTargetException failure) {
            if (!(failure.getCause() instanceof IllegalStateException)) throw failure;
        } finally { fixtureReject = false; }
        if (creationFixture.getField("displayCreated").getBoolean(null)) throw new AssertionError("Rejected creation became visible to Core");
        requireFixtureField("displayFramebufferWidth", 3200);
        requireFixtureField("displayWidth", 1111);
    }

    private static void seedCreationFixture(int framebufferWidth, int framebufferHeight) throws Exception {
        creationFixture.getField("displayCreated").setBoolean(null, false);
        for (var field : List.of("latestWidth", "displayWidth")) creationFixture.getField(field).setInt(null, 1111);
        for (var field : List.of("latestHeight", "displayHeight")) creationFixture.getField(field).setInt(null, 777);
        creationFixture.getField("displayFramebufferWidth").setInt(null, framebufferWidth);
        creationFixture.getField("displayFramebufferHeight").setInt(null, framebufferHeight);
        fixtureQueries = 0;
        fixtureLateFramebuffer = null;
    }

    private static void requireFixtureField(String name, int expected) throws Exception {
        if (creationFixture.getField(name).getInt(null) != expected) throw new AssertionError("Wrong copied " + name);
    }

    private static void requireFixtureGetter(String name, int expected) throws Exception {
        if (!creationFixture.getMethod(name).invoke(null).equals(expected)) throw new AssertionError("Changed Display getter contract: " + name);
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
        byte[] control = (byte[])transform.invoke(null, original, expected);
        if (Arrays.equals(original, control) || !ClassFile.of().verify(control).isEmpty()) {
            throw new AssertionError("Unmodified lifecycle positive control did not transform successfully");
        }
        try {
            transform.invoke(null, changed, expected);
            throw new AssertionError("Changed GLFW lifecycle count accepted");
        } catch (InvocationTargetException failure) {
            if (!(failure.getCause() instanceof IllegalStateException expectedFailure)
                    || !expectedFailure.getMessage().contains("Unexpected Display lifecycle")) throw failure;
        }
    }

    private static void changedCreationPublicationChecks(byte[] original, Map<String, Integer> expected) throws Exception {
        byte[] changed = ClassFile.of().transformClass(ClassFile.of().parse(original),
            ClassTransform.transformingMethodBodies(
                method -> method.methodName().equalsString("create") && method.methodType().equalsString("()V"),
                (builder, element) -> {
                    if (element instanceof FieldInstruction field && field.opcode() == Opcode.PUTSTATIC
                            && field.owner().asInternalName().equals("org/lwjglx/opengl/Display")
                            && field.name().equalsString("displayCreated")) builder.pop();
                    else builder.with(element);
                }));
        var transform = ToolkitWindowBootstrap.class.getDeclaredMethod("transformDisplay", byte[].class, Map.class);
        transform.setAccessible(true);
        try {
            transform.invoke(null, changed, expected);
            throw new AssertionError("Missing creation publication accepted");
        } catch (InvocationTargetException failure) {
            if (!(failure.getCause() instanceof IllegalStateException expectedFailure)
                    || !expectedFailure.getMessage().contains("Unexpected Display creation publication")) throw failure;
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
            "glfwDestroyWindow", official ? 3 : 2, "glfwPollEvents", 1, "creationViewport", 1);
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
        var lifecycleExpected = new HashMap<>(expected);
        lifecycleExpected.remove("creationViewport");
        changedLifecycleChecks(original, lifecycleExpected);
        changedCreationPublicationChecks(original, lifecycleExpected);
        creationCacheChecks(patched, official);
        creationObservationChecks();
        creationGuardChecks();
        viewportChecks();
        presentationChecks();
        ownedCreationSizeChecks();
        visibilityChecks();
        System.out.println("PASS exact hooks, verifier, unknown fingerprint and lifecycle-count rejection, agent definition, original resource preserved, fail-closed visibility tokens, pinned optimizer presentation, exact owned creation geometry, creation-cache transitions and publication order, observed viewport contracts; GLFW not initialized");
    }
}
