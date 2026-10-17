package net.alexredby.pztoolkitjavapatches;

import gnu.trove.map.hash.THashMap;
import me.zed_0xff.zombie_buddy.Accessor;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PacketTypes.PacketType;
import zombie.network.packets.INetworkPacket;

public final class MedicalVisuals {
    public static InventoryItem before(Object models, IsoGameCharacter character, String type, boolean supported) {
        if (!supported || !GameClient.client || GameServer.server || !(character instanceof IsoPlayer player)
                || !player.isLocalPlayer() || player.onlineId == -1) return null;
        var items = Accessor.tryGet(models, "itemMap", (THashMap<?, ?>)null);
        var item = items == null ? null : items.get(type);
        return item instanceof InventoryItem visual && player.getWornItems().contains(visual) ? visual : null;
    }

    public static void after(IsoGameCharacter character, InventoryItem removed) {
        if (removed == null || !GameClient.client || GameServer.server || GameClient.connection == null
                || !GameClient.connection.isReady() || character.getWornItems().contains(removed)) return;
        // Native removal bypasses setWornItem; otherwise the next server sync resurrects these IDs.
        INetworkPacket.send(PacketType.SyncClothing, character);
    }
}
