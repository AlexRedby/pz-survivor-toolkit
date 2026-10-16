package net.alexredby.animalhandsrace;

import java.nio.ByteBuffer;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.AnimalInventoryItem;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.EquipPacket;
import zombie.network.packets.character.AnimalCommandPacket;

/** Test fixture only: changes delivery order, never packet data or native handler bodies. */
public final class Main {
    public static boolean armed, releasing, insideEquipParse;
    public static IsoPlayer target;
    public static AnimalCommandPacket pending;
    public static UdpConnection pendingConnection;
    public static int wireAnimalId = -1, echoedAnimalId = -1, releaseCount;

    public static void log(String text) { System.out.println("[ANIMAL_HANDS_RACE] " + text); }
    public static int id(InventoryItem item) { return item == null ? -1 : item.getID(); }
    public static String state(IsoGameCharacter player) {
        if (player == null) return "player=null";
        return "player=" + player.getOnlineID() + " primary=" + id(player.getPrimaryHandItem())
            + " secondary=" + id(player.getSecondaryHandItem());
    }
    public static IsoPlayer player(EquipPacket packet) {
        PlayerID field = Accessor.tryGet(packet, "player", (PlayerID)null);
        return field == null ? null : field.getPlayer();
    }
    @LuaMethod(name="animalHandsRaceArm", global=true)
    public static String arm(IsoPlayer owner) {
        if (!GameClient.client || owner == null || !owner.isLocalPlayer()) return "FAIL requires local client owner";
        if (pending != null) return "FAIL release pending command first";
        target = owner; armed = true; wireAnimalId = -1; echoedAnimalId = -1; releaseCount = 0;
        log("ARM " + state(owner));
        return "armed";
    }
    @LuaMethod(name="animalHandsRaceStatus", global=true)
    public static String status() {
        return "armed=" + armed + " pending=" + (pending == null ? -1 : id(pending.item))
            + " wireAnimal=" + wireAnimalId + " echoedAnimal=" + echoedAnimalId
            + " releases=" + releaseCount + " " + state(target);
    }
    @LuaMethod(name="animalHandsRaceRelease", global=true)
    public static String release() {
        if (pending == null) { armed = false; return "no pending command"; }
        var command = pending; var connection = pendingConnection;
        pending = null; pendingConnection = null; armed = false; releasing = true;
        try {
            log("RELEASE_BEFORE item=" + id(command.item) + " " + state(target));
            command.processClient(connection);
            releaseCount++;
            log("RELEASE_AFTER item=" + id(command.item) + " inventoryHas="
                + target.getInventory().contains(command.item) + " " + state(target));
            return status();
        } finally { releasing = false; }
    }
    public static boolean defer(AnimalCommandPacket packet, UdpConnection connection) {
        if (!GameClient.client || releasing || !armed || pending != null
            || packet.type != AnimalCommandPacket.Type.RemoveAndGrabAnimalFromTrailer
            || packet.playerId.getPlayer() != target) return false;
        if (packet.item == null) { log("NULL_INCOMING_ITEM " + state(target)); return false; }
        // Copy parsed fields because IConnection reuses its packet singleton on the next receive.
        var copy = new AnimalCommandPacket();
        copy.set(packet.type, packet.animalId.getAnimal(), target, packet.vehicleId.getVehicle(), packet.item);
        copy.animalId.copy(packet.animalId); copy.playerId.copy(packet.playerId);
        copy.flags = packet.flags; copy.x = packet.x; copy.y = packet.y; copy.z = packet.z;
        pending = copy; pendingConnection = connection;
        log("DEFER item=" + id(copy.item) + " animal=" + copy.animalId.getID() + " " + state(target));
        if (echoedAnimalId == id(copy.item)) {
            // Equip won the race naturally before this command reached its handler.
            log("NATURAL_EQUIP_FIRST item=" + id(copy.item));
            pending = null; pendingConnection = null; armed = false;
            return false;
        }
        return true;
    }
    public static void equipProcessed(EquipPacket packet) {
        var owner = player(packet);
        if (!GameClient.client || owner != target || !armed) return;
        log("EQUIP_CLIENT_ECHO wireAnimal=" + wireAnimalId + " " + state(owner));
        if (wireAnimalId < 0) return;
        echoedAnimalId = wireAnimalId;
        if (pending != null && id(pending.item) == wireAnimalId) release();
    }
    public static void main(String[] args) { log("LOADED test-only native packet order probe"); }

