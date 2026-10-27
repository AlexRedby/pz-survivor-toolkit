package net.alexredby.pztoolkitjavapatches

import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.inventory.types.InventoryContainer

/** Native encumbrance remains authoritative; a controlled cart adds no separate bag penalty. */
internal object CartSpeedParity {
    @JvmStatic
    fun bagPenalty(character: IsoGameCharacter?, bag: InventoryContainer?, original: Float): Float {
        val player = character as? IsoPlayer ?: return original
        if (
            !Main.CART_SUPPORTED ||
                bag == null ||
                player.getPrimaryHandItem() !== bag ||
                !CartSteeringHooks.supportedCart(player) ||
                !CartSteeringHooks.enabled(player)
        )
            return original
        return 0f
    }
}
