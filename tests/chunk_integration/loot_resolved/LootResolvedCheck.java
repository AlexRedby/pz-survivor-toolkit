import com.sun.management.ThreadMXBean;
import java.lang.reflect.Method;
import zombie.core.random.Rand;
import zombie.core.random.RandAbstract;
import zombie.core.random.RandStandard;
import org.uncommons.maths.random.CellularAutomatonRNG;
import zombie.inventory.ItemPickInfo;
import zombie.inventory.ItemPickerJava.ItemPickerContainer;
import zombie.inventory.ItemPickerJava.ItemPickerRoom;
import zombie.inventory.types.InventoryContainer;
import zombie.entity.ComponentType;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.locks.LockSupport;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.ZomboidFileSystem;
import zombie.inventory.ItemContainer;
import zombie.inventory.ItemPickerJava;
import zombie.inventory.ItemPickerJava.ItemPickerItem;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemTag;
import zombie.scripting.objects.ItemType;
import zombie.scripting.objects.ScriptModule;

/**
 * Headless consumer of the external game classes; no native implementation is reproduced.
 * Uses native default constructors and explicit options, not a loaded game script/mod pack.
 * Run from an empty scratch directory with an owned absolute -Dpz.test.cache directory.
 */
public final class LootResolvedCheck {
    private static ItemContainer container;
    private static final List<Vector> vectors = new ArrayList<>();
    private static volatile long sink;
    private static int reportedVectors;

    private record Vector(String label, ItemPickerItem picker, float density, boolean junk) {
        float run() {
            return ItemPickerJava.pztest$iteration(picker, null, container, density, junk);
        }
    }

