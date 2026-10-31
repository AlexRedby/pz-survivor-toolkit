package toolkit.lootresolved.bootstrap;

import java.nio.file.*;
import java.util.Properties;

/** Headless admission checks only: no factory/world/success-path claim. */
public final class BootstrapChecks {
    private static void refusedProfile(Runnable work) {
        try { work.run(); throw new AssertionError("unreviewed runtime profile admitted"); }
        catch (IllegalStateException expected) { }
    }
    private static void profileChecks() throws Exception {
        if (Bootstrap.runtimeProfileChecked()) throw new AssertionError("profile checked during premain");
        if (!Bootstrap.optimizerManifest().equals("none")) {
            refusedProfile(() -> Bootstrap.verifyRuntimeProfile(false,false));
            Properties profile = new Properties();
            try (var in = Bootstrap.class.getResourceAsStream("optimizer-profile.properties")) { profile.load(in); }
            for (String key : profile.stringPropertyNames()) System.setProperty(key,profile.getProperty(key));
            Bootstrap.verifyRuntimeProfile(false,false);
            String key = "pzopt.entityUpdateParallel", original = System.getProperty(key);
            System.setProperty(key, original.equals("true") ? "false" : "true");
            refusedProfile(() -> Bootstrap.verifyRuntimeProfile(false,false));
            System.setProperty(key,original);
            System.setProperty("pzopt.unreviewedLootFixtureOption","false");
            refusedProfile(() -> Bootstrap.verifyRuntimeProfile(false,false));
            System.clearProperty("pzopt.unreviewedLootFixtureOption");
            refusedProfile(() -> Bootstrap.verifyRuntimeProfile(true,false));
            Bootstrap.verifyRuntimeProfile(false,false);
        } else {
            Bootstrap.verifyRuntimeProfile(false,false);
            System.setProperty("pzopt.unreviewedLootFixtureOption","false");
            refusedProfile(() -> Bootstrap.verifyRuntimeProfile(false,false));
            System.clearProperty("pzopt.unreviewedLootFixtureOption");
            Bootstrap.verifyRuntimeProfile(false,false);
        }
        System.out.println("LOOT_RESOLVED_RUNTIME_PROFILE_CHECK_PASS " + Bootstrap.resourceProfile());
    }
    /** Pure selector/ownership tests. These do not run or claim a real Host server. */
    private static void selectorChecks(Path cache) throws Exception {
        Path owned = cache.resolve("selector-owned"); Files.createDirectory(owned);
        Files.writeString(owned.resolve("smoke-user.txt"),"owned-selector-check\n");
        Files.writeString(owned.resolve(Bootstrap.OPT_IN),Bootstrap.text("token.txt") + "\n");
        Path marker = owned.resolve(Bootstrap.HOST_AUTHORITY);
        if (!Bootstrap.selectResourceProfile(owned,"zombie.network.GameServer",true).equals("optimized-client"))
            throw new AssertionError("missing Host marker admitted");
        Files.writeString(marker,"wrong-token\n");
        if (!Bootstrap.selectResourceProfile(owned,"zombie.network.GameServer",true).equals("optimized-client"))
            throw new AssertionError("foreign Host marker admitted");
        Files.writeString(marker,Bootstrap.text("token.txt") + "\n");
        for (String command : new String[]{"ToolkitSmokeLauncher zombie.network.GameServer","zombie.network.GameServerOther", ""})
            if (!Bootstrap.selectResourceProfile(owned,command,true).equals("optimized-client")) throw new AssertionError("foreign main admitted");
        if (!Bootstrap.selectResourceProfile(owned,"zombie.network.GameServer --fixture",true).equals("native-host"))
            throw new AssertionError("explicit owned Host selector refused");
        Files.writeString(owned.resolve(Bootstrap.OPT_IN),"wrong-token\n");
        if (!Bootstrap.selectResourceProfile(owned,"zombie.network.GameServer",true).equals("optimized-client"))
            throw new AssertionError("foreign cache admitted");
        Files.writeString(owned.resolve(Bootstrap.OPT_IN),Bootstrap.text("token.txt") + "\n");
        Files.delete(marker); Files.createSymbolicLink(marker,owned.resolve(Bootstrap.OPT_IN));
        if (!Bootstrap.selectResourceProfile(owned,"zombie.network.GameServer",true).equals("optimized-client"))
            throw new AssertionError("symlink Host marker admitted");
        if (!Bootstrap.selectResourceProfile(owned,"zombie.network.GameServer",false).equals("native"))
            throw new AssertionError("native fixture role changed");
        System.out.println("LOOT_RESOLVED_HOST_SELECTOR_CHECK_PASS pure-selector-only");
    }
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
            profileChecks();
            selectorChecks(cache);
            RngScopeChecks.run();
            toolkit.lootresolved.runtime.RuntimeCleanupChecks.run();
        }
        System.out.println("LOOT_RESOLVED_BOOTSTRAP_CHECK_PASS " + Bootstrap.mode() + " " + scenario);
    }
}
