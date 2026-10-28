package net.alexredby.pztoolkitjavapatches

import java.util.Stack
import org.joml.Vector3f
import se.krka.kahlua.j2se.KahluaTableImpl
import sun.misc.Unsafe
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.inventory.InventoryItem
import zombie.iso.IsoGridSquare
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.pathfind.PathFindBehavior2
import zombie.pathfind.PathFindBehavior2.BehaviorResult
import zombie.vehicles.BaseVehicle

object CartPickupApproachTest {
    private lateinit var unsafe: Unsafe

    private fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(owner: Any, name: String, value: Any?) {
        var type: Class<*>? = owner.javaClass
        while (type != null) {
            try {
                val field = type.getDeclaredField(name)
                field.isAccessible = true
                field.set(owner, value)
                return
            } catch (missing: NoSuchFieldException) {
                type = type.superclass
            }
        }
        throw NoSuchFieldException(name)
    }

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        lateinit var actions: Stack<BaseAction>
        lateinit var path: PathFindBehavior2
        lateinit var testVehicle: BaseVehicle
        var protection = 0
        var moves = 0
        var turning = false
        var wantsTurn = false
        var animation: AnimationPlayer? = null
        var px = 10f
        var py = 20f
        var nx = 10f
        var ny = 20f

        override fun isTurning(): Boolean = turning

        override fun shouldBeTurning(): Boolean = wantsTurn

        override fun getAnimationPlayer(): AnimationPlayer? = animation

        override fun hasAnimationPlayer(): Boolean = animation != null

        override fun getX(): Float = px

        override fun getY(): Float = py

        override fun moveUnmodded(dx: Float, dy: Float) {
            moves++
            nx = px + dx
            ny = py + dy
        }

        fun settle() {
            px = nx
            py = ny
        }

        override fun isLocalPlayer(): Boolean = protection != 1

        override fun isDead(): Boolean = protection == 2

        override fun isAiming(): Boolean = protection == 3

        override fun hasHitReaction(): Boolean = protection == 4

        override fun isKnockedDown(): Boolean = protection == 5

        override fun isGettingUp(): Boolean = protection == 6

        override fun getVehicle(): BaseVehicle? = if (protection == 7) testVehicle else null

        override fun isGrappling(): Boolean = protection == 8

        override fun isBeingGrappled(): Boolean = protection == 9

        override fun isRagdollSimulationActive(): Boolean = protection == 10

        override fun getCharacterActions(): Stack<BaseAction> = actions

