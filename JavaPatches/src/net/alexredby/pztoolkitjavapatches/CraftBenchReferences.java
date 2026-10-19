package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.network.ByteBufferReader;
import zombie.entity.ComponentType;
import zombie.entity.GameEntityManager;
import zombie.iso.IsoObject;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.PZNetKahluaTableImpl;

/** Refresh a registered workstation's lazy spatial ID before native component lookup. */
public final class CraftBenchReferences {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/network/PZNetKahluaTableImpl.class",
            "201f0e59502fc5a106f8c9021e0b0d13a30dcb8d0beb9e8934cec390231ddba6")
        && BytecodeSupport.supports("zombie/iso/IsoObject.class", "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2")
        && BytecodeSupport.supports("zombie/entity/GameEntityManager.class", "679953e42c73179cf083a40af5c1d67de67452519dace5efa517369c974a9775")
        && BytecodeSupport.supports("zombie/entity/GameEntity.class", "fb46c896c05e72b5f951943b1adfac580a57ae709a6f496b77aa954b6a1886ee")
        && BytecodeSupport.supports("zombie/entity/ComponentType.class", "28f3d346c47a0b1804c7258659587c0f415eef3d510d6cd67c50d2ff291ebcda");

    public static void refresh(PZNetKahluaTableImpl table, ByteBufferReader reader, byte type, boolean supported) {
        if (!supported || !GameServer.server || type != 36 || reader.bb.remaining() < 10
                || !(table.rawget("isoObject") instanceof IsoObject object)) return;
        var probe = reader.bb.duplicate().order(reader.bb.order());
        long requested = probe.getLong();
        if (probe.getShort() != ComponentType.CraftBench.GetID()) return;
        var square = object.getSquare();
        int index = object.getObjectIndex();
        if (square == null || index < 0 || object.isFloor() || !object.hasComponent(ComponentType.CraftBench)) return;
        // Match the exact loaded object; never search for a nearby/replacement forge.
        long spatial = ((long)index << 40) + ((long)square.getZ() << 32)
            + ((long)square.getY() << 16) + square.getX();
        if (spatial != requested) return;
        Long previous = Accessor.tryGet(object, "isoEntityNetId", (Long)null);
        if (previous == null || previous == -1 || previous == requested
                || GameEntityManager.GetEntity(previous) != object) return;
        // This native getter updates the old/new registry keys itself. The original
        // decoder still reads the unchanged payload and returns the real component.
        object.getEntityNetID();
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
