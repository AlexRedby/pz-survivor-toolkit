package zombie.scripting.entity.components.fluids;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;
import zombie.scripting.ScriptBucketCollection;
import zombie.core.random.RandAbstract;
import zombie.core.random.RandStandard;
import zombie.entity.ComponentType;
import zombie.entity.components.fluids.Fluid;
import zombie.entity.components.fluids.FluidContainer;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptParser;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemType;
import zombie.scripting.objects.ScriptModule;

/** Native component initialization only: no output item, world, window or Lua callback. */
public final class FoodReplacementOutputChecks {
    static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    static final class CountedRandom extends Random {
        int draws;
        CountedRandom() { super(12345L); }
        @Override protected int next(int bits) { draws++; return super.next(bits); }
    }

    static ScriptParser.Block nativeModule(String file) throws Exception {
        return ScriptParser.parse(ScriptParser.stripComments(Files.readString(Path.of(file))))
            .getBlock("module", "Base");
    }

    static Item nativeItem(ScriptParser.Block moduleBlock, ScriptModule module, String name) throws Exception {
        var block = moduleBlock.getBlock("item", name);
        require(block != null, "native item missing: " + name);
        // Icon eagerly loads GPU textures in Item.Load. The headless check omits only
        // that rendering field; all factory metadata and component blocks stay native.
        var icon = block.getValue("Icon");
        require(icon != null, "native output icon missing: " + name);
        block.values.remove(icon);
        block.elements.remove(icon);
        var body = new StringBuilder();
        block.prettyPrint(0, body);
        var item = new Item();
        item.setModule(module);
        item.InitLoadPP(name);
        item.Load(name, body.toString());
        require(item.getItemType() == ItemType.NORMAL && item.getCount() == 1 && !item.getObsolete(),
            name + " is no longer a single normal output");
        require(item.getLuaCreate() == null && item.getItemConfig() == null && item.getItemConfigKey() == null,
            name + " gained a factory callback/configuration");
        require(item.getReplaceOnUse() == null && item.getReplaceOnDeplete() == null,
            name + " gained a replacement");
        return item;
    }

    static FluidContainerScript emptyScript(Item item) {
        var components = item.getComponentScripts();
        require(components.size() == 1, item.getName() + " component count changed");
        var component = components.get(0);
        require(component.getClass() == FluidContainerScript.class
            && component == item.getComponentScriptFor(ComponentType.FluidContainer),
            item.getName() + " sole component is not the native fluid script");
        var fluid = (FluidContainerScript)component;
        require(fluid.getInitialFluids() == null || fluid.getInitialFluids().isEmpty(),
            item.getName() + " gained initial fluid");
        require(Float.isFinite(fluid.getCapacity()) && fluid.getCapacity() > 0,
            item.getName() + " capacity is invalid");
        return fluid;
    }

    static FluidContainer create(FluidContainerScript script) {
        return (FluidContainer)ComponentType.FluidContainer.CreateComponentFromScript(script);
    }

    static void empty(FluidContainer container, float capacity, String name) {
        require(container.isEmpty() && container.getAmount() == 0 && container.getCapacity() == capacity,
            name + " was not initialized empty at its script capacity");
    }

    static FluidContainerScript probe(String fluids) throws Exception {
        var script = (FluidContainerScript)ComponentType.FluidContainer.CreateComponentScript();
        var parent = new zombie.scripting.entity.GameEntityScript();
        parent.setModule(ScriptManager.instance.moduleMap.get("Base"));
        parent.InitLoadPP("FoodOutputProbe");
        script.setParent(parent);
        script.load(ScriptParser.parse("component FluidContainer { Capacity = 0.3, InitialPercentMin = 0.2, InitialPercentMax = 0.8, "
            + fluids + " }").getBlock("component", "FluidContainer"));
        script.OnScriptsLoaded(ScriptLoadMode.Init);
        return script;
    }

