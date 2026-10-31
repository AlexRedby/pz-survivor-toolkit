package toolkit.lootresolved.runtime;

import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import org.uncommons.maths.random.CellularAutomatonRNG;
import se.krka.kahlua.integration.annotations.LuaMethod;
import toolkit.lootresolved.bootstrap.Bootstrap;
import zombie.SandboxOptions;
import zombie.core.random.*;
import zombie.entity.GameEntity;
import zombie.entity.GameEntityManager;
import zombie.inventory.*;
import zombie.inventory.ItemPickerJava.*;
import zombie.inventory.types.*;
import zombie.iso.InstanceTracker;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemTag;

/** Real-game-only, explicitly invoked semantic bank. No world/stash/factory substitutes. */
public final class Main {
    private static String status = "not-run", scenario = "", callbackMode = "", failure = "";
    private static final StringBuilder rows = new StringBuilder("kind\tcase\tdetail\n");
    private static final List<ItemContainer> roots = new ArrayList<>();
    private static final Set<InventoryItem> created = Collections.newSetFromMap(new IdentityHashMap<>());
    private static final Set<InventoryItem> inserted = Collections.newSetFromMap(new IdentityHashMap<>());
    private static final Map<String,Integer> spawnBaselines = new TreeMap<>();
    private static ItemPickerItem nextPicker;
    private static boolean mutated, nesting, nestedDone;
    private static int accepts, fills, cases;
    private static Thread owner;
    private static volatile Throwable callbackFailure;
    public static void main(String[] args) {
        System.out.println("[LOOT_RESOLVED_RUNTIME] BRIDGE mode=" + Bootstrap.mode() + " state=" + Bootstrap.state());
    }
    @LuaMethod(name="lootResolvedRuntimeStatus", global=true)
    public static String status() { return status; }