        override fun getPathFindBehavior2(): PathFindBehavior2 = path
    }

    private class Cart : InventoryItem(null, null, null, null as String?) {
        lateinit var kind: String
        var world: IsoWorldInventoryObject? = null

        override fun getFullType(): String = kind

        override fun getWorldItem(): IsoWorldInventoryObject? = world
    }

    private class World : IsoWorldInventoryObject(null as zombie.iso.IsoCell?) {
        var heldItem: InventoryItem? = null
        var testSquare: IsoGridSquare? = null

        override fun getItem(): InventoryItem? = heldItem

        override fun getSquare(): IsoGridSquare? = testSquare
    }

    private data class Fixture(
        val player: Player,
        val cart: Cart,
        val world: World,
        val action: LuaTimedActionNew,
        val table: KahluaTableImpl,
    )

    private fun fixture(kind: String = "SaucedWheelbarrow.WheelbarrowWood"): Fixture {
        val player = allocate(Player::class.java)
        player.actions = Stack()
        player.testVehicle = allocate(BaseVehicle::class.java)
        player.px = 10f
        player.nx = 10f
        player.py = 20f
        player.ny = 20f
        player.path = PathFindBehavior2(player)
        field(player.path, "goal", PathFindBehavior2.Goal.Location)
        field(player.path, "targetX", 10.03f)
        field(player.path, "targetY", 20.04f)
        field(player.path, "targetZ", 0f)
        val cart = allocate(Cart::class.java)
        val world = allocate(World::class.java)
        cart.kind = kind
        cart.world = world
        world.heldItem = cart
        world.testSquare = allocate(IsoGridSquare::class.java)
        val action = allocate(LuaTimedActionNew::class.java)
        action.chr = player
        action.maxTime = -1
        val table = KahluaTableImpl(HashMap<Any, Any>())
        val meta = KahluaTableImpl(HashMap<Any, Any>())
        meta.rawset("Type", "ISWalkToTimedActionF")
        table.setMetatable(meta)
        table.rawset("character", player)
        table.rawset("toolkitWoodCartItem", cart)
        table.rawset("location", Vector3f(10.03f, 20.04f, 0f))
        field(action, "table", table)
        player.actions.add(action)
        return Fixture(player, cart, world, action, table)
    }

    private fun arrival(kind: String) {
        var f = fixture(kind)
        var p = f.player
        for (nativeResult in arrayOf(BehaviorResult.Working, BehaviorResult.Failed)) check(
            CartPickupApproach.result(p, p.path, nativeResult) == nativeResult && p.moves == 0,
            "changed unresolved native path",
        )
        check(
            CartPickupApproach.result(p, p.path, BehaviorResult.Succeeded) ==
                BehaviorResult.Working,
            "nearby off-center start succeeded",
        )
        check(
            p.px == 10f &&
                p.py == 20f &&
                Math.hypot((p.nx - p.px).toDouble(), (p.ny - p.py).toDouble()) <= .02001,
            "alignment teleported or exceeded bounded step",
        )
        p.nx = 10.03f
        p.ny = 20.04f
        check(
            CartPickupApproach.result(p, p.path, BehaviorResult.Succeeded) ==
                BehaviorResult.Working,
            "accepted unresolved Next position",
        )
        for (i in 1 until 45) check(
            CartPickupApproach.result(p, p.path, BehaviorResult.Succeeded) ==
                (if (i == 44) BehaviorResult.Failed else BehaviorResult.Working),
            "blocked correction did not honor its attempted-update budget",
        )
        f = fixture(kind)
        p = f.player
        var success = false
        for (i in 0 until 100) {
            val result = CartPickupApproach.result(p, p.path, BehaviorResult.Succeeded)
            if (result == BehaviorResult.Succeeded) {
                success = true
                break
            }
            check(result == BehaviorResult.Working, "unblocked final approach failed")
            p.settle()
        }
        check(
            success && Math.hypot((p.px - 10.03f).toDouble(), (p.py - 20.04f).toDouble()) <= .002,
            "approach did not reach actual target",
        )
        for (x in floatArrayOf(9f, Float.NaN)) {
            f = fixture(kind)
            f.player.px = x
            check(
                CartPickupApproach.result(f.player, f.player.path, BehaviorResult.Succeeded) ==
                    BehaviorResult.Failed && f.player.moves == 0,
                "unsafe correction moved actor",
            )
        }
        f = fixture(kind)
        p = f.player
        f.table.getMetatable().rawset("Type", "ToolkitWoodCartPickup")
        check(
            CartPickupApproach.suppressDeferred(p),
            "arrived wheelbarrow pickup retained locomotion blend: $kind",
        )
        p.actions.clear()
        check(
            !CartPickupApproach.suppressDeferred(p),
            "finished wheelbarrow pickup retained movement lease: $kind",
        )
        f = fixture(kind)
        f.table.rawset("toolkitWoodCartItem", null)
        check(
            CartPickupApproach.result(f.player, f.player.path, BehaviorResult.Succeeded) ==
                BehaviorResult.Succeeded && f.player.moves == 0,
            "ordinary path acquired precise movement",
        )
    }

    private fun scopeAndCleanup() {
        for (guard in 1..10) {
            val f = fixture()
            f.player.protection = guard
            check(
                CartPickupApproach.result(f.player, f.player.path, BehaviorResult.Succeeded) ==
                    BehaviorResult.Succeeded && f.player.moves == 0,
                "moved protected player $guard",
            )
            f.table.getMetatable().rawset("Type", "ToolkitWoodCartPickup")
            check(
                !CartPickupApproach.suppressDeferred(f.player),
                "suppressed protected player $guard",
            )
        }
        for (guard in 0 until 16) {
            val f = fixture()
            when (guard) {
                0 -> f.table.getMetatable().rawset("Type", "ISWalkToTimedAction")
                1 -> f.table.rawset("character", allocate(Player::class.java))
                2 -> f.cart.kind = "Other.Cart"
                3 -> f.cart.world = null
                4 -> f.world.heldItem = allocate(Cart::class.java)
                5 -> f.world.testSquare = null
                6 -> (f.table.rawget("location") as Vector3f).x += .001f
                7 -> f.action.forceStop = true
                8 -> f.action.forceComplete = true
                9 -> f.action.maxTime = 0
                10 -> f.player.actions.add(allocate(BaseAction::class.java))
                11 -> f.player.actions.clear()
                12 -> field(f.player.path, "goal", PathFindBehavior2.Goal.None)
                13 -> (f.table.rawget("location") as Vector3f).y = Float.NaN
                14 -> f.action.chr = allocate(Player::class.java)
                15 -> field(f.action, "table", null)
            }
            check(
                CartPickupApproach.result(f.player, f.player.path, BehaviorResult.Succeeded) ==
                    BehaviorResult.Succeeded && f.player.moves == 0,
                "corrected unrelated/invalid action $guard",
            )
        }
        val f = fixture()
        f.player.setDeferredMovementEnabled(false)
        check(
            !CartPickupApproach.suppressDeferred(f.player) && !f.player.isDeferredMovementEnabled(),
            "cart walk changed native movement policy",
        )
        f.player.actions.clear()
        check(!f.player.isDeferredMovementEnabled(), "scope rewrote stored disabled movement flag")
        f.player.setDeferredMovementEnabled(true)
        f.player.actions.add(f.action)
        check(
            f.player.isDeferredMovementEnabled(),
            "cart walk suppressed native climbing translation",
        )
        f.table.getMetatable().rawset("Type", "ToolkitWoodCartPickup")
        check(!f.player.isDeferredMovementEnabled(), "pickup allowed residual deferred motion")
        f.player.actions.clear()
        check(
            !CartPickupApproach.suppressDeferred(f.player) && f.player.isDeferredMovementEnabled(),
            "cancel retained cart movement suppression",
        )
        f.player.actions.add(f.action)
        f.action.forceStop = true
        check(
            !CartPickupApproach.suppressDeferred(f.player) && f.player.isDeferredMovementEnabled(),
            "stopped pickup retained movement suppression",
        )
        f.action.forceStop = false
        f.table.getMetatable().rawset("Type", "ToolkitWoodCartPickup")
        f.table.rawset("toolkitWoodCartItem", null)
        f.table.rawset("location", null)
        check(
            CartPickupApproach.suppressDeferred(f.player) && !f.player.isDeferredMovementEnabled(),
            "native pickup hook allowed locomotion blend translation",
        )
        f.action.maxTime = 0
        check(
            !CartPickupApproach.suppressDeferred(f.player) && f.player.isDeferredMovementEnabled(),
            "finished pickup retained movement suppression",
        )
    }

    private fun facing(): Fixture {
        val f = fixture("SaucedWheelbarrow.WheelbarrowMetal")
        f.table.getMetatable().rawset("Type", "ToolkitWoodCartPickup")
        f.table.rawset("itemId", f.cart.getID().toDouble())
        f.player.animation = allocate(AnimationPlayer::class.java)
        field(f.player.animation!!, "targetDir", zombie.iso.Vector2())
        field(f.player, "forwardDirection", zombie.iso.Vector2())
        f.player.animation!!.setMaxTwistAngle(Math.toRadians(45.0).toFloat())
        f.player.setTargetAndCurrentDirection(
            Math.cos(1.3847381 - Math.PI / 2).toFloat(),
            Math.sin(1.3847381 - Math.PI / 2).toFloat(),
        )
        return f
    }

    private fun facingCompletion() {
        var f = facing()
        val target = Math.PI.toFloat() / 2
        var before = f.player.animation!!.getRenderedAngle()
        var aligned = false
        for (i in 0 until 60) {
            aligned = CartPickupApproach.face(f.player, f.world, 10f, 20f, target)
            val now = f.player.animation!!.getRenderedAngle()
            check(
                now >= before && now - before <= .030001f,
                "idle facing snapped or rotated away from handles",
            )
            check(
                f.player.px == 10f && f.player.py == 20f && f.player.moves == 0,
                "facing completion moved actor",
            )
            check(
                Math.abs(f.player.getForwardDirectionX() - 1) < .00001 &&
                    Math.abs(f.player.getForwardDirectionY()) < .00001,
                "bounded completion lost full native facing request",
            )
            before = now
            if (aligned) break
        }
        check(
            aligned && Math.abs(target - before) < Math.toRadians(1.0),
            "recorded yaw270 idle remainder did not finish",
        )
        for (guard in 0 until 12) {
            f = facing()
            when (guard) {
                0 -> f.player.turning = true
                1 -> f.player.wantsTurn = true
                2 -> f.player.px += .003f
                3 -> f.table.rawset("itemId", f.cart.getID().toDouble() + 1)
                4 -> f.cart.world = null
                5 -> f.table.getMetatable().rawset("Type", "ISWalkToTimedActionF")
                6 -> f.player.protection = 1
                7 -> f.action.forceStop = true
                8 -> f.player.protection = 2
                9 -> f.player.actions.clear()
                10 -> f.player.animation!!.setMaxTwistAngle(.01f)
                11 -> f.world.testSquare = null
            }
            before = f.player.animation!!.getRenderedAngle()
            check(
                !CartPickupApproach.face(f.player, f.world, 10f, 20f, target) &&
                    f.player.animation!!.getRenderedAngle() == before,
                "facing completion bypassed native/action/position gate $guard",
            )
        }
        f = facing()
        f.player.animation!!.setMaxTwistAngle(
            target - f.player.animation!!.getRenderedAngle() - .005f,
        )
        before = f.player.animation!!.getRenderedAngle()
        CartPickupApproach.face(f.player, f.world, 10f, 20f, target)
        check(
            f.player.animation!!.getRenderedAngle() > before,
            "native one-degree excess-twist dead zone remained stuck",
        )
        val time = zombie.GameTime.getInstance()
        val saved = time.getTrueMultiplier()
        try {
            time.setMultiplier(100f)
            f = facing()
            before = f.player.animation!!.getRenderedAngle()
            CartPickupApproach.face(f.player, f.world, 10f, 20f, target)
            check(
                f.player.animation!!.getRenderedAngle() - before <= .030001f,
                "fast game speed snapped final facing",
            )
            time.setMultiplier(0f)
            f = facing()
            before = f.player.animation!!.getRenderedAngle()
            check(
                !CartPickupApproach.face(f.player, f.world, 10f, 20f, target) &&
                    f.player.animation!!.getRenderedAngle() == before,
                "paused game advanced facing",
            )
        } finally {
            time.setMultiplier(saved)
        }
        val method =
            CartTransition::class
                .java
                .getMethod("face", IsoPlayer::class.java, IsoWorldInventoryObject::class.java)
        val exposed =
            method.getAnnotation(se.krka.kahlua.integration.annotations.LuaMethod::class.java)
        check(
            exposed != null && exposed.global && exposed.name == "toolkitWoodCartFace",
            "pickup face bridge is not exposed to Lua",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        unsafe = field.get(null) as Unsafe
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartPickupApproachTest::class.java.classLoader,
        )
        check(
            Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED,
            "native cart approach fixture is unsupported",
        )
        arrival("SaucedWheelbarrow.WheelbarrowWood")
        arrival("SaucedWheelbarrow.WheelbarrowMetal")
        arrival("SaucedCarts.ShoppingCart")
        scopeAndCleanup()
        facingCompletion()
        println("CART_PICKUP_APPROACH_PASS")
    }
}
