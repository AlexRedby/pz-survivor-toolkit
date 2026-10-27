package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaThread;
import sun.misc.Unsafe;
import zombie.Lua.LuaManager;
import zombie.characterTextures.BloodBodyPartType;
import zombie.characterTextures.BloodClothingType;
import zombie.core.Core;
import zombie.core.random.RandAbstract;
import zombie.core.random.RandLua;
import zombie.core.random.RandStandard;
import zombie.core.skinnedmodel.visual.ItemVisual;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.Clothing;
import zombie.inventory.types.InventoryContainer;
import zombie.network.GameClient;
import zombie.network.GameServer;

public final class ItemLaundryPropertiesChecks {
    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }

    private static final class NoRandom extends Random {
        @Override protected int next(int bits) { throw new AssertionError("laundry tagging consumed RNG"); }
    }

    private static Field field(Class<?> owner, String name) throws Exception {
        var field = owner.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    public static void main(String[] args) throws Exception {
        RandStandard.INSTANCE.init();
        RandLua.INSTANCE.init();
        Core.debug = false;
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemLaundryPropertiesChecks.class.getClassLoader());
        var bridge = Exposer.getClassesWithGlobalLuaMethod().stream()
            .filter(type -> type.getName().equals("net.alexredby.pztoolkitjavapatches.ItemLaundryProperties"))
            .findFirst().orElseThrow(() -> new AssertionError("ZombieBuddy did not discover the laundry bridge"));
        require(Path.of(bridge.getProtectionDomain().getCodeSource().getLocation().toURI())
            .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "bridge did not come from the built JAR");
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newTable();
        LuaManager.exposer = new LuaManager.Exposer(new KahluaConverterManager(), LuaManager.platform, LuaManager.env);
        Exposer.afterExposeAll();
        var function = LuaManager.env.rawget("toolkitItemLaundryDirty");
        require(function != null && ItemLaundryProperties.SUPPORTED, "laundry global or native bytecode support missing");
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;

        var unsafe = (Unsafe) field(Unsafe.class, "theUnsafe").get(null);
        var visualField = field(InventoryItem.class, "visual");
        var randomField = field(RandAbstract.class, "rand");
        var standardRandom = randomField.get(RandStandard.INSTANCE);
        var luaRandom = randomField.get(RandLua.INSTANCE);
        // Bare native objects isolate reads from constructors, appearance assets,
        // textures and the random draws performed by normal item construction.
        var clothing = (Clothing) unsafe.allocateInstance(Clothing.class);
        var bag = (InventoryContainer) unsafe.allocateInstance(InventoryContainer.class);
        var unrelated = (InventoryItem) unsafe.allocateInstance(InventoryItem.class);
        require(thread.call(function, new Object[]{null}) == null, "nil item was not unknown");
        require(thread.call(function, new Object[]{unrelated}) == null, "unmanaged item acquired laundry state");
        try {
            randomField.set(RandStandard.INSTANCE, new NoRandom());
            randomField.set(RandLua.INSTANCE, new NoRandom());
            for (boolean client : new boolean[]{false, true}) {
                GameClient.client = client;
                GameServer.server = !client;
                for (var item : List.of(clothing, bag)) {
                    item.setBloodClothingType(new ArrayList<>(List.of(BloodClothingType.Shirt)));
                    visualField.set(item, null);
                    require(Boolean.FALSE.equals(thread.call(function, new Object[]{item})), "absent visual invented stains");
                    require(visualField.get(item) == null, "laundry read initialized an ItemVisual");
                    require(ItemLaundryProperties.read(item, false) == null, "unsupported bytecode exposed stains");
                    var visual = new ItemVisual();
                    visualField.set(item, visual);
                    for (boolean blood : new boolean[]{false, true}) {
                        for (boolean dirt : new boolean[]{false, true}) {
                            visual.setBlood(BloodBodyPartType.Torso_Upper, blood ? 0.5f : 0);
                            visual.setDirt(BloodBodyPartType.Torso_Lower, dirt ? 0.5f : 0);
                            // Aggregate clothing values alone are not native admission.
                            if (item == clothing) { clothing.setDirtiness(100); clothing.setBloodLevel(100); }
                            require(Boolean.valueOf(blood || dirt).equals(thread.call(function, new Object[]{item})),
                                "covered-part visual stains differ from native laundry predicates");
                            require(visualField.get(item) == visual, "laundry read replaced the existing visual");
                            require(visual.getBlood(BloodBodyPartType.Torso_Upper) == (blood ? 127 / 255.0f : 0)
                                && visual.getDirt(BloodBodyPartType.Torso_Lower) == (dirt ? 127 / 255.0f : 0),
                                "laundry read changed physical stains");
                        }
                    }
                    visual.clear();
                    visual.setBlood(BloodBodyPartType.Foot_L, 1);
                    visual.setDirt(BloodBodyPartType.Foot_R, 1);
                    require(Boolean.FALSE.equals(thread.call(function, new Object[]{item})), "uncovered stains became laundry");
                    item.setBloodClothingType(new ArrayList<>());
                    require(Boolean.FALSE.equals(thread.call(function, new Object[]{item})), "empty coverage admitted stains");
                    item.setBloodClothingType(null);
                    require(Boolean.FALSE.equals(thread.call(function, new Object[]{item})), "absent coverage admitted stains");
                    require(visualField.get(item) == visual, "coverage checks changed visual state");
                }
            }
        } finally {
            randomField.set(RandStandard.INSTANCE, standardRandom);
            randomField.set(RandLua.INSTANCE, luaRandom);
            GameClient.client = false;
            GameServer.server = false;
        }
        System.out.println("ITEM_LAUNDRY_PROPERTIES_CHECKS_PASS (covered-part blood/dirt, clothing/bags, null visual, no RNG or visual writes, nil/unsupported, built-JAR global and Kahlua)");
        System.exit(0);
    }
}