    static void loadFluids() throws Exception {
        // Use the complete shipped definition set so native initialization guards remain active.
        var module = new ScriptModule();
        module.Load(ScriptLoadMode.Init, "Base", Files.readString(Path.of("media/scripts/generated/fluids.txt")));
        module.fluidDefinitionScripts.LoadScripts(ScriptLoadMode.Init);
        require(!module.fluidDefinitionScripts.isHasLoadErrors(), "native fluid definitions failed to load");
        ScriptManager.instance.moduleMap.put("Base", module);
        ScriptManager.instance.moduleList.add(module);
        Field collections = ScriptManager.class.getDeclaredField("bucketCollectionList");
        collections.setAccessible(true);
        for (Object collection : (java.util.List<?>)collections.get(ScriptManager.instance))
            ((ScriptBucketCollection<?>)collection).registerModule(module);
        Fluid.Init(ScriptLoadMode.Init);
        require(Fluid.FluidsInitialized() && Fluid.Get("Water") != null, "native water initialization failed");
    }

    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        zombie.debug.DebugType.General.setLogSeverity(zombie.debug.LogSeverity.All);
        RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Field mod = ScriptManager.class.getDeclaredField("currentLoadFileMod");
        mod.setAccessible(true);
        mod.set(null, "pz-vanilla");
        zombie.world.WorldDictionary.StartScriptLoading();
        loadFluids();
        var module = ScriptManager.instance.moduleMap.get("Base");
        var nativeItems = nativeModule("media/scripts/generated/items/normal.txt");
        var can = nativeItem(nativeItems, module, "TinCanEmpty");
        var bowl = nativeItem(nativeItems, module, "Bowl");
        var pan = nativeItem(nativeItems, module, "RoastingPan");
        require(!pan.hasComponents() && pan.getComponentScripts().isEmpty(), "plain roasting pan gained components");
        require(can.getActualWeight() == 0.2f && bowl.getActualWeight() == 0.5f, "native shell weight changed");
        var canScript = emptyScript(can);
        var bowlScript = emptyScript(bowl);

        Field random = RandAbstract.class.getDeclaredField("rand");
        random.setAccessible(true);
        Object previous = random.get(RandStandard.INSTANCE);
        var counted = new CountedRandom();
        random.set(RandStandard.INSTANCE, counted);
        try {
            var nilFluids = probe("");
            var emptyFluids = probe("Fluids { fluid = Water:1.0, }");
            require(nilFluids.getInitialFluids() == null, "nil initial-fluid probe changed");
            // Exercise the separate non-null/empty branch with a real parsed native list.
            emptyFluids.getInitialFluids().clear();
            require(emptyFluids.getInitialFluids().isEmpty(), "empty initial-fluid probe changed");
            for (var script : new FluidContainerScript[]{canScript, bowlScript, nilFluids, emptyFluids}) {
                int before = counted.draws;
                var container = create(script);
                empty(container, script.getCapacity(), script.getName());
                require(counted.draws == before, "empty initialization consumed initial-amount RNG");
                FluidContainer.DisposeContainer(container);
            }
            var filledScript = probe("Fluids { fluid = Water:1.0, }");
            require(!filledScript.getInitialFluids().isEmpty(), "nonempty control lost its initial fluid");
            int before = counted.draws;
            var filled = create(filledScript);
            require(counted.draws > before, "ranged nonempty control did not exercise initial-amount RNG");
            require(!filled.isEmpty() && filled.getAmount() > 0 && filled.getAmount() <= filled.getCapacity(),
                "nonempty control did not create real native fluid");
            FluidContainer.DisposeContainer(filled);
            var reused = create(canScript);
            require(reused == filled, "fixture did not reuse the released native component");
            empty(reused, canScript.getCapacity(), "reused can");
            FluidContainer.DisposeContainer(reused);
            System.out.println("FOOD_REPLACEMENT_OUTPUT_CHECKS_PASS (native TinCanEmpty/Bowl, plain RoastingPan, exact component identity, nil/empty fluids, zero empty RNG draws, ranged filled control, clean pool reuse)");
        } finally {
            random.set(RandStandard.INSTANCE, previous);
        }
    }
}
