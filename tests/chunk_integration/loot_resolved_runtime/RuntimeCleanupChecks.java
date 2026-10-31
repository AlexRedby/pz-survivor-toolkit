package toolkit.lootresolved.runtime;

import java.lang.reflect.*;
import java.util.*;
import zombie.inventory.*;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.InstanceTracker;

/** Constructor-built cleanup check only. No game/factory/initialization success claim. */
public final class RuntimeCleanupChecks {
    private static Object value(String name) throws Exception {
        Field field = Main.class.getDeclaredField(name); field.setAccessible(true); return field.get(null);
    }
    @SuppressWarnings("unchecked")
    public static void run() throws Exception {
        zombie.ZomboidFileSystem.instance.setCacheDir(toolkit.lootresolved.bootstrap.Bootstrap.cache().toString());
        zombie.ZomboidFileSystem.instance.init(); // Native filesystem only; empty scratch cwd, no world.
        ItemContainer root = new ItemContainer("cleanup-check",null,null); root.setCapacity(100);
        InventoryContainer bag = new InventoryContainer("Base","FixtureBag","FixtureBag","Item_None");
        InventoryItem child = new InventoryItem("Base","FixtureChild","FixtureChild","Item_None");
        Map<String,Integer> baselines = (Map<String,Integer>)value("spawnBaselines");
        for (InventoryItem item : List.of(bag,child)) baselines.put(item.getFullType(),InstanceTracker.get("Item Spawns",item.getFullType()));
        if (ItemSpawner.spawnItem(bag,root,false) != bag || ItemSpawner.spawnItem(child,bag.getInventory(),false) != child)
            throw new AssertionError("native constructor-built insertion failed");
        ((List<ItemContainer>)value("roots")).add(root);
        ((Set<InventoryItem>)value("created")).addAll(List.of(bag,child));
        ((Set<InventoryItem>)value("inserted")).addAll(List.of(bag,child));
        Map<String,Integer> before = new HashMap<>(baselines);
        Method cleanup = Main.class.getDeclaredMethod("cleanup"); cleanup.setAccessible(true);
        cleanup.invoke(null);
        if (bag.getContainer() != null || child.getContainer() != null || !root.getItems().isEmpty() || !bag.getInventory().getItems().isEmpty())
            throw new AssertionError("cleanup retained container identity");
        for (var entry : before.entrySet())
            if (InstanceTracker.get("Item Spawns",entry.getKey()) != entry.getValue()) throw new AssertionError("native spawn counter not restored");
        if (!((Set<?>)value("created")).isEmpty() || !baselines.isEmpty()) throw new AssertionError("fixture retained identities");
        System.out.println("LOOT_RESOLVED_NATIVE_CLEANUP_CHECK_PASS constructor-items-only");
    }
}
