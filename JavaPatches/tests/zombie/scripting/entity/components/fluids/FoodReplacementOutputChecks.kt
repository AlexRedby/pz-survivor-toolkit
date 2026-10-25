package zombie.scripting.entity.components.fluids

import java.nio.file.Files
import java.nio.file.Path
import java.util.Random
import zombie.core.random.RandAbstract
import zombie.core.random.RandStandard
import zombie.entity.ComponentType
import zombie.entity.components.fluids.Fluid
import zombie.entity.components.fluids.FluidContainer
import zombie.scripting.ScriptBucketCollection
import zombie.scripting.ScriptLoadMode
import zombie.scripting.ScriptManager
import zombie.scripting.ScriptParser
import zombie.scripting.objects.Item
import zombie.scripting.objects.ItemType
import zombie.scripting.objects.ScriptModule

/** Native component initialization only: no output item, world, window or Lua callback. */
object FoodReplacementOutputChecks {
    @JvmStatic
    fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    class CountedRandom : Random(12345L) {
        @JvmField var draws = 0

        override fun next(bits: Int): Int {
            draws++
            return super.next(bits)
        }
    }

    @JvmStatic
    fun nativeModule(file: String?): ScriptParser.Block =
        ScriptParser.parse(ScriptParser.stripComments(Files.readString(Path.of(file))))
            .getBlock("module", "Base")

    @JvmStatic
    fun nativeItem(moduleBlock: ScriptParser.Block, module: ScriptModule?, name: String): Item {
        val block = moduleBlock.getBlock("item", name)
        require(block != null, "native item missing: " + name)
        // Icon eagerly loads GPU textures in Item.Load. The headless check omits only
        // that rendering field; all factory metadata and component blocks stay native.
        val icon = block.getValue("Icon")
        require(icon != null, "native output icon missing: " + name)
        block.values.remove(icon)
        block.elements.remove(icon)
        val body = StringBuilder()
        block.prettyPrint(0, body)
        val item = Item()
        item.setModule(module)
        item.InitLoadPP(name)
        item.Load(name, body.toString())
        require(
            item.getItemType() === ItemType.NORMAL && item.getCount() == 1 && !item.getObsolete(),
            name + " is no longer a single normal output",
        )
        require(
            item.getLuaCreate() == null &&
                item.getItemConfig() == null &&
                item.getItemConfigKey() == null,
            name + " gained a factory callback/configuration",
        )
        require(
            item.getReplaceOnUse() == null && item.getReplaceOnDeplete() == null,
            name + " gained a replacement",
        )
        return item
    }

    @JvmStatic
    fun emptyScript(item: Item): FluidContainerScript {
        val components = item.getComponentScripts()
        require(components.size == 1, item.getName() + " component count changed")
        val component = components[0]
        require(
            component.javaClass === FluidContainerScript::class.java &&
                component === item.getComponentScriptFor(ComponentType.FluidContainer),
            item.getName() + " sole component is not the native fluid script",
        )
        val fluid = component as FluidContainerScript
        require(
            fluid.getInitialFluids() == null || fluid.getInitialFluids().isEmpty(),
            item.getName() + " gained initial fluid",
        )
        require(
            java.lang.Float.isFinite(fluid.getCapacity()) && fluid.getCapacity() > 0,
            item.getName() + " capacity is invalid",
        )
        return fluid
    }

    @JvmStatic
    fun create(script: FluidContainerScript?): FluidContainer =
        ComponentType.FluidContainer.CreateComponentFromScript(script) as FluidContainer

    @JvmStatic
    fun empty(container: FluidContainer, capacity: Float, name: String?) {
        require(
            container.isEmpty() &&
                container.getAmount() == 0f &&
                container.getCapacity() == capacity,
            name + " was not initialized empty at its script capacity",
        )
    }

    @JvmStatic
    fun probe(fluids: String): FluidContainerScript {
        val script = ComponentType.FluidContainer.CreateComponentScript() as FluidContainerScript
        val parent = zombie.scripting.entity.GameEntityScript()
        parent.setModule(ScriptManager.instance.moduleMap["Base"])
        parent.InitLoadPP("FoodOutputProbe")
        script.setParent(parent)
        script.load(
            ScriptParser.parse(
                    "component FluidContainer { Capacity = 0.3, InitialPercentMin = 0.2, InitialPercentMax = 0.8, " +
                        fluids +
                        " }",
                )
                .getBlock("component", "FluidContainer"),
        )
        script.OnScriptsLoaded(ScriptLoadMode.Init)
        return script
    }

