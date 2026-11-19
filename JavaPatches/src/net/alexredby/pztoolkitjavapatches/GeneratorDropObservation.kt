package net.alexredby.pztoolkitjavapatches

import java.lang.ref.WeakReference
import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.inventory.InventoryItem
import zombie.iso.objects.IsoGenerator
import zombie.network.GameClient

/** A synchronous authority observation; it grants no action or ownership rights. */
object GeneratorDropObservation {
    @Patch(className = "zombie.iso.objects.IsoGenerator", methodName = "setInfoFromItem", warmUp = true, strictMatch = true)
    object ItemConversion {
        @JvmStatic
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        fun exit(@Patch.This generator: IsoGenerator, @Patch.Argument(0) source: InventoryItem?,
                 @Patch.Thrown failure: Throwable?) {
            observed(source, generator, failure)
        }
    }

    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/iso/objects/IsoGenerator.class",
            "c5c58877781d10c0eb72c8af7dd71746de10a33a9a730a8c39637d49ef23cbc7",
        ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoGridSquare.class",
                "b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5",
            )

    private class Scope(handle: KahluaTable, source: InventoryItem) {
        val handle = WeakReference(handle)
        val source = WeakReference(source)
        var generator: WeakReference<IsoGenerator>? = null
        var invalid = false
    }

    private val current = ThreadLocal<Scope>()
    private val walker = StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE)

    /** Call immediately before one owned stock synchronous equip completion. */
    @JvmStatic
    @LuaMethod(name = "toolkitGeneratorDropBegin", global = true)
    fun begin(source: InventoryItem?): KahluaTable? {
        val previous = current.get()
        if (previous != null) {
            previous.invalid = true
            current.remove()
            return null
        }
        if (!SUPPORTED || GameClient.client || source == null) return null
        val platform = LuaManager.platform ?: return null
        val handle = platform.newTable()
        current.set(Scope(handle, source))
        return handle
    }

    private fun nativeConstructor(): Boolean =
        walker.walk { frames ->
            val game = frames.filter { it.className == "zombie.iso.objects.IsoGenerator" || it.className == "zombie.iso.IsoGridSquare" }.iterator()
            if (!game.hasNext()) return@walk false
            val info = game.next()
            if (info.className != "zombie.iso.objects.IsoGenerator" || info.methodName != "setInfoFromItem") return@walk false
            if (!game.hasNext()) return@walk false
            val constructor = game.next()
            if (constructor.className != "zombie.iso.objects.IsoGenerator" || constructor.methodName != "<init>" ||
                constructor.descriptor != "(Lzombie/inventory/InventoryItem;Lzombie/iso/IsoCell;Lzombie/iso/IsoGridSquare;)V") return@walk false
            if (!game.hasNext()) return@walk false
            val drop = game.next()
            drop.className == "zombie.iso.IsoGridSquare" && drop.methodName == "AddWorldInventoryItem" &&
                drop.descriptor == "(Lzombie/inventory/InventoryItem;FFFZZ)Lzombie/inventory/InventoryItem;"
        }

    @JvmStatic
    fun observed(source: InventoryItem?, generator: IsoGenerator?, failure: Throwable?) {
        // The ordinary path pays only the empty ThreadLocal read.
        val scope = current.get() ?: return
        if (scope.source.get() !== source) return
        if (!SUPPORTED || GameClient.client || failure != null || generator == null ||
            scope.generator != null || !nativeConstructor()) {
            scope.invalid = true
            return
        }
        scope.generator = WeakReference(generator)
    }

    /** Always close the thread's scope. The caller must separately prove native success. */
    @JvmStatic
    @LuaMethod(name = "toolkitGeneratorDropFinish", global = true)
    fun finish(handle: KahluaTable?): IsoGenerator? {
        val scope = current.get() ?: return null
        current.remove()
        if (!SUPPORTED || GameClient.client || handle == null || scope.handle.get() !== handle || scope.invalid) return null
        val source = scope.source.get() ?: return null
        val generator = scope.generator?.get() ?: return null
        val square = generator.square ?: return null
        // setInfoFromItem runs before placement. Only a constructed, live native object is exposed.
        if (generator.objectIndex < 0 || square.objects.count { it === generator } != 1 ||
            square.specialObjects.count { it === generator } != 1 || source.worldItem != null) return null
        return generator
    }

    /** Use from the completion wrapper's error path, without replaying any native effects. */
    @JvmStatic
    @LuaMethod(name = "toolkitGeneratorDropCancel", global = true)
    fun cancel(handle: KahluaTable?) {
        // Even a wrong handle revokes the current observation, never another observation's rights.
        current.remove()
    }
}
