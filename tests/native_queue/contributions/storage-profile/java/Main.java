package toolkit.inventorywork;

import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.network.GameServer;

/** Disposable counter only: native Food.updateAge() always executes unchanged. */
public final class Main {
    public static void main(String[] args) {
        System.out.println("[INVENTORY_WORK_PROBE] HELPER_READY inert_until_owned_scope=true");
    }

    private static Thread owner;
    private static boolean scoped;
    private static long calls, origin;

    @LuaMethod(name="inventoryWorkProbeInit", global=true)
    public static boolean init() throws Exception {
        String expected = System.getenv("PZ_INVENTORY_WORK_TEST_CACHE");
        if (expected == null || GameServer.server || !"MainThread".equals(Thread.currentThread().getName()))
            throw new IllegalStateException("Owned inventory-work client required");
        Path actual = Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath();
        Path marker = actual.resolve("Lua/smoke-user.txt");
        if (!Path.of(expected).isAbsolute() || !Path.of(expected).toRealPath().equals(actual)
                || !Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS) || Files.size(marker) > 1024
                || !"client1".equals(Files.readString(marker).trim()))
            throw new IllegalStateException("Owned inventory-work cache/marker required");
        if (owner != null || scoped) throw new IllegalStateException("One observer initialization required");
        owner = Thread.currentThread(); origin = System.nanoTime();
        return true;
    }

    private static void owned() {
        if (owner == null || Thread.currentThread() != owner)
            throw new IllegalStateException("Initialized observer owner required");
    }

    @LuaMethod(name="inventoryWorkProbeClockMs", global=true)
    public static double clockMs() {
        owned();
        return (System.nanoTime() - origin) / 1_000_000.0;
    }

    @LuaMethod(name="inventoryWorkProbeBegin", global=true)
    public static double begin() {
        owned();
        if (scoped) throw new IllegalStateException("Nested renderer observer scope");
        calls = 0; scoped = true;
        return clockMs();
    }

    @LuaMethod(name="inventoryWorkProbeEnd", global=true)
    public static double end() {
        owned();
        if (!scoped) throw new IllegalStateException("Missing renderer observer scope");
        scoped = false;
        return calls;
    }

    public static void foodAgeEntered() {
        // No clock, allocation, stack inspection or gameplay mutation per item.
        if (scoped && Thread.currentThread() == owner) calls++;
    }

    // strictMatch plus zero-parameter advice selects updateAge(), excluding
    // updateAge(boolean). The latter is called by the zero-argument method.
    @Patch(className="zombie.inventory.types.Food", methodName="updateAge", strictMatch=true)
    public static class FoodAge {
        @Patch.OnEnter public static void enter() { Main.foodAgeEntered(); }
    }
}
