package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.network.ByteBufferReader;
import zombie.network.IConnection;
import zombie.network.packets.ItemStatsPacket;

/** Restore omitted wire values before the connection's cached packet is parsed again. */
public final class ItemStatsDefaults {
    public static final boolean SUPPORTED = ItemStatsDefaultLogic.supported;

    public static void reset(ItemStatsPacket packet, boolean supported) {
        ItemStatsDefaultLogic.reset(packet, supported);
    }

    @Patch(className="zombie.network.packets.ItemStatsPacket", methodName="parse", warmUp=true, strictMatch=true)
    public static class Parsed {
        @Patch.OnEnter
        public static void enter(@Patch.This ItemStatsPacket packet, @Patch.Argument(0) ByteBufferReader reader,
                                 @Patch.Argument(1) IConnection connection) {
            reset(packet, SUPPORTED);
        }
    }
}
