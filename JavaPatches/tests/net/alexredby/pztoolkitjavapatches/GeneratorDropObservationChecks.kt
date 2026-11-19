package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import java.lang.instrument.Instrumentation
import net.bytebuddy.ByteBuddy
import net.bytebuddy.description.method.MethodDescription
import net.bytebuddy.dynamic.loading.ClassReloadingStrategy
import net.bytebuddy.implementation.MethodCall
import net.bytebuddy.matcher.ElementMatchers
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.LuaCaller
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.inventory.InventoryItem
import zombie.iso.IsoCell
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.iso.objects.IsoGenerator
import zombie.iso.sprite.IsoSprite
import zombie.iso.sprite.IsoSpriteManager
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.scripting.objects.Item

/** Native grid conversion and constructor, with inert world placement and no game window. */
object GeneratorDropObservationChecks {
    private val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
    private fun verify(value: Boolean, message: String) { if (!value) throw AssertionError(message) }
    private fun field(type: Class<*>, target: Any, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }

    @JvmStatic
    fun place(square: IsoGridSquare, value: IsoObject) {
        square.objects.add(value)
        square.specialObjects.add(value)
    }

    private fun source(): InventoryItem {
        val item = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        val script = Item()
        script.worldObjectSprite = "toolkit_fixture_generator"
        item.setScriptItem(script)
        field(InventoryItem::class.java, item, "fullType", "Base.GeneratorFixture")
        field(InventoryItem::class.java, item, "module", "Base")
        field(InventoryItem::class.java, item, "type", "GeneratorFixture")
        item.modData.rawset("fuel", 12.5)
        return item
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.ZomboidFileSystem.instance.init()
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        val converters = KahluaConverterManager()
        LuaManager.caller = LuaCaller(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", javaClass.classLoader)
        Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        val begin = LuaManager.env.rawget("toolkitGeneratorDropBegin")
        val finish = LuaManager.env.rawget("toolkitGeneratorDropFinish")
        val cancel = LuaManager.env.rawget("toolkitGeneratorDropCancel")
        verify(begin != null && finish != null && cancel != null, "ZombieBuddy did not expose observation globals")
        verify(GeneratorDropObservation.SUPPORTED, "current native generator/grid bytecode is unsupported")
        // Keep native AddWorldInventoryItem and IsoGenerator constructor/setInfoFromItem intact;
        // replace only unrelated placement side effects that require a running world's subsystems.
        val instrumentation = Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
            ?: throw AssertionError("ZombieBuddy instrumentation unavailable")
        ByteBuddy().redefine(IsoGridSquare::class.java)
            .method(ElementMatchers.named<MethodDescription>("AddSpecialObject").and(ElementMatchers.takesArguments(IsoObject::class.java)))
            .intercept(MethodCall.invoke(javaClass.getMethod("place", IsoGridSquare::class.java, IsoObject::class.java)).withThis().withArgument(0))
            .make().load(javaClass.classLoader, ClassReloadingStrategy.of(instrumentation))
        GameClient.client = false
        GameServer.server = false
        val cell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        field(IsoCell::class.java, cell, "processItemsRemove", HashSet<InventoryItem>())
        IsoWorld.instance.currentCell = cell
        val square = unsafe.allocateInstance(IsoGridSquare::class.java) as IsoGridSquare
        field(IsoGridSquare::class.java, square, "objects", ArrayList<IsoObject>())
        field(IsoGridSquare::class.java, square, "specialObjects", ArrayList<IsoObject>())
        IsoSpriteManager.instance.namedMap["toolkit_fixture_generator"] = IsoSprite()
        val item = source()
        fun drop(value: InventoryItem = item): IsoGenerator {
            verify(square.AddWorldInventoryItem(value, 0f, 0f, 0f) === value, "native drop changed its return contract")
            return square.objects.last() as IsoGenerator
        }

        drop()
        verify(GeneratorDropObservation.finish(null) == null, "unscoped drop granted a receipt")
        val handle = thread.call(begin, arrayOf<Any?>(item))
        verify(handle != null, "real Kahlua begin returned nil")
        val exact = drop()
        verify(thread.call(finish, arrayOf(handle)) === exact, "real woven constructor did not return exact world generator")
        verify(exact.fuel == 12.5f && exact.modData.rawget("generatorFullType") == "Base.GeneratorFixture", "observation changed native conversion state")
        verify(thread.call(finish, arrayOf(handle)) == null, "receipt could be reused")

        val foreignHandle = GeneratorDropObservation.begin(item)
        drop(source())
        verify(GeneratorDropObservation.finish(foreignHandle) == null, "foreign equal-type generator matched original source")
        val duplicate = GeneratorDropObservation.begin(item)
        drop(); drop()
        verify(GeneratorDropObservation.finish(duplicate) == null, "duplicate native conversions retained ancestry")
        val direct = GeneratorDropObservation.begin(item)
        IsoGenerator(item, cell, square)
        verify(GeneratorDropObservation.finish(direct) == null, "direct constructor bypassed native grid conversion proof")
        val mutated = GeneratorDropObservation.begin(item)
        exact.setInfoFromItem(item)
        verify(GeneratorDropObservation.finish(mutated) == null, "non-constructor setInfoFromItem minted ancestry")
        val nested = GeneratorDropObservation.begin(item)
        verify(GeneratorDropObservation.begin(item) == null, "nested scope was admitted")
        drop()
        verify(GeneratorDropObservation.finish(nested) == null, "nested scope retained outer authority")
        val canceled = thread.call(begin, arrayOf<Any?>(item))
        drop()
        thread.call(cancel, arrayOf(canceled))
        verify(thread.call(finish, arrayOf(canceled)) == null, "canceled completion exposed ancestry")
        val removed = GeneratorDropObservation.begin(item)
        val gone = drop()
        square.objects.remove(gone)
        verify(GeneratorDropObservation.finish(removed) == null, "removed world output retained ancestry")
        val wrong = GeneratorDropObservation.begin(item)
        drop()
        verify(GeneratorDropObservation.finish(LuaManager.platform.newTable()) == null && GeneratorDropObservation.finish(wrong) == null, "forged handle retained an observation")
        GameClient.client = true
        verify(GeneratorDropObservation.begin(item) == null, "MP client admitted authority observation")
        GameClient.client = false
        verify(GeneratorDropObservation.begin(null) == null, "missing source admitted scope")
        println("GENERATOR_DROP_OBSERVATION_CHECKS_PASS (woven native grid/constructor, exact output, Kahlua exposure, foreign/duplicate/direct/mutation/nested/cancel/removed/client guards)")
        kotlin.system.exitProcess(0)
    }
}
