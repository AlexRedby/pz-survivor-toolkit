package net.alexredby.optimizertrial;

import java.io.InputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.ProtectionDomain;
import java.util.HashMap;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.bytebuddy.jar.asm.*;

/** Native class/resource and actual ZombieBuddy weaving checks; no game loop, world, UI or optimizer methods run. */
public final class BridgeChecks {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static final Map<String, Map<String, String>> TARGETS = Map.of(
        "zombie/Lua/LuaEventManager", Map.of("triggerEvent", "event"),
        "zombie/gameStates/GameLoadingState", Map.of("enter", "load"),
        "zombie/GameWindow", Map.of("frameStep", "frame"),
        "zombie/core/skinnedmodel/advancedanimation/AnimationSet", Map.of("Reset", "animationReset"),
        "zombie/gameStates/IngameState", Map.of("enter", "worldEntered", "exit", "worldExited"),
        "zombie/gameStates/ServerDisconnectState", Map.of("enter", "disconnected"));

    public static final class TelemetryEnv {
        public Object observer;
        public Object rawget(Object name) { return "PZOptimizerTrialTelemetryFlush".equals(name) ? observer : null; }
    }
    public static final class TelemetryLua {
        public static Object env, caller = new Object(), thread = new Object();
        static final StringBuilder calls = new StringBuilder();
        public static void call(String name, Object reason) { calls.append(name).append(':').append(reason).append(';'); }
    }

    /** Exercise bridge decisions with inert stand-ins; never invoke an official preload or native world method. */
    public static final class BoundaryChecks {
        public static boolean client, server, interruptJoin;
        static final StringBuilder calls = new StringBuilder();
        public static void start() { calls.append("start;"); }
        public static void join() { calls.append("join;"); if (interruptJoin) Thread.currentThread().interrupt(); }
        public static void animal() { calls.append("animal;"); }
        public static void drain() { calls.append("drain;"); }

