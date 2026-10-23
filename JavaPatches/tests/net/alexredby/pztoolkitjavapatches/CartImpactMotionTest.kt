package net.alexredby.pztoolkitjavapatches

import sun.misc.Unsafe
import zombie.ai.State
import zombie.ai.states.CollideWithWallState
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.iso.IsoGridSquare
import zombie.iso.Vector2
import zombie.iso.objects.IsoWorldInventoryObject

object CartImpactMotionTest {
    private lateinit var unsafe: Unsafe

    private fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(actual: Double, expected: Double, message: String) {
        check(Math.abs(actual - expected) < .00001, "$message: $actual != $expected")
    }

    @Suppress("UNCHECKED_CAST")
    private fun contacts(): MutableMap<IsoPlayer, Any> {
        val field = CartImpactMotion::class.java.getDeclaredField("contacts")
        field.isAccessible = true
        return field.get(null) as MutableMap<IsoPlayer, Any>
    }

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        var collision = false
        var testDead = false
        var testRemote = false
        var getup = false
        var grapple = false
        var ragdoll = false
        var primary: InventoryItem? = null
        var secondary: InventoryItem? = null
        var slow = 0f

        override fun isLocalPlayer(): Boolean = !testRemote

        override fun isNpc(): Boolean = false

        override fun isDead(): Boolean = testDead

        override fun isCurrentState(state: State?): Boolean =
            collision && state === CollideWithWallState.instance()

        override fun isGettingUp(): Boolean = getup

        override fun isGrappling(): Boolean = grapple

        override fun isBeingGrappled(): Boolean = false

        override fun isRagdollSimulationActive(): Boolean = ragdoll

        override fun getVehicle(): zombie.vehicles.BaseVehicle? = null

        override fun getVariableBoolean(name: String?): Boolean = false

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary

        override fun getSlowFactor(): Float = slow

