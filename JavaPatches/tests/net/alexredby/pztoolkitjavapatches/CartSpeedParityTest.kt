package net.alexredby.pztoolkitjavapatches

import sun.misc.Unsafe
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.InventoryContainer
import zombie.scripting.objects.CharacterTrait
import zombie.scripting.objects.Item

/** Executes the actual woven native bag penalty, including rejected ownership/control scopes. */
object CartSpeedParityTest {
    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var primary: InventoryItem? = null
        @JvmField var secondary: InventoryItem? = null
        @JvmField var inventory: ItemContainer? = null
        @JvmField var active = false
        @JvmField var local = true
        @JvmField var dead = false
        @JvmField var npc = false
        @JvmField var path = false
        @JvmField var reaction = false

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary

        override fun getInventory(): ItemContainer? = inventory

        override fun getVariableBoolean(name: String?): Boolean =
            active && name == "ToolkitCartMotion"

        override fun isLocalPlayer(): Boolean = local

        override fun isDead(): Boolean = dead

        override fun isNpc(): Boolean = npc

        override fun hasHitReaction(): Boolean = reaction

        override fun isKnockedDown(): Boolean = false

        override fun isGettingUp(): Boolean = false

        override fun isGrappling(): Boolean = false

        override fun isBeingGrappled(): Boolean = false

        override fun isRagdollSimulationActive(): Boolean = false

        override fun hasPath(): Boolean = path

        override fun getPathFindBehavior2(): zombie.pathfind.PathFindBehavior2? = null

        override fun isCurrentState(state: zombie.ai.State?): Boolean = false

        override fun hasTrait(trait: CharacterTrait?): Boolean = false
    }

    private fun check(value: Boolean, label: String) {
        if (!value) throw AssertionError(label)
    }

    private fun close(actual: Float, expected: Float, label: String) {
        check(
            actual.isFinite() && kotlin.math.abs(actual - expected) < .000001f,
            "$label: $actual != $expected",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartSpeedParityTest::class.java.classLoader,
        )
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        val unsafe = field.get(null) as Unsafe
        val player = unsafe.allocateInstance(Player::class.java) as Player
        player.local = true
        player.inventory = ItemContainer()
        val penalty =
            IsoGameCharacter::class
                .java
                .getDeclaredMethod(
                    "calcRunSpeedModByBag",
                    InventoryContainer::class.java,
                )
        penalty.isAccessible = true
        fun native(bag: InventoryContainer): Float = penalty.invoke(player, bag) as Float
        fun bag(type: String, modifier: Float, contents: Float): InventoryContainer {
            val result =
                unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
            result.setModule(type.substringBefore('.'))
            result.setType(type.substringAfter('.'))
            result.setActualWeight(4f)
            result.setName(type)
            val script = unsafe.allocateInstance(Item::class.java) as Item
            script.runSpeedModifier = modifier
            result.setScriptItem(script)
            val inventory = ItemContainer()
            inventory.setCapacity(40)
            if (contents > 0) {
                val ballast = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
                ballast.setName("Speed comparison ballast")
                ballast.setActualWeight(contents)
                ballast.setCustomWeight(true)
                inventory.getItems().add(ballast)
            }
            result.setItemContainer(inventory)
            result.setContainer(player.inventory)
            return result
        }
        check(Main.CART_SUPPORTED, "native bytecode must support the cart boundary")
        for (type in
            arrayOf(
                "SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal",
                "SaucedCarts.ShoppingCart",
            )) {
            for (modifier in floatArrayOf(.7f, .75f, .9f, 1f, 1.1f)) {
                for (contents in floatArrayOf(0f, 20f)) {
                    val cart = bag(type, modifier, contents)
                    player.primary = cart
                    player.secondary = cart
                    player.active = false
                    val original = native(cart)
                    close(
                        original,
                        (modifier - 1) * (1 + contents / 40 / 2),
                        "unchanged native baseline $type/$modifier/$contents",
                    )
                    player.active = true
                    close(native(cart), 0f, "cart weight is not charged a second bag penalty")
                    close(
                        cart.getScriptItem().runSpeedModifier,
                        modifier,
                        "shared script metadata must remain unchanged",
                    )
                    player.secondary = null
                    close(native(cart), original, "one-hand inventory container stays native")
                    player.secondary = cart
                    player.local = false
                    close(
                        native(cart),
                        original,
                        "remote/server native calculation stays unchanged",
                    )
                    player.local = true
                    player.dead = true
                    close(native(cart), original, "dead actor stays native")
                    player.dead = false
                    player.npc = true
                    close(native(cart), original, "NPC stays native")
                    player.npc = false
                    player.reaction = true
                    close(native(cart), original, "native reaction keeps its fallback")
                    player.reaction = false
                    val owner = player.inventory
                    cart.setContainer(ItemContainer())
                    close(native(cart), original, "foreign cart owner stays native")
                    cart.setContainer(owner)
                    val other = bag("Base.Bag_Schoolbag", .8f, 10f)
                    val otherExpected = (.8f - 1) * (1 + 10f / 40 / 2)
                    close(native(other), otherExpected, "other bags keep their native penalty")
                    player.primary = other
                    player.secondary = other
                    close(native(other), otherExpected, "ordinary two-hand bags stay native")
                }
            }
        }
        close(CartSpeedParity.bagPenalty(null, null, -.2f), -.2f, "absent actor stays native")
        println("CART_SPEED_PARITY_PASS")
    }
}
