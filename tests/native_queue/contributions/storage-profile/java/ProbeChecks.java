package toolkit.inventorywork;

import java.lang.reflect.Field;
import me.zed_0xff.zombie_buddy.Patch;
import me.zed_0xff.zombie_buddy.PatchEngine;
import zombie.inventory.types.Food;
import zombie.GameTime;

/** Headless scope/error/thread guards; native weaving is calibrated by the Lua fixture. */
public final class ProbeChecks {
    private static void require(boolean result, String message) {
        if (!result) throw new AssertionError(message);
    }
    private static void rejects(Runnable callback) {
        try { callback.run(); } catch (IllegalStateException expected) { return; }
        throw new AssertionError("Observer accepted invalid scope");
    }
    public static void main(String[] args) throws Exception {
        rejects(Main::begin);
        Field owner = Main.class.getDeclaredField("owner"); owner.setAccessible(true);
        owner.set(null, Thread.currentThread());
        Field origin = Main.class.getDeclaredField("origin"); origin.setAccessible(true);
        origin.setLong(null, System.nanoTime());
        Main.foodAgeEntered();
        Main.begin(); require(Main.end() == 0, "Out-of-scope calls counted");
        rejects(Main::end);
        double start = Main.begin();
        rejects(Main::begin);
        Main.FoodAge.enter(); Main.FoodAge.enter();
        Thread background = new Thread(Main::foodAgeEntered);
        background.start(); background.join();
        require(Main.clockMs() >= start, "Clock moved backwards");
        require(Main.end() == 2, "Scope/thread count differs");
        Main.begin(); require(Main.end() == 0, "Counts leaked between renderer calls");
        Patch patch = Main.FoodAge.class.getAnnotation(Patch.class);
        require(patch.strictMatch() && patch.methodName().equals("updateAge")
                && patch.className().equals("zombie.inventory.types.Food")
                && Main.FoodAge.class.getDeclaredMethod("enter").getParameterCount() == 0,
                "Zero-argument strict native advice contract differs");
        if (args.length > 0 && args[0].equals("--woven")) wovenChecks();
        System.out.println("InventoryWorkProbe scope/thread/error checks passed");
    }
    private static void wovenChecks() throws Exception {
        PatchEngine.applyPatches("toolkit.inventorywork", ProbeChecks.class.getClassLoader());
        // A deliberately incomplete native receiver exercises real advice and
        // the native error path without starting any game/world/GUI lifecycle.
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe"); singleton.setAccessible(true);
        Food food = (Food) unsafeClass.getMethod("allocateInstance", Class.class).invoke(singleton.get(null), Food.class);
        GameTime.instance = null;
        Main.begin();
        try {
            food.updateAge();
            throw new AssertionError("Native error was suppressed");
        } catch (NullPointerException expected) {
            require(expected.getStackTrace()[0].getClassName().equals("zombie.inventory.types.Food"),
                    "Expected native Food failure");
        } finally { require(Main.end() == 1, "Woven zero-argument native entry count differs"); }
        Main.begin();
        try {
            food.updateAge(false);
            throw new AssertionError("Native boolean-overload error was suppressed");
        } catch (NullPointerException expected) {
            require(expected.getStackTrace()[0].getClassName().equals("zombie.inventory.types.Food"),
                    "Expected native boolean overload failure");
        } finally { require(Main.end() == 0, "Boolean native overload was counted"); }
        System.out.println("InventoryWorkProbe woven native overload/error calibration passed");
    }
}