        override fun setCurrentSquareFromPosition() {}
    }

    private class Cart : InventoryItem(null, null, null, null as String?) {
        var world: IsoWorldInventoryObject? = null

        override fun getFullType(): String = "SaucedWheelbarrow.WheelbarrowWood"

        override fun getWorldItem(): IsoWorldInventoryObject? = world
    }

    private class World : IsoWorldInventoryObject(null as zombie.iso.IsoCell?) {
        var testSquare: IsoGridSquare? = null
        var heldItem: InventoryItem? = null
        var px = 0f
        var py = 0f
        var pz = 0f

        override fun getSquare(): IsoGridSquare? = testSquare

        override fun getItem(): InventoryItem? = heldItem

        override fun getWorldPosX(): Float = px

        override fun getWorldPosY(): Float = py

        override fun getWorldPosZ(): Float = pz
    }

    private data class Fixture(val player: Player, val cart: Cart, val world: World)

    private fun fixture(): Fixture {
        CartImpactMotion.reset()
        val player = allocate(Player::class.java)
        player.collision = true
        player.setX(10f)
        player.setY(20f)
        player.setZ(0f)
        player.setNextX(10.03f)
        player.setNextY(20f)
        player.reqMovement = Vector2()
        val cart = allocate(Cart::class.java)
        val world = allocate(World::class.java)
        cart.world = world
        world.heldItem = cart
        world.px = 10.7f
        world.py = 20f
        world.testSquare = allocate(IsoGridSquare::class.java)
        return Fixture(player, cart, world)
    }

    private fun geometry() {
        val out = Vector2()
        for (i in 0 until 16) {
            val angle = i * Math.PI / 8
            val nx = Math.cos(angle)
            val ny = Math.sin(angle)
            val tx = -ny
            val ty = nx
            CartImpactMotion.clip(
                (.2 * nx + .1 * tx).toFloat(),
                (.2 * ny + .1 * ty).toFloat(),
                10 - .05 * nx,
                20 - .05 * ny,
                10.0,
                20.0,
                nx,
                ny,
                out,
            )
            close(out.x * nx + out.y * ny, .05, "inward component exceeds remaining room")
            close(out.x * tx + out.y * ty, .1, "lateral component changed")
            CartImpactMotion.clip(
                (-.2 * nx + .1 * tx).toFloat(),
                (-.2 * ny + .1 * ty).toFloat(),
                10.0,
                20.0,
                10.0,
                20.0,
                nx,
                ny,
                out,
            )
            close(out.x * nx + out.y * ny, -.2, "native rebound changed")
            close(out.x * tx + out.y * ty, .1, "backward lateral component changed")
            CartImpactMotion.clip(
                (.2 * nx).toFloat(),
                (.2 * ny).toFloat(),
                10 + .01 * nx,
                20 + .01 * ny,
                10.0,
                20.0,
                nx,
                ny,
                out,
            )
            close(out.getLength().toDouble(), 0.0, "already-forward actor was teleported backwards")
        }
    }

    private fun wovenMovement() {
        val f = fixture()
        CartImpactMotion.begin(f.player, f.cart, f.world)
        check(contacts().containsKey(f.player), "confirmed contact not registered")
        check(CartImpactMotion.poseAgeNanos(f.player) >= 0, "confirmed contact has no pose lease")
        f.player.moveUnmodded(.25f, .1f)
        close(f.player.getNextX().toDouble(), 10.03, "woven native hook allowed forward root step")
        close(f.player.getNextY().toDouble(), 20.1, "woven native hook changed lateral step")
        f.player.slow = .5f
        f.player.moveUnmodded(-.2f, 0f)
        close(f.player.getNextX().toDouble(), 9.93, "native slowFactor or rebound lost")
        f.player.moveUnmodded(.5f, 0f)
        check(f.player.getNextX() <= 10.03001f, "re-entry crossed fixed plane")
        val floor = ItemContainer("floor", null, null)
        floor.AddItem(f.cart)
        CartImpactMotion.tick()
        check(contacts().containsKey(f.player), "native floor projection ended contact")
        // Body contact outlives the independent 240ms cart render settle.
        val old = contacts()[f.player]!!
        val components = old.javaClass.recordComponents
        val values = arrayOfNulls<Any>(components.size)
        for (i in components.indices) {
            val accessor = components[i].accessor
            accessor.isAccessible = true
            values[i] =
                if (components[i].name == "started") System.nanoTime() - 500_000_000L
                else accessor.invoke(old)
        }
        val constructor = old.javaClass.declaredConstructors[0]
        constructor.isAccessible = true
        contacts()[f.player] = constructor.newInstance(*values)
        CartImpactMotion.tick()
        check(contacts().containsKey(f.player), "contact expired with render settle")
        values[values.size - 1] = System.nanoTime() - CartImpactMotion.MAX_NANOS - 1
        contacts()[f.player] = constructor.newInstance(*values)
        CartImpactMotion.tick()
        check(!contacts().containsKey(f.player), "expired episode retained restriction")
        val before = f.player.getNextX()
        f.player.slow = 0f
        f.player.moveUnmodded(.2f, 0f)
        close((f.player.getNextX() - before).toDouble(), .2, "expiry retained root restriction")
    }

    private fun lifecycle() {
        for (bad in 0 until 14) {
            val f = fixture()
            CartImpactMotion.begin(f.player, f.cart, f.world)
            when (bad) {
                0 -> f.player.collision = false
                1 -> f.player.testDead = true
                2 -> f.player.testRemote = true
                3 -> f.player.getup = true
                4 -> f.player.grapple = true
                5 -> f.player.ragdoll = true
                6 -> f.cart.world = null
                7 -> f.world.testSquare = null
                8 -> f.world.heldItem = allocate(Cart::class.java)
                9 -> f.cart.setContainer(ItemContainer("inventory", null, null))
                10 -> f.player.setZ(1f)
                11 -> f.player.primary = allocate(Cart::class.java)
                12 -> f.world.px += .05f
                13 -> f.cart.setWorldZRotation(30f)
            }
            check(
                CartImpactMotion.poseAgeNanos(f.player) == -1L,
                "invalid episode retained pose lease $bad",
            )
            val step = CartImpactMotion.movement(f.player, .2f, .1f)
            close(step.x.toDouble(), .2, "invalid episode changed input $bad")
            close(step.y.toDouble(), .1, "invalid episode changed lateral $bad")
            check(!contacts().containsKey(f.player), "invalid episode retained $bad")
        }
        for (slow in floatArrayOf(-1f, 1.5f, Float.NaN, Float.POSITIVE_INFINITY)) {
            val f = fixture()
            CartImpactMotion.begin(f.player, f.cart, f.world)
            f.player.slow = slow
            close(
                CartImpactMotion.movement(f.player, .2f, 0f).x.toDouble(),
                .2,
                "abnormal native slowFactor altered",
            )
            check(contacts().isEmpty(), "abnormal slowFactor contact retained")
        }
        for (mode in 0 until 2) {
            val f = fixture()
            CartImpactMotion.begin(f.player, f.cart, f.world)
            zombie.network.GameClient.client = mode == 0
            zombie.network.GameServer.server = mode == 1
            try {
                close(
                    CartImpactMotion.movement(f.player, .2f, 0f).x.toDouble(),
                    .2,
                    "MP movement altered",
                )
                CartImpactMotion.begin(f.player, f.cart, f.world)
                check(contacts().isEmpty(), "MP contact registered")
            } finally {
                zombie.network.GameClient.client = false
                zombie.network.GameServer.server = false
            }
        }
        val f = fixture()
        f.player.primary = f.cart
        CartImpactMotion.begin(f.player, f.cart, f.world)
        check(contacts().isEmpty(), "held item started impact contact")
        f.player.primary = null
        CartImpactMotion.begin(f.player, f.cart, f.world)
        CartEmergencyDrop.reset()
        check(contacts().isEmpty(), "world reset retained contact")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        unsafe = field.get(null) as Unsafe
        Main.main(emptyArray())
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartImpactMotionTest::class.java.classLoader,
        )
        check(Main.CART_SUPPORTED && Main.CART_TRANSITION_SUPPORTED, "unsupported native hooks")
        geometry()
        wovenMovement()
        lifecycle()
        println(
            "CART_IMPACT_MOTION_PASS (woven root bound, native rebound/slowFactor, floor ownership, state cleanup and SP scope)",
        )
    }
}
