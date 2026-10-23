package net.alexredby.pztoolkitjavapatches

import gnu.trove.map.hash.THashMap
import me.zed_0xff.zombie_buddy.Accessor
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes.PacketType
import zombie.network.packets.INetworkPacket

object MedicalVisuals {
    @JvmStatic
    fun before(
        models: Any?,
        character: IsoGameCharacter?,
        type: String?,
        supported: Boolean,
    ): InventoryItem? {
        if (
            !supported ||
                !GameClient.client ||
                GameServer.server ||
                character !is IsoPlayer ||
                !character.isLocalPlayer ||
                character.onlineId.toInt() == -1
        )
            return null
        val items = Accessor.tryGet<THashMap<*, *>>(models, "itemMap", null)
        val item = items?.get(type)
        return if (item is InventoryItem && character.wornItems.contains(item)) item else null
    }

    @JvmStatic
    fun after(character: IsoGameCharacter?, removed: InventoryItem?) {
        if (
            removed == null ||
                !GameClient.client ||
                GameServer.server ||
                GameClient.connection == null ||
                !GameClient.connection.isReady
        )
            return
        val patient = character ?: throw NullPointerException()
        if (patient.wornItems.contains(removed)) return
        // Native removal bypasses setWornItem; otherwise the next server sync resurrects these IDs.
        INetworkPacket.send(PacketType.SyncClothing, character)
    }
}
