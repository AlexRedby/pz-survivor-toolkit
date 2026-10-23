package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import java.util.regex.Pattern
import zombie.GameTime
import zombie.ai.states.CollideWithWallState
import zombie.characters.IsoPlayer
import zombie.network.GameClient

/** One bounded cosmetic snapshot; native packets retain movement and equipment authority. */
internal object CartMotionSync {
    const val KEY = "ToolkitCartPose"
    const val CHANGE_NANOS = 100_000_000L
    const val HEARTBEAT_NANOS = 1_000_000_000L
    const val STALE_NANOS = 3_000_000_000L
    private val senders = WeakHashMap<IsoPlayer?, Sender>()
    private val remotes = WeakHashMap<IsoPlayer?, Remote>()
    private var pruned = 0L
    private val separator = Pattern.compile(",")

    @JvmRecord data class Pose(val cart: Int, val serial: Long, val flags: Int, val x: Float, val y: Float, val pace: Float, val speed: Float,
        val brakeRate: Float, val lean: Float, val pressure: Float, val side: Float, val fast: Float) {
        fun valid(): Boolean = serial > 0 && flags >= 0 && flags <= 15 && (flags and 8 == 0 || flags and 7 == 1) && x.isFinite() && y.isFinite()
            && pace.isFinite() && speed.isFinite() && brakeRate.isFinite() && lean.isFinite() && pressure.isFinite() && side.isFinite() && fast.isFinite()
            && Math.abs(x) <= 1 && Math.abs(y) <= 1 && pace >= 0 && pace <= 2.5f && (speed == -1f || speed >= 0 && speed <= 50)
            && brakeRate >= 0 && brakeRate <= 10 && Math.abs(lean) <= 1 && pressure >= 0 && pressure <= 1 && side >= -.5f && side <= 0 && fast >= 0 && fast <= 1
        fun body(): String = "$flags,${q(x)},${q(y)},${q(pace)},${q(speed)},${q(brakeRate)},${q(lean)},${q(pressure)},${q(side)},${q(fast)}"
        fun encode(): String = "1,$cart,$serial,${body()}"
        override fun toString(): String = "Pose[cart=$cart, serial=$serial, flags=$flags, x=$x, y=$y, pace=$pace, speed=$speed, brakeRate=$brakeRate, lean=$lean, pressure=$pressure, side=$side, fast=$fast]"
        private companion object { @JvmStatic private fun q(value: Float): Float = Math.round(value * 1000) / 1000f }
    }
    @JvmStatic fun parse(value: String?): Pose? {
        if (value == null || value.length > 240) return null
        val fields = separator.split(value, -1)
        if (fields.size != 13 || fields[0] != "1") return null
        return try {
            val cart = Integer.parseInt(fields[1]); val flags = Integer.parseInt(fields[3]); val serial = java.lang.Long.parseLong(fields[2])
            val f = FloatArray(9)
            for (i in f.indices) { f[i] = java.lang.Float.parseFloat(fields[i + 4]); if (!f[i].isFinite()) return null }
            val pose = Pose(cart, serial, flags, f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8])
            if (pose.valid()) pose else null
        } catch (ignored: NumberFormatException) { null }
    }
    class Sender {
        @JvmField var cart = 0
        @JvmField var item: Any? = null
        @JvmField var serial = 0L
        @JvmField var sent = 0L
        @JvmField var body: String? = null
        fun due(pose: Pose?, identity: Any?, now: Long): Boolean = body == null || item !== identity || cart != pose!!.cart || now - sent >= HEARTBEAT_NANOS
            || body != pose.body() && now - sent >= CHANGE_NANOS
        fun next(pose: Pose?, identity: Any?, now: Long): String {
            item = identity; cart = pose!!.cart; body = pose.body(); sent = now
            return Pose(cart, ++serial, pose.flags, pose.x, pose.y, pose.pace, pose.speed, pose.brakeRate, pose.lean, pose.pressure, pose.side, pose.fast).encode()
        }
    }
    class Remote {
        @JvmField var raw: String? = null
        @JvmField var pose: Pose? = null
        @JvmField var received = 0L
        @JvmField var locomotion: Pose? = null
        @JvmField var locomotionReceived = 0L
        @JvmField var owned = false
        @JvmField var item: Any? = null
        @JvmField var x = 0f
        @JvmField var y = 0f
        @JvmField var pace = 0f
        @JvmField var speed = 0f
        @JvmField var lean = 0f
        @JvmField var pressure = 0f
        @JvmField var side = 0f
        @JvmField var fast = 0f
        @JvmField var heading = 0.0
        @JvmField var facing = false
        fun receive(value: String?, now: Long) {
            if (raw == value) return
            val previous = pose
            raw = value; pose = parse(value); received = now
            val current = pose
            if (current == null || locomotion != null && locomotion!!.cart != current.cart) locomotion = null
            if (current != null && current.flags and 2 == 0 && (current.x != 0f || current.y != 0f) && current.pace > 0 && current.speed != 0f) {
                locomotion = current; locomotionReceived = now
            }
            if (current != null && !owned) seed()
            else if (current != null && (previous == null || (previous.speed < 0) != (current.speed < 0))) speed = current.speed
        }
        fun bind(identity: Any?) {
            if (item === identity) return
            if (item != null) locomotion = null
            item = identity; facing = false
            seed()
        }
        fun budget(catchup: Boolean, now: Long): Pose? {
            if (!catchup) return pose
            return if (locomotion != null && locomotion!!.cart == pose!!.cart && now - locomotionReceived <= STALE_NANOS) locomotion else null
        }
        private fun seed() {
            val current = pose ?: return
            x = current.x; y = current.y; pace = current.pace; speed = current.speed
            lean = current.lean; pressure = current.pressure; side = current.side; fast = current.fast
        }
        fun matches(cart: Int, now: Long): Boolean = pose != null && pose!!.cart == cart && now - received <= STALE_NANOS
        fun blend(seconds: Float) {
            val t = (1 - Math.exp(-Math.max(0.0, Math.min(.1, seconds.toDouble())) / .06)).toFloat()
            val current = pose!!
            x += (current.x - x) * t; y += (current.y - y) * t; pace += (current.pace - pace) * t
            if (current.speed < 0) speed = -1f else speed += (current.speed - speed) * t
            lean += (current.lean - lean) * t; pressure += (current.pressure - pressure) * t; side += (current.side - side) * t; fast += (current.fast - fast) * t
        }
    }
    @JvmStatic fun publish(player: IsoPlayer?, lean: Double, pressure: Double, side: Float, fast: Float, speed: Double) {
        if (!Main.CART_SYNC_SUPPORTED || !connected() || !player!!.isLocalPlayer()) return
        if (!CartSteeringHooks.enabled(player)) { reset(player); return }
        val flags = (if (player.getVariableBoolean("ToolkitCartPivot")) 1 else 0) or (if (player.getVariableBoolean("ToolkitCartWoodBrake")) 2 else 0) or
            (if (player.getVariableBoolean("ToolkitCartBrakeSprint")) 4 else 0) or (if (player.getVariableBoolean("ToolkitCartBrace")) 8 else 0)
        val brake = CartLegPace.brakeTrack(player)
        val pose = Pose(player.getPrimaryHandItem().getID(), 1, flags, player.getVariableFloat("ToolkitCartStepX", 0f), player.getVariableFloat("ToolkitCartStepY", 0f),
            player.getVariableFloat("ToolkitCartLegPace", 1f), speed.toFloat(), if (brake == null) 0f else brake.getSpeedDelta(), lean.toFloat(), pressure.toFloat(), side, fast)
        if (!pose.valid()) { reset(player); return }
        val sender = senders.computeIfAbsent(player) { Sender() }; val now = System.nanoTime()
        if (sender.due(pose, player.getPrimaryHandItem(), now)) player.setVariable(KEY, sender.next(pose, player.getPrimaryHandItem(), now))
    }
    private fun eligible(player: IsoPlayer): Boolean = !player.isNpc() && player.getVariableBoolean("ToolkitCartMotion")
        && !player.isAiming() && !player.isSneaking() && player.getVehicle() == null && CartSteeringHooks.supportedCart(player) && !player.isDead() && !player.hasHitReaction()
        && !player.isKnockedDown() && !player.isGettingUp() && !player.isGrappling() && !player.isBeingGrappled() && !player.isRagdollSimulationActive()
        && !player.getVariableBoolean("IsPerformingAnAction") && !player.isCurrentState(CollideWithWallState.instance())
    @JvmStatic fun rootStopped(pose: Pose?): Boolean = pose!!.speed == 0f || pose.pace == 0f || pose.flags and 1 != 0 && pose.x == 0f && pose.y == 0f
    @JvmStatic fun catchingUp(player: IsoPlayer?): Boolean {
        val network = player!!.getNetworkCharacterAI()
        if (network == null || !player.isPlayerMoving() || !network.targetX.isFinite() || !network.targetY.isFinite()) return false
        // Match native updateRemotePlayer's effective target and arrival test.
        return Math.floor(player.getX().toDouble()) != Math.floor(network.targetX.toDouble()) || Math.floor(player.getY().toDouble()) != Math.floor(network.targetY.toDouble())
            || Math.floor(player.getZ().toDouble()) != network.targetZ.toDouble() || Math.abs(player.getX() - network.targetX) + Math.abs(player.getY() - network.targetY) > .2f
    }
    /** Called at the animation hook after native remote interpolation and collisions. */
    @JvmStatic fun update(player: IsoPlayer?): Boolean {
        if (Main.CART_SYNC_SUPPORTED && GameClient.client) {
            if (connected()) prune(GameClient.IDToPlayerMap, System.nanoTime()) else { clearAll(); CartActionSync.clearAll() }
        }
        if (player!!.isLocalPlayer()) return false
        if (!Main.CART_SYNC_SUPPORTED || !connected()) return true
        val remote = remotes.computeIfAbsent(player) { Remote() }
        if (CartActionSync.update(player)) { clear(player, remote); return true }
        val now = System.nanoTime(); remote.receive(player.getVariableString(KEY), now)
        if (!eligible(player) || !remote.matches(player.getPrimaryHandItem().getID(), now)) { clear(player, remote); return true }
        remote.bind(player.getPrimaryHandItem()); CartGrounding.refreshRemoteModel(player)
        remote.blend(GameTime.getInstance().getRealworldSecondsSinceLastUpdate()); remote.owned = true
        applyLocomotion(player, remote, now)
        val network = player.getNetworkCharacterAI()
        if (network != null && network.prediction.direction.isFinite()) {
            val target = network.prediction.direction.toDouble()
            if (!remote.facing) { remote.heading = target; remote.facing = true }
            val dt = Math.max(0.0, Math.min(.1, GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()))
            remote.heading += CartSteeringMath.wrap(target - remote.heading) * (1 - Math.exp(-dt / .06))
            player.setTargetAndCurrentDirection(Math.cos(remote.heading).toFloat(), Math.sin(remote.heading).toFloat())
        }
        return true
    }
    @JvmStatic fun applyLocomotion(player: IsoPlayer?, remote: Remote?, now: Long) {
        val catchup = rootStopped(remote!!.pose) && catchingUp(player); val budget = remote.budget(catchup, now)
        val x = if (catchup && budget != null) budget.x else remote.x; val y = if (catchup && budget != null) budget.y else remote.y
        val speed = if (catchup && budget != null) budget.speed else remote.speed; val pace = if (catchup && budget != null) budget.pace else remote.pace
        // Native catch-up consumes extracted root motion; without recent history, native cart nodes supply the budget.
        player!!.setVariable("ToolkitCartPivot", budget != null && budget.flags and 1 != 0)
        player.setVariable("ToolkitCartStepX", x); player.setVariable("ToolkitCartStepY", y)
        player.setVariable("ToolkitCartWoodBrake", remote.pose!!.flags and 2 != 0); player.setVariable("ToolkitCartBrakeSprint", remote.pose!!.flags and 4 != 0)
        player.setVariable("ToolkitCartBrace", !catchup && remote.pose!!.flags and 8 != 0 && CartTransition.wheelbarrow(player.getPrimaryHandItem()))
        if (budget != null) {
            if (CartTransition.wheelbarrow(player.getPrimaryHandItem()) && remote.pose!!.flags and 2 == 0 && budget.speed >= 0) CartLegPace.applySpeed(player, speed, x, y)
            CartLegPace.apply(player, pace)
        }
        val brake = CartLegPace.brakeTrack(player)
        if (!catchup && brake != null && remote.pose!!.brakeRate > 0) brake.setSpeedDelta(remote.pose!!.brakeRate)
    }
    private fun clear(player: IsoPlayer?, remote: Remote?) {
        CartObserverRender.forget(player)
        remote!!.locomotion = null
        player!!.setVariable("ToolkitCartBrace", false)
        if (!remote.owned) return
        remote.owned = false; remote.facing = false; remote.item = null
        player.setVariable("ToolkitCartPivot", false); player.setVariable("ToolkitCartStepX", 0f); player.setVariable("ToolkitCartStepY", 0f)
        player.setVariable("ToolkitCartWoodBrake", false); player.setVariable("ToolkitCartBrakeSprint", false); player.clearVariable("ToolkitCartLegPace")
    }
    @JvmStatic fun reset(player: IsoPlayer?) {
        CartObserverRender.forget(player)
        if (senders.remove(player) != null && Main.CART_SYNC_SUPPORTED && connected() && player!!.isLocalPlayer()) player.setVariable(KEY, "")
        val remote = remotes.remove(player)
        if (remote != null) clear(player, remote)
    }
    @JvmStatic fun connected(): Boolean = GameClient.client && GameClient.connection != null && GameClient.instance.connected
    @JvmStatic fun prune(online: Map<Short, IsoPlayer>?, now: Long) {
        if (now - pruned < HEARTBEAT_NANOS) return
        pruned = now
        for (player in ArrayList(remotes.keys)) {
            val id = player!!.getOnlineID()
            if (online!![id] === player) continue
            val remote = remotes.remove(player)
            if (remote != null) clear(player, remote)
            CartActionSync.forget(player); CartTransition.endRemote(player)
        }
    }
    @JvmStatic fun clearAll() {
        CartObserverRender.clearAll(); senders.clear()
        for (player in ArrayList(remotes.keys)) { clear(player, remotes[player]); CartTransition.endRemote(player) }
        remotes.clear(); pruned = 0
    }
    private fun visual(player: IsoPlayer?): Remote? {
        if (!Main.CART_SYNC_SUPPORTED) return null
        val remote = remotes[player]
        return if (remote != null && remote.owned && eligible(player!!) && remote.matches(player.getPrimaryHandItem().getID(), System.nanoTime())) remote else null
    }
    @JvmStatic fun visualEnabled(player: IsoPlayer?): Boolean = if (player!!.isLocalPlayer()) CartSteeringHooks.enabled(player) else visual(player) != null
    @JvmStatic fun lean(player: IsoPlayer?): Double = visual(player)?.lean?.toDouble() ?: 0.0
    @JvmStatic fun pressure(player: IsoPlayer?): Double = visual(player)?.pressure?.toDouble() ?: 0.0
    @JvmStatic fun sideClearance(player: IsoPlayer?): Float = visual(player)?.side ?: 0f
    @JvmStatic fun fastWeight(player: IsoPlayer?): Float = visual(player)?.fast ?: 0f
}
