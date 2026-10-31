package toolkit.lootresolved.bootstrap;

import java.nio.file.*;

/** Headless admission checks only: no factory/world/success-path claim. */
public final class BootstrapChecks {
    public static void main(String[] args) throws Exception {
        Path cache = Path.of(args[0]);
        String scenario = args[1];
        if (scenario.equals("preload") && (!Bootstrap.active() || !Bootstrap.cache().equals(cache.toRealPath())))
            throw new AssertionError("Actual ZB-Preload entry/cache did not activate:" + Bootstrap.state());
        if (scenario.equals("already-loaded")) Class.forName("zombie.inventory.ItemPickerJava", false, BootstrapChecks.class.getClassLoader());
        boolean active = Bootstrap.install(cache);
        if (scenario.equals("missing-token")) {
            if (active || !Bootstrap.state().contains("owned-cache-opt-in")) throw new AssertionError(Bootstrap.state());
        } else if (scenario.equals("already-loaded")) {
            if (active || !Bootstrap.state().contains("already-loaded")) throw new AssertionError(Bootstrap.state());
        } else {
            if (!active) throw new AssertionError(Bootstrap.state());
            var random = zombie.core.random.RandAbstract.class.getDeclaredField("rand");
            random.setAccessible(true);
            random.set(zombie.core.random.RandStandard.INSTANCE,
                new org.uncommons.maths.random.CellularAutomatonRNG(new byte[]{7,19,31,43}));
            Bootstrap.beginRng();
            zombie.core.random.Rand.Next(1);
            Bootstrap.endRng();
            Bootstrap.beginRng();
            Thread worker = new Thread(() -> zombie.core.random.Rand.Next(1), "foreign-rng-check");
            worker.start(); worker.join();
            try { Bootstrap.endRng(); throw new AssertionError("foreign-thread RNG admitted"); }
            catch (IllegalStateException expected) {
                if (!expected.getMessage().equals("foreign-thread-native-RNG")) throw expected;
            }
            toolkit.lootresolved.runtime.RuntimeCleanupChecks.run();
        }
        System.out.println("LOOT_RESOLVED_BOOTSTRAP_CHECK_PASS " + Bootstrap.mode() + " " + scenario);
    }
}