    private static void require(boolean value, String message) {
        if (!value) throw new IllegalStateException(message);
    }
    private static Field field(Class<?> type, String name) throws Exception {
        Field field = type.getDeclaredField(name); field.setAccessible(true); return field;
    }
    private static void row(String kind, String text) {
        require(rows.length() < 1_000_000, "receipt-limit");
        rows.append(kind).append('\t').append(scenario).append('\t')
            .append(text.replace('\t',' ').replace('\r',' ').replace('\n',' ')).append('\n');
    }
    private static String bits(float value) { return Integer.toHexString(Float.floatToRawIntBits(value)); }
    private static void onOwner() { require(Thread.currentThread() == owner, "foreign-thread-fixture-callback"); }
    private static ItemContainer container(int capacity) {
        ItemContainer container = new ItemContainer("lootResolvedRuntime", null, null);
        container.setCapacity(capacity);
        container.setAcceptItemFunction("LootResolvedRuntimeAccept");
        roots.add(container);
        return container;
    }
    private static ItemPickerItem picker(String name) {
        ItemPickerItem item = new ItemPickerItem(); item.itemName = name; item.chance = Float.POSITIVE_INFINITY; return item;
    }
    private static ItemPickerContainer distribution(String... names) {
        ItemPickerContainer dist = new ItemPickerContainer();
        dist.rolls = 1; dist.ignoreZombieDensity = true;
        dist.items = Arrays.stream(names).map(Main::picker).toArray(ItemPickerItem[]::new);
        return dist;
    }
    private static void direct(ItemPickerContainer dist, ItemContainer out) {
        ItemPickerJava.doRollItem(dist, out, 0f, null, true, null);
    }
    private static InventoryContainer bag() {
        InventoryItem item = InventoryItemFactory.CreateItem("Base.Bag_Schoolbag");
        require(item instanceof InventoryContainer, "native-bag-factory");
        created.add(item);
        spawnBaselines.putIfAbsent(item.getFullType(), InstanceTracker.get("Item Spawns",item.getFullType()));
        InventoryContainer bag = (InventoryContainer)item;
        require(bag.isInitialised(), "native-bag-not-initialised");
        bag.getInventory().setAcceptItemFunction("LootResolvedRuntimeAccept");
        bag.getInventory().setCapacity(1000);
        roots.add(bag.getInventory());
        return bag;
    }
    @LuaMethod(name="lootResolvedRuntimeAccept", global=true)
    public static boolean accept(ItemContainer container, InventoryItem item) {
        try { return acceptInternal(container,item); }
        catch (Throwable problem) { callbackFailure = problem; throw new IllegalStateException("fixture-accept-failure",problem); }
    }
    private static boolean acceptInternal(ItemContainer container, InventoryItem item) {
        if (!"running".equals(status)) return true;
        onOwner();
        require(++accepts <= 512, "accept-limit");
        created.add(item);
        spawnBaselines.putIfAbsent(item.getFullType(), InstanceTracker.get("Item Spawns",item.getFullType()));
        row("ACCEPT", accepts + ":" + item.getFullType() + ":initialized=" + item.isInitialised());
        require(item.isInitialised(), "native-created-item-not-initialised");
        if (item instanceof InventoryContainer bag)
            bag.getInventory().setAcceptItemFunction("LootResolvedRuntimeAccept");
        if (!mutated && nextPicker != null) {
            if (callbackMode.equals("name")) {
                nextPicker.itemName = "Base.Bandage"; mutated = true;
                row("MUTATE", "next-name=Base.Bandage");
            } else if (callbackMode.equals("tags-options")) {
                Item script = ScriptManager.instance.FindItem("Base.Pen");
                script.getTags().add(ItemTag.IS_MEMENTO);
                SandboxOptions.instance.lootItemRemovalList.setValue("Base.Pen");
                mutated = true;
                row("MUTATE", "Pen-tag=" + script.getTags().contains(ItemTag.IS_MEMENTO)
                    + ":loot=" + ItemPickerJava.getLootType(script) + ":removed="
                    + SandboxOptions.instance.lootItemRemovalListContains("Base.Pen"));
            }
        }
        if (callbackMode.equals("deny") || callbackMode.equals("error")) return false;
        inserted.add(item);
        return true;
    }
    /** Forwarded by an actual native OnFillContainer Lua event handler; third arg varies natively. */
    @LuaMethod(name="lootResolvedRuntimeFill", global=true)
    public static void fill(Object room, Object name, Object target) {
        try { fillInternal(room,name,target); }
        catch (Throwable problem) { callbackFailure = problem; throw new IllegalStateException("fixture-fill-failure",problem); }
    }
    private static void fillInternal(Object room, Object name, Object target) {
        if (!"running".equals(status)) return;
        onOwner();
        require(++fills <= 128, "fill-limit");
        row("FILL", fills + ":" + String.valueOf(room) + ":" + String.valueOf(name)
            + ":target=" + (target == null ? "null" : target.getClass().getName()));
        if (callbackMode.equals("nested") && !nesting && !nestedDone) {
            nesting = true; nestedDone = true;
            try {
                row("NEST", "begin");
                ItemContainer inside = container(1000);
                direct(distribution("Base.Bandage"), inside);
                require(!inside.getItems().isEmpty(), "reentrant-native-roll-empty");
                snapshot(inside, "reentrant", 0);
                row("NEST", "end");
            } finally { nesting = false; }
        }
    }
    @LuaMethod(name="lootResolvedRuntimeWantsAcceptError", global=true)
    public static boolean wantsAcceptError() { return "running".equals(status) && callbackMode.equals("error"); }

