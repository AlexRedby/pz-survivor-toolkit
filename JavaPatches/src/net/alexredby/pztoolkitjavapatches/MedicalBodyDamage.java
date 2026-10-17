package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Accessor;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.BodyDamageUpdatePacket;

public final class MedicalBodyDamage {
    public static boolean skip(BodyDamageUpdatePacket packet, boolean supported) {
        if (!supported) return false;
        var type = Accessor.tryGet(packet, "packetType", (Enum<?>)null);
        if (type == null || !type.name().equals("UPDATE")) return false;
        var patient = Accessor.tryGet(packet, "remotePlayer", (PlayerID)null);
        // B42.21 processClient line 100 dereferences a PlayerID removed while the update was in flight.
        return patient != null && patient.getPlayer() == null;
    }
}
