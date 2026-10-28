package net.alexredby.pztoolkitjavapatches

import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.iso.IsoCell
import zombie.iso.objects.IsoWorldInventoryObject

/** Aggregate native reads for the Lua highlighter; discovery and highlight writes remain in Lua. */
object GroundHighlight {
    @JvmField
    internal val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/iso/IsoObject.class",
            "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2",
        ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoWorldInventoryObject.class",
                "7be6f2d54525fa587908ce8efa7da5d26cfd3d19bd1cc02911ee12f7649857b3",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoGridSquare.class",
                "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoCell.class",
                "5e9a88e1cd9a3f370e31ae0152c9de381d649caea7cab750ebc82a91b4e1f767",
            ) &&
            BytecodeSupport.supports(
                "zombie/inventory/InventoryItem.class",
                "48f01be16d1ef1b76e37638fac6e25ca4eb285ad38ab2f462caa5597318c7f9d",
            ) &&
            BytecodeSupport.supports(
                "zombie/scripting/objects/Item.class",
                "9e6a2f7fe48cc66843fea06b4821063d7cc6a73eaba0de8ee51d0a15c373202e",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/textures/ColorInfo.class",
                "ed39ba090c8577ee1b2c83a85b7b52445cdfca6b75b657abb3af7181a7b807ce",
            )

    @JvmStatic
    @LuaMethod(name = "toolkitGroundHighlightDistance", global = true)
    fun distance(
        objectOnGround: IsoWorldInventoryObject?,
        cell: IsoCell?,
        playerNum: Int,
        z: Double,
        x: Double,
        y: Double,
        maxRadius: Double,
    ): Double? = readDistance(objectOnGround, cell, playerNum, z, x, y, maxRadius, SUPPORTED)

    /** Nil means unavailable; a negative distance means that the current object is ineligible. */
    internal fun readDistance(
        objectOnGround: IsoWorldInventoryObject?,
        cell: IsoCell?,
        playerNum: Int,
        z: Double,
        x: Double,
        y: Double,
        maxRadius: Double,
        supported: Boolean,
    ): Double? {
        if (!supported) return null
        val current = objectOnGround ?: return -1.0
        val square = current.getSquare()
        val item = current.getItem()
        if (square == null || item == null || item.getWorldItem() !== current) return -1.0
        if (square.getZ().toDouble() != z) return -1.0
        if (
            cell == null ||
                cell.getGridSquare(square.getX(), square.getY(), square.getZ()) !== square
        )
            return -1.0
        if (!square.isCanSee(playerNum)) return -1.0
        if (!current.getDoRender() || current.getTargetAlpha(playerNum) <= 0f) return -1.0
        // Preserve the Lua getter dispatch and its missing-script error instead of hiding it.
        if (item.getScriptItem().isWorldRender() != true) return -1.0
        // Native positions are floats, but Lua promotes each one before subtraction/arithmetic.
        val dx = current.getWorldPosX().toDouble() - x
        val dy = current.getWorldPosY().toDouble() - y
        val distance = dx * dx + dy * dy
        return if (distance <= maxRadius * maxRadius) distance else -1.0
    }

    @JvmStatic
    @LuaMethod(name = "toolkitGroundHighlightMatches", global = true)
    fun matches(
        objectOnGround: IsoWorldInventoryObject?,
        playerNum: Int,
        packedOutline: Int,
        attached: Boolean,
        r: Double,
        g: Double,
        b: Double,
        a: Double,
    ): Boolean? =
        readMatches(objectOnGround, playerNum, packedOutline, attached, r, g, b, a, SUPPORTED)

    internal fun readMatches(
        objectOnGround: IsoWorldInventoryObject?,
        playerNum: Int,
        packedOutline: Int,
        attached: Boolean,
        r: Double,
        g: Double,
        b: Double,
        a: Double,
        supported: Boolean,
    ): Boolean? {
        if (!supported) return null
        val current = objectOnGround ?: return false
        val colour = current.getHighlightColor(playerNum)
        return current.isHighlighted(playerNum) &&
            current.isOutlineHighlight(playerNum) &&
            current.isOutlineHlAttached(playerNum) == attached &&
            current.getOutlineHighlightCol(playerNum) == packedOutline &&
            colour.getR().toDouble() == r &&
            colour.getG().toDouble() == g &&
            colour.getB().toDouble() == b &&
            colour.getA().toDouble() == a
    }
}
