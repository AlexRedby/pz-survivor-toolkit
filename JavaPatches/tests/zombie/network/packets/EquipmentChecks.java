package zombie.network.packets;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferReader;
import zombie.network.GameClient;
import net.alexredby.pztoolkitjavapatches.Main;

public final class EquipmentChecks {
    static final class LocalPlayer extends IsoPlayer {
        LocalPlayer() { super(null); }
        public boolean isLocalPlayer() { return true; }
    }
    static final class CountingPacket extends EquipPacket {
        int acknowledgements;
        public void sendToServer(zombie.network.PacketTypes.PacketType type) { acknowledgements++; }
    }
    static void owner(EquipPacket packet, IsoPlayer owner) throws Exception {
        Field field = zombie.network.fields.character.PlayerID.class.getDeclaredField("player");
        field.setAccessible(true); field.set(packet.player, owner);
    }
    static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Field field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true);
        Unsafe unsafe = (Unsafe)field.get(null);
        IsoPlayer local = (IsoPlayer)unsafe.allocateInstance(LocalPlayer.class);
        IsoPlayer remote = (IsoPlayer)unsafe.allocateInstance(IsoPlayer.class);
        EquipPacket packet = new EquipPacket(); owner(packet, local);
        EquipPacket other = new EquipPacket(); owner(other, local);
        ByteBufferReader unread = new ByteBufferReader(ByteBuffer.wrap(new byte[]{2}));
        ByteBufferReader complete = new ByteBufferReader(ByteBuffer.allocate(0));
        GameClient.client = true;
        require(Main.EQUIPMENT_SUPPORTED, "unsupported equipment baseline");
        Main.EquipmentParsed.exit(packet, unread, null);
        require(Main.EquipmentEcho.enter(packet, null), "incomplete local packet acknowledged");
        require(!Main.EquipmentEcho.enter(packet, null), "repeated packet suppressed");
        Main.EquipmentParsed.exit(packet, complete, null);
        require(!Main.EquipmentEcho.enter(packet, null), "valid equipment update suppressed");
        Main.EquipmentParsed.exit(packet, unread, null);
        require(!Main.EquipmentEcho.enter(other, null), "different packet suppressed");
        require(!Main.EquipmentEcho.enter(packet, null), "stale incomplete state retained");
        Main.EquipmentParsed.exit(packet, unread, null);
        Main.EquipmentParsed.exit(packet, complete, null);
        require(!Main.EquipmentEcho.enter(packet, null), "reused packet retained rejection");
        owner(packet, remote);
        Main.EquipmentParsed.exit(packet, unread, null);
        require(!Main.EquipmentEcho.enter(packet, null), "remote equipment update suppressed");
        GameClient.client = false; owner(packet, local);
        Main.EquipmentParsed.exit(packet, unread, null);
        require(!Main.EquipmentEcho.enter(packet, null), "server or standalone update suppressed");
        GameClient.client = true;
        CountingPacket counted = new CountingPacket(); owner(counted, local);
        Main.EquipmentParsed.exit(counted, unread, null);
        counted.processClient(null);
        require(counted.acknowledgements == 1, "vanilla did not acknowledge incomplete equipment");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", EquipmentChecks.class.getClassLoader());
        Main.EquipmentParsed.exit(counted, unread, null);
        counted.processClient(null);
        require(counted.acknowledgements == 1, "woven prefix acknowledged incomplete equipment");
        Main.EquipmentParsed.exit(counted, complete, null);
        counted.processClient(null);
        require(counted.acknowledgements == 2, "woven prefix blocked valid equipment acknowledgement");
        require(unread.bb.position() == 0, "inspection consumed packet data");
        System.out.println("EQUIPMENT_CHECKS_PASS (vanilla versus woven acknowledgement, incomplete local ack, complete, repeat, reused/different packet, remote/server guards)");
    }
}
