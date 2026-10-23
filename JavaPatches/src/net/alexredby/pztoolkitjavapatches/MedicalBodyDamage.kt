package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import zombie.network.fields.character.PlayerID
import zombie.network.packets.BodyDamageUpdatePacket

object MedicalBodyDamage {
    @JvmStatic
    fun skip(packet: BodyDamageUpdatePacket?, supported: Boolean): Boolean {
        if (!supported) return false
        val type = Accessor.tryGet<Enum<*>>(packet, "packetType", null)
        if (type == null || type.name != "UPDATE") return false
        val patient = Accessor.tryGet<PlayerID>(packet, "remotePlayer", null)
        // B42.21 processClient line 100 dereferences a PlayerID removed while the update was in flight.
        return patient != null && patient.player == null
    }
}
