package net.alexredby.trialprobe;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.Properties;

/** Observes initial definitions after the optional optimizer, before ZombieBuddy. */
public final class TrialProbe implements ClassFileTransformer {
    private final String arm;
    private final Instrumentation instrumentation;
    private final Map<String, String> pending = new HashMap<>();
    private boolean failed;

    private TrialProbe(String arm, Instrumentation instrumentation) throws Exception {
        this.instrumentation = instrumentation;
        if (!"Control".equals(arm) && !"Optimized".equals(arm)) throw new IllegalArgumentException("Missing trial arm");
        this.arm = arm;
        Properties targets = new Properties();
        try (var stream = TrialProbe.class.getResourceAsStream(arm + ".properties")) {
            if (stream == null) throw new IllegalStateException("Missing trial class fingerprints");
            targets.load(stream);
        }
        if (targets.isEmpty()) throw new IllegalStateException("Empty trial class fingerprints");
        for (String name : targets.stringPropertyNames()) pending.put(name, targets.getProperty(name));
    }

    public static void premain(String args, Instrumentation instrumentation) throws Exception {
        var probe = new TrialProbe(System.getProperty("pz.optimizerTrial.arm"), instrumentation);
        instrumentation.addTransformer(probe);
        for (Class<?> loaded : instrumentation.getAllLoadedClasses()) {
            if (loaded.getClassLoader() == ClassLoader.getSystemClassLoader()) {
                probe.checkAlreadyLoaded(loaded.getName().replace('.', '/'));
            }
        }
    }

    private synchronized void checkAlreadyLoaded(String name) {
        if (pending.containsKey(name)) fail(name, "loaded before observer");
    }

    private void fail(String name, String reason) {
        failed = true;
        System.err.println("[OptimizerTrial] effective classes failed mode=" + arm + " class=" + name + " " + reason);
    }

    @Override
    public synchronized byte[] transform(ClassLoader loader, String name, Class<?> redefined,
                                         ProtectionDomain domain, byte[] bytes) {
        if (failed || loader != ClassLoader.getSystemClassLoader() || redefined != null) return null;
        String expected = pending.get(name);
        if (expected == null) return null;
        try {
            String actual = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
            if (!actual.equals(expected)) {
                fail(name, "unexpected SHA-256 " + actual);
            } else {
                pending.remove(name);
                if (pending.isEmpty()) {
                    instrumentation.removeTransformer(this);
                    System.out.println("[OptimizerTrial] effective classes verified mode=" + arm);
                }
            }
        } catch (Exception e) {
            fail(name, e.toString());
        }
        return null;
    }
}
