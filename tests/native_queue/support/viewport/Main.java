package net.alexredby.nativeviewport;

import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;

/** Disposable bridge to the common owned-window bootstrap; no rendering mutation. */
public final class Main {
    public static void main(String[] args) {
        if (!zombie.network.GameServer.server) return;
        try {
            ClassLoader loader = Main.class.getClassLoader();
            if (loader.getResource("pzopt/Config.class") != null)
                throw new IllegalStateException("client optimizer resource visible on Host server");
            for (Object key : System.getProperties().keySet())
                if (key instanceof String name && name.startsWith("pzopt."))
                    throw new IllegalStateException("optimizer property on Host server: " + name);
            java.util.Properties expected = new java.util.Properties();
            try (var in = loader.getResourceAsStream("native-optimizer-guards.properties")) {
                if (in == null) throw new IllegalStateException("missing native resource inventory");
                expected.load(in);
            }
            if (expected.isEmpty()) throw new IllegalStateException("empty native resource inventory");
            for (String name : expected.stringPropertyNames()) {
                try (var in = loader.getResourceAsStream(name)) {
                    if (in == null) throw new IllegalStateException("missing native resource " + name);
                    String sha = java.util.HexFormat.of().formatHex(
                        java.security.MessageDigest.getInstance("SHA-256").digest(in.readAllBytes()));
                    if (!expected.getProperty(name).equals(sha))
                        throw new IllegalStateException("non-native Host resource " + name);
                }
            }
            System.out.println("[OptimizerTrialProbe] native server resources=" + expected.size() + " overlayAbsent=true");
        } catch (Exception error) {
            System.err.println("[OptimizerTrialProbe] FAIL " + error);
            throw new IllegalStateException(error);
        }
    }

    @LuaMethod(name = "toolkitTestViewport", global = true)
    public static KahluaTable observe(int width, int height) throws Exception {
        int[] values = (int[]) Class.forName("ToolkitWindowBootstrap")
            .getMethod("observeViewport", int.class, int.class).invoke(null, width, height);
        KahluaTable result = LuaManager.platform.newTable();
        for (int i = 0; i < values.length; i++) result.rawset((double) (i + 1), (double) values[i]);
        return result;
    }
}
