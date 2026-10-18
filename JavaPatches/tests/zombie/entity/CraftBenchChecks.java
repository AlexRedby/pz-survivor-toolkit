package zombie.entity;

import java.nio.ByteBuffer;
import java.nio.BufferUnderflowException;
import java.util.LinkedHashMap;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.CraftBenchReferences;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.JavaFunction;
import sun.misc.Unsafe;
import zombie.Lua.LuaManager;
import zombie.core.Transaction.TransactionState;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.entity.components.crafting.CraftBench;
import zombie.entity.util.LongMap;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PZNetKahluaTableImpl;
import zombie.network.ServerMap;
import zombie.network.packets.NetTimedActionPacket;
import zombie.util.list.PZArrayList;

/** Reproduce native CraftBench decoding after another object on its square is removed. */
public final class CraftBenchChecks {
    static Unsafe unsafe;
    static int constructors, requests;
    public static final class Map extends ServerMap {
        IsoGridSquare square;
        public IsoGridSquare getGridSquare(int x, int y, int z) {
            return square.getX() == x && square.getY() == y && square.getZ() == z ? square : null;
        }
    }
    record Fixture(IsoGridSquare square, PZArrayList<IsoObject> objects, IsoObject forge,
                   CraftBench bench, PZNetKahluaTableImpl table) {}
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static void set(Class<?> type, Object target, String name, Object value) throws Exception {
        var field = type.getDeclaredField(name);field.setAccessible(true);field.set(target, value);
    }
    @SuppressWarnings("unchecked")
    static LongMap<GameEntity> registry() throws Exception {
        var field = GameEntityManager.class.getDeclaredField("idToEntityMap");field.setAccessible(true);
        return (LongMap<GameEntity>)field.get(null);
    }
    static long id(int index) { return ((long)index << 40) + ((long)10510 << 16) + 10714; }
    static ByteBufferReader payload(long id) {
        var bytes = ByteBuffer.allocate(14);
        bytes.putLong(id).putShort(ComponentType.CraftBench.GetID()).putInt(0x13572468).flip();
        return new ByteBufferReader(bytes);
    }
    static void missing(PZNetKahluaTableImpl table, long id) {
        try {
            table.load(payload(id), null, (byte)36);
            throw new AssertionError("missing native CraftBench owner did not fail");
        } catch (NullPointerException expected) {
            require(expected.getStackTrace()[0].getMethodName().equals("loadComponent"), "wrong native failure");
        }
    }
    static Fixture fixture() throws Exception {
        registry().clear();
        var square = (IsoGridSquare)unsafe.allocateInstance(IsoGridSquare.class);
        set(IsoGridSquare.class, square, "x", 10714);set(IsoGridSquare.class, square, "y", 10510);
        var objects = new PZArrayList<IsoObject>(IsoObject.class, 4);
        set(IsoGridSquare.class, square, "objects", objects);
        var floor = new IsoObject();floor.setSquare(square);objects.add(floor);
        var clutter = new IsoObject();clutter.setSquare(square);objects.add(clutter);
        var forge = new IsoObject();forge.setSquare(square);objects.add(forge);
        var bench = (CraftBench)ComponentType.CraftBench.CreateComponent();
        require(((GameEntity)forge).addComponent(bench), "fixture could not attach native CraftBench");
        require(forge.getEntityNetID() == id(2), "unexpected native entity ID format");
        registry().put(id(2), forge);
        objects.remove(clutter);
        // The client refreshes its copy while encoding. The server's native registry
        // still contains the former index until getEntityNetID is called there.
        require(forge.getObjectIndex() == 1 && GameEntityManager.GetEntity(id(1)) == null,
            "fixture did not retain the stale server registry");
        var table = new PZNetKahluaTableImpl(new LinkedHashMap<>());
        table.rawset("isoObject", forge);
        return new Fixture(square, objects, forge, bench, table);
    }
    static void framing(ByteBufferReader reader) {
        require(reader.bb.getInt() == 0x13572468 && !reader.bb.hasRemaining(), "component wire framing changed");
    }
    static void packet(Fixture fixture, boolean workstation) throws Exception {
        var map = (Map)unsafe.allocateInstance(Map.class);map.square = fixture.square;
        ServerMap.instance = map;
        IsoWorld.instance.currentCell = (IsoCell)unsafe.allocateInstance(IsoCell.class);
        var type = LuaManager.platform.newTable();
        type.rawset("new", (JavaFunction)(frame, count) -> {
            require(frame.get(1) == fixture.forge, "native NetObject decoded a different workstation");
            require(frame.get(2) == (workstation ? fixture.bench : null), "native constructor lost CraftBench/null");
            require("following-argument".equals(frame.get(3)), "constructor argument order changed");
            constructors++;frame.push(LuaManager.platform.newTable());return 1;
        });
        String name = (workstation ? "CraftBenchProbe" : "HandcraftProbe") + ++requests;
        LuaManager.env.rawset(name, type);
        var bytes = ByteBuffer.allocate(1024);var writer = new ByteBufferWriter(bytes);
        writer.putByte(17);writer.putEnum(TransactionState.Request);writer.putShort((short)19);writer.putByte(-1);
        writer.putUTF(name);writer.putUTF("forge-simple-blade-reference");
        writer.putInt(3);
        writer.putByte(1);writer.putUTF("isoObject");writer.putByte(7);
        PZNetKahluaTableImpl.saveIsoObject(bytes, fixture.forge);
        writer.putByte(1);writer.putUTF("craftBench");writer.putByte(workstation ? (byte)36 : (byte)27);
        if (workstation) bytes.putLong(id(1)).putShort(ComponentType.CraftBench.GetID());
        writer.putByte(1);writer.putUTF("following");writer.putByte(1);writer.putUTF("following-argument");
        bytes.flip();var packet = new NetTimedActionPacket();packet.parse(new ByteBufferReader(bytes), null);
        require(packet.action != null && !bytes.hasRemaining(), "native request did not construct exactly one action");
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var unsafeField = Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        unsafe = (Unsafe)unsafeField.get(null);
        LuaManager.platform = new J2SEPlatform();LuaManager.env = LuaManager.platform.newTable();
        LuaManager.thread = new se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        GameServer.server = true;GameClient.client = false;
        var fixture = fixture();
        missing(fixture.table, id(1));
        try { packet(fixture, true);throw new AssertionError("native stale workstation request unexpectedly succeeded"); }
        catch (NullPointerException expected) {
            require(expected.getStackTrace()[0].getMethodName().equals("loadComponent"), "wrong request failure");
        }
        require(constructors == 0, "failed native request reached the constructor");
        System.out.println("REPRODUCED native CraftBench loadComponent NPE after square object-index shift");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CraftBenchChecks.class.getClassLoader());
        require(CraftBenchReferences.SUPPORTED, "unsupported CraftBench patch baseline");
        var reader = payload(id(1));
        require(fixture.table.load(reader, null, (byte)36) == fixture.bench, "patched decoder lost exact native CraftBench");
        framing(reader);
        require(GameEntityManager.GetEntity(id(1)) == fixture.forge && GameEntityManager.GetEntity(id(2)) == null,
            "native registry did not refresh the moved index");
        reader = payload(id(1));
        require(fixture.table.load(reader, null, (byte)36) == fixture.bench, "valid native component changed");framing(reader);
        fixture = fixture();reader = payload(id(1));
        CraftBenchReferences.refresh(fixture.table, reader, (byte)36, false);
        require(reader.bb.position() == 0 && GameEntityManager.GetEntity(id(1)) == null, "unsupported refresh activated");
        GameServer.server = false;missing(fixture.table, id(1));GameServer.server = true;
        missing(new PZNetKahluaTableImpl(new LinkedHashMap<>()), id(1));
        missing(fixture.table, id(3));
        require(GameEntityManager.GetEntity(id(1)) == null, "mismatched payload refreshed a different object");
        reader = payload(id(1));reader.bb.limit(9);
        try { fixture.table.load(reader, null, (byte)36);throw new AssertionError("truncated component accepted"); }
        catch (BufferUnderflowException expected) {}
        require(GameEntityManager.GetEntity(id(1)) == null, "truncated payload mutated the registry");
        fixture.objects.remove(fixture.forge);missing(fixture.table, id(1));
        fixture = fixture();registry().clear();missing(fixture.table, id(1));
        require(GameEntityManager.GetEntity(id(1)) == null, "unregistered workstation was resurrected");
        fixture = fixture();packet(fixture, true);
        require(constructors == 1, "native request constructor was replayed");
        fixture = fixture();packet(fixture, false);
        require(constructors == 2 && GameEntityManager.GetEntity(id(1)) == null, "non-workstation request changed registry");
        System.out.println("CRAFT_BENCH_CHECKS_PASS (native stale-index NPE; woven exact component/framing; full request parsing; handcraft/null, removed, mismatched, unregistered, unsupported and truncated guards)");
    }
}
