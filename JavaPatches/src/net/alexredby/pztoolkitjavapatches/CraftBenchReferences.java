package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.network.ByteBufferReader;
import zombie.network.IConnection;
import zombie.network.PZNetKahluaTableImpl;

/** Refresh a registered workstation's lazy spatial ID before native component lookup. */
public final class CraftBenchReferences {
    public static final boolean SUPPORTED = CraftBenchReferenceLogic.supported;

    public static void refresh(PZNetKahluaTableImpl table, ByteBufferReader reader, byte type, boolean supported) {
        CraftBenchReferenceLogic.refresh(table, reader, type, supported);
    }

    @Patch(className="zombie.network.PZNetKahluaTableImpl", methodName="load", warmUp=true, strictMatch=true)
    public static class Decoded {
        @Patch.OnEnter
        public static void enter(@Patch.This PZNetKahluaTableImpl table, @Patch.Argument(0) ByteBufferReader reader,
                                 @Patch.Argument(1) IConnection connection, @Patch.Argument(2) byte type) {
            refresh(table, reader, type, SUPPORTED);
        }
    }
}