    @JvmStatic
    fun loadFluids() {
        // Use the complete shipped definition set so native initialization guards remain active.
        val module = ScriptModule()
        module.Load(
            ScriptLoadMode.Init,
            "Base",
            Files.readString(Path.of("media/scripts/generated/fluids.txt")),
        )
        module.fluidDefinitionScripts.LoadScripts(ScriptLoadMode.Init)
        require(
            !module.fluidDefinitionScripts.isHasLoadErrors(),
            "native fluid definitions failed to load",
        )
        ScriptManager.instance.moduleMap["Base"] = module
        ScriptManager.instance.moduleList.add(module)
        val collections = ScriptManager::class.java.getDeclaredField("bucketCollectionList")
        collections.setAccessible(true)
        for (collection in collections.get(ScriptManager.instance) as List<*>) (collection
                as ScriptBucketCollection<*>)
            .registerModule(module)
        Fluid.Init(ScriptLoadMode.Init)
        require(
            Fluid.FluidsInitialized() && Fluid.Get("Water") != null,
            "native water initialization failed",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.debug.DebugType.General.setLogSeverity(zombie.debug.LogSeverity.All)
        RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val mod = ScriptManager::class.java.getDeclaredField("currentLoadFileMod")
        mod.setAccessible(true)
        mod.set(null, "pz-vanilla")
        zombie.world.WorldDictionary.StartScriptLoading()
        loadFluids()
        val module = ScriptManager.instance.moduleMap["Base"]
        val nativeItems = nativeModule("media/scripts/generated/items/normal.txt")
        val can = nativeItem(nativeItems, module, "TinCanEmpty")
        val bowl = nativeItem(nativeItems, module, "Bowl")
        val pan = nativeItem(nativeItems, module, "RoastingPan")
        require(
            !pan.hasComponents() && pan.getComponentScripts().isEmpty(),
            "plain roasting pan gained components",
        )
        require(
            can.getActualWeight() == 0.2f && bowl.getActualWeight() == 0.5f,
            "native shell weight changed",
        )
        val canScript = emptyScript(can)
        val bowlScript = emptyScript(bowl)
        val random = RandAbstract::class.java.getDeclaredField("rand")
        random.setAccessible(true)
        val previous = random.get(RandStandard.INSTANCE)
        val counted = CountedRandom()
        random.set(RandStandard.INSTANCE, counted)
        try {
            val nilFluids = probe("")
            val emptyFluids = probe("Fluids { fluid = Water:1.0, }")
            require(nilFluids.getInitialFluids() == null, "nil initial-fluid probe changed")
            // Exercise the separate non-null/empty branch with a real parsed native list.
            emptyFluids.getInitialFluids().clear()
            require(emptyFluids.getInitialFluids().isEmpty(), "empty initial-fluid probe changed")
            for (script in arrayOf(canScript, bowlScript, nilFluids, emptyFluids)) {
                val before = counted.draws
                val container = create(script)
                empty(container, script.getCapacity(), script.getName())
                require(counted.draws == before, "empty initialization consumed initial-amount RNG")
                FluidContainer.DisposeContainer(container)
            }
            val filledScript = probe("Fluids { fluid = Water:1.0, }")
            require(
                !filledScript.getInitialFluids().isEmpty(),
                "nonempty control lost its initial fluid",
            )
            val before = counted.draws
            val filled = create(filledScript)
            require(
                counted.draws > before,
                "ranged nonempty control did not exercise initial-amount RNG",
            )
            require(
                !filled.isEmpty() &&
                    filled.getAmount() > 0 &&
                    filled.getAmount() <= filled.getCapacity(),
                "nonempty control did not create real native fluid",
            )
            FluidContainer.DisposeContainer(filled)
            val reused = create(canScript)
            require(reused === filled, "fixture did not reuse the released native component")
            empty(reused, canScript.getCapacity(), "reused can")
            FluidContainer.DisposeContainer(reused)
            println(
                "FOOD_REPLACEMENT_OUTPUT_CHECKS_PASS (native TinCanEmpty/Bowl, plain RoastingPan, exact component identity, nil/empty fluids, zero empty RNG draws, ranged filled control, clean pool reuse)",
            )
        } finally {
            random.set(RandStandard.INSTANCE, previous)
        }
    }
}
