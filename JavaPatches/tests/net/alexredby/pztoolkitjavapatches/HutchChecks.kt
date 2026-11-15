package net.alexredby.pztoolkitjavapatches

import zombie.iso.objects.*

import java.util.ArrayList
import java.util.HashMap
import java.util.HashSet
import sun.misc.Unsafe
import zombie.characters.animals.IsoAnimal
import zombie.core.PerformanceSettings
import zombie.iso.IsoCell
import zombie.iso.IsoChunk
import zombie.iso.IsoObject
import zombie.popman.animal.HutchManager

object HutchChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var cell: IsoCell
    private lateinit var removals: CountingSet

    class CountingSet : HashSet<IsoObject>() {
        var calls = 0

        override fun add(element: IsoObject): Boolean {
            calls++
            return super.add(element)
        }
    }

    class Hutch : IsoHutch(null) {
        override fun getCell(): IsoCell = HutchChecks.cell

        override fun getChunk(): IsoChunk? = null

        override fun clearOnOverlay() {}

        override fun removeLightSourceFromWorld() {}

        override fun couldBePoweredByGenerator(): Boolean = false

        override fun flagForHotSave() {}
    }

    class Animal : IsoAnimal(null) {
        var removals = 0
        var failure: RuntimeException? = null

        override fun removeFromUpdateLists() {
            removals++
            failure?.let { throw it }
        }
    }

    private fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    @Suppress("UNCHECKED_CAST")
    private fun hutch(): Hutch {
        val hutch = Hutch()
        val set =
            IsoCell::class.java.getDeclaredField("processIsoObjectSet").apply {
                isAccessible = true
            }
        (set.get(cell) as MutableSet<IsoObject>).add(hutch)
        cell.addToStaticUpdaterObjectList(hutch)
        HutchManager.getInstance().add(hutch)
        return hutch
    }

    private fun animal(): Animal = unsafe.allocateInstance(Animal::class.java) as Animal

    private fun unload(meta: Boolean) {
        val hutch = hutch()
        val first = animal()
        val last = animal()
        hutch.animalInside[0] = first
        hutch.animalInside[1] = null
        hutch.animalInside[2] = last
        NativeFixtureAccess.set(hutch, "animalInsideSize", 3.toByte())
        val original = hutch.animalInside
        val contents = HashMap(original)
        val before = removals.calls
        if (meta) hutch.removeFromWorldToMeta() else hutch.removeFromWorld()
        require(first.removals == 1 && last.removals == 1, "valid animals not cleaned exactly once")
        require(
            removals.calls == before + 1 && removals.contains(hutch),
            "native superclass cleanup skipped or repeated",
        )
        require(
            !cell.staticUpdaterObjectList.contains(hutch),
            "native static updater cleanup skipped",
        )
        require(
            hutch.animalInside === original && original == contents,
            "animal slots or identity changed",
        )
        require(NativeFixtureAccess.get<Byte>(hutch, "animalInsideSize").toInt() == 3, "stored count changed")
        val list =
            HutchManager::class.java.getDeclaredField("hutchList").apply { isAccessible = true }
        require(
            !(list.get(HutchManager.getInstance()) as List<*>).contains(hutch),
            "manager cleanup skipped",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        unsafe = field.get(null) as Unsafe
        cell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        removals = CountingSet()
        for (name in
            listOf(
                "processIsoObjectSet",
                "staticUpdaterObjectSet",
                "processIsoObjectRemove",
                "staticUpdaterObjectList",
            )) {
            val list = IsoCell::class.java.getDeclaredField(name).apply { isAccessible = true }
            list.set(
                cell,
                if (name == "processIsoObjectRemove") removals
                else if (name.endsWith("List")) ArrayList<IsoObject>() else HashSet<IsoObject>(),
            )
        }
        // Native IsoObject removal unregisters entities even for this isolated fixture.
        NativeFixtureAccess.field(zombie.entity.GameEntityManager::class.java, "engine")
            .set(null, zombie.entity.Engine())
        PerformanceSettings.fboRenderChunk = false

        // B42.22 owns the null-slot check. Exercise native cleanup without applying patches.
        for (mode in 0 until 3) {
            zombie.network.GameClient.client = mode == 0
            zombie.network.GameServer.server = mode == 2
            unload(false)
            unload(true)
        }

        val empty = hutch()
        var original = empty.animalInside
        empty.removeFromWorld()
        require(empty.animalInside === original && original.isEmpty(), "empty map replaced")
        val valid = animal()
        empty.animalInside[7] = valid
        empty.removeFromWorld()
        require(
            valid.removals == 1 && empty.animalInside === original,
            "valid-only cleanup changed",
        )
        empty.animalInside[7] = null
        empty.removeFromWorld()
        empty.removeFromWorld()
        require(
            empty.animalInside === original && original.size == 1 && original.containsKey(7),
            "repeated null-only unload changed slots",
        )

        val failing = hutch()
        val broken = animal()
        broken.failure = IllegalStateException("unrelated animal cleanup error")
        failing.animalInside[0] = broken
        failing.animalInside[1] = null
        original = failing.animalInside
        try {
            failing.removeFromWorld()
            throw AssertionError("unrelated exception swallowed")
        } catch (expected: IllegalStateException) {
            require(expected === broken.failure, "unrelated exception replaced")
        }
        require(
            failing.animalInside === original && original.size == 2 && broken.removals == 1,
            "exception did not restore slots",
        )

        println(
            "HUTCH_CHECKS_PASS (native null-safe direct/meta unload, client/SP/server, exact cleanup, slot restoration, repeat unload, unrelated errors)",
        )
    }
}
