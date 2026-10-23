package zombie.entity

import java.nio.ByteBuffer
import java.nio.BufferUnderflowException
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.CraftBenchReferences
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.JavaFunction
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.core.Transaction.TransactionState
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.entity.components.crafting.CraftBench
import zombie.entity.util.LongMap
import zombie.iso.IsoCell
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PZNetKahluaTableImpl
import zombie.network.ServerMap
import zombie.network.packets.NetTimedActionPacket
import zombie.util.list.PZArrayList

/** Reproduce native CraftBench decoding after another object on its square is removed. */
object CraftBenchChecks {
    private lateinit var unsafe: Unsafe
    private var constructors = 0
    private var requests = 0

    class Map : ServerMap() {
        lateinit var square: IsoGridSquare
        override fun getGridSquare(x: Int, y: Int, z: Int): IsoGridSquare? =
            square.takeIf { it.x == x && it.y == y && it.z == z }
    }

    class VirtualObject : IsoObject() {
        var squareReads = 0
        override fun getSquare(): IsoGridSquare? { squareReads++; return super.getSquare() }
    }

    private class Fixture(val square: IsoGridSquare, val objects: PZArrayList<IsoObject>, val forge: IsoObject,
                          val bench: CraftBench, val table: PZNetKahluaTableImpl)

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun set(type: Class<*>, target: Any, name: String, value: Any) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }

    @Suppress("UNCHECKED_CAST")
    private fun registry(): LongMap<GameEntity> = GameEntityManager::class.java.getDeclaredField("idToEntityMap")
        .apply { isAccessible = true }.get(null) as LongMap<GameEntity>

    private fun id(index: Int): Long = (index.toLong() shl 40) + (10510L shl 16) + 10714

    private fun payload(id: Long): ByteBufferReader {
        val bytes = ByteBuffer.allocate(14)
        bytes.putLong(id).putShort(ComponentType.CraftBench.GetID()).putInt(0x13572468).flip()
        return ByteBufferReader(bytes)
    }

    private fun missing(table: PZNetKahluaTableImpl, id: Long) {
        try {
            table.load(payload(id), null, 36.toByte())
            throw AssertionError("missing native CraftBench owner did not fail")
        } catch (expected: NullPointerException) {
            require(expected.stackTrace[0].methodName == "loadComponent", "wrong native failure")
        }
    }

    private fun fixture(): Fixture {
        registry().clear()
        val square = unsafe.allocateInstance(IsoGridSquare::class.java) as IsoGridSquare
        set(IsoGridSquare::class.java, square, "x", 10714)
        set(IsoGridSquare::class.java, square, "y", 10510)
        val objects = PZArrayList<IsoObject>(IsoObject::class.java, 4)
        set(IsoGridSquare::class.java, square, "objects", objects)
        val floor = IsoObject(); floor.square = square; objects.add(floor)
        val clutter = IsoObject(); clutter.square = square; objects.add(clutter)
        val forge = VirtualObject(); forge.square = square; objects.add(forge)
        val bench = ComponentType.CraftBench.CreateComponent() as CraftBench
        require((forge as GameEntity).addComponent(bench), "fixture could not attach native CraftBench")
        require(forge.entityNetID == id(2), "unexpected native entity ID format")
        registry().put(id(2), forge)
        objects.remove(clutter)
        require(forge.objectIndex == 1 && GameEntityManager.GetEntity(id(1)) == null,
            "fixture did not retain the stale server registry")
        val table = PZNetKahluaTableImpl(LinkedHashMap<Any, Any>())
        table.rawset("isoObject", forge)
        return Fixture(square, objects, forge, bench, table)
    }

    private fun framing(reader: ByteBufferReader) {
        require(reader.bb.int == 0x13572468 && !reader.bb.hasRemaining(), "component wire framing changed")
    }

    private fun packet(fixture: Fixture, workstation: Boolean) {
        val map = unsafe.allocateInstance(Map::class.java) as Map
        map.square = fixture.square
        ServerMap.instance = map
        IsoWorld.instance.currentCell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        val type = LuaManager.platform.newTable()
        type.rawset("new", JavaFunction { frame, _ ->
            require(frame.get(1) === fixture.forge, "native NetObject decoded a different workstation")
            require(frame.get(2) === (if (workstation) fixture.bench else null), "native constructor lost CraftBench/null")
            require("following-argument" == frame.get(3), "constructor argument order changed")
            constructors++
            frame.push(LuaManager.platform.newTable())
            1
        })
        val name = (if (workstation) "CraftBenchProbe" else "HandcraftProbe") + ++requests
        LuaManager.env.rawset(name, type)
        val bytes = ByteBuffer.allocate(1024)
        val writer = ByteBufferWriter(bytes)
        writer.putByte(17.toByte()); writer.putEnum(TransactionState.Request); writer.putShort(19.toShort()); writer.putByte((-1).toByte())
        writer.putUTF(name); writer.putUTF("forge-simple-blade-reference")
        writer.putInt(3)
        writer.putByte(1.toByte()); writer.putUTF("isoObject"); writer.putByte(7.toByte())
        PZNetKahluaTableImpl.saveIsoObject(bytes, fixture.forge)
        writer.putByte(1.toByte()); writer.putUTF("craftBench"); writer.putByte((if (workstation) 36 else 27).toByte())
        if (workstation) bytes.putLong(id(1)).putShort(ComponentType.CraftBench.GetID())
        writer.putByte(1.toByte()); writer.putUTF("following"); writer.putByte(1.toByte()); writer.putUTF("following-argument")
        bytes.flip()
        val packet = NetTimedActionPacket()
        packet.parse(ByteBufferReader(bytes), null)
        require(packet.action != null && !bytes.hasRemaining(), "native request did not construct exactly one action")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init()
        unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
        LuaManager.platform = J2SEPlatform(); LuaManager.env = LuaManager.platform.newTable()
        LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller = se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        GameServer.server = true; GameClient.client = false
        var fixture = fixture()
        missing(fixture.table, id(1))
        try {
            packet(fixture, true)
            throw AssertionError("native stale workstation request unexpectedly succeeded")
        } catch (expected: NullPointerException) {
            require(expected.stackTrace[0].methodName == "loadComponent", "wrong request failure")
        }
        require(constructors == 0, "failed native request reached the constructor")
        println("REPRODUCED native CraftBench loadComponent NPE after square object-index shift")
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CraftBenchChecks::class.java.classLoader)
        require(CraftBenchReferences.SUPPORTED, "unsupported CraftBench patch baseline")
        var reader = payload(id(1))
        require(fixture.table.load(reader, null, 36.toByte()) === fixture.bench, "patched decoder lost exact native CraftBench")
        framing(reader)
        require(GameEntityManager.GetEntity(id(1)) === fixture.forge && GameEntityManager.GetEntity(id(2)) == null,
            "native registry did not refresh the moved index")
        reader = payload(id(1))
        require(fixture.table.load(reader, null, 36.toByte()) === fixture.bench, "valid native component changed")
        framing(reader)
        fixture = fixture(); reader = payload(id(1))
        CraftBenchReferences.refresh(fixture.table, reader, 36.toByte(), false)
        require(reader.bb.position() == 0 && GameEntityManager.GetEntity(id(1)) == null, "unsupported refresh activated")
        // These lazy nullable boundaries must stay inert until their corresponding guard succeeds.
        CraftBenchReferences.refresh(null, null, 36.toByte(), false)
        CraftBenchReferences.refresh(null, null, 27.toByte(), true)
        CraftBenchReferences.refresh(null, ByteBufferReader(ByteBuffer.allocate(9)), 36.toByte(), true)
        val virtualObject = fixture.forge as VirtualObject
        virtualObject.squareReads = 0
        // Refusing an absent registry entry stops before native entityNetID can call getters itself.
        registry().clear()
        CraftBenchReferences.refresh(fixture.table, reader, 36.toByte(), true)
        require(virtualObject.squareReads > 0,
            "repair bypassed virtual spatial getters through public Java fields")
        registry().put(id(2), fixture.forge)
        GameServer.server = false; missing(fixture.table, id(1)); GameServer.server = true
        missing(PZNetKahluaTableImpl(LinkedHashMap<Any, Any>()), id(1))
        missing(fixture.table, id(3))
        require(GameEntityManager.GetEntity(id(1)) == null, "mismatched payload refreshed a different object")
        reader = payload(id(1)); reader.bb.limit(9)
        try {
            fixture.table.load(reader, null, 36.toByte())
            throw AssertionError("truncated component accepted")
        } catch (expected: BufferUnderflowException) { }
        require(GameEntityManager.GetEntity(id(1)) == null, "truncated payload mutated the registry")
        fixture.objects.remove(fixture.forge); missing(fixture.table, id(1))
        fixture = fixture(); registry().clear(); missing(fixture.table, id(1))
        require(GameEntityManager.GetEntity(id(1)) == null, "unregistered workstation was resurrected")
        fixture = fixture(); packet(fixture, true)
        require(constructors == 1, "native request constructor was replayed")
        fixture = fixture(); packet(fixture, false)
        require(constructors == 2 && GameEntityManager.GetEntity(id(1)) == null, "non-workstation request changed registry")
        println("CRAFT_BENCH_CHECKS_PASS (native stale-index NPE; woven exact component/framing; full request parsing; handcraft/null, removed, mismatched, unregistered, unsupported and truncated guards)")
    }
}
