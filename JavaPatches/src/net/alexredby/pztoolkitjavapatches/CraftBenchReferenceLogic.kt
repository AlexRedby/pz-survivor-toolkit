package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import zombie.core.network.ByteBufferReader
import zombie.entity.ComponentType
import zombie.entity.GameEntity
import zombie.entity.GameEntityManager
import zombie.entity.util.LongMap
import zombie.iso.IsoObject
import zombie.network.GameServer
import zombie.network.PZNetKahluaTableImpl

/** Refresh only the exact registered workstation described by the untouched wire payload. */
internal object CraftBenchReferenceLogic {
    @JvmField
    val supported =
        BytecodeSupport.supports(
            "zombie/network/PZNetKahluaTableImpl.class",
            "d57f0a86e74b58afca38a594950010d3f1209cddfca8664683c6f404c72ade6e",
        ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoObject.class",
                "7a99d06875c19ff132940d7192b414496537076e83474db0abc0cb38de6be70a",
            ) &&
            BytecodeSupport.supports(
                "zombie/entity/GameEntityManager.class",
                "15ac8173e8a81f72d3d93792f6fb77d7e6a0c8f997b0b44ec7830f9052f25f62",
            ) &&
            BytecodeSupport.supports(
                "zombie/entity/GameEntity.class",
                "48ae3968d3bbfaabae9611f83c261ecf05e8fe6eccfcde2e998ef765b71c68fd",
            ) &&
            BytecodeSupport.supports(
                "zombie/entity/ComponentType.class",
                "28f3d346c47a0b1804c7258659587c0f415eef3d510d6cd67c50d2ff291ebcda",
            ) &&
            BytecodeSupport.supports(
                "zombie/entity/util/LongMap.class",
                "655eb56f40c5b405a5827030a9011b8453045b5c9a1988866f3c259b45249b7e",
            )

    @JvmStatic
    fun refresh(
        table: PZNetKahluaTableImpl?,
        reader: ByteBufferReader?,
        type: Byte,
        supported: Boolean,
    ) {
        if (!supported || !GameServer.server || type.toInt() != 36) return
        // Preserve the native nullable boundary's short-circuit order and exception type.
        val bytes = (reader ?: throw NullPointerException()).bb
        if (bytes.remaining() < 10) return
        val obj =
            (table ?: throw NullPointerException()).rawget("isoObject") as? IsoObject ?: return
        val probe = bytes.duplicate().order(bytes.order())
        val requested = probe.long
        if (probe.short != ComponentType.CraftBench.GetID()) return
        val square = obj.getSquare()
        val index = obj.objectIndex
        if (
            square == null ||
                index < 0 ||
                obj.isFloor ||
                !obj.hasComponent(ComponentType.CraftBench)
        )
            return
        val spatial =
            (index.toLong() shl 40) +
                (square.getZ().toLong() shl 32) +
                (square.getY().toLong() shl 16) +
                square.getX()
        if (spatial != requested) return
        val previous = Accessor.tryGet<Long>(obj, "isoEntityNetId", null) ?: return
        if (previous == -1L || previous == requested) return
        val registry = Accessor.tryGet<LongMap<GameEntity>>(
            GameEntityManager::class.java, "idToEntityMap", null) ?: return
        if (registry.javaClass != LongMap::class.java) return
        synchronized(registry) {
            // GetEntity now refreshes the found entity before returning it. Inspect the
            // backing registry first so a collision cannot invoke another entity's getter.
            if (registry.get(previous) !== obj) return
            // The native getter updates both registry keys; the decoder still reads its
            // original buffer. checkEntityIDChange uses this same reentrant monitor.
            obj.entityNetID
        }
    }
}