    private static void snapshot(ItemContainer container, String prefix, int depth) {
        require(depth <= 8, "nested-content-depth");
        row("CONTAINER", prefix + ":count=" + container.getItems().size() + ":explored=" + container.isExplored());
        int i = 0;
        for (InventoryItem item : container.getItems()) {
            created.add(item);
            require(item.isInitialised(), "snapshot-item-not-initialised");
            String position = prefix + "/" + i++;
            String details = position + ":" + item.getClass().getName() + ":" + item.getFullType()
                + ":id=" + item.getID() + ":condition=" + item.getCondition() + ":age=" + bits(item.getAge())
                + ":uses=" + item.getUses() + ":current=" + item.getCurrentUses() + ":currentf=" + bits(item.getCurrentUsesFloat())
                + ":initialized=" + item.isInitialised();
            if (item instanceof Food food) details += ":heat=" + bits(food.getHeat()) + ":frozen=" + food.isFrozen();
            if (item.getFluidContainer() != null) {
                var fluids = item.getFluidContainer();
                details += ":fluid=" + bits(fluids.getAmount()) + "/" + bits(fluids.getCapacity());
                // Enumerating actual components avoids depending on a display/translation string.
                for (var fluid : zombie.entity.components.fluids.Fluid.getAllFluids()) {
                    float amount = fluids.getSpecificFluidAmount(fluid);
                    if (amount != 0) details += ":" + fluid.getFluidTypeString() + "=" + bits(amount);
                }
            }
            row("ITEM", details);
            if (item instanceof InventoryContainer bag) snapshot(bag.getInventory(), position, depth + 1);
        }
    }
    private static void collect(ItemContainer container, int depth) {
        require(depth <= 8,"cleanup-container-depth");
        for (InventoryItem item : new ArrayList<>(container.getItems())) {
            created.add(item);
            if (item instanceof InventoryContainer bag) collect(bag.getInventory(),depth + 1);
        }
    }
    private static void cleanup() throws Exception {
        // Gather and detach every child before resetting any InventoryContainer: its reset invokes
        // reset recursively on children, which must first have their own identities unregistered.
        for (ItemContainer container : roots) collect(container,0);
        for (InventoryItem item : new ArrayList<>(created))
            if (item instanceof InventoryContainer bag) collect(bag.getInventory(),0);
        Map<String,Integer> expectedSpawns = new TreeMap<>();
        for (InventoryItem item : inserted) expectedSpawns.merge(item.getFullType(),1,Integer::sum);
        for (InventoryItem item : created) {
            if (item.getContainer() != null) item.getContainer().Remove(item);
            require(item.getContainer() == null,"generated-container-retained");
        }
        for (ItemContainer container : roots) require(container.getItems().isEmpty(),"root-contents-retained");
        // Native AddItem unconditionally queues inserted items for processing. Remove does not
        // remove that queue entry; remove only the fixture's identities from both actual queues.
        var cell = zombie.iso.IsoWorld.instance.currentCell;
        if (cell != null) {
            cell.getProcessItems().removeIf(created::contains);
            cell.getProcessItemsRemove().removeIf(created::contains);
            require(Collections.disjoint(cell.getProcessItems(),created)
                && Collections.disjoint(cell.getProcessItemsRemove(),created),"generated-process-entry-retained");
        }
        Method unregister = GameEntityManager.class.getDeclaredMethod("UnregisterEntity", GameEntity.class);
        unregister.setAccessible(true);
        for (InventoryItem item : created) {
            String fullType = item.getFullType();
            long id = item.getEntityNetID();
            var registered = GameEntityManager.GetEntity(id);
            require(registered == null || registered == item, "generated-entity-id-collision");
            if (registered == item) unregister.invoke(null, item);
            item.reset();
            require(GameEntityManager.GetEntity(id) != item && !item.isAddedToEngine(), "generated-entity-retained");
            require(fullType.equals(item.getFullType()),"reset-changed-fulltype");
        }
        // Acceptance precedes insertion/inc. Check the actual native counter delta before reversing
        // anything, so a swallowed insertion error or another spawn cannot undercount the world.
        for (var entry : spawnBaselines.entrySet())
            require((long)InstanceTracker.get("Item Spawns",entry.getKey()) - entry.getValue()
                == expectedSpawns.getOrDefault(entry.getKey(),0),"spawn-counter-provenance:" + entry.getKey());
        for (var entry : expectedSpawns.entrySet()) {
            require(spawnBaselines.containsKey(entry.getKey()),"missing-spawn-counter-baseline");
            InstanceTracker.adj("Item Spawns",entry.getKey(),-entry.getValue());
            require(InstanceTracker.get("Item Spawns",entry.getKey()) == spawnBaselines.get(entry.getKey()),"spawn-counter-restore");
        }
        row("CLEANUP", "items=" + created.size() + ":inserted=" + inserted.size() + ":spawn-counters=verified:process-queues=clear");
        roots.clear(); created.clear(); inserted.clear(); spawnBaselines.clear();
    }
    private static void seeded(int number) throws Exception {
        field(RandAbstract.class, "rand").set(RandStandard.INSTANCE,
            new CellularAutomatonRNG(new byte[]{7,19,31,(byte)(43 + number)}));
        field(RandAbstract.class, "id").setInt(RandStandard.INSTANCE, 0);
    }
    private interface Work { void run() throws Exception; }
    private static void test(String name, String mode, Work work) throws Exception {
        scenario = name; callbackMode = mode; accepts = fills = 0; mutated = nestedDone = false; nextPicker = null;
        seeded(cases);
        row("BEGIN", "seed-index=" + cases + ":rolls-multiplier=" + SandboxOptions.instance.rollsMultiplier.getValue());
        try {
            work.run();
            require(callbackFailure == null, "native-protected-call-swallowed-fixture-failure:" + callbackFailure);
            row("END", "next-rng=" + Rand.Next(1_000_000) + ":accepts=" + accepts + ":fills=" + fills);
            cases++;
        } finally { cleanup(); }
    }
    @LuaMethod(name="lootResolvedRuntimeRun", global=true)
    public static synchronized boolean run() {
        if (!status.equals("not-run")) return status.equals("complete");
        Object savedRandom = null;
        int savedId = 0;
        String savedRemoval = null;
        Set<ItemTag> savedTags = null;
        Item pen = null;
        boolean rngStarted = false;
        status = "running"; owner = Thread.currentThread();
        try {
            require(Bootstrap.active() && Bootstrap.owned(Bootstrap.cache()), "bootstrap-not-admitted:" + Bootstrap.state());
            require(Path.of(zombie.ZomboidFileSystem.instance.getCacheDir()).toRealPath().equals(Bootstrap.cache()), "actual-cache-mismatch");
            require(Files.isRegularFile(Bootstrap.cache().resolve("Lua/smoke-user.txt"), LinkOption.NOFOLLOW_LINKS), "actual-cache-owned-marker");
            require(!GameClient.client || GameServer.server, "authority-required");
            require(!GameEntityManager.isEngineProcessing(), "entity-engine-processing");
            double rolls = SandboxOptions.instance.rollsMultiplier.getValue();
            require(Double.isFinite(rolls) && rolls >= 0 && rolls <= 16, "unsupported-rolls-multiplier");
            for (String name : new String[]{"Base.Nails", "Base.Bandage", "Base.Pen", "Base.Apple", "Base.WaterBottle", "Base.Bag_Schoolbag"})
                require(ScriptManager.instance.FindItem(name) != null, "missing-real-script:" + name);
            savedRandom = field(RandAbstract.class,"rand").get(RandStandard.INSTANCE);
            savedId = field(RandAbstract.class,"id").getInt(RandStandard.INSTANCE);
            savedRemoval = SandboxOptions.instance.lootItemRemovalList.getValue();
            pen = ScriptManager.instance.FindItem("Base.Pen"); savedTags = new HashSet<>(pen.getTags());
            Bootstrap.beginRng(); rngStarted = true;
            row("ENV", "authority=" + (GameServer.server ? "server" : "singleplayer") + ":thread=" + owner.getName());
            test("direct-real-items", "", () -> {
                ItemContainer out = container(1000);
                direct(distribution("Nails", "Base.Bandage", "Base.Apple", "Base.WaterBottle"), out);
                require(out.getItems().size() >= 4 && accepts >= 4, "direct-success-count");
                snapshot(out,"direct",0);
            });
            test("bag-real-items", "", () -> {
                InventoryContainer bag = bag();
                ItemPickerJava.rollContainerItem(bag, null, distribution("Nails", "Base.Bandage", "Base.Pen"));
                require(bag.getInventory().getItems().size() >= 3 && accepts >= 3, "bag-success-count");
                snapshot(bag.getInventory(),"bag",0);
            });
            test("accept-mutates-next-name", "name", () -> {
                ItemContainer out = container(1000); ItemPickerContainer dist = distribution("Base.Nails", "Base.Pen"); nextPicker = dist.items[1];
                direct(dist,out);
                require(mutated && out.getItems().stream().anyMatch(i -> i.getFullType().equals("Base.Bandage")), "next-name-mutation-not-observed");
                require(out.getItems().stream().noneMatch(i -> i.getFullType().equals("Base.Pen")), "stale-next-name");
                snapshot(out,"mutated",0);
            });
            test("accept-mutates-tags-options", "tags-options", () -> {
                ItemContainer out = container(1000); ItemPickerContainer dist = distribution("Base.Nails", "Base.Pen"); nextPicker = dist.items[1];
                direct(dist,out);
                require(mutated && out.getItems().stream().noneMatch(i -> i.getFullType().equals("Base.Pen")), "live-removal-not-observed");
                snapshot(out,"removed",0);
            });
            SandboxOptions.instance.lootItemRemovalList.setValue(savedRemoval);
            pen.getTags().clear(); pen.getTags().addAll(savedTags);
            test("native-nested-fill-reentrant", "nested", () -> {
                ItemContainer out = container(1000);
                ItemPickerContainer dist = distribution("Base.Bag_Schoolbag"); dist.bags = distribution("Base.Nails");
                direct(dist,out);
                require(fills > 0 && nestedDone, "actual-native-fill-event-not-observed");
                require(out.getItems().stream().anyMatch(i -> i instanceof InventoryContainer b && !b.getInventory().getItems().isEmpty()), "native-nested-bag-empty");
                snapshot(out,"nested",0);
            });
            test("native-denied", "deny", () -> {
                ItemContainer out = container(1000); direct(distribution("Base.Nails", "Base.Pen"),out);
                require(out.getItems().isEmpty() && accepts == 1, "denied-native-order"); snapshot(out,"denied",0);
            });
            test("native-full", "", () -> {
                ItemContainer out = container(0); direct(distribution("Base.Nails", "Base.Pen"),out);
                require(out.getItems().isEmpty() && accepts == 0, "full-native-order"); snapshot(out,"full",0);
            });
            test("native-accept-error", "error", () -> {
                ItemContainer out = container(1000); direct(distribution("Base.Nails", "Base.Pen"),out);
                require(out.getItems().isEmpty() && accepts == 1, "error-native-order"); snapshot(out,"error",0);
            });
            require(Bootstrap.active(), "bootstrap-invalidated-during-bank:" + Bootstrap.state());
            status = "complete";
        } catch (Throwable problem) {
            failure = problem.toString(); status = "failed";
            problem.printStackTrace();
        } finally {
            try {
                if (!created.isEmpty() || !roots.isEmpty()) cleanup();
            } catch (Throwable problem) { failure += ";cleanup:" + problem; status = "failed"; }
            try {
                if (pen != null && savedTags != null) { pen.getTags().clear(); pen.getTags().addAll(savedTags); }
                if (savedRemoval != null) SandboxOptions.instance.lootItemRemovalList.setValue(savedRemoval);
            } catch (Throwable problem) { failure += ";script-option-restore:" + problem; status = "failed"; }
            try {
                if (savedRandom != null && created.isEmpty() && roots.isEmpty()) {
                    field(RandAbstract.class,"rand").set(RandStandard.INSTANCE,savedRandom);
                    field(RandAbstract.class,"id").setInt(RandStandard.INSTANCE,savedId);
                }
                else if (savedRandom != null) throw new IllegalStateException("RNG restore withheld: generated item cleanup failed");
            } catch (Throwable problem) { failure += ";rng-restore:" + problem; status = "failed"; }
            try {
                if (rngStarted) Bootstrap.endRng();
            } catch (Throwable problem) { failure += ";rng-ownership:" + problem; status = "failed"; }
            try {
                require(Bootstrap.cache() != null && Bootstrap.owned(Bootstrap.cache()), "receipt-cache-guard");
                Bootstrap.writeActivation();
                Files.writeString(Bootstrap.cache().resolve("loot-resolved-runtime.tsv"),rows);
                Files.writeString(Bootstrap.cache().resolve("loot-resolved-runtime-status.txt"),
                    "status=" + status + "\nmode=" + Bootstrap.mode() + "\npid=" + ProcessHandle.current().pid() + "\ncases=" + cases + "\nreason=" + failure.replace('\n',' ') + "\n"
                    + "source_square=uncovered\nlive_script_reload=uncovered\nmodule_item_replacement=uncovered\n");
            } catch (Throwable problem) { status = "failed"; failure += ";receipt:" + problem; }
            owner = null;
            System.out.println("[LOOT_RESOLVED_RUNTIME] FINISH status=" + status + " cases=" + cases + " reason=" + failure);
        }
        return status.equals("complete");
    }
}