        static void set(String name, Object value) throws Exception {
            var field = Main.class.getDeclaredField(name); field.setAccessible(true); field.set(null, value);
        }
        static boolean enabled() throws Exception {
            var field = Main.class.getDeclaredField("enabled"); field.setAccessible(true); return field.getBoolean(null);
        }
        static void reset(String mode) throws Exception {
            for (String name : new String[]{"animationStarted", "clientResetSeen", "loadingStarted", "worldActive", "sessionEnded",
                    "tileProofNeeded", "bakeProofNeeded", "drainObserved", "exitingWorld"}) set(name, false);
            set("enabled", true); set("booted", true); set("mode", mode); set("gameThread", Thread.currentThread());
            set("clientMode", BoundaryChecks.class.getField("client")); set("serverMode", BoundaryChecks.class.getField("server"));
            set("startAnim", BoundaryChecks.class.getMethod("start")); set("joinAnim", BoundaryChecks.class.getMethod("join"));
            set("startAnimal", BoundaryChecks.class.getMethod("animal")); set("drainAnimal", BoundaryChecks.class.getMethod("drain"));
            set("telemetryLua", TelemetryLua.class);
            set("telemetryHookReady", true);
            client = server = interruptJoin = false; calls.setLength(0);
        }
        static void run() throws Exception {
            require(Main.launchMode("singleplayer").equals("singleplayer") && Main.launchMode("multiplayer").equals("multiplayer"), "supported modes");
            for (String invalid : new String[]{"", "Multiplayer", "host", " multiplayer"}) {
                try { Main.launchMode(invalid); throw new AssertionError("accepted mode=" + invalid); }
                catch (IllegalArgumentException expected) { /* exact mode contract */ }
            }
            reset("multiplayer");
            Main.event("OnGameBoot"); Main.frame();
            require(enabled() && calls.isEmpty(), "MP menu boot ran preloads or drain");
            client = true;
            Main.event("OnGameBoot");
            require(enabled() && calls.isEmpty(), "MP client flag without native reset ran preloads");
            Main.animationReset(); Main.event("OnGameBoot"); Main.frame();
            require(enabled() && calls.toString().equals("start;"), "MP post-reset boot did not start exactly once");
            Main.load(); Main.frame();
            require(enabled() && calls.toString().equals("start;join;animal;"), "load order or pre-world drain");
            set("worldActive", true); Main.frame();
            require(calls.toString().equals("start;join;animal;drain;"), "active MP world did not drain");
            Main.worldExited(); Main.animationReset(); Main.event("OnGameBoot"); Main.worldExitCompleted(); Main.frame();
            require(enabled() && calls.toString().equals("start;join;animal;drain;"), "session end drained or disabled normal exit");
            Main.load(); require(!enabled(), "second world accepted stale preload state");

            reset("multiplayer"); client = true; Main.load();
            require(!enabled() && calls.isEmpty(), "MP missing session preload was accepted");
            reset("multiplayer"); client = true; Main.animationReset(); Main.event("OnGameBoot"); Main.animationReset();
            require(!enabled() && calls.toString().equals("start;"), "reset after preload did not require restart");
            reset("multiplayer"); client = true; Main.animationReset(); Main.event("OnGameBoot"); Main.event("OnGameBoot");
            require(!enabled() && calls.toString().equals("start;"), "repeated boot reused preload state");
            reset("multiplayer"); client = true; Main.animationReset(); Main.event("OnGameBoot"); Main.load(); Main.load();
            require(!enabled() && calls.toString().equals("start;join;animal;"), "second load reran helpers");
            reset("singleplayer"); Main.event("OnGameBoot"); Main.load();
            require(enabled() && calls.toString().equals("start;join;animal;"), "SP lifecycle changed");
            reset("singleplayer"); client = true; Main.event("OnGameBoot");
            require(!enabled() && calls.isEmpty(), "SP mode accepted MP session");
            reset("multiplayer"); client = true; server = true; Main.event("OnGameBoot");
            require(!enabled() && calls.isEmpty(), "server process accepted");
            reset("multiplayer"); client = true; Main.animationReset(); Main.event("OnGameBoot"); interruptJoin = true; Main.load();
            require(!enabled() && calls.toString().equals("start;join;") && Thread.interrupted(), "interrupted join ran animal start");
            reset("multiplayer"); Main.worldEntered();
            require(!enabled() && calls.isEmpty(), "world without loading accepted");
            reset("multiplayer"); client = true; Main.worldEntered();
            require(!enabled() && calls.isEmpty(), "client world without loading accepted");
            require(Main.worldReady(null, new Object()) && !Main.worldReady(null, null), "native world cell gate");
            var release = new java.util.concurrent.CountDownLatch(1);
            Thread loading = new Thread(() -> { try { release.await(); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); } });
            loading.start();
            try { require(!Main.worldReady(loading, new Object()), "live native loader accepted"); }
            finally { release.countDown(); loading.join(); }
            require(Main.worldReady(loading, new Object()), "finished native loader rejected");
            set("enabled", false);
            TelemetryLua.env = null; Main.worldExited(); Main.disconnected();
            require(TelemetryLua.calls.isEmpty(), "missing Lua environment did not no-op");
            var env = new TelemetryEnv(); TelemetryLua.env = env;
            Main.worldExited(); Main.disconnected();
            require(TelemetryLua.calls.isEmpty(), "missing observer did not no-op");
            env.observer = new Object(); Main.worldExited(); Main.disconnected();
            require(TelemetryLua.calls.toString().equals("PZOptimizerTrialTelemetryFlush:WorldExit;PZOptimizerTrialTelemetryFlush:Disconnect;"),
                "disabled/control bridge did not flush live observer before exits");
            set("telemetryHookReady", false); Main.worldExited(); Main.disconnected();
            require(TelemetryLua.calls.toString().equals("PZOptimizerTrialTelemetryFlush:WorldExit;PZOptimizerTrialTelemetryFlush:Disconnect;"),
                "unverified lifecycle invoked telemetry observer");
            set("telemetryHookReady", true);
            TelemetryLua.env = new TelemetryEnv(); Main.worldExited(); Main.disconnected();
            require(TelemetryLua.calls.toString().equals("PZOptimizerTrialTelemetryFlush:WorldExit;PZOptimizerTrialTelemetryFlush:Disconnect;"),
                "bridge reused an observer from the previous Lua environment");
            reset("singleplayer"); set("enabled", false); set("booted", false); set("gameThread", null);
            set("clientMode", null); set("serverMode", null);
            System.out.println("CLIENT_LIFECYCLE_BOUNDARIES_PASS modes=exact mpPostReset=true server=closed repeatSession=closed preWorldDrain=closed interrupt=closed");
            System.out.println("TELEMETRY_EXIT_BOUNDARIES_PASS disabledBridgeFlush=true missingObserver=noop liveEnvironment=true unverifiedLifecycle=closed");
        }
    }

    static final class PropertiesCheck {
        static void run() {
            var pins = Main.properties("optimizer-trial-profile.properties");
            System.setProperty("pz.optimizerTrial.profile", Main.PROFILE);
            for (String key : pins.stringPropertyNames()) System.setProperty("pzopt." + key, pins.getProperty(key));
            Main.verifyProfile();
            System.setProperty("pzopt.unreviewedFutureFlag", "true");
            try { Main.verifyProfile(); throw new AssertionError("accepted extra pin"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("unknown"), expected.toString()); }
            finally { System.clearProperty("pzopt.unreviewedFutureFlag"); }
            for (String key : pins.stringPropertyNames()) {
                System.clearProperty("pzopt." + key);
                try { Main.verifyProfile(); throw new AssertionError("accepted missing pin " + key); }
                catch (IllegalStateException expected) { require(expected.getMessage().contains("differs"), expected.toString()); }
                System.setProperty("pzopt." + key, pins.getProperty(key));
            }
            // Retain the exact inactive-simulation profile for official class initialization during retransformation.
            // prewarm remains unset: no optimizer algorithm or game loop is invoked.
            System.out.println("PROFILE_GATES_PASS pins=" + pins.size());
        }
    }

    static void nativeClientOrder() throws Exception {
        boolean[] reset = {false}, mods = {false}, models = {false}, boot = {false}, ordered = {false};
        try (InputStream in = BridgeChecks.class.getClassLoader().getResourceAsStream("zombie/core/Core.class")) {
            new ClassReader(in).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access, String method, String descriptor, String signature, String[] exceptions) {
                    if (!method.equals("ResetLua") || !descriptor.equals("(Ljava/lang/String;Ljava/lang/String;)V")) return null;
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitLdcInsn(Object value) { if ("OnGameBoot".equals(value)) boot[0] = true; }
                        @Override public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean itf) {
                            if (owner.equals("zombie/core/skinnedmodel/advancedanimation/AnimationSet") && name.equals("Reset")) reset[0] = true;
                            if (owner.equals("zombie/ZomboidFileSystem") && name.equals("loadMods")) mods[0] = reset[0];
                            if (owner.equals("zombie/core/skinnedmodel/ModelManager") && name.equals("loadModAnimations")) models[0] = mods[0];
                            if (owner.equals("zombie/Lua/LuaEventManager") && name.equals("triggerEvent") && boot[0]) ordered[0] = models[0];
                        }
                    };
                }
            }, ClassReader.SKIP_DEBUG);
        }
        require(ordered[0], "native client reset no longer reloads mods/models before OnGameBoot");
        boolean[] client = {false}, reason = {false}, connection = {false};
        try (InputStream in = BridgeChecks.class.getClassLoader().getResourceAsStream("zombie/gameStates/ConnectToServerState.class")) {
            new ClassReader(in).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access, String method, String descriptor, String signature, String[] exceptions) {
                    if (!method.equals("receiveServerOptions")) return null;
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitLdcInsn(Object value) {
                            if ("client".equals(value)) client[0] = true;
                            if ("ConnectedToServer".equals(value)) reason[0] = true;
                        }
                        @Override public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean itf) {
                            if (owner.equals("zombie/core/Core") && name.equals("ResetLua")) connection[0] = client[0] && reason[0];
                        }
                    };
                }
            }, ClassReader.SKIP_DEBUG);
        }
        require(connection[0], "native connection no longer resets client Lua before loading");
        boolean[] assigned = {false}, started = {false}, cleared = {false};
        try (InputStream in = BridgeChecks.class.getClassLoader().getResourceAsStream("zombie/gameStates/GameLoadingState.class")) {
            new ClassReader(in).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access, String method, String descriptor, String signature, String[] exceptions) {
                    if (!method.equals("enter") && !method.equals("exit")) return null;
                    return new MethodVisitor(Opcodes.ASM9) {
                        boolean nullValue;
                        @Override public void visitInsn(int opcode) { nullValue = opcode == Opcodes.ACONST_NULL; }
                        @Override public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
                            if (owner.equals("zombie/gameStates/GameLoadingState") && name.equals("loader") && opcode == Opcodes.PUTSTATIC) {
                                if (method.equals("enter")) assigned[0] = true;
                                if (method.equals("exit") && nullValue) cleared[0] = true;
                            }
                        }
                        @Override public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean itf) {
                            if (method.equals("enter") && owner.equals("java/lang/Thread") && name.equals("start")) started[0] = assigned[0];
                        }
                    };
                }
            }, ClassReader.SKIP_DEBUG);
        }
        require(started[0] && cleared[0], "native loader no longer starts in enter and clears in exit");
        System.out.println("NATIVE_CLIENT_ORDER_PASS connectionReset=true animationResetBeforeMods=true postResetBootAfterModels=true loadingThreadLifecycle=true");
    }

    static void lifecycleInventories(ClassLoader optimized) throws Exception {
        Main.verifyLifecycle(optimized, true);
        var connection = BridgeChecks.class.getClassLoader().getResource("zombie/gameStates/ServerDisconnectState.class").openConnection();
        require(connection instanceof java.net.JarURLConnection, "native lifecycle resource must come from the game JAR");
        var nativeJar = ((java.net.JarURLConnection) connection).getJarFileURL();
        try (URLClassLoader nativeOnly = new URLClassLoader(new java.net.URL[]{nativeJar}, ClassLoader.getPlatformClassLoader())) {
            Main.verifyLifecycle(nativeOnly, false);
            try { Main.verifyLifecycle(nativeOnly, true); throw new AssertionError("optimized gate accepted native lifecycle bytes"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("original class hash"), expected.toString()); }
            try { Main.verifyLifecycle(optimized, false); throw new AssertionError("control gate accepted optimized lifecycle bytes"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("original class hash"), expected.toString()); }
            ClassLoader changed = new ClassLoader(nativeOnly) {
                @Override public InputStream getResourceAsStream(String name) {
                    return name.equals("zombie/GameWindow.class") ? new java.io.ByteArrayInputStream(new byte[]{0}) : super.getResourceAsStream(name);
                }
            };
            try { Main.verifyLifecycle(changed, false); throw new AssertionError("control accepted changed lifecycle class"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("original class hash"), expected.toString()); }
            ClassLoader missing = new ClassLoader(nativeOnly) {
                @Override public InputStream getResourceAsStream(String name) {
                    return name.equals("zombie/gameStates/ServerDisconnectState.class") ? null : super.getResourceAsStream(name);
                }
            };
            try { Main.verifyLifecycle(missing, false); throw new AssertionError("control accepted missing lifecycle class"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("original class hash"), expected.toString()); }
        }
        // Exercise the actual no-opt-in main with native resources, without game class initialization.
        var bridgeJar = Main.class.getProtectionDomain().getCodeSource().getLocation();
        try (URLClassLoader control = new URLClassLoader(new java.net.URL[]{bridgeJar, nativeJar}, ClassLoader.getPlatformClassLoader())) {
            Class<?> bridge = Class.forName(Main.class.getName(), true, control);
            bridge.getMethod("main", String[].class).invoke(null, (Object) new String[0]);
            var ready = bridge.getDeclaredField("telemetryHookReady"); ready.setAccessible(true);
            var enabled = bridge.getDeclaredField("enabled"); enabled.setAccessible(true);
            require(ready.getBoolean(null) && !enabled.getBoolean(null), "native inactive bridge did not verify lifecycle independently of optimizer");
        }
        System.out.println("LIFECYCLE_INVENTORIES_PASS nativeControl=true optimized=true crossProfile=closed nativeMutation=closed nativeMissing=closed");
    }

    public static void main(String[] args) throws Exception {
        Path archive = Path.of(args[0]), overlay = Path.of(args[1]), cache = Path.of(args[2]);
        require(!Boolean.getBoolean("pz.optimizerTrial.prewarm"), "checks must never arm optimizer execution");
        Main.main(new String[0]);
        Main.event("OnGameBoot"); Main.load(); Main.frame();
        try (URLClassLoader resources = new URLClassLoader(new java.net.URL[]{overlay.toUri().toURL()}, BridgeChecks.class.getClassLoader()) {
            @Override public java.net.URL getResource(String name) {
                java.net.URL own = findResource(name);
                return own == null ? super.getResource(name) : own;
            }
        }) {
            ClassLoader noForeignLoads = new ClassLoader(resources) {
                @Override protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
                    if (name.startsWith("pzopt.")) throw new AssertionError("foreign class loaded: " + name);
                    return super.loadClass(name, resolve);
                }
            };
            Main.verifyResources(noForeignLoads, archive, cache);
            lifecycleInventories(noForeignLoads);
            Files.createDirectories(cache.resolve("Lua"));
            Path flags = cache.resolve("Lua/pzopt-harness.txt"); Files.writeString(flags, "mode=drive\n");
            try { Main.verifyResources(noForeignLoads, archive, cache); throw new AssertionError("accepted harness state"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("automation state"), expected.toString()); }
            finally { Files.delete(flags); }
            ClassLoader changed = new ClassLoader(resources) {
                @Override public InputStream getResourceAsStream(String name) {
                    if (name.equals("zombie/GameWindow.class")) return new java.io.ByteArrayInputStream(new byte[]{0});
                    return super.getResourceAsStream(name);
                }
            };
            try { Main.verifyResources(changed, archive, cache); throw new AssertionError("accepted changed native class"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("original class hash"), expected.toString()); }
            ClassLoader changedHelper = new ClassLoader(resources) {
                @Override public InputStream getResourceAsStream(String name) {
                    if (name.equals("pzopt/BootAsync.class")) return new java.io.ByteArrayInputStream(new byte[]{0});
                    return super.getResourceAsStream(name);
                }
            };
            try { Main.verifyResources(changedHelper, archive, cache); throw new AssertionError("accepted changed helper"); }
            catch (IllegalStateException expected) { require(expected.getMessage().contains("official resource mismatch"), expected.toString()); }
        }
        PropertiesCheck.run();
        BoundaryChecks.run();
        nativeClientOrder();
        var enabledField = Main.class.getDeclaredField("enabled"); enabledField.setAccessible(true);
        enabledField.setBoolean(null, true);
        Main.load();
        require(!enabledField.getBoolean(null), "missing boot event did not close the preload gate");
        var bootedField = Main.class.getDeclaredField("booted"); bootedField.setAccessible(true);
        var threadField = Main.class.getDeclaredField("gameThread"); threadField.setAccessible(true);
        bootedField.setBoolean(null, true); threadField.set(null, new Thread()); enabledField.setBoolean(null, true);
        Main.frame();
        require(!enabledField.getBoolean(null), "wrong lifecycle thread did not close the preload gate");
        bootedField.setBoolean(null, false); threadField.set(null, null);
        System.out.println("LIFECYCLE_GATES_PASS missingBoot=closed wrongThread=closed");
        System.out.println("RESOURCE_GATES_PASS positive=888 nativeMutation=closed helperMutation=closed harnessState=closed foreignLoads=0");
        byte[] window;
        try (InputStream in = BridgeChecks.class.getClassLoader().getResourceAsStream("zombie/GameWindow.class")) { window = in.readAllBytes(); }
        boolean[] model = {false}, boot = {false}, valid = {false};
        new ClassReader(window).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                if (!name.equals("enter")) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitLdcInsn(Object value) { if ("OnGameBoot".equals(value)) boot[0] = true; }
                    @Override public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean itf) {
                        if (owner.equals("zombie/core/skinnedmodel/ModelManager") && name.equals("create")) model[0] = true;
                        if (owner.equals("zombie/Lua/LuaEventManager") && name.equals("triggerEvent") && boot[0]) valid[0] = model[0];
                    }
                };
            }
        }, ClassReader.SKIP_DEBUG);
        require(valid[0], "native OnGameBoot no longer follows ModelManager.create");
        var instrumentationField = Loader.class.getDeclaredField("g_instrumentation"); instrumentationField.setAccessible(true);
        Instrumentation instrumentation = (Instrumentation) instrumentationField.get(null);
        require(instrumentation != null, "launch checks with the real ZombieBuddy javaagent");
        // Define LuaEventManager before registration, reproducing late retransformation. No method is invoked.
        Class.forName("zombie.Lua.LuaEventManager", false, BridgeChecks.class.getClassLoader());
        PatchEngine.applyPatches("net.alexredby.optimizertrial", BridgeChecks.class.getClassLoader());
        Map<String, Boolean> observed = new HashMap<>();
        ClassFileTransformer observer = new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader, String name, Class<?> type, ProtectionDomain domain, byte[] bytes) {
                if (!TARGETS.containsKey(name)) return null;
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access, String method, String descriptor, String signature, String[] exceptions) {
                        String wanted = TARGETS.get(name).get(method);
                        if (wanted == null || (name.endsWith("LuaEventManager") && !descriptor.equals("(Ljava/lang/String;)V"))) return null;
                        return new MethodVisitor(Opcodes.ASM9) {
                            boolean sawBridge;
                            @Override public void visitMethodInsn(int opcode, String owner, String method, String descriptor, boolean itf) {
                                if (owner.equals("net/alexredby/optimizertrial/Main") && method.equals(wanted)) {
                                    sawBridge = true;
                                    observed.put(name + "/" + wanted, true);
                                }
                                if (name.equals("zombie/gameStates/IngameState") && owner.equals("net/alexredby/optimizertrial/Main") && method.equals("worldExitCompleted"))
                                    observed.put(name + "/worldExitCompleted", true);
                                if (name.equals("zombie/gameStates/ServerDisconnectState") && owner.equals("zombie/Lua/LuaEventManager") && method.equals("ResetCallbacks"))
                                    observed.put(name + "/flushBeforeReset", sawBridge);
                            }
                        };
                    }
                }, ClassReader.SKIP_DEBUG);
                return null;
            }
        };
        instrumentation.addTransformer(observer, true);
        try {
            for (String name : TARGETS.keySet()) {
                Class<?> type = Class.forName(name.replace('/', '.'), false, BridgeChecks.class.getClassLoader());
                instrumentation.retransformClasses(type);
                for (String method : TARGETS.get(name).values())
                    require(Boolean.TRUE.equals(observed.get(name + "/" + method)), "ZombieBuddy did not weave " + name + "/" + method);
            }
            java.util.List<String> helpers = new java.util.ArrayList<>();
            require(Boolean.TRUE.equals(observed.get("zombie/gameStates/IngameState/worldExitCompleted")), "ZombieBuddy did not weave exit completion");
            require(Boolean.TRUE.equals(observed.get("zombie/gameStates/ServerDisconnectState/flushBeforeReset")), "disconnect flush is not before native callback reset");
            for (Class<?> type : instrumentation.getAllLoadedClasses()) {
                if (type.getName().startsWith("pzopt.")) helpers.add(type.getName());
                require(!java.util.Set.of("pzopt.BootAsync", "pzopt.AnimalPreload", "pzopt.UpdateBatch", "pzopt.AnimBatch").contains(type.getName()),
                    "optimizer execution subsystem unexpectedly loaded: " + type.getName());
            }
            java.util.Collections.sort(helpers);
            System.out.println("WEAVING_OFFICIAL_INITIALIZERS " + helpers);
        } finally { instrumentation.removeTransformer(observer); }
        System.out.println("ZOMBIEBUDDY_WEAVING_PASS nativeTargets=6 nativeMethods=7 lateLuaEventRetransform=true bootAfterModels=true disconnectFlushBeforeReset=true preloadSubsystemsLoaded=0");
    }
}
