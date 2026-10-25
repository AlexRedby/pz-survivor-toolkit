package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.model.ItemModelRenderer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.iso.IsoGridSquare
import zombie.iso.objects.IsoWorldInventoryObject

object CartEmergencyDropTest {
    private lateinit var unsafe: Unsafe

    private fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(a: Number, b: Number, tolerance: Double, message: String) {
        check(Math.abs(a.toDouble() - b.toDouble()) <= tolerance, "$message: $a != $b")
    }

    private fun get(target: Any, name: String): Any? {
        val f = target.javaClass.getDeclaredField(name)
        f.isAccessible = true
        return f.get(target)
    }

    private fun set(target: Any, name: String, value: Any?) {
        val f = target.javaClass.getDeclaredField(name)
        f.isAccessible = true
        f.set(target, value)
    }

    @Suppress("UNCHECKED_CAST")
    private fun releases(): MutableMap<InventoryItem, Any> {
        val f = CartEmergencyDrop::class.java.getDeclaredField("releases")
        f.isAccessible = true
        return f.get(null) as MutableMap<InventoryItem, Any>
    }

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        var primary: InventoryItem? = null
        var secondary: InventoryItem? = null

        override fun isLocalPlayer(): Boolean = false

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary
    }

    private class Cart : InventoryItem(null, null, null, null as String?) {
        var world: IsoWorldInventoryObject? = null
        var kind: String? = null

        override fun getFullType(): String = kind ?: "SaucedWheelbarrow.WheelbarrowWood"

        override fun getWorldItem(): IsoWorldInventoryObject? = world
    }

    private class World : IsoWorldInventoryObject(null as zombie.iso.IsoCell?) {
        var testSquare: IsoGridSquare? = null
        var heldItem: InventoryItem? = null
        var invalidations = 0
        var px = 10f
        var py = 20f
        var pz = 2f

        override fun getSquare(): IsoGridSquare? = testSquare

        override fun getItem(): InventoryItem? = heldItem

        override fun getWorldPosX(): Float = px

        override fun getWorldPosY(): Float = py

        override fun getWorldPosZ(): Float = pz

        override fun invalidateRenderChunkLevel(flags: Long) {
            check(flags == 256L, "wrong invalidation")
            invalidations++
        }
    }

    private data class Fixture(
        val player: Player,
        val cart: Cart,
        val world: World,
        val release: Any,
    )

    private fun fixture(kind: String): Fixture {
        val player = allocate(Player::class.java)
        val cart = allocate(Cart::class.java)
        cart.kind = kind
        val world = allocate(World::class.java)
        world.testSquare = allocate(IsoGridSquare::class.java)
        world.px = 10f
        world.py = 20f
        world.pz = 2f
        world.heldItem = cart
        cart.world = world
        val source = CartTransitionMath.Placement(10f, 20f, 2.05f, 0f, 30f, 8f, .85f)
        val target = CartTransitionMath.Placement(10f, 20f, 2.00175f, 0f, 30f, 0f, .85f)
        val type = Class.forName(CartEmergencyDrop::class.java.name + "\$Release")
        val constructor =
            type.getDeclaredConstructor(
                IsoPlayer::class.java,
                CartTransitionMath.Placement::class.java,
                CartTransitionMath.Placement::class.java,
                Matrix4f::class.java,
                Long::class.javaPrimitiveType,
            )
        constructor.isAccessible = true
        val release =
            constructor.newInstance(
                player,
                source,
                target,
                Matrix4f()
                    .scale(
                        if (CartWheelbarrow.forType(kind) === CartWheelbarrow.METAL)
                            .0091743395f / .85f
                        else 90f,
                    ),
                System.nanoTime(),
            )
        releases()[cart] = release
        return Fixture(player, cart, world, release)
    }

    private fun geometry() {
        for (profile in arrayOf(CartWheelbarrow.WOOD, CartWheelbarrow.METAL)) {
            val model =
                if (profile === CartWheelbarrow.WOOD)
                    Matrix4f().rotateX(Math.PI.toFloat() / 2).scale(90f)
                else Matrix4f().scale(.0091743395f / .85f)
            val axle = profile.center(Vector3f())
            for (angle in floatArrayOf(0f, .3f, 1.57f, 3.14f, 4.7f, 6.1f)) for (bank in
                floatArrayOf(-.122173f, 0f, .122173f)) for (shift in floatArrayOf(0f, -.24f)) {
                val held = profile.held(Matrix4f())
                check(
                    CartGrounding.alignWheelbarrow(
                        held,
                        profile,
                        bank,
                        Math.abs(bank),
                        shift,
                        Matrix4f(),
                    ),
                    "held alignment",
                )
                val landing =
                    CartTransition.dropPlacement(
                        held,
                        model,
                        10.25f,
                        20.75f,
                        2f,
                        angle,
                        1f,
                        0f,
                        profile,
                    )
                val ground = Matrix4f()
                check(
                    landing != null &&
                        CartTransitionMath.worldToActor(
                            landing,
                            model,
                            10.25f,
                            20.75f,
                            2f,
                            angle,
                            ground,
                        ),
                    "emergency landing missing",
                )
                val first = held.transformPosition(axle, Vector3f())
                val last = ground.transformPosition(axle, Vector3f())
                close(first.x, last.x, .00001, "landing axle lateral jump")
                close(first.z, last.z, .00001, "landing axle fore-aft jump")
                val out = Matrix4f()
                val low0 = CartGrounding.wheelbarrowLowest(held, profile)
                val low1 = CartGrounding.wheelbarrowLowest(ground, profile)
                for (i in 0..100) {
                    check(
                        CartEmergencyDrop.settle(held, ground, i / 100.0, out, profile),
                        "settle failed",
                    )
                    val actual = out.transformPosition(axle, Vector3f())
                    close(actual.x, first.x, .00002, "settle axle sideways drift")
                    close(actual.z, first.z, .00002, "settle axle forward drift")
                    val low = CartGrounding.wheelbarrowLowest(out, profile)
                    check(
                        low >= Math.min(low0, low1) - .00001 &&
                            low <= Math.max(low0, low1) + .00001,
                        "wheel jumped vertically during settle",
                    )
                }
                check(out.equals(ground, .000001f), "endpoint differs from stock world transform")
                CartEmergencyDrop.settle(held, ground, 0.0, out, profile)
                check(out.equals(held, .000001f), "initial pose discontinuous")
            }
        }
        check(
            !CartEmergencyDrop.settle(Matrix4f().m00(Float.NaN), Matrix4f(), .5, Matrix4f()),
            "invalid source accepted",
        )
        check(
            !CartEmergencyDrop.settle(Matrix4f(), Matrix4f(), Double.NaN, Matrix4f()),
            "invalid clock accepted",
        )
        check(CartEmergencyDrop.fresh(100, 99, 1f, 2f, 3f, 1.2f, 2f, 3f), "fresh source refused")
        check(!CartEmergencyDrop.fresh(100, 101, 1f, 2f, 3f, 1f, 2f, 3f), "future source accepted")
        check(
            !CartEmergencyDrop.fresh(CartEmergencyDrop.FRESH_NANOS + 1, 0, 1f, 2f, 3f, 1f, 2f, 3f),
            "stale source accepted",
        )
        check(!CartEmergencyDrop.fresh(100, 99, 1f, 2f, 3f, 1f, 2f, 4f), "wrong floor accepted")
        check(!CartEmergencyDrop.fresh(100, 99, 1f, 2f, 3f, 2f, 2f, 3f), "teleport accepted")
    }

    private fun ownershipAndPool(kind: String) {
        var f = fixture(kind)
        CartEmergencyDrop.finish(f.player, f.cart)
        check(
            get(f.release, "world") === f.world && f.world.invalidations == 1,
            "exact confirmed drop did not bind",
        )
        val started = get(f.release, "started") as Long
        CartEmergencyDrop.finish(f.player, f.cart)
        check(
            get(f.release, "started") as Long == started && f.world.invalidations == 1,
            "duplicate completion restarted settle",
        )
        val renderer = ItemModelRenderer()
        renderer.x = 10f
        renderer.y = 20f
        renderer.z = 2.00175f
        renderer.angle.set(0f, 30f, 0f)
        val matrix = Matrix4f().scale(76.5f)
        set(renderer, "transform", matrix)
        set(f.release, "started", System.nanoTime() - CartEmergencyDrop.SETTLE_NANOS / 2)
        CartEmergencyDrop.render(renderer, f.cart)
        check(!matrix.equals(Matrix4f().scale(76.5f), .001f), "active presentation did not render")
        CartEmergencyDrop.clear(renderer)
        check(
            matrix.equals(Matrix4f().scale(76.5f), .000001f) && renderer.angle.y == 30f,
            "pooled matrix/angle not restored",
        )
        CartEmergencyDrop.render(renderer, f.cart)
        // Real init advice restores old state before native initialization replaces its values.
        Main.WoodenWorldScale.enter(renderer)
        matrix.translation(5f, 6f, 7f)
        renderer.angle.set(11f, 12f, 13f)
        CartEmergencyDrop.render(renderer, allocate(Cart::class.java))
        check(
            matrix.equals(Matrix4f().translation(5f, 6f, 7f), .000001f) && renderer.angle.y == 12f,
            "foreign pooled item inherited pose",
        )
        CartEmergencyDrop.render(renderer, f.cart)
        set(f.release, "started", System.nanoTime() - CartEmergencyDrop.SETTLE_NANOS - 1)
        CartEmergencyDrop.tick()
        check(
            !releases().containsKey(f.cart) && f.world.invalidations >= 2,
            "final FBO invalidation or expiry missing",
        )
        CartEmergencyDrop.render(renderer, f.cart)
        check(
            matrix.equals(Matrix4f().translation(5f, 6f, 7f), .000001f),
            "expiry did not restore renderer",
        )
        for (bad in 0 until 7) {
            f = fixture(kind)
            if (bad == 0) f.player.primary = f.cart
            if (bad == 1) f.cart.setContainer(allocate(ItemContainer::class.java))
            if (bad == 2) f.world.heldItem = allocate(Cart::class.java)
            if (bad == 3) f.world.px += .1f
            if (bad == 5) f.world.testSquare = null
            if (bad == 6)
                set(f.release, "prepared", System.nanoTime() - CartEmergencyDrop.FRESH_NANOS - 1)
            CartEmergencyDrop.finish(
                if (bad == 4) allocate(Player::class.java) else f.player,
                f.cart,
            )
            check(
                !releases().containsKey(f.cart) && f.world.invalidations == 0,
                "invalid authoritative handoff accepted $bad",
            )
        }
        f = fixture(kind)
        CartEmergencyDrop.finish(f.player, f.cart)
        f.cart.world = null
        CartEmergencyDrop.tick()
        check(!releases().containsKey(f.cart), "pickup retained release")
        f = fixture(kind)
        CartEmergencyDrop.finish(f.player, f.cart)
        f.world.testSquare = null
        CartEmergencyDrop.tick()
        check(
            !releases().containsKey(f.cart) && f.world.invalidations == 1,
            "removed world retained release or invalidated missing square",
        )
        f = fixture(kind)
        CartEmergencyDrop.finish(f.player, f.cart)
        CartEmergencyDrop.render(renderer, f.cart)
        CartEmergencyDrop.reset()
        check(
            releases().isEmpty() && matrix.equals(Matrix4f().translation(5f, 6f, 7f), .000001f),
            "session reset retained world or renderer state",
        )
        f = fixture(kind)
        CartEmergencyDrop.finish(f.player, f.cart)
        val floor = ItemContainer("floor", null, null)
        floor.AddItem(f.cart)
        check(f.cart.getContainer() === floor, "native floor projection did not assign container")
        // Isolate ownership; native AddItem class loading is not the settle clock.
        set(f.release, "started", System.nanoTime())
        CartEmergencyDrop.tick()
        check(releases().containsKey(f.cart), "native floor projection ended settling")
        CartEmergencyDrop.render(renderer, f.cart)
        check(
            !matrix.equals(Matrix4f().translation(5f, 6f, 7f), .000001f),
            "floor-projected cart stopped settling",
        )
        CartEmergencyDrop.clear(renderer)
        f.cart.setContainer(ItemContainer("inventory", null, null))
        CartEmergencyDrop.tick()
        check(!releases().containsKey(f.cart), "real inventory transfer retained release")
        f = fixture(kind)
        zombie.network.GameClient.client = true
        try {
            CartEmergencyDrop.finish(f.player, f.cart)
            check(!releases().containsKey(f.cart), "MP release was altered")
        } finally {
            zombie.network.GameClient.client = false
            releases().clear()
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val u = Unsafe::class.java.getDeclaredField("theUnsafe")
        u.isAccessible = true
        unsafe = u.get(null) as Unsafe
        check(Main.CART_TRANSITION_SUPPORTED, "unsupported local source")
        // Finish class loading before the real250ms freshness window begins.
        zombie.network.GameClient.client = false
        zombie.network.GameServer.server = false
        geometry()
        ownershipAndPool("SaucedWheelbarrow.WheelbarrowWood")
        ownershipAndPool("SaucedWheelbarrow.WheelbarrowMetal")
        println(
            "CART_EMERGENCY_DROP_PASS (axle/floor continuity, freshness, exact ownership, pooled restoration, expiry and MP fallback)",
        )
    }
}