    public static void main(String[] args) throws Exception {
        boolean measure = List.of(args).contains("--measure");
        resetRandom();
        String cacheProperty = System.getProperty("pz.test.cache");
        require(cacheProperty != null && Path.of(cacheProperty).isAbsolute(),
            "supply an owned absolute -Dpz.test.cache directory");
        Files.createDirectories(Path.of(cacheProperty));
        require(!Files.exists(Path.of("media")), "run from an empty scratch directory");
        ZomboidFileSystem.instance.setCacheDir(cacheProperty);
        ZomboidFileSystem.instance.init();
        container = new ItemContainer();
        SandboxOptions options = SandboxOptions.instance;
        options.maximumDiminishedLoot.setValue(0);
        GameTime.instance = new GameTime();
        ScriptManager manager = ScriptManager.instance;
        ScriptModule base = module(manager, "Base");
        ScriptModule imports = module(manager, "Imported");
        ScriptModule consumer = module(manager, "Consumer");
        consumer.imports.add("Imported");
        map(manager, "moduleAliases").put("Alias", "Imported");
        Item ordinary = item(manager, base, "Ordinary", true);
        Item fallback = item(manager, base, "Fallback", false);
        Item imported = item(manager, imports, "ImportedItem", false);
        Item food = item(manager, base, "FreshFood", true);
        field(Item.class, "itemType").set(food, ItemType.FOOD);
        Item tagged = item(manager, base, "Tagged", true);
        tags(tagged).add(ItemTag.MORE_WHEN_NO_ZOMBIES);
        Item ignore = item(manager, base, "IgnoreDensity", true);
        tags(ignore).add(ItemTag.IGNORE_ZOMBIE_DENSITY);
        // Distinct modifiers make category changes observable without Lua or script loading.
        field(ItemPickerJava.class, "otherLootModifier").setFloat(null, 0.625f);
        field(ItemPickerJava.class, "foodLootModifier").setFloat(null, 1.75f);
        field(ItemPickerJava.class, "cannedFoodLootModifier").setFloat(null, 1.125f);
        field(ItemPickerJava.class, "ammoLootModifier").setFloat(null, 0.3125f);
        options.zombies.setValue(3);
        options.zombieConfig.populationMultiplier.setValue(1.0);
        options.lootItemRemovalList.setValue("");

        for (String name : new String[]{"Base.Ordinary", "Ordinary", "Base.Fallback",
                "Alias.ImportedItem", "Consumer.ImportedItem", "Imported.ImportedItem",
                "Missing", "Base.Missing", "Base.OrdinaryEmpty", "Base.MissingEmpty",
                "Base.FreshFood", "Base.Tagged", "Base.IgnoreDensity"}) {
            add(name, name, 0.137f, 7.125f, false);
            add(name + "/junk", name, 0.137f, 7.125f, true);
        }
        // Verify the intended native lookup paths before timing or comparing outputs.
        require(manager.FindItem("Base.Ordinary") == ordinary, "fulltype lookup");
        require(manager.FindItem("Base.Fallback") == fallback, "module lookup");
        require(manager.FindItem("Alias.ImportedItem") == imported, "alias lookup");
        require(manager.FindItem("Consumer.ImportedItem") == imported, "import lookup");
        require(!items(manager).hasFullType("Base.Fallback"), "fallback must bypass fulltype map");
        for (Vector vector : vectors) report(vector);
        // A modifier-only Empty fallback must never become the original item for base/density.
        options.zombies.setValue(6);
        report(new Vector("empty-fallback-more-with-no-zombies", picker("Base.TaggedEmpty", 0.137f), 7.125f, false));
        report(new Vector("empty-fallback-ignore-density", picker("Base.IgnoreDensityEmpty", 0.137f), 7.125f, false));
        item(manager, base, "TaggedEmpty", true);
        report(new Vector("existing-empty-original-wins", picker("Base.TaggedEmpty", 0.137f), 7.125f, false));
        options.zombies.setValue(3);
        for (float chance : new float[]{0f, -0f, Float.MIN_VALUE, 0.1f, 1f, -2.75f,
                Float.MAX_VALUE, Float.POSITIVE_INFINITY, Float.NaN}) {
            report(new Vector("float/" + Integer.toHexString(Float.floatToRawIntBits(chance)),
                picker("Base.Ordinary", chance), 0.375f, false));
        }
        for (float density : new float[]{0f, -0f, -3.25f, Float.MIN_VALUE, Float.MAX_VALUE}) {
            report(new Vector("density/" + Integer.toHexString(Float.floatToRawIntBits(density)),
                picker("Base.Tagged", 0.137f), density, false));
        }
        Vector mutable = new Vector("mutable", picker("Base.Ordinary", 0.137f), 7.125f, false);
        options.lootItemRemovalList.setValue("Base.Ordinary");
        report("removed-fulltype", mutable);
        report(new Vector("removed-fulltype/junk", mutable.picker, 7.125f, true));
        options.lootItemRemovalList.setValue("Ordinary");
        report("removed-shortname", mutable);
        options.lootItemRemovalList.setValue("");
        report("removal-cleared", mutable);
        tags(ordinary).add(ItemTag.MORE_WHEN_NO_ZOMBIES);
        options.zombies.setValue(6);
        report("tag-added/no-zombies", mutable);
        options.zombies.setValue(3);
        options.zombieConfig.populationMultiplier.setValue(0.0);
        report("population-zero", mutable);
        options.zombieConfig.populationMultiplier.setValue(1.0);
        report("population-restored", mutable);
        tags(ordinary).clear();
        report("tag-removed", mutable);
        ordinary.displayCategory = "Ammo";
        report("category-ammo", mutable);
        ordinary.displayCategory = null;
        report("category-restored", mutable);
        tags(ordinary).add(ItemTag.IGNORE_ZOMBIE_DENSITY);
        report("ignore-density-added", mutable);
        tags(ordinary).clear();
        report("ignore-density-removed", mutable);
        options.maximumDiminishedLoot.setValue(37);
        options.daysUntilMaximumDiminishedLoot.setValue(0);
        report("sandbox-diminished-loot", mutable);
        options.maximumDiminishedLoot.setValue(0);
        Item replacement = item(manager, base, "Ordinary", true);
        tags(replacement).add(ItemTag.MORE_WHEN_NO_ZOMBIES);
        options.zombies.setValue(6);
        report("fulltype-replaced", mutable);
        Item fallbackReplacement = item(manager, base, "Fallback", false);
        tags(fallbackReplacement).add(ItemTag.MORE_WHEN_NO_ZOMBIES);
        report(new Vector("module-replaced", picker("Base.Fallback", 0.137f), 7.125f, false));
        base.items.getScriptMap().put("Ordinary", ordinary);
        items(manager).getFullTypeToScriptMap().put("Base.Ordinary", ordinary);
        base.items.getScriptMap().put("Fallback", fallback);
        options.zombies.setValue(3);
        report("fulltype-restored", mutable);
        require(reportedVectors == 59, "unexpected regression vector count: " + reportedVectors);
        for (String category : new String[]{"Memento", "FirstAid", "VehicleMaintenance", "Material", "Gardening",
                "Tool", "Cooking", "Fishing", "Food", "Ammo", "Bag", "SkillBook", "RecipeResource", null}) {
            ordinary.displayCategory = category;
            report("live-category/" + category, mutable);
        }
        ordinary.displayCategory = null;
        for (ItemTag tag : new ItemTag[]{ItemTag.GENERATOR, ItemTag.IS_MEMENTO, ItemTag.FARMING_LOOT,
                ItemTag.AMMO_CASE, ItemTag.FIREARM_LOOT, ItemTag.KEY_RING}) {
            tags(ordinary).add(tag);
            report("live-tag/" + tag.getTranslationName(), mutable);
            tags(ordinary).remove(tag);
            report("live-tag-removed/" + tag.getTranslationName(), mutable);
        }
        ordinary.medical = true;
        ordinary.displayCategory = "Tool";
        report("precedence-medical-over-tool", mutable);
        tags(ordinary).add(ItemTag.GENERATOR);
        report("precedence-generator-over-medical", mutable);
        tags(ordinary).clear(); ordinary.medical = false; ordinary.displayCategory = null;
        nativeRolls(manager, base, ordinary);
        exceptions();
        resetRandom();
        Group[] groups = benchmarkGroups(manager, base, imports);
        verifyGroups(groups);
        if (measure) measure(groups);
    }

