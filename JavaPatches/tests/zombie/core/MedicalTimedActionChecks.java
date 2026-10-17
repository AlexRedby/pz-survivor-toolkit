package zombie.core;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.BufferUnderflowException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import net.alexredby.pztoolkitjavapatches.Main;
import net.alexredby.pztoolkitjavapatches.MedicalTimedActions;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import sun.misc.Unsafe;
import zombie.Lua.LuaManager;
import zombie.GameTime;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.BodyDamage.BodyPart;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.PZNetKahluaTableImpl;
import zombie.network.PacketTypes;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.NetTimedActionPacket;

public final class MedicalTimedActionChecks {
    static int constructors, acknowledgements;
    static BodyPart body;
    static Patient patient;
    static ByteBufferReader parsing;
    static Runnable nestedConstructor;

    public static final class Patient extends IsoPlayer {
        BodyDamage damage;
        Patient() { super(null); }
        public BodyDamage getBodyDamage() { return damage; }
    }
    public static final class Connection extends UdpConnection {
        ByteBuffer bytes;
        Connection() { super(null, 0, 0); }
        public ByteBufferWriter startPacket() { bytes.clear(); return new ByteBufferWriter(bytes); }
        public void endPacket(int priority, int reliability, byte channel) {
            bytes.flip();var reader = new ByteBufferReader(bytes);
            reader.getByte();require(reader.getShort() == PacketTypes.PacketType.NetTimedAction.getId(), "wrong rejection packet");
            require(reader.getByte() == 17 && reader.getEnum(Transaction.TransactionState.class) == Transaction.TransactionState.Reject,
                "native rejection changed transaction or state");
            var doctor = new PlayerID();doctor.parse(reader, null);
            require(doctor.getID() == 19 && !reader.bb.hasRemaining(), "native rejection changed doctor/framing");
            acknowledgements++;
        }
    }
    interface Checked { void run() throws Exception; }
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static void expect(Class<? extends Throwable> type, Checked callback) throws Exception {
        try { callback.run();throw new AssertionError("missing native failure " + type); }
        catch (Throwable failure) { if (!type.isInstance(failure)) throw new AssertionError("wrong failure", failure); }
    }
    static Field field(Class<?> type, String name) throws Exception {
        var field = type.getDeclaredField(name);field.setAccessible(true);return field;
    }
    static void clean() throws Exception {
        require(((ThreadLocal<?>)field(MedicalTimedActions.class, "current").get(null)).get() == null, "parse scope leaked");
    }
    static PZNetKahluaTableImpl table() { return new PZNetKahluaTableImpl(new LinkedHashMap<>()); }
    static void player(ByteBufferWriter writer, short id) { writer.putShort(id);writer.putByte(-1); }
    static ByteBufferReader bodyValue(short id) {
        var bytes = ByteBuffer.allocate(7);var writer = new ByteBufferWriter(bytes);player(writer, id);writer.putInt(0);bytes.flip();
        return new ByteBufferReader(bytes);
    }
    static ByteBufferReader wire(boolean medical, short patientID, byte finalType) {
        var bytes = ByteBuffer.allocate(512);var writer = new ByteBufferWriter(bytes);
        writer.putByte(17);writer.putEnum(Transaction.TransactionState.Request);player(writer, (short)19);
        writer.putUTF(medical ? "MedicalProbe" : "GenericProbe");writer.putUTF("owned-request");
        writer.putInt(medical ? 3 : 2);
        writer.putByte(1);writer.putUTF("owner");writer.putByte(8);player(writer, (short)19);
        if (medical) {writer.putByte(1);writer.putUTF("bodyPart");writer.putByte(10);player(writer, patientID);writer.putInt(0);}
        writer.putByte(1);writer.putUTF("following");writer.putByte(finalType);
        if (finalType == 1) writer.putUTF("after-body-payload");
        bytes.flip();return new ByteBufferReader(bytes);
    }
    static void ctor(boolean medical) {
        var type = LuaManager.platform.newTable();
        type.rawset("new", (JavaFunction)(frame, count) -> {
            constructors++;
            require(frame.get(1) == GameServer.IDToPlayerMap.get((short)19), "constructor doctor changed");
            require(!medical || frame.get(2) == body, "constructor lost exact native BodyPart");
            require(frame.get(medical ? 3 : 2).equals("after-body-payload"), "remaining payload changed");
            require(!parsing.bb.hasRemaining(), "constructor ran before complete argument decoding");
            Runnable nested = nestedConstructor;nestedConstructor = null;if (nested != null) nested.run();
            frame.push(LuaManager.platform.newTable());return 1;
        });
        LuaManager.env.rawset(medical ? "MedicalProbe" : "GenericProbe", type);
    }
    static NetTimedActionPacket parse(ByteBufferReader reader) {
        var packet = new NetTimedActionPacket();parsing = reader;packet.parse(reader, null);return packet;
    }
    static void scopeChecks() throws Exception {
        var packet = new NetTimedActionPacket();packet.state = Transaction.TransactionState.Request;
        packet.playerId.setID((short)19);packet.playerId.setPlayerIndex((byte)-1);
        field(PlayerID.class, "player").set(packet.playerId, GameServer.IDToPlayerMap.get((short)19));
        var previous = table();((NetTimedAction)packet).actionArgs = previous;previous.rawset("live", "unchanged");
        var reader = bodyValue((short)20);
        var outer = MedicalTimedActions.begin(packet, reader, true);
        require(MedicalTimedActions.beginArguments(previous, reader) == null, "cached Request args activated before current header");
        ((NetTimedAction)packet).actionArgs = table();var arguments = MedicalTimedActions.beginArguments(((NetTimedAction)packet).actionArgs, reader);
        var duplicate = new ByteBufferReader(reader.bb.duplicate());
        MedicalTimedActions.beforeValue(((NetTimedAction)packet).actionArgs, duplicate, null, (byte)10);
        MedicalTimedActions.beforeValue(((NetTimedAction)packet).actionArgs, new ByteBufferReader(reader.bb), null, (byte)10);
        var inner = MedicalTimedActions.begin(new NetTimedAction(), reader, true);
        MedicalTimedActions.beforeValue(((NetTimedAction)packet).actionArgs, reader, null, (byte)10);
        require(!MedicalTimedActions.end(inner, new IllegalStateException("foreign")), "nested foreign failure suppressed");
        Throwable stale = null;
        try { MedicalTimedActions.beforeValue(((NetTimedAction)packet).actionArgs, reader, null, (byte)10); }
        catch (RuntimeException failure) { stale = failure; }
        require(stale != null && reader.bb.position() == 0, "outer scope not restored or lookahead consumed payload");
        MedicalTimedActions.endArguments(arguments);
        require(MedicalTimedActions.beginArguments(((NetTimedAction)packet).actionArgs, reader) == null, "Lua constructor could reactivate argument decoding");
        require(MedicalTimedActions.end(outer, stale), "owned stale signal not handled");
        require(previous.rawget("live").equals("unchanged"), "live previous args mutated");
        clean();
        expect(NullPointerException.class, () -> table().load(bodyValue((short)20), null, (byte)10));
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var unsafeField = Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe)unsafeField.get(null);
        GameTime.setInstance(new GameTime());
        LuaManager.platform = new J2SEPlatform();LuaManager.env = LuaManager.platform.newTable();
        LuaManager.thread = new se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        var doctor = (Patient)unsafe.allocateInstance(Patient.class);doctor.onlineId = 19;
        patient = (Patient)unsafe.allocateInstance(Patient.class);patient.onlineId = 20;
        field(zombie.iso.IsoObject.class, "ecsComponentMap").set(doctor, new java.util.HashMap<>());
        field(zombie.iso.IsoObject.class, "ecsComponentMap").set(patient, new java.util.HashMap<>());
        patient.damage = (BodyDamage)unsafe.allocateInstance(BodyDamage.class);
        body = (BodyPart)unsafe.allocateInstance(BodyPart.class);
        field(BodyDamage.class, "bodyParts").set(patient.damage, new ArrayList<>(java.util.List.of(body)));
        GameServer.server = true;GameClient.client = false;GameServer.IDToPlayerMap.put((short)19, doctor);
        ctor(true);ctor(false);
        require(Main.MEDICAL_TIMED_ACTION_SUPPORTED, "unsupported timed-action patch baseline");
        require(Main.supports("zombie/network/PZNetKahluaTableImpl.class", "201f0e59502fc5a106f8c9021e0b0d13a30dcb8d0beb9e8934cec390231ddba6"), "unsupported native table decoder");
        require(!Main.supports("zombie/network/PZNetKahluaTableImpl.class", "unknown"), "unknown decoder accepted");
        var unsupportedReader = bodyValue((short)20);
        var unsupported = MedicalTimedActions.begin(new NetTimedActionPacket(), unsupportedReader, false);
        require(unsupported == null && !MedicalTimedActions.end(unsupported, null), "unsupported decoder guard activated");
        MedicalTimedActions.beforeValue(table(), unsupportedReader, null, (byte)10);
        expect(NullPointerException.class, () -> table().load(unsupportedReader, null, (byte)10));clean();
        expect(NullPointerException.class, () -> parse(wire(true, (short)20, (byte)1)));
        require(constructors == 0, "original stale request constructed action");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MedicalTimedActionChecks.class.getClassLoader());
        var staleReader = wire(true, (short)20, (byte)1);var stale = new NetTimedActionPacket();
        var live = LuaManager.platform.newTable();live.rawset("live", "unchanged");stale.action = live;
        var oldArgs = table();oldArgs.rawset("live", "unchanged");((NetTimedAction)stale).actionArgs = oldArgs;
        stale.parse(staleReader, null);
        clean();
        require(constructors == 0 && stale.action == null && ((NetTimedAction)stale).actionArgs.size() == 0 && !staleReader.bb.hasRemaining(), "stale packet reached constructor or retained payload/action");
        require(live.rawget("live").equals("unchanged") && oldArgs.size() == 1, "cached live action/args mutated");
        var existing = new NetTimedAction();existing.id = 18;existing.playerId.copy(stale.playerId);
        existing.state = Transaction.TransactionState.Accept;existing.action = live;existing.actionArgs = oldArgs;
        @SuppressWarnings("unchecked") var actions = (java.util.Queue<Object>)field(ActionManager.class, "actions").get(null);
        actions.add(existing);
        var connection = (Connection)unsafe.allocateInstance(Connection.class);connection.bytes = ByteBuffer.allocate(1024);
        stale.processServer(PacketTypes.PacketType.NetTimedAction, connection);
        require(acknowledgements == 1 && constructors == 0, "native Reject acknowledgement lost");
        require(actions.contains(existing) && existing.state == Transaction.TransactionState.Accept
            && existing.action == live && existing.actionArgs == oldArgs, "stale request canceled/mutated prior ActionManager action");
        actions.remove(existing);
        GameServer.IDToPlayerMap.put((short)20, patient);
        require(parse(wire(true, (short)20, (byte)1)).action != null && constructors == 1, "valid medical parse was changed/repeated");
        clean();
        require(parse(wire(false, (short)20, (byte)1)).action != null && constructors == 2, "generic non-body parse was changed/repeated");
        clean();
        nestedConstructor = () -> require(parse(wire(false, (short)20, (byte)1)).action != null, "nested generic parse changed");
        require(parse(wire(true, (short)20, (byte)1)).action != null && constructors == 4, "nested parse lost/repeated constructor");
        clean();
        var unknown = wire(true, (short)20, (byte)100);
        expect(RuntimeException.class, () -> parse(unknown));require(constructors == 4, "unknown value reached constructor");clean();
        var truncated = wire(true, (short)20, (byte)1);truncated.bb.limit(truncated.bb.limit()-5);
        expect(BufferUnderflowException.class, () -> parse(truncated));clean();
        GameServer.IDToPlayerMap.remove((short)20);
        expect(NullPointerException.class, () -> table().load(bodyValue((short)20), null, (byte)10));
        scopeChecks();
        System.out.println("MEDICAL_TIMED_ACTION_CHECKS_PASS (original NPE, woven stale Reject/no constructor, valid medical/generic single parse, exact framing, unsupported/unknown/truncated failures, nested and cached scope isolation)");
    }
}
