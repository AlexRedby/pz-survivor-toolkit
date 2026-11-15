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
            "7a99d06875c19ff132940d7192b414496537076e83474db0abc0cb38de6be70a",
        ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoWorldInventoryObject.class",
                "1019fd27cfce76d84a8db499a71568429e87e95de504e041a202e0ba9c01ee0b",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoGridSquare.class",
                "b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoCell.class",
                "6c261778f1fac0c660ba8b6167b9bf5d318e8bd126378e3c1b3667c9469910ab",
            ) &&
            BytecodeSupport.supports(
                "zombie/inventory/InventoryItem.class",
                "b45d4438636509d992aaa7b7505ef8323cd898947efc27bf1f7e762951d6643d",
            ) &&
            BytecodeSupport.supports(
                "zombie/scripting/objects/Item.class",
                "92f0b1dc3c96c97e6ce709542edbd9f5969b663934fb0c124014de53c37c3ab5",
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
