package net.alexredby.pztoolkitjavapatches

import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.characters.NetworkPlayerAI
import zombie.inventory.InventoryItem
import zombie.core.skinnedmodel.advancedanimation.*
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.iso.Vector2
import zombie.network.GameClient

object CartMotionSyncTest {
    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        var testId: Short = 0; var px = 0f; var py = 0f; var pz = 0f; var testMoving = false
        var held: InventoryItem? = null; var ai: NetworkPlayerAI? = null
        var floats: MutableMap<String?, Float>? = null; var booleans: MutableMap<String?, Boolean>? = null
        var node: AnimNode? = null; var clips: MutableMap<String, AnimationClip>? = null; var direction: Vector2? = null
        override fun getOnlineID(): Short = testId
        override fun getX(): Float = px
        override fun getY(): Float = py
        override fun getZ(): Float = pz
        override fun isPlayerMoving(): Boolean = testMoving
        override fun getNetworkCharacterAI(): NetworkPlayerAI? = ai
        override fun getCurrentState(): zombie.ai.State? = null
        override fun getPrimaryHandItem(): InventoryItem? = held
        override fun getAdvancedAnimator(): AdvancedAnimator? = null
        override fun setVariable(key: String?, value: Float): IAnimationVariableSlot? {
            if (floats == null) floats = HashMap(); floats!![key] = value; return null
        }
        override fun setVariable(key: String?, value: Boolean): IAnimationVariableSlot? {
            if (booleans == null) booleans = HashMap(); booleans!![key] = value; return null
        }
        override fun getVariableFloat(key: String?, fallback: Float): Float = if (floats == null) fallback else floats!!.getOrDefault(key, fallback)
        override fun clearVariable(key: String?) { floats?.remove(key) }
        override fun getDeferredMovement(out: Vector2): Vector2 {
            val pick = node!!.blend2dPicker.Pick(getVariableFloat("ToolkitCartStepX", 0f), getVariableFloat("ToolkitCartStepY", 0f), Anim2DBlendPicker.PickResults())
            out.set(0f, 0f)
            for (i in 0 until pick.numNodes) {
                val blend = if (i == 0) pick.node1 else if (i == 1) pick.node2 else pick.node3
                val weight = if (i == 0) pick.scale1 else if (i == 1) pick.scale2 else pick.scale3
                val clip = clips!![blend.animName]!!
                val root = clip.getTotalTranslation("Translation_Data", zombie.core.skinnedmodel.animation.BoneAxis.Y, Vector2())
                out.x += weight * root.x / clip.getDuration(); out.y += weight * root.y / clip.getDuration()
            }
            out.scale(.1f * getVariableFloat("ToolkitCartLegPace", 1f)); return out
        }
        override fun moveUnmodded(dx: Float, dy: Float) { px += dx; py += dy }
        override fun faceLocationF(x: Float, y: Float): Boolean = true
        override fun setForwardDirection(x: Float, y: Float) { direction = Vector2(x, y) }
        override fun getForwardDirection(): Vector2? = direction
    }
    private fun check(value: Boolean, message: String) { if (!value) throw AssertionError(message) }
    private fun unsafe(): Unsafe { val field = Unsafe::class.java.getDeclaredField("theUnsafe"); field.isAccessible = true; return field.get(null) as Unsafe }
    private fun connection() {
        val peer = unsafe().allocateInstance(zombie.core.raknet.UdpConnection::class.java) as zombie.core.raknet.UdpConnection
        val oldClient = GameClient.client; val oldConnected = GameClient.instance.connected; val oldPeer = GameClient.connection
        try {
            GameClient.client = false; GameClient.connection = peer; GameClient.instance.connected = true
            check(!CartMotionSync.connected(), "single-player retained a stale multiplayer connection")
            GameClient.client = true; GameClient.connection = null
            check(!CartMotionSync.connected(), "missing client transport accepted snapshots")
            GameClient.connection = peer; GameClient.instance.connected = false
            check(!CartMotionSync.connected(), "client sent snapshots before its native handshake")
            GameClient.instance.connected = true
            check(!peer.isFullyConnected() && CartMotionSync.connected(), "active Host client incorrectly required the server peer's fullyConnected flag")
            GameClient.instance.disconnect(false)
            check(!CartMotionSync.connected(), "native disconnect retained cosmetic snapshot sends")
        } finally { GameClient.connection = oldPeer; GameClient.client = oldClient; GameClient.instance.connected = oldConnected }
    }
    @Suppress("UNCHECKED_CAST") private fun lifecycle() {
        val unsafe = unsafe()
        val first = unsafe.allocateInstance(Player::class.java) as Player; first.testId = 1
        val gone = unsafe.allocateInstance(Player::class.java) as Player; gone.testId = 2
        val replaced = unsafe.allocateInstance(Player::class.java) as Player; replaced.testId = 1
        val motions = CartMotionSync::class.java.getDeclaredField("remotes"); motions.isAccessible = true
        val actions = CartActionSync::class.java.getDeclaredField("remotes"); actions.isAccessible = true
        val motionMap = motions.get(null) as MutableMap<Player, CartMotionSync.Remote>
        val actionMap = actions.get(null) as MutableMap<Player, CartActionSync.Remote>
        motionMap[first] = CartMotionSync.Remote(); motionMap[gone] = CartMotionSync.Remote()
        actionMap[first] = CartActionSync.Remote(); actionMap[gone] = CartActionSync.Remote()
        CartMotionSync.prune(mapOf(1.toShort() to first), CartMotionSync.HEARTBEAT_NANOS)
        check(motionMap.size == 1 && actionMap.size == 1, "disconnected owner retained sync caches")
        CartMotionSync.prune(mapOf(1.toShort() to replaced), CartMotionSync.HEARTBEAT_NANOS + 1)
        check(motionMap.size == 1, "cleanup exceeded its once-per-second bound")
        CartMotionSync.prune(mapOf(1.toShort() to replaced), 2 * CartMotionSync.HEARTBEAT_NANOS)
        check(motionMap.isEmpty() && actionMap.isEmpty(), "reused online ID retained old actor state")
        motionMap[first] = CartMotionSync.Remote(); actionMap[first] = CartActionSync.Remote(); CartTransition.end(null)
        check(motionMap.isEmpty() && actionMap.isEmpty(), "menu cleanup retained sync state")
    }
    @Suppress("UNCHECKED_CAST") private fun nativeCatchup() {
        val unsafe = unsafe(); val player = unsafe.allocateInstance(Player::class.java) as Player
        val network = unsafe.allocateInstance(NetworkPlayerAI::class.java) as NetworkPlayerAI; player.ai = network
        player.px = 10.1f; player.py = 20.1f; player.testMoving = true
        network.targetX = 11.2f; network.targetY = 20.8f; network.targetZ = 0; network.moving = false; network.predictionType = 0
        val node = AnimNode(); val idle = Anim2DBlend(); idle.animName = "idle"
        val walk = Anim2DBlend(); walk.animName = "walk"; walk.posY = 1f
        val right = Anim2DBlend(); right.animName = "walk"; right.posX = 1f
        val triangle = Anim2DBlendTriangle(); triangle.node1 = idle; triangle.node2 = walk; triangle.node3 = right
        node.blend2dPicker = Anim2DBlendPicker(); node.blend2dPicker.SetPickTriangles(listOf(triangle)); player.node = node
        player.clips = HashMap()
        for (name in arrayOf("idle", "walk")) {
            val start = Keyframe(); val end = Keyframe(); start.boneName = "Translation_Data"; end.boneName = "Translation_Data"
            start.position = org.lwjgl.util.vector.Vector3f(); end.position = org.lwjgl.util.vector.Vector3f(0f, 0f, if (name == "walk") -1f else 0f); end.time = 1f
            player.clips!![name] = AnimationClip(1f, listOf(start, end), name, true)
        }
        val path = unsafe.allocateInstance(zombie.pathfind.PathFindBehavior2::class.java) as zombie.pathfind.PathFindBehavior2
        val owner = path.javaClass.getDeclaredField("chr"); owner.isAccessible = true; owner.set(path, player)
        val moving = CartMotionSync.Pose(123, 1, 1, 0f, 1f, 1.04f, .8f, 0f, .1f, 0f, 0f, 0f)
        val stopped = CartMotionSync.Pose(123, 2, 1, 0f, 0f, 1.04f, -1f, 0f, 0f, 0f, 0f, 0f)
        val remote = CartMotionSync.Remote(); remote.receive(moving.encode(), 0); remote.bind(Any()); remote.owned = true
        remote.receive(stopped.encode(), 100_000_000L); remote.blend(.1f)
        player.setVariable("ToolkitCartStepX", 0f); player.setVariable("ToolkitCartStepY", 0f)
        val beforeX = player.px; val beforeY = player.py
        path.moveToPoint(network.targetX, network.targetY, 1f)
        check(player.px == beforeX && player.py == beforeY, "native fixture must reproduce stationary-root catch-up starvation")
        check(CartMotionSync.catchingUp(player), "static owner prediction incorrectly prevented native observer catch-up")
        CartMotionSync.applyLocomotion(player, remote, 100_000_000L)
        check(player.getDeferredMovement(Vector2()).getLength() > .09f, "stopped aggregate starved native animation root budget")
        check(remote.budget(true, 100_000_000L)?.speed == .8f, "numeric applied root budget was lost during catch-up")
        path.moveToPoint(network.targetX, network.targetY, 1f)
        check(player.px > beforeX && player.py > beforeY, "native moveToPoint failed to consume retained animation root budget")
        check(network.targetX == 11.2f && network.targetY == 20.8f && !network.moving && network.predictionType.toInt() == 0, "cosmetic catch-up changed native target or packet flags")
        val brake = CartMotionSync.Pose(123, 3, 3, 0f, .001f, .001f, .001f, .8f, -.2f, 1f, -.1f, 1f)
        remote.receive(brake.encode(), 200_000_000L); remote.receive(stopped.encode(), 300_000_000L)
        check(remote.budget(true, 300_000_000L)?.y == 1f, "tiny braking tail replaced useful catch-up locomotion")
        check(remote.budget(true, CartMotionSync.STALE_NANOS + 1) == null, "old moving history retained an unbounded catch-up budget")
        player.px = 11.19f; player.py = 20.79f; check(!CartMotionSync.catchingUp(player), "native same-tile arrival tolerance did not release catch-up")
        player.px = 10.99f; player.py = 20.8f; network.targetX = 11.01f; check(CartMotionSync.catchingUp(player), "nearby target across a tile boundary was falsely considered arrived")
        player.px = 11.01f; network.targetZ = 1; check(CartMotionSync.catchingUp(player), "target on another floor was falsely considered arrived")
        network.targetZ = 0; player.px = 10.1f; player.testMoving = false; check(!CartMotionSync.catchingUp(player), "native action/stopped movement decision was overridden")
        player.testMoving = true; network.targetX = Float.NaN; check(!CartMotionSync.catchingUp(player), "invalid native target activated catch-up"); network.targetX = 11.2f
        val late = CartMotionSync.Remote(); late.receive(stopped.encode(), 0); player.setVariable("ToolkitCartLegPace", .77f)
        CartMotionSync.applyLocomotion(player, late, 1)
        check(player.booleans!!["ToolkitCartPivot"] == false, "late observer without history did not select native locomotion fallback")
        check(player.getVariableFloat("ToolkitCartLegPace", 0f) == .77f, "native fallback changed custom track cadence")
        val numericStop = CartMotionSync.Pose(123, 4, 1, 0f, 1f, 1f, 0f, 0f, 0f, 0f, 0f, 0f)
        check(CartMotionSync.rootStopped(numericStop), "numeric zero budget bypassed catch-up protection")
        remote.bind(Any()); check(remote.budget(true, 1) == null, "same-ID cart replacement inherited previous root budget")
        remote.receive(moving.encode(), 1); remote.receive("invalid", 2); check(remote.locomotion == null, "malformed state retained catch-up history")
        remote.receive(moving.encode(), 3); remote.receive("", 4); check(remote.locomotion == null, "explicit release retained catch-up history")
        remote.receive(moving.encode(), 5); remote.owned = true
        val motions = CartMotionSync::class.java.getDeclaredField("remotes"); motions.isAccessible = true
        (motions.get(null) as MutableMap<Player, CartMotionSync.Remote>)[player] = remote
        CartMotionSync.reset(player); check(remote.locomotion == null && !remote.owned, "native cleanup retained borrowed locomotion after action/identity reset")
    }
    @Suppress("UNCHECKED_CAST") private fun effortReplication() {
        val unsafe = unsafe(); val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(zombie.inventory.types.InventoryContainer::class.java) as zombie.inventory.types.InventoryContainer
        cart.setModule("SaucedWheelbarrow"); cart.setType("WheelbarrowWood"); player.held = cart
        val effort = CartMotionSync.Pose(123, 1, 9, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)
        check(effort == CartMotionSync.parse(effort.encode()), "reserved brace flag lost its bounded v1 roundtrip")
        check(effort.encode().split(',').size == 13, "effort added a protocol field")
        for (flags in intArrayOf(8, 10, 11, 12, 13, 14, 15, 16, -1)) {
            val invalid = CartMotionSync.Pose(123, 1, flags, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)
            check(!invalid.valid() && CartMotionSync.parse(invalid.encode()) == null, "accepted invalid effort flag combination $flags")
        }
        for (flags in 0..7) check(CartMotionSync.parse(CartMotionSync.Pose(123, 1, flags, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f).encode()) != null, "existing v1 flag combination changed")
        val remote = CartMotionSync.Remote(); remote.receive(effort.encode(), 0); remote.owned = true; CartMotionSync.applyLocomotion(player, remote, 0)
        check(player.booleans!!["ToolkitCartBrace"] == true, "remote wood did not retain explicit owner effort")
        val stopped = CartMotionSync.Pose(123, 2, 1, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)
        remote.receive(stopped.encode(), 1); CartMotionSync.applyLocomotion(player, remote, 1)
        check(player.booleans!!["ToolkitCartBrace"] == false, "ordinary idle inferred effort or retained release")
        remote.receive(effort.encode(), 2); cart.setType("WheelbarrowMetal"); CartMotionSync.applyLocomotion(player, remote, 2)
        check(player.booleans!!["ToolkitCartBrace"] == true, "metal observer lost shared wheelbarrow effort")
        cart.setModule("SaucedCarts"); cart.setType("ShoppingCart"); CartMotionSync.applyLocomotion(player, remote, 2)
        check(player.booleans!!["ToolkitCartBrace"] == false, "wheelbarrow effort escaped to shopping cart")
        cart.setModule("SaucedWheelbarrow"); cart.setType("WheelbarrowWood")
        val network = unsafe.allocateInstance(NetworkPlayerAI::class.java) as NetworkPlayerAI; player.ai = network
        player.px = 10f; player.py = 20f; player.testMoving = true; network.targetX = 11f; network.targetY = 20f
        CartMotionSync.applyLocomotion(player, remote, 2); check(player.booleans!!["ToolkitCartBrace"] == false, "effort starved required native remote catch-up")
        player.testMoving = false; CartMotionSync.applyLocomotion(player, remote, 3)
        check(player.booleans!!["ToolkitCartBrace"] == true, "arrived observer failed to resume owner effort")
        val remotes = CartMotionSync::class.java.getDeclaredField("remotes"); remotes.isAccessible = true
        (remotes.get(null) as MutableMap<Player, CartMotionSync.Remote>)[player] = remote
        CartMotionSync.reset(player); check(player.booleans!!["ToolkitCartBrace"] == false, "reset retained remote effort")
        val sender = CartMotionSync.Sender(); val identity = Any(); sender.next(stopped, identity, 0)
        check(!sender.due(effort, identity, CartMotionSync.CHANGE_NANOS - 1) && sender.due(effort, identity, CartMotionSync.CHANGE_NANOS), "effort bypassed existing snapshot rate")
    }
    @JvmStatic fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init()
        val pose = CartMotionSync.Pose(123, 1, 7, .25f, -.8f, 1.25f, .7f, .85f, -.12f, .14f, -.085f, 1f)
        check(pose == CartMotionSync.parse(pose.encode()), "snapshot roundtrip lost visual state"); val encoded = pose.encode()
        for (malformed in arrayOf("", encoded + ",0", encoded + ",", encoded.substring(2), encoded.replaceFirst("1,123", "2,123"),
            encoded.replace("123,1,7", "123,0,7"), encoded.replace("123,1,7", "123,1,8"), encoded.replace("0.25", "NaN"), encoded.replace("0.25", "Infinity"),
            encoded.replace("0.25", "1.01"), encoded.replace("1.25", "-1"), encoded.replace("1.25", "2.51"), encoded.replace("0.7", "51"),
            encoded.replace("0.7", "-0.5"), encoded.replace("0.7", "-1.001"), encoded.replace("0.7", "-2"), encoded.replace("0.85", "11"),
            encoded.replace("-0.12", "-1.01"), encoded.replace("0.14", "-0.1"), encoded.replace("-0.085", "-0.501"), "x".repeat(241)))
            check(CartMotionSync.parse(malformed) == null, "accepted malformed snapshot: $malformed")
        val sender = CartMotionSync.Sender(); val item = Any(); val otherItem = Any()
        check(sender.due(pose, item, 0), "first held snapshot was delayed"); val first = sender.next(pose, item, 0)
        check(!sender.due(pose, item, CartMotionSync.HEARTBEAT_NANOS - 1), "idle pose flooded packets")
        check(sender.due(pose, item, CartMotionSync.HEARTBEAT_NANOS), "idle heartbeat missing")
        val changed = CartMotionSync.Pose(123, 1, 1, -.2f, .8f, 1f, 1f, 0f, 0f, 0f, 0f, 0f)
        check(!sender.due(changed, item, CartMotionSync.CHANGE_NANOS - 1), "motion exceeded 10 Hz")
        check(sender.due(changed, item, CartMotionSync.CHANGE_NANOS), "changed motion was not published")
        val replacement = CartMotionSync.Pose(124, 1, 1, 0f, 1f, 1f, 1f, 0f, 0f, 0f, 0f, 0f)
        check(sender.due(replacement, item, 1), "cart identity handoff was throttled"); check(sender.due(pose, otherItem, 1), "same-ID replacement object inherited sender state")
        check(!sender.due(changed, item, -1), "negative elapsed time bypassed the rate cap")
        var sent = 0; val burst = CartMotionSync.Sender(); var now = 0L
        while (now < 1_000_000_000L) { val active = if (now % 2_000_000L == 0L) pose else changed; if (burst.due(active, item, now)) { burst.next(active, item, now); sent++ }; now += 1_000_000L }
        check(sent <= 10, "transient input exceeded 10 snapshots per second")
        check(sender.next(pose, item, CartMotionSync.HEARTBEAT_NANOS) != first, "heartbeat cannot refresh receiver age")
        val remote = CartMotionSync.Remote(); remote.receive(first, 0)
        val modes = CartMotionSync.Remote(); modes.receive(first, 0); modes.owned = true; val nativeCadence = encoded.replace("0.7", "-1")
        check(CartMotionSync.parse(nativeCadence) != null, "native cadence sentinel rejected")
        modes.receive(nativeCadence, 1); modes.blend(.016f); check(modes.speed == -1f, "native cadence mode interpolated through a numeric root budget")
        modes.receive(encoded, 2); modes.blend(.016f); check(modes.speed == pose.speed, "root budget resumed from the negative sentinel")
        remote.bind(item); remote.x = -1f; remote.facing = true; remote.bind(otherItem)
        check(remote.x == pose.x && !remote.facing, "same-ID object handoff retained previous visual interpolation")
        check(remote.matches(123, CartMotionSync.STALE_NANOS), "valid snapshot expired too soon"); check(!remote.matches(124, 1), "different cart inherited the old pose")
        check(!remote.matches(123, CartMotionSync.STALE_NANOS + 1), "stale snapshot never expired")
        remote.receive(first, CartMotionSync.STALE_NANOS + 1); check(!remote.matches(123, CartMotionSync.STALE_NANOS + 1), "reading unchanged state revived a stale snapshot")
        remote.receive(sender.next(pose, item, CartMotionSync.STALE_NANOS + 2), CartMotionSync.STALE_NANOS + 2)
        check(remote.matches(123, CartMotionSync.STALE_NANOS + 2), "fresh heartbeat failed to resume observer")
        remote.receive("", CartMotionSync.STALE_NANOS + 3); check(!remote.matches(123, CartMotionSync.STALE_NANOS + 3), "release retained the pose")
        remote.receive("invalid", CartMotionSync.STALE_NANOS + 4); check(remote.pose == null, "malformed packet retained prior pose")
        val restarted = CartMotionSync.Sender(); remote.receive(restarted.next(pose, item, 1), CartMotionSync.STALE_NANOS + 5)
        check(remote.matches(123, CartMotionSync.STALE_NANOS + 5), "sender reset serial failed after ordered release")
        effortReplication(); lifecycle(); connection(); nativeCatchup()
        println("CART_MOTION_SYNC_PASS")
    }
}
