package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import zombie.core.network.ByteBufferReader
import zombie.entity.ComponentType
import zombie.entity.GameEntityManager
import zombie.iso.IsoObject
import zombie.network.GameServer
import zombie.network.PZNetKahluaTableImpl

/** Refresh only the exact registered workstation described by the untouched wire payload. */
internal object CraftBenchReferenceLogic {
    @JvmField
    val supported = BytecodeSupport.supports("zombie/network/PZNetKahluaTableImpl.class",
        "201f0e59502fc5a106f8c9021e0b0d13a30dcb8d0beb9e8934cec390231ddba6") &&
        BytecodeSupport.supports("zombie/iso/IsoObject.class", "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2") &&
        BytecodeSupport.supports("zombie/entity/GameEntityManager.class", "679953e42c73179cf083a40af5c1d67de67452519dace5efa517369c974a9775") &&
        BytecodeSupport.supports("zombie/entity/GameEntity.class", "fb46c896c05e72b5f951943b1adfac580a57ae709a6f496b77aa954b6a1886ee") &&
        BytecodeSupport.supports("zombie/entity/ComponentType.class", "28f3d346c47a0b1804c7258659587c0f415eef3d510d6cd67c50d2ff291ebcda")

    @JvmStatic
    fun refresh(table: PZNetKahluaTableImpl?, reader: ByteBufferReader?, type: Byte, supported: Boolean) {
        if (!supported || !GameServer.server || type.toInt() != 36) return
        // Preserve the native nullable boundary's short-circuit order and exception type.
        val bytes = (reader ?: throw NullPointerException()).bb
        if (bytes.remaining() < 10) return
        val obj = (table ?: throw NullPointerException()).rawget("isoObject") as? IsoObject ?: return
        val probe = bytes.duplicate().order(bytes.order())
        val requested = probe.long
        if (probe.short != ComponentType.CraftBench.GetID()) return
        val square = obj.getSquare()
        val index = obj.objectIndex
        if (square == null || index < 0 || obj.isFloor || !obj.hasComponent(ComponentType.CraftBench)) return
        val spatial = (index.toLong() shl 40) + (square.getZ().toLong() shl 32) +
            (square.getY().toLong() shl 16) + square.getX()
        if (spatial != requested) return
        val previous = Accessor.tryGet<Long>(obj, "isoEntityNetId", null) ?: return
        if (previous == -1L || previous == requested || GameEntityManager.GetEntity(previous) !== obj) return
        // The native getter updates both registry keys; the decoder still reads its original buffer.
        obj.entityNetID
    }
}
