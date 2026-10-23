package net.alexredby.pztoolkitjavapatches

import sun.misc.Unsafe
import zombie.ai.StateMachine
import zombie.characters.IsoPlayer
import zombie.characters.NetworkPlayerAI
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.InventoryContainer
import zombie.iso.Vector2
import zombie.network.PacketTypes.PacketType
import zombie.network.packets.character.PlayerPacket

object CartNetworkHeadingTest {
    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        var primary: InventoryItem? = null
        var secondary: InventoryItem? = null
        var testInventory: ItemContainer? = null
        var ai: NetworkPlayerAI? = null
        var machine: StateMachine? = null
        var accepted = 0f
        var desired = 0f
        var local = true
        var enabled = true
        var testDead = false
        var run = true
        var sprint = false

        override fun getOnlineID(): Short = 11

        override fun getNetworkCharacterAI(): NetworkPlayerAI? = ai

        override fun getActionStateName(): String = "movement"

        override fun isLocalPlayer(): Boolean = local

        override fun getECSComponentMap():
            HashMap<
                Class<out zombie.characters.ecs.ECSComponent>,
                zombie.characters.ecs.ECSComponent,
            > = HashMap()

        override fun isNpc(): Boolean = false

        override fun isDead(): Boolean = testDead

        override fun hasHitReaction(): Boolean = false

        override fun isKnockedDown(): Boolean = false

        override fun isGettingUp(): Boolean = false

        override fun isGrappling(): Boolean = false

        override fun isBeingGrappled(): Boolean = false

        override fun isRagdollSimulationActive(): Boolean = false

        override fun hasPath(): Boolean = false

        override fun getPathFindBehavior2(): zombie.pathfind.PathFindBehavior2? = null

        override fun getStateMachine(): StateMachine {
            if (machine == null) machine = StateMachine(this)
            return machine!!
        }

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary

        override fun getInventory(): ItemContainer? = testInventory

        override fun getAnimForwardDirection(out: Vector2): Vector2 =
            out.set(
                Math.cos(accepted.toDouble()).toFloat(),
                Math.sin(accepted.toDouble()).toFloat(),
            )

        override fun getDirectionAngleRadians(): Float = desired

        override fun getForwardDirectionX(): Float = Math.cos(desired.toDouble()).toFloat()

        override fun getForwardDirectionY(): Float = Math.sin(desired.toDouble()).toFloat()

        override fun isRunning(): Boolean = run

        override fun isSprinting(): Boolean = sprint

        override fun getVariableBoolean(name: String?): Boolean =
            name!!.equals("ToolkitCartMotion") && enabled

        override fun getVariableFloat(name: String?, fallback: Float): Float =
            if (name!!.equals("WalkSpeed")) .8f else fallback

        override fun getAdvancedAnimator(): AdvancedAnimator? = null

        override fun setVariable(name: String?, value: Boolean): IAnimationVariableSlot? = null

        override fun setVariable(name: String?, value: Float): IAnimationVariableSlot? = null

        override fun clearVariable(name: String?) {}

        override fun setTargetAndCurrentDirection(x: Float, y: Float) {}
    }

    private class NativeAI(owner: Player) : NetworkPlayerAI(owner) {
        var testOwner: Player? = null
        var sampled = 0f

        override fun set(packet: PlayerPacket): PacketType {
            // Native producer's input-facing value before collision/animation hook.
            val direction = testOwner!!.getDirectionAngleRadians()
            packet.prediction.direction = direction
            sampled = direction
            packet.prediction.x = 17f
            packet.prediction.y = 29f
            packet.prediction.z = 2
            packet.prediction.moveDirection = -.9f
            packet.prediction.speed = .75f
            packet.prediction.distance = 8
            packet.booleanVariables = 123
            return PacketType.PlayerUpdateReliable
        }
    }

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun cart(unsafe: Unsafe, inventory: ItemContainer?): InventoryContainer =
        (unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer).apply {
            setModule("SaucedWheelbarrow")
            setType("WheelbarrowWood")
            setContainer(inventory)
        }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        val unsafe = field.get(null) as Unsafe
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartNetworkHeadingTest::class.java.classLoader,
        )
        check(Main.CART_SYNC_SUPPORTED, "native packet heading fixture is unsupported")
        val player = unsafe.allocateInstance(Player::class.java) as Player
        player.local = true
        player.enabled = true
        player.run = true
        player.accepted = .7f
        player.onlineId = 11
        player.testInventory = ItemContainer()
        player.primary = cart(unsafe, player.testInventory)
        player.secondary = player.primary
        val ai = unsafe.allocateInstance(NativeAI::class.java) as NativeAI
        ai.testOwner = player
        player.ai = ai
        // Seed accepted yaw, then emulate later input update before Packet.set.
        CartSteeringHooks.heading(player)
        for (target in
            floatArrayOf(
                player.accepted + Math.PI.toFloat() / 4,
                player.accepted + Math.PI.toFloat(),
            )) {
            player.desired = target
            val packet = PlayerPacket()
            check(
                packet.set(player) == PacketType.PlayerUpdateReliable,
                "native packet return type changed",
            )
            check(
                ai.sampled == target && player.desired == target,
                "packet correction rewrote the local input facing",
            )
            check(
                Math.abs(packet.prediction.direction - player.accepted) < 1e-6,
                "packet sent turn/reverse intent instead of accepted yaw",
            )
            check(
                packet.prediction.x == 17f &&
                    packet.prediction.y == 29f &&
                    packet.prediction.z.toInt() == 2 &&
                    packet.prediction.moveDirection == -.9f &&
                    packet.prediction.speed == .75f &&
                    packet.prediction.distance.toInt() == 8,
                "cart heading correction changed native prediction movement",
            )
            check(
                packet.booleanVariables.toInt() == 123 &&
                    packet.id.getID().toInt() == 11 &&
                    packet.variables.getPacketSizeBytes() == 11 &&
                    player.run &&
                    !player.sprint,
                "cart heading correction changed native identity/gait/variables",
            )
        }
        for (guard in 0 until 5) {
            player.local = guard != 0
            player.enabled = guard != 1
            player.testDead = guard == 2
            val original = player.primary
            if (guard == 3) {
                player.primary = null
                player.secondary = null
            }
            if (guard == 4) {
                player.primary = cart(unsafe, player.testInventory)
                player.secondary = player.primary
            }
            val packet = PlayerPacket()
            packet.set(player)
            check(
                packet.prediction.direction == player.desired,
                "packet correction escaped local enabled same-cart ownership",
            )
            player.primary = original
            player.secondary = original
        }
        player.local = true
        player.enabled = true
        player.testDead = false
        CartSteeringHooks.reset(player)
        val packet = PlayerPacket()
        packet.set(player)
        check(
            packet.prediction.direction == player.desired,
            "uninitialized cart state overrode native direction",
        )
        println("CART_NETWORK_HEADING_PASS")
    }
}
