package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import zombie.core.network.ByteBufferReader
import zombie.network.IConnection
import zombie.network.PZNetKahluaTableImpl

/** Refresh a registered workstation's lazy spatial ID before native component lookup. */
object CraftBenchReferences {
    @JvmField val SUPPORTED = CraftBenchReferenceLogic.supported

    @JvmStatic
    fun refresh(
        table: PZNetKahluaTableImpl?,
        reader: ByteBufferReader?,
        type: Byte,
        supported: Boolean,
    ) {
        CraftBenchReferenceLogic.refresh(table, reader, type, supported)
    }

    @Patch(
        className = "zombie.network.PZNetKahluaTableImpl",
        methodName = "load",
        warmUp = true,
        strictMatch = true,
    )
    object Decoded {
        @JvmStatic
        @Patch.OnEnter
        fun enter(
            @Patch.This table: PZNetKahluaTableImpl?,
            @Patch.Argument(0) reader: ByteBufferReader?,
            @Patch.Argument(1) connection: IConnection?,
            @Patch.Argument(2) type: Byte,
        ) {
            refresh(table, reader, type, SUPPORTED)
        }
    }
}
