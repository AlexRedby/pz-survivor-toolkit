package toolkit.lootresolved.bootstrap;

/** ZombieBuddy's explicit ZB-Preload entry point; never enabled by the ordinary mod alone. */
public final class PreMain {
    public static void premain(String[] args) {
        String config = me.zed_0xff.zombie_buddy.Agent.arguments.get("config_dir");
        if (config == null) {
            System.out.println("[LOOT_RESOLVED_RUNTIME] ACTIVATION disabled:missing-explicit-agent-config-dir");
            return;
        }
        java.nio.file.Path directory = java.nio.file.Path.of(config).toAbsolutePath().normalize();
        if (directory.getParent() == null || !directory.getFileName().toString().equals("zombie-buddy")) {
            System.out.println("[LOOT_RESOLVED_RUNTIME] ACTIVATION disabled:agent-config-dir-contract");
            return;
        }
        Bootstrap.install(directory.getParent());
    }
}