    @Patch(className="zombie.network.packets.character.AnimalCommandPacket", methodName="processClient", warmUp=true, strictMatch=true)
    public static class DelayGrab {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This AnimalCommandPacket packet, @Patch.Argument(0) UdpConnection connection) {
            return Main.defer(packet, connection);
        }
    }
    @Patch(className="zombie.network.packets.EquipPacket", methodName="parse", warmUp=true, strictMatch=true)
    public static class ReadEquip {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,
                                 @Patch.Argument(1) zombie.network.IConnection connection) { if (GameClient.client) { Main.insideEquipParse = true; Main.wireAnimalId = -1; } }
        @Patch.OnExit
        public static void exit(@Patch.This EquipPacket packet,
                                @Patch.Argument(0) zombie.core.network.ByteBufferReader reader,
                                @Patch.Argument(1) zombie.network.IConnection connection) {
            if (GameClient.client) {
                Main.insideEquipParse = false;
                if (Main.player(packet) == Main.target) Main.log("EQUIP_PARSED wireAnimal=" + Main.wireAnimalId + " remaining=" + reader.bb.remaining() + " " + Main.state(Main.target));
            }
        }
    }
    @Patch(className="zombie.inventory.InventoryItem", methodName="loadItem", warmUp=true, strictMatch=true)
    public static class ReadEquipItem {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) ByteBuffer buffer, @Patch.Argument(1) int version,
                                @Patch.Return InventoryItem item) {
            if (Main.insideEquipParse && item instanceof AnimalInventoryItem) Main.wireAnimalId = item.getID();
        }
    }
    @Patch(className="zombie.network.packets.EquipPacket", methodName="processClient", warmUp=true, strictMatch=true)
    public static class EchoEquip {
        @Patch.OnExit
        public static void exit(@Patch.This EquipPacket packet, @Patch.Argument(0) UdpConnection connection) {
            Main.equipProcessed(packet);
        }
    }
    @Patch(className="zombie.network.packets.EquipPacket", methodName="processServer", warmUp=true)
    public static class ReceiveEcho {
        @Patch.OnEnter
        public static void enter(@Patch.This EquipPacket packet) {
            Main.log("EQUIP_SERVER_BEFORE requestedPrimary=" + Accessor.tryGet(packet, "primaryHand", -999)
                + " requestedSecondary=" + Accessor.tryGet(packet, "secondaryHand", -999) + " " + Main.state(Main.player(packet)));
        }
        @Patch.OnExit
        public static void exit(@Patch.This EquipPacket packet) { Main.log("EQUIP_SERVER_AFTER " + Main.state(Main.player(packet))); }
    }
    @Patch(className="zombie.characters.IsoGameCharacter", methodName="dropHeavyItems", warmUp=true)
    public static class DropHeavy {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoGameCharacter owner) {
            if (owner.getPrimaryHandItem() instanceof AnimalInventoryItem || owner.getSecondaryHandItem() instanceof AnimalInventoryItem)
                Main.log("DROP_HEAVY server=" + GameServer.server + " " + Main.state(owner));
        }
    }
    @Patch(className="zombie.characters.IsoGameCharacter", methodName="dropHeldItems", warmUp=true)
    public static class DropHeld {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoGameCharacter owner) {
            if (owner.getPrimaryHandItem() instanceof AnimalInventoryItem || owner.getSecondaryHandItem() instanceof AnimalInventoryItem)
                Main.log("DROP_HELD server=" + GameServer.server + " " + Main.state(owner));
        }
    }
}
