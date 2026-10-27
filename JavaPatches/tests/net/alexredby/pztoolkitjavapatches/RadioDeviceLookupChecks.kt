package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.inventory.InventoryItem
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.iso.objects.IsoRadio
import zombie.iso.objects.IsoTelevision
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.radio.devices.DeviceData
import zombie.util.list.PZArrayList
import zombie.vehicles.VehiclePart

/** Headless real-game Kahlua/native identity regression; does not launch or install the game. */
object RadioDeviceLookupChecks {
    private val unsafe =
        Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
            as Unsafe
    private var cases = 0

    private fun set(owner: Any, type: Class<*>, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(owner, value)
    }

    private fun <T> nativeShell(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun square(): IsoGridSquare =
        nativeShell(IsoGridSquare::class.java).apply {
            set(
                this,
                IsoGridSquare::class.java,
                "worldObjects",
                ArrayList<IsoWorldInventoryObject>(),
            )
            set(this, IsoGridSquare::class.java, "objects", PZArrayList(IsoObject::class.java, 16))
        }

    private fun item(id: Int, fullType: String): InventoryItem =
        nativeShell(InventoryItem::class.java).apply {
            setID(id)
            rename(this, fullType)
        }

    private fun rename(item: InventoryItem, fullType: String) {
        set(item, InventoryItem::class.java, "fullType", fullType)
        set(item, InventoryItem::class.java, "module", fullType.substringBefore('.'))
        set(item, InventoryItem::class.java, "type", fullType.substringAfter('.'))
    }

    private fun wrapper(item: InventoryItem?, square: IsoGridSquare): IsoWorldInventoryObject =
        nativeShell(IsoWorldInventoryObject::class.java).apply {
            this.item = item
            setSquare(square)
        }

    private fun runLua(source: String): Any? =
        LuaManager.thread.call(
            LuaCompiler.loadstring(source, "radio-device-lookup-check", LuaManager.env),
            emptyArray<Any?>(),
        )

    private fun check(expected: String, reuse: Boolean = false, invalidated: Boolean = false) {
        runLua("Check('$expected', $reuse, $invalidated)")
        cases++
    }

    private fun setup() {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager()
        KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        val types =
            listOf(
                InventoryItem::class.java,
                IsoObject::class.java,
                IsoRadio::class.java,
                IsoTelevision::class.java,
                IsoWorldInventoryObject::class.java,
                IsoGridSquare::class.java,
                DeviceData::class.java,
                VehiclePart::class.java,
                ArrayList::class.java,
                PZArrayList::class.java,
            )
        for (type in types) LuaManager.exposer.setExposed(type)
        for (type in types) {
            LuaManager.exposer.exposeLikeJava(type, LuaManager.env)
            // exposeLikeJava alone does not supply the short names used by native instanceof.
            LuaManager.exposer.typeMap[type.simpleName] = type
            check(LuaManager.exposer.isExposed(type)) { "native type not exposed: $type" }
        }
        LuaManager.exposer.exposeGlobalClassFunction(
            LuaManager.env,
            LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class
                .java
                .getMethod("instof", Any::class.java, String::class.java),
            "instanceof",
        )
        LuaManager.thread = KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        runLua(
            """
            PZSurvivorToolkit={}
            require=function(name)
                assert(name=='PZSurvivorToolkit/Settings', 'unexpected dependency '..name)
            end
            getItemNameFromFullType=function(value) return 'translated:'..value end
            """
                .trimIndent(),
        )
        val path =
            Path.of(System.getProperty("pz.test.project"))
                .resolve(
                    "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVDeviceResolver.lua",
                )
        LuaManager.env.rawset("Resolver", runLua(Files.readString(path)) as KahluaTable)
        runLua(
            """
            Binding=nil
            function Check(expected,reuse,invalidated)
                local previous=Binding
                local cached,binding=Resolver.fullType(Device,Binding)
                local uncached=Resolver.fullType(Device)
                assert(cached==expected, 'cached expected '..tostring(expected)..' got '..tostring(cached))
                assert(uncached==expected, 'uncached expected '..tostring(expected)..' got '..tostring(uncached))
                if reuse then assert(binding==previous and binding~=nil, 'valid binding replaced') end
                if invalidated then
                    assert(previous~=nil and binding~=previous, 'invalid native binding reused')
                end
                if expected=='Base.RadioMakeShift' then assert(binding==nil, 'fallback was cached')
                else assert(binding~=nil, 'native positive lookup did not create a binding') end
                Binding=binding
            end
            function TimedLookup(count,cached)
                local binding=Binding
                for i=1,count do
                    local fullType,nextBinding=Resolver.fullType(Device,cached and binding or nil)
                    assert(fullType=='Regression.Radio', 'timing lookup changed identity')
                    if cached then
                        assert(nextBinding==binding, 'timing replaced a valid binding')
                    end
                end
            end
            """
                .trimIndent(),
        )
    }

    private fun timing(label: String, square: IsoGridSquare) {
        check("Regression.Radio")
        runLua("TimedLookup(10,true); TimedLookup(2,false)")
        val cached = LongArray(3)
        val uncached = LongArray(3)
        val function = LuaManager.env.rawget("TimedLookup")
        for (sample in cached.indices) {
            var start = System.nanoTime()
            LuaManager.thread.call(function, arrayOf<Any?>(1000.0, true))
            cached[sample] = (System.nanoTime() - start) / 1000
            start = System.nanoTime()
            LuaManager.thread.call(function, arrayOf<Any?>(20.0, false))
            uncached[sample] = (System.nanoTime() - start) / 20
        }
        println(
            "RADIO_LOOKUP_TIMING list=$label world=${square.worldObjects.size} " +
                "objects=${square.objects.size} samples=3 cached_calls=1000 uncached_calls=20 " +
                "cached_ns_per_call=${cached.joinToString(",")} " +
                "uncached_ns_per_call=${uncached.joinToString(",")} " +
                "scope=resolver_leaf_not_FPS",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        setup()
        // Allocate native shells to avoid unrelated renderer/chat/world startup. All lookup,
        // collection, item and userdata operations below use the real, unoverridden game methods.
        val square = square()
        val radio = nativeShell(IsoRadio::class.java)
        radio.setSquare(square)
        radio.setModData(LuaManager.platform.newTable())
        radio.modData.rawset("RadioItemID", 42.0)
        val item = item(42, "Regression.Radio")
        val target = wrapper(item, square)
        val other = wrapper(item(43, "Regression.Other"), square)
        LuaManager.env.rawset("Device", radio)
        LuaManager.env.rawset("NativeSquare", square)
        LuaManager.env.rawset("NativeItem", item)
        LuaManager.env.rawset("NativeObject", target)
        runLua(
            """
            assert(instanceof(Device,'IsoRadio') and instanceof(Device,'IsoObject'))
            assert(not instanceof(Device,'InventoryItem') and not instanceof(Device,'VehiclePart'))
            assert(instanceof(NativeSquare,'IsoGridSquare'))
            assert(instanceof(NativeObject,'IsoWorldInventoryObject'))
            assert(instanceof(NativeItem,'InventoryItem'))
            assert(Device:getSquare()==NativeSquare and NativeObject:getItem()==NativeItem)
            assert(NativeSquare:getWorldObjects()==NativeSquare:getWorldObjects())
            assert(NativeSquare:getObjects()==NativeSquare:getObjects())
            """
                .trimIndent(),
        )
        check("Base.RadioMakeShift")
        square.worldObjects.add(target)
        check("Regression.Radio")
        check("Regression.Radio", reuse = true)
        set(square, IsoGridSquare::class.java, "worldObjects", arrayListOf(target))
        check("Regression.Radio", invalidated = true)
        square.worldObjects.add(0, other)
        check("Regression.Radio", invalidated = true)
        square.worldObjects.removeAt(0)
        check("Regression.Radio", invalidated = true)
        square.worldObjects.add(other)
        java.util.Collections.swap(square.worldObjects, 0, 1)
        check("Regression.Radio", invalidated = true)
        // Removal deliberately leaves the world wrapper's and radio's square references stale.
        square.worldObjects.remove(target)
        check(target.square === square && radio.square === square)
        check("Base.RadioMakeShift")
        check("Base.RadioMakeShift")
        square.objects.add(target)
        check("Regression.Radio")
        check("Regression.Radio", reuse = true)
        square.objects.add(0, other)
        check("Regression.Radio", invalidated = true)
        square.objects.removeAt(0)
        check("Regression.Radio", invalidated = true)
        val replacement = wrapper(item, square)
        square.objects[0] = replacement
        check("Regression.Radio", invalidated = true)
        val replacementItem = item(42, "Regression.Replacement")
        replacement.item = replacementItem
        check("Regression.Replacement", invalidated = true)
        rename(replacementItem, "Regression.Renamed")
        check("Regression.Renamed", reuse = true)
        replacementItem.setID(44)
        check("Base.RadioMakeShift")
        radio.modData.rawset("RadioItemID", 44.0)
        check("Regression.Renamed")
        // Replace the actual native list object while retaining its member and position.
        val newObjects = PZArrayList(IsoObject::class.java, 16)
        newObjects.add(replacement)
        set(square, IsoGridSquare::class.java, "objects", newObjects)
        check("Regression.Renamed", invalidated = true)
        val moved = square()
        moved.worldObjects.add(wrapper(item(44, "Regression.Moved"), moved))
        radio.setSquare(moved)
        check("Regression.Moved", invalidated = true)
        radio.setSquare(square)
        check("Regression.Renamed", invalidated = true)
        // A second real radio may share a square/ID, but must not inherit another device's binding.
        val peer = nativeShell(IsoRadio::class.java)
        peer.setSquare(square)
        peer.setModData(radio.modData)
        LuaManager.env.rawset("Device", peer)
        check("Regression.Renamed", invalidated = true)
        square.objects.clear()
        square.worldObjects.clear()
        radio.modData.rawset("RadioItemID", 42.0)
        LuaManager.env.rawset("Device", radio)
        repeat(10_000) { square.worldObjects.add(wrapper(null, square)) }
        square.worldObjects.add(target)
        timing("worldObjects", square)
        square.worldObjects.clear()
        repeat(10_000) { square.objects.add(wrapper(null, square)) }
        square.objects.add(target)
        timing("objects", square)
        runLua(
            """
            assert(Device:getSquare()==NativeSquare and NativeObject:getItem()==NativeItem)
            assert(NativeSquare:getObjects():get(10000)==NativeObject)
            """
                .trimIndent(),
        )
        println(
            "RADIO_DEVICE_LOOKUP_CHECKS_PASS cases=$cases native_identity=true stress_objects=10000",
        )
    }
}