    private static void add(String label, String name, float chance, float density, boolean junk) {
        vectors.add(new Vector(label, picker(name, chance), density, junk));
    }

    private static ItemPickerItem picker(String name, float chance) {
        ItemPickerItem picker = new ItemPickerItem();
        picker.itemName = name;
        picker.chance = chance;
        return picker;
    }

    private static ScriptModule module(ScriptManager manager, String name) throws Exception {
        ScriptModule module = new ScriptModule();
        module.name = name;
        manager.moduleMap.put(name, module);
        manager.moduleList.add(module);
        items(manager).registerModule(module);
        return module;
    }

    private static Item item(ScriptManager manager, ScriptModule module, String name, boolean fulltype) throws Exception {
        Item item = new Item();
        item.setModule(module);
        item.setName(name);
        module.items.getScriptMap().put(name, item);
        if (fulltype) items(manager).getFullTypeToScriptMap().put(item.getFullName(), item);
        return item;
    }

    @SuppressWarnings("unchecked")
    private static ScriptBucketCollection<Item> items(ScriptManager manager) throws Exception {
        return (ScriptBucketCollection<Item>)field(ScriptManager.class, "items").get(manager);
    }

    @SuppressWarnings("unchecked")
    private static Set<ItemTag> tags(Item item) throws Exception {
        return (Set<ItemTag>)field(Item.class, "itemTags").get(item);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, String> map(Object target, String name) throws Exception {
        return (Map<String, String>)field(target.getClass(), name).get(target);
    }

    private static Field field(Class<?> owner, String name) throws Exception {
        Field field = owner.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static void report(Vector vector) { report(vector.label, vector); }

    private static void report(String label, Vector vector) {
        System.out.printf(Locale.ROOT, "VECTOR %s %08x%n", label,
            bits(vector));
        System.out.printf(Locale.ROOT, "VECTOR %s/rng %08x%n", label, Rand.Next(1_000_000));
        reportedVectors++;
    }


    private static int bits(Vector vector) {
        int expected = Float.floatToRawIntBits(ItemPickerJava.getActualSpawnChance(
            vector.picker, null, container, vector.density, vector.junk));
        int actual = Float.floatToRawIntBits(vector.run());
        require(expected == actual, "direct native parity failed: " + vector.label);
        return actual;
    }

    private static void resetRandom() throws Exception {
        // Native CA RNG, deterministic seed. Do not substitute java.util.Random for the native RNG.
        byte[] seed = new byte[4];
        seed[0] = 7; seed[1] = 19; seed[2] = 31; seed[3] = 43;
        field(RandAbstract.class, "rand").set(RandStandard.INSTANCE, new CellularAutomatonRNG(seed));
        field(RandAbstract.class, "id").setInt(RandStandard.INSTANCE, 0);
    }

    private static void exceptions() {
        for (String name : new String[]{null, ""}) {
            ItemPickerItem picker = picker(name, 0.5f);
            String nativeError = outcome(() -> ItemPickerJava.getActualSpawnChance(picker, null, container, 1f, false));
            String bridgeError = outcome(() -> new Vector("exception", picker, 1f, false).run());
            require(nativeError.equals(bridgeError), "exception mismatch " + name + ": " + nativeError + "/" + bridgeError);
            System.out.println("VECTOR exception/" + name + " " + nativeError);
        }
    }
    private interface Calculation { float run(); }
    private static String outcome(Calculation work) {
        try { return "value/" + Integer.toHexString(Float.floatToRawIntBits(work.run())); }
        catch (Throwable error) {
            if (error instanceof AssertionError && error.getCause() != null) error = error.getCause();
            return error.getClass().getName();
        }
    }

    private static void nativeRolls(ScriptManager manager, ScriptModule base, Item ordinary) throws Exception {
        Method direct = ItemPickerJava.class.getDeclaredMethod("doRollItemInternal", ItemPickInfo.class,
            ItemPickerContainer.class, ItemContainer.class, float.class, zombie.characters.IsoGameCharacter.class,
            boolean.class, ItemPickerRoom.class, boolean.class);
        direct.setAccessible(true);
        Item fluid = item(manager, base, "FluidFixture", true);
        fluid.getComponentScripts().add(ComponentType.FluidContainer.CreateComponentScript());
        require(fluid.containsComponent(ComponentType.FluidContainer), "valid native Empty-fluid fixture");
        fluid.obsolete = true;
        ordinary.obsolete = true;
        for (String name : new String[]{"Base.Ordinary", "Base.Missing", "Base.FluidFixtureEmpty"}) {
            for (float chance : new float[]{Float.NEGATIVE_INFINITY, Float.POSITIVE_INFINITY}) {
                ItemPickerContainer dist = new ItemPickerContainer();
                dist.items = new ItemPickerItem[]{picker(name, chance), picker("Base.Ordinary", chance)};
                dist.rolls = 2f;
                resetRandom();
                direct.invoke(null, null, dist, container, 0.0f, null, false, null, false);
                require(container.getItems().isEmpty(), "obsolete/missing roll unexpectedly created contents");
                System.out.println("VECTOR native-doRoll/" + name + "/" + chance + " next=" + Rand.Next(1_000_000));
            }
        }
        // This uses a native constructor and native bag loop; it does not instantiate loot.
        InventoryContainer bag = new InventoryContainer("Base", "Fixture", "Fixture", "Item_None");
        Method nested = ItemPickerJava.class.getDeclaredMethod("rollContainerItemInternal", ItemPickInfo.class,
            InventoryContainer.class, zombie.characters.IsoGameCharacter.class, ItemPickerContainer.class, boolean.class);
        nested.setAccessible(true);
        for (String name : new String[]{"Base.Ordinary", "Base.Missing", "Base.FluidFixtureEmpty", "Base.OrdinaryEmpty"}) {
            for (float chance : new float[]{Float.NEGATIVE_INFINITY, Float.POSITIVE_INFINITY}) {
                ItemPickerContainer dist = new ItemPickerContainer();
                dist.items = new ItemPickerItem[]{picker(name, chance), picker("Base.Ordinary", chance)};
                dist.rolls = 2f; dist.ignoreZombieDensity = true;
                resetRandom();
                nested.invoke(null, null, bag, null, dist, false);
                require(bag.getInventory().getItems().isEmpty(), "bag roll unexpectedly created contents");
                System.out.println("VECTOR native-bagRoll/" + name + "/" + chance + " next=" + Rand.Next(1_000_000));
            }
        }
        ordinary.obsolete = false;
    }

    private record Group(String label, Vector[] inputs, String scope) { }

    private static Group[] benchmarkGroups(ScriptManager manager, ScriptModule base, ScriptModule imported)
            throws Exception {
        // Deliberately synthetic equal-coverage data. These weights are NOT gameplay frequencies.
        String[] categories = {null, "Memento", "FirstAid", "VehicleMaintenance", "Material", "Gardening",
            "Tool", "Cooking", "Fishing", "Food", "Ammo", "Bag", "SkillBook", "RecipeResource"};
        ItemTag[] tagKinds = {ItemTag.GENERATOR, ItemTag.IS_MEMENTO, ItemTag.FARMING_LOOT, ItemTag.AMMO_CASE,
            ItemTag.FIREARM_LOOT, ItemTag.KEY_RING, ItemTag.IGNORE_ZOMBIE_DENSITY, ItemTag.MORE_WHEN_NO_ZOMBIES};
        float[] chances = {0f, 0.01f, 0.05f, 0.137f, 0.5f, 1f, 2.5f, 10f};
        String[] modifierFields = {"otherLootModifier", "mementoLootModifier", "medicalLootModifier",
            "mechanicsLootModifier", "materialLootModifier", "farmingLootModifier", "toolLootModifier",
            "cookwareLootModifier", "survivalGearsLootModifier", "cannedFoodLootModifier", "foodLootModifier",
            "ammoLootModifier", "weaponLootModifier", "rangedWeaponLootModifier", "keyLootModifier",
            "containerLootModifier", "skillBookLootModifier", "recipeResourceLootModifier",
            "literatureLootModifier", "clothingLootModifier", "mediaLootModifier"};
        for (int i = 0; i < modifierFields.length; i++)
            field(ItemPickerJava.class, modifierFields[i]).setFloat(null, 0.25f + i * 0.0625f);
        SandboxOptions.instance.lootItemRemovalList.setValue("");
        SandboxOptions.instance.maximumDiminishedLoot.setValue(0);
        SandboxOptions.instance.zombies.setValue(3);
        SandboxOptions.instance.zombieConfig.populationMultiplier.setValue(1.0);
        Vector[] shortNames = new Vector[64], fullNames = new Vector[64], stress = new Vector[64];
        for (int i = 0; i < 64; i++) {
            String name = String.format(Locale.ROOT, "BenchItem%02d", i);
            Item script = item(manager, base, name, true);
            script.displayCategory = categories[i % categories.length];
            script.medical = i % 11 == 0;
            script.mechanicsItem = i % 13 == 0;
            script.survivalGear = i % 17 == 0;
            for (int tag = 0; tag < i % 4; tag++) tags(script).add(tagKinds[(i + tag) % tagKinds.length]);
            ItemType type = switch (i % 8) {
                case 1 -> ItemType.FOOD;
                case 2 -> ItemType.WEAPON;
                case 3 -> ItemType.CLOTHING;
                case 4 -> ItemType.LITERATURE;
                default -> ItemType.NORMAL;
            };
            field(Item.class, "itemType").set(script, type);
            require(items(manager).hasFullType("Base." + name), "loaded fulltype map fixture");
            float chance = chances[i % chances.length], density = (i % 5) * 1.375f;
            boolean junk = i % 4 == 0;
            shortNames[i] = new Vector(name, picker(name, chance), density, junk);
            fullNames[i] = new Vector("Base." + name, picker("Base." + name, chance), density, junk);
            String stressName;
            if (i % 4 < 2) stressName = i % 4 == 0 ? "Base." + name : name;
            else {
                Item copy = item(manager, imported, name, true);
                copy.displayCategory = script.displayCategory;
                copy.medical = script.medical;
                copy.mechanicsItem = script.mechanicsItem;
                copy.survivalGear = script.survivalGear;
                tags(copy).addAll(tags(script));
                field(Item.class, "itemType").set(copy, type);
                stressName = (i % 4 == 2 ? "Alias." : "Consumer.") + name;
            }
            stress[i] = new Vector(stressName, picker(stressName, chance), density, junk);
        }
        String[] absent = {"AbsentBench", "Base.AbsentBench", "BenchItem11Empty", "Base.BenchItem11Empty",
            "Base.BenchItem00Empty", "Base.FluidFixtureEmpty", "Base.NoSuchBenchEmpty", "NoSuchBenchEmpty"};
        Vector[] fallback = new Vector[64];
        for (int i = 0; i < fallback.length; i++) {
            String name = absent[i % absent.length];
            require(manager.FindItem(name) == null, "fallback control must have null original: " + name);
            fallback[i] = new Vector(name, picker(name, chances[(i / absent.length) % chances.length]),
                (i % 5) * 1.375f, i % 4 == 0);
        }
        return new Group[]{
            new Group("varied-unqualified-base", shortNames, "primary-synthetic-short-name-coverage"),
            new Group("single-unqualified-base", new Vector[]{shortNames[20]}, "constant-input-control"),
            new Group("varied-fulltype", fullNames, "qualified-lookup-control"),
            new Group("lookup-stress", stress, "artificial-equal-four-way-lookup-stress"),
            new Group("missing-empty-control", fallback, "unchanged-original-null-paths")};
    }

    private static void verifyGroups(Group[] groups) throws Exception {
        for (Group group : groups) {
            System.out.println("GROUP " + group.label + " " + group.inputs.length + " " + group.scope);
            for (int i = 0; i < group.inputs.length; i++) {
                Vector vector = group.inputs[i];
                int expected = Float.floatToRawIntBits(ItemPickerJava.getActualSpawnChance(
                    vector.picker, null, container, vector.density, vector.junk));
                resetRandom();
                int nativeBits = Float.floatToRawIntBits(ItemPickerJava.pztest$iterationNative(
                    vector.picker, null, container, vector.density, vector.junk));
                int nativeNext = Rand.Next(1_000_000);
                resetRandom();
                int resolvedBits = Float.floatToRawIntBits(ItemPickerJava.pztest$iterationResolved(
                    vector.picker, null, container, vector.density, vector.junk));
                int resolvedNext = Rand.Next(1_000_000);
                require(expected == nativeBits && expected == resolvedBits && nativeNext == resolvedNext,
                    "same-JVM input/RNG parity: " + group.label + "/" + i);
                Item script = ScriptManager.instance.FindItem(vector.picker.itemName);
                String loot = script == null ? "missing" : ItemPickerJava.getLootType(script);
                int tagCount = script == null ? -1 : script.getTags().size();
                System.out.printf(Locale.ROOT, "INPUT %s %d %s %08x %08x %s %s %d %08x %d%n",
                    group.label, i, vector.picker.itemName, Float.floatToRawIntBits(vector.picker.chance),
                    Float.floatToRawIntBits(vector.density), vector.junk, loot, tagCount, nativeBits, nativeNext);
            }
        }
        resetRandom();
    }

    private static void measure(Group[] groups) throws Exception {
        var runtime = ManagementFactory.getRuntimeMXBean();
        ThreadMXBean bean = (ThreadMXBean)ManagementFactory.getThreadMXBean();
        require(bean.isCurrentThreadCpuTimeSupported(), "thread CPU timing unavailable");
        require(bean.isThreadAllocatedMemorySupported(), "thread allocation timing unavailable");
        bean.setThreadCpuTimeEnabled(true);
        bean.setThreadAllocatedMemoryEnabled(true);
        long id = Thread.currentThread().threadId();
        int iterations = Integer.getInteger("loot.iterations", 50_000);
        int pairs = Integer.getInteger("loot.pairs", 12);
        int fork = Integer.getInteger("loot.fork", 0);
        require(iterations > 0 && pairs >= 2 && pairs % 2 == 0, "positive iterations and even pairs >=2 required");
        // Every fork contains BOTH modes. The same method has two symmetric direct-call
        // loops, not two MethodHandles or a per-iteration polymorphic dispatch.
        phase("timer-api-warmup-begin");
        Object warmMonitor = new Object();
        long[][][][] measured = new long[groups.length][pairs][2][7];
        for (int warmup = 0; warmup < 20_000; warmup++) {
            synchronized (warmMonitor) { warmMonitor.notifyAll(); }
            // The all-JIT gate observed a late isThreadCpuTimeEnabled C2 compile.
            // Exercise these actual timer-state predicates directly before windows.
            long enabled = (bean.isThreadCpuTimeEnabled() ? 1L : 0L)
                + (bean.isThreadAllocatedMemoryEnabled() ? 1L : 0L);
            sink = runtime.getUptime() + bean.getThreadAllocatedBytes(id)
                + bean.getCurrentThreadCpuTime() + System.nanoTime() + enabled;
        }
        phase("timer-api-warmup-end");
        separateReporting();
        // The all-JIT-gated 50k run showed this wrapper's first C1 compilation
        // during measured call ~256. Cross that observed threshold BEFORE windows,
        // without forcing C2 or repeating ten thousand expensive seeded halves.
        long[] scratch = new long[7];
        phase("short-wrapper-warmup-begin");
        for (int warmup = 0; warmup < 64; warmup++) {
            Group group = groups[warmup % groups.length];
            measuredHalf(group.inputs, 1, false, runtime, bean, id, scratch);
            measuredHalf(group.inputs, 1, true, runtime, bean, id, scratch);
        }
        phase("short-wrapper-warmup-end");
        // Train both full calculation branches on every varied input group.
        phase("long-warmup-begin");
        for (int warmup = 0; warmup < 16; warmup++) {
            for (int group = 0; group < groups.length; group++) {
                boolean firstResolved = (warmup + group + fork) % 2 != 0;
                measuredHalf(groups[group].inputs, iterations, firstResolved, runtime, bean, id, scratch);
                measuredHalf(groups[group].inputs, iterations, !firstResolved, runtime, bean, id, scratch);
            }
        }
        phase("long-warmup-end");
        phase("measure-ready");
        separateReporting(); // Keep milestone formatting outside the first +/-1ms window.
        for (int pair = 0; pair < pairs; pair++) {
            // Rotate group position as well as AB/BA order; pair each identical input.
            for (int position = 0; position < groups.length; position++) {
                int group = (position + pair) % groups.length;
                boolean firstResolved = (pair + group + fork) % 2 != 0;
                int first = firstResolved ? 1 : 0, second = 1 - first;
                measuredHalf(groups[group].inputs, iterations, firstResolved, runtime, bean, id, measured[group][pair][first]);
                measuredHalf(groups[group].inputs, iterations, !firstResolved, runtime, bean, id, measured[group][pair][second]);
                long[] nativeRow = measured[group][pair][0], resolvedRow = measured[group][pair][1];
                require(nativeRow[5] == resolvedRow[5] && nativeRow[6] == resolvedRow[6], "pair checksum/RNG mismatch");
            }
        }
        long lastWindowEnd = 0;
        for (long[][][] group : measured) for (long[][] pair : group) for (long[] row : pair)
            lastWindowEnd = Math.max(lastWindowEnd, row[1]);
        long waitStarted = System.nanoTime();
        separateReporting();
        long waitedNanos = System.nanoTime() - waitStarted, reportAt = runtime.getUptime();
        require(reportAt - lastWindowEnd >= 10, "reporting separation too short");
        phase("measure-complete");
        System.out.printf(Locale.ROOT, "REPORT_GAP %d %d %d%n", lastWindowEnd, reportAt, waitedNanos);
        for (int group = 0; group < groups.length; group++) {
            for (int pair = 0; pair < pairs; pair++) {
                String order = (pair + group + fork) % 2 == 0 ? "AB" : "BA";
                for (int mode = 0; mode < 2; mode++) {
                    String name = mode == 0 ? "native" : "candidate";
                    long[] row = measured[group][pair][mode];
                    System.out.printf(Locale.ROOT, "WINDOW %s %d %s %s %d %d%n",
                        groups[group].label, pair, order, name, row[0], row[1]);
                    System.out.printf(Locale.ROOT, "PAIR %s %d %s %s %d %d %d %d %d %d%n",
                        groups[group].label, pair, order, name, iterations, row[2], row[3], row[4], row[5], row[6]);
                }
            }
        }
    }

    private static void measuredHalf(Vector[] group, int count, boolean resolved,
            java.lang.management.RuntimeMXBean runtime, ThreadMXBean bean, long id, long[] row) throws Exception {
        resetRandom(); // Outside the unit: identical native CA state for both halves.
        long beganAt = runtime.getUptime(), allocated = bean.getThreadAllocatedBytes(id);
        long cpu = bean.getCurrentThreadCpuTime(), start = System.nanoTime();
        long checksum = pairedLoop(group, count, resolved);
        long elapsed = System.nanoTime() - start;
        cpu = bean.getCurrentThreadCpuTime() - cpu;
        allocated = bean.getThreadAllocatedBytes(id) - allocated;
        long endedAt = runtime.getUptime();
        row[0] = beganAt; row[1] = endedAt; row[2] = elapsed; row[3] = cpu; row[4] = allocated;
        row[5] = checksum; row[6] = Rand.Next(1_000_000);
    }

    private static long pairedLoop(Vector[] group, int count, boolean resolved) {
        long sum = 0;
        if (resolved) {
            for (int i = 0; i < count; i++) {
                Vector vector = group[i % group.length];
                sum += Float.floatToRawIntBits(ItemPickerJava.pztest$iterationResolved(
                    vector.picker, null, container, vector.density, vector.junk));
            }
        } else {
            for (int i = 0; i < count; i++) {
                Vector vector = group[i % group.length];
                sum += Float.floatToRawIntBits(ItemPickerJava.pztest$iterationNative(
                    vector.picker, null, container, vector.density, vector.junk));
            }
        }
        sink = sum;
        return sum;
    }

    private static void phase(String name) {
        System.out.println("PHASE " + name + " " + ManagementFactory.getRuntimeMXBean().getUptime());
    }

    private static void separateReporting() {
        long deadline = System.nanoTime() + 20_000_000L;
        long remaining;
        while ((remaining = deadline - System.nanoTime()) > 0) {
            // parkNanos may return spuriously; park again for the remaining duration.
            // An interrupted park would return immediately and cause a busy loop.
            require(!Thread.currentThread().isInterrupted(), "interrupted reporting separation");
            LockSupport.parkNanos(remaining);
        }
    }

}
