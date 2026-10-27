package net.alexredby.pztoolkitjavapatches

import com.google.common.collect.ImmutableSet
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import java.lang.reflect.Field
import java.nio.file.Files
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.core.random.RandAbstract
import zombie.core.random.RandLua
import zombie.core.random.RandStandard
import zombie.entity.ComponentType
import zombie.entity.components.fluids.Fluid
import zombie.entity.components.fluids.FluidCategory
import zombie.scripting.ScriptLoadMode
import zombie.scripting.ScriptParser
import zombie.scripting.entity.components.fluids.FluidContainerScript

object FluidScriptPropertiesChecks {
    private fun verify(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun script(amount: String): FluidContainerScript {
        val component = ComponentType.FluidContainer.CreateComponentScript() as FluidContainerScript
        val block =
            ScriptParser.parse(
                    "component FluidContainer { ContainerName = Bottle, Capacity = 3.5, $amount " +
                        "Fluids { fluid = Petrol:1, } }",
                )
                .getBlock("component", "FluidContainer")
        FluidContainerScript::class
            .java
            .getDeclaredMethod("load", ScriptParser.Block::class.java)
            .apply { isAccessible = true }
            .invoke(component, block)
        component.OnScriptsLoaded(ScriptLoadMode.Init)
        // The minimal JVM omits global fluid-script registration. Prepare its native cached
        // reference before observing read-only preview behavior.
        field(FluidContainerScript.FluidScript::class.java, "fluid")
            .set(component.getInitialFluids()[0], Fluid.Petrol)
        return component
    }

    private fun snapshot(component: FluidContainerScript): List<Any?> =
        (listOf(component) + component.getInitialFluids()).flatMap { owner ->
            owner.javaClass.declaredFields
                .filter { !java.lang.reflect.Modifier.isStatic(it.modifiers) }
                .map { member ->
                    member.isAccessible = true
                    val value = member.get(owner)
                    if (value is Float) value.toRawBits() else value
                }
        }

    private fun randomState(): ByteArray {
        val bytes = ByteArrayOutputStream()
        ObjectOutputStream(bytes).use {
            it.writeObject(field(RandAbstract::class.java, "rand").get(RandStandard.INSTANCE))
            it.writeInt(field(RandAbstract::class.java, "id").getInt(RandStandard.INSTANCE))
        }
        return bytes.toByteArray()
    }

    private fun runLua(source: String): Any? =
        LuaManager.thread.call(
            LuaCompiler.loadstring(source, "fluid-script-preview-check", LuaManager.env),
            emptyArray<Any?>(),
        )

    private fun loadRules(): KahluaTable {
        runLua(
            """
            ComponentType={FluidContainer='FluidContainer'}
            FluidCategory={Medical='Medical',Alcoholic='Alcoholic',Beverage='Beverage',Fuel='Fuel',
                HairDyes='HairDyes',Dyes='Dyes',Paint='Paint',Water='Water',Hazardous='Hazardous'}
            ItemType={NORMAL='Normal'}
            local legacy={useVanillaDefaults=function() return false end,forType=function() end}
            require=function(name)
                if name=='PZSurvivorToolkit/ItemCategoryData' then return {} end
                if name=='PZSurvivorToolkit/LegacyItemCategories' then return legacy end
                error('unexpected dependency '..name)
            end
            string.contains=function(text,part) return string.find(text,part,1,true)~=nil end
            """
                .trimIndent(),
        )
        // Keep real component/list methods and bridge invocation; only the outer ScriptItem is a
        // stub.
        val types =
            listOf(
                FluidContainerScript::class.java,
                FluidContainerScript.FluidScript::class.java,
                java.util.ArrayList::class.java,
                Fluid::class.java,
            )
        for (type in types) LuaManager.exposer.setExposed(type)
        for (type in types) {
            LuaManager.exposer.exposeLikeJava(type, LuaManager.env)
            verify(
                LuaManager.exposer.isExposed(type),
                "native fixture class was not exposed: $type",
            )
        }
        val categories = LuaManager.platform.newTable()
        for (category in FluidCategory.values()) categories.rawset(category.name, category)
        LuaManager.env.rawset("FluidCategory", categories)
        val root = Path.of(System.getProperty("pz.test.project"))
        val rules =
            runLua(
                Files.readString(
                    root.resolve(
                        "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemCategoryRules.lua",
                    ),
                ),
            )
                as KahluaTable
        LuaManager.env.rawset("PreviewRules", rules)
        runLua(
            """
            PreviewScript={getFullName=function() return 'Regression.FluidPreview' end,
                getDisplayCategory=function() return 'Junk' end,
                getItemType=function() return 'Normal' end,
                containsComponent=function() return true end,
                getComponentScriptFor=function() return PreviewComponent end}
            function PreviewRepeated(expected)
                for i=1,100 do assert(PreviewRules.forScript(PreviewScript)==expected) end
            end
            """
                .trimIndent(),
        )
        return rules
    }

    @JvmStatic
    fun main(args: Array<String>) {
        RandStandard.INSTANCE.init()
        RandLua.INSTANCE.init()
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            FluidScriptPropertiesChecks::class.java.classLoader,
        )
        val bridge =
            Exposer.getClassesWithGlobalLuaMethod().firstOrNull {
                it.name == "net.alexredby.pztoolkitjavapatches.FluidScriptProperties"
            } ?: throw AssertionError("ZombieBuddy did not discover the fluid metadata bridge")
        verify(
            Path.of(bridge.protectionDomain.codeSource.location.toURI()) ==
                Path.of(System.getProperty("pz.test.patch.jar")),
            "fluid metadata bridge was not loaded from the built JAR",
        )
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager()
        KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        Exposer.afterExposeAll()
        val function = LuaManager.env.rawget("toolkitScriptFluidInitialAmounts")
        verify(
            function != null && FluidScriptProperties.SUPPORTED,
            "fluid bridge or native hash missing",
        )
        LuaManager.thread = KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        loadRules()
        // Supply only the native fuel category needed by this minimal script fixture.
        field(Fluid::class.java, "categories")
            .set(Fluid.Petrol, ImmutableSet.of(FluidCategory.Fuel))

        val vectors =
            listOf(
                Triple("", 3.5f, 3.5f),
                Triple("InitialPercent = 0,", 0f, 0f),
                Triple("InitialPercent = 0.2,", .2f * 3.5f, .2f * 3.5f),
                Triple("InitialPercentMin = 0.1, InitialPercentMax = 0.9,", .1f * 3.5f, .9f * 3.5f),
                Triple("InitialPercentMin = 0, InitialPercentMax = 1,", 0f, 3.5f),
                Triple("InitialPercentMin = 2, InitialPercentMax = -1,", 0f, 3.5f),
            )
        for ((definition, min, max) in vectors) {
            val component = script(definition)
            val fields = snapshot(component)
            val random = randomState()
            repeat(100) {
                val amounts =
                    LuaManager.thread.call(function, arrayOf<Any?>(component)) as KahluaTable
                verify(
                    amounts.rawget("min") == min.toDouble() &&
                        amounts.rawget("max") == max.toDouble(),
                    "bridge changed exact normalized native bounds: $definition",
                )
            }
            LuaManager.env.rawset("PreviewComponent", component)
            runLua("PreviewRepeated('${if (max > 0f) "mechanicsFuel" else "containerLiquid"}')")
            verify(random.contentEquals(randomState()), "repeated Lua previews advanced native RNG")
            verify(
                fields == snapshot(component),
                "metadata or Lua preview changed native script fields",
            )
            verify(
                FluidScriptProperties.read(component, false) == null,
                "unsupported bytecode exposed bounds",
            )
        }
        verify(
            LuaManager.thread.call(function, arrayOf<Any?>(null)) == null,
            "missing component did not remain nil in Kahlua",
        )
        val ranged = script("InitialPercentMin = 0.1, InitialPercentMax = 0.9,")
        val fields = snapshot(ranged)
        val random = randomState()
        ranged.getInitialAmount()
        verify(!random.contentEquals(randomState()), "negative control did not advance native RNG")
        verify(fields == snapshot(ranged), "negative control unexpectedly changed script fields")
        field(FluidContainerScript::class.java, "initialAmountMax").setFloat(ranged, Float.NaN)
        verify(
            FluidScriptProperties.initialAmounts(ranged) == null,
            "invalid bounds exposed a value",
        )
        println(
            "FLUID_SCRIPT_PROPERTIES_CHECKS_PASS (exact finalized native bounds, nil/unsupported, " +
                "built-JAR global, real Kahlua category previews, unchanged native fields/RNG, native getter negative control)",
        )
        kotlin.system.exitProcess(0)
    }
}
