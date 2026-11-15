package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import zombie.network.fields.character.OnlinePlayer
import zombie.network.packets.BodyDamageUpdatePacket

object MedicalBodyDamage {
    @JvmStatic
    fun skip(packet: BodyDamageUpdatePacket?, supported: Boolean): Boolean {
        if (!supported) return false
        val type = Accessor.tryGet<Enum<*>>(packet, "packetType", null)
        if (type == null || type.name != "UPDATE") return false
        val patient = Accessor.tryGet<OnlinePlayer>(packet, "remotePlayer", null)
        // An UPDATE may outlive the remote player's replica.
        return patient != null && patient.player == null
    }
}
