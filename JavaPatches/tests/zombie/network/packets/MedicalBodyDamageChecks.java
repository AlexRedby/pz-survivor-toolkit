package zombie.network.packets;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.Main;
import net.alexredby.pztoolkitjavapatches.MedicalBodyDamage;
import sun.misc.Unsafe;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.IsoPlayer;
import zombie.characters.Stats;
import zombie.network.fields.character.PlayerID;

public final class MedicalBodyDamageChecks {
    public static final class Patient extends IsoPlayer {
        BodyDamage damage;
        Stats stats;
        Patient() { super(null); }
        public BodyDamage getBodyDamageRemote() { return damage; }
        public Stats getStats() { return stats; }
    }

    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static Field field(Class<?> type, String name) throws Exception {
        Field value = type.getDeclaredField(name); value.setAccessible(true); return value;
    }
    static ByteBuffer data(BodyDamageUpdatePacket packet) throws Exception {
        return (ByteBuffer)field(BodyDamageUpdatePacket.class, "data").get(packet);
    }
    static BodyDamageUpdatePacket packet(String type, IsoPlayer patient) throws Exception {
        var packet = new BodyDamageUpdatePacket();
        var typeField = field(BodyDamageUpdatePacket.class, "packetType");
        for (Object value : typeField.getType().getEnumConstants())
            if (((Enum<?>)value).name().equals(type)) typeField.set(packet, value);
        var id = (PlayerID)field(BodyDamageUpdatePacket.class, "remotePlayer").get(packet);
        field(PlayerID.class, "player").set(id, patient);
        // Native UPDATE overall-health payload, then BD_END. Keep its position nonzero to detect skipped parsing.
        ByteBuffer data = ByteBuffer.allocate(12).put((byte)50).putFloat(73.5f).put((byte)4).put((byte)1).putFloat(12.5f).put((byte)65);
        field(BodyDamageUpdatePacket.class, "data").set(packet, data);
        return packet;
    }
    static void staleThrows(BodyDamageUpdatePacket packet) {
        try { packet.processClient(null); throw new AssertionError("native stale UPDATE did not reproduce NPE"); }
        catch (NullPointerException expected) {
            require(expected.getMessage().contains("getBodyDamageRemote"), "unrelated native NPE: " + expected);
        }
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        require(Main.MEDICAL_BODY_DAMAGE_SUPPORTED, "unsupported medical patch baseline");
        require(BytecodeSupport.supports("zombie/network/packets/BodyDamageUpdatePacket.class", "2e37ca1add6b8696464285bd498e7c97cd9712c9094c51d1d57daac688145c8c"), "unsupported native packet");
        require(BytecodeSupport.supports("zombie/network/fields/character/PlayerID.class", "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56"), "unsupported native player resolution");
        require(!BytecodeSupport.supports("zombie/network/packets/BodyDamageUpdatePacket.class", "unknown"), "unknown bytecode accepted");
        Field unsafeField = Unsafe.class.getDeclaredField("theUnsafe"); unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe)unsafeField.get(null);
        var patient = (Patient)unsafe.allocateInstance(Patient.class);
        patient.damage = (BodyDamage)unsafe.allocateInstance(BodyDamage.class); patient.stats = new Stats();
        var stale = packet("UPDATE", null);
        require(!MedicalBodyDamage.skip(stale, false), "unsupported guard skipped packet");
        staleThrows(stale);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MedicalBodyDamageChecks.class.getClassLoader());
        stale = packet("UPDATE", null);
        stale.processClient(null);
        require(data(stale).position() == 12, "stale UPDATE consumed payload");
        for (var type : new String[]{"START_UPDATING", "STOP_UPDATING"}) {
            var control = packet(type, null);
            require(!MedicalBodyDamage.skip(control, true), "control packet skipped");
            control.processClient(null); require(data(control).position() == 12, "control packet parsed UPDATE data");
        }
        var valid = packet("UPDATE", patient);
        require(!MedicalBodyDamage.skip(valid, true), "valid UPDATE skipped");
        valid.processClient(null);
        require(patient.damage.getOverallBodyHealth() == 73.5f && patient.damage.getRemotePainLevel() == 4
            && patient.damage.isFakeInfected && patient.stats.get(zombie.characters.CharacterStat.ZOMBIE_INFECTION) == 12.5f,
            "valid native UPDATE effect lost");
        require(data(valid).position() == 12, "valid native payload not fully consumed");
        System.out.println("MEDICAL_BODY_DAMAGE_CHECKS_PASS (original stale NPE, woven stale no-op, native valid effects, controls and unsupported guards)");
    }
}
