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
    static final Map<String, String> TARGETS = Map.of(
        "zombie/Lua/LuaEventManager", "event",
        "zombie/gameStates/GameLoadingState", "load",
        "zombie/GameWindow", "frame");

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
                boolean[] found = {false};
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access, String method, String descriptor, String signature, String[] exceptions) {
                        String wanted = name.endsWith("LuaEventManager") ? "triggerEvent" : name.endsWith("GameWindow") ? "frameStep" : "enter";
                        if (!method.equals(wanted) || (name.endsWith("LuaEventManager") && !descriptor.equals("(Ljava/lang/String;)V"))) return null;
                        return new MethodVisitor(Opcodes.ASM9) {
                            @Override public void visitMethodInsn(int opcode, String owner, String method, String descriptor, boolean itf) {
                                if (owner.equals("net/alexredby/optimizertrial/Main") && method.equals(TARGETS.get(name))) found[0] = true;
                            }
                        };
                    }
                }, ClassReader.SKIP_DEBUG);
                observed.put(name, found[0]);
                return null;
            }
        };
        instrumentation.addTransformer(observer, true);
        try {
            for (String name : TARGETS.keySet()) {
                Class<?> type = Class.forName(name.replace('/', '.'), false, BridgeChecks.class.getClassLoader());
                instrumentation.retransformClasses(type);
                require(Boolean.TRUE.equals(observed.get(name)), "ZombieBuddy did not weave " + name);
            }
            java.util.List<String> helpers = new java.util.ArrayList<>();
            for (Class<?> type : instrumentation.getAllLoadedClasses()) {
                if (type.getName().startsWith("pzopt.")) helpers.add(type.getName());
                require(!java.util.Set.of("pzopt.BootAsync", "pzopt.AnimalPreload", "pzopt.UpdateBatch", "pzopt.AnimBatch").contains(type.getName()),
                    "optimizer execution subsystem unexpectedly loaded: " + type.getName());
            }
            java.util.Collections.sort(helpers);
            System.out.println("WEAVING_OFFICIAL_INITIALIZERS " + helpers);
        } finally { instrumentation.removeTransformer(observer); }
        System.out.println("ZOMBIEBUDDY_WEAVING_PASS nativeTargets=3 lateLuaEventRetransform=true bootAfterModels=true preloadSubsystemsLoaded=0");
    }
}
