package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import java.util.regex.Pattern
import zombie.GameTime
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem

/** Action presentation has a separate lease from ordinary held-cart locomotion. */
internal object CartActionSync {
    const val KEY = "ToolkitCartActionPose"
    private val senders = WeakHashMap<IsoPlayer?, Sender>()
    private val remotes = WeakHashMap<IsoPlayer?, Remote>()
    private var generation = 0L
    private val separator = Pattern.compile(",")

    @JvmRecord data class Pose(val cart: Int, val action: Long, val serial: Long, val flags: Int, val progress: Float, val cancelled: Float,
        val x: Float, val y: Float, val z: Float, val xr: Float, val zr: Float, val yr: Float, val scale: Float) {
        fun pickup(): Boolean = flags and 1 != 0
        fun recovering(): Boolean = flags and 2 != 0
        fun valid(): Boolean = action > 0 && serial > 0 && flags >= 0 && flags <= 3
            && progress.isFinite() && cancelled.isFinite() && progress >= 0 && progress <= 1 && cancelled >= 0 && cancelled <= 1
            && (!recovering() || cancelled > 0 && progress <= cancelled)
            && x.isFinite() && y.isFinite() && Math.abs(x) <= 1_000_000 && Math.abs(y) <= 1_000_000
            && z.isFinite() && z >= -32 && z <= 64 && xr.isFinite() && zr.isFinite() && yr.isFinite()
            && Math.abs(xr) <= 360 && Math.abs(zr) <= 360 && Math.abs(yr) <= 360 && scale.isFinite() && scale > 0 && scale <= 100
        fun nearby(px: Float, py: Float, pz: Float): Boolean = Math.hypot((x - px).toDouble(), (y - py).toDouble()) <= 2.5 && Math.abs(z - pz) <= .25
        fun placement(): CartTransitionMath.Placement = CartTransitionMath.Placement(x, y, z, xr, zr, yr, scale)
        fun body(): String = "$cart,$action,$flags,${q(progress)},${q(cancelled)},$x,$y,$z,$xr,$zr,$yr,$scale"
        fun encode(packet: Long): String = "1,$packet,${body()}"
        override fun toString(): String = "Pose[cart=$cart, action=$action, serial=$serial, flags=$flags, progress=$progress, cancelled=$cancelled, x=$x, y=$y, z=$z, xr=$xr, zr=$zr, yr=$yr, scale=$scale]"
        private companion object { @JvmStatic private fun q(value: Float): Float = Math.round(value * 1000) / 1000f }
    }
    @JvmStatic fun parse(value: String?): Pose? {
        if (value == null || value.length > 300) return null
        val f = separator.split(value, -1)
        if (f.size != 14 || f[0] != "1") return null
        return try {
            val pose = Pose(Integer.parseInt(f[2]), java.lang.Long.parseLong(f[3]), java.lang.Long.parseLong(f[1]), Integer.parseInt(f[4]),
                java.lang.Float.parseFloat(f[5]), java.lang.Float.parseFloat(f[6]), java.lang.Float.parseFloat(f[7]), java.lang.Float.parseFloat(f[8]),
                java.lang.Float.parseFloat(f[9]), java.lang.Float.parseFloat(f[10]), java.lang.Float.parseFloat(f[11]), java.lang.Float.parseFloat(f[12]), java.lang.Float.parseFloat(f[13]))
            if (pose.valid()) pose else null
        } catch (ignored: NumberFormatException) { null }
    }
    class Sender {
        @JvmField var item: Any? = null
        @JvmField var serial = 0L
        @JvmField var sent = 0L
        @JvmField var action = 0L
        @JvmField var flags = 0
        @JvmField var body: String? = null
        fun due(pose: Pose?, identity: Any?, now: Long): Boolean = body == null || item !== identity || action != pose!!.action || flags != pose.flags
            || now - sent >= CartMotionSync.HEARTBEAT_NANOS || body != pose.body() && now - sent >= CartMotionSync.CHANGE_NANOS
        fun next(pose: Pose?, identity: Any?, now: Long): String {
            item = identity; action = pose!!.action; flags = pose.flags; body = pose.body(); sent = now
            return pose.encode(++serial)
        }
    }
    class Remote {
        @JvmField var raw: String? = null
        @JvmField var pose: Pose? = null
        @JvmField var received = 0L
        @JvmField var progress = 0f
        fun receive(value: String?, now: Long) {
            if (raw == value) return
            val previous = pose
            raw = value; pose = parse(value); received = now
            val current = pose
            if (current != null && (previous == null || previous.action != current.action || previous.cart != current.cart)) progress = current.progress
            if (current != null && current.recovering()) progress = Math.min(progress, current.cancelled)
        }
        fun fresh(now: Long): Boolean = pose != null && now - received <= CartMotionSync.STALE_NANOS
        fun progress(seconds: Float): Float {
            progress += (pose!!.progress - progress) * (1 - Math.exp(-Math.max(0.0, Math.min(.1, seconds.toDouble())) / .06)).toFloat()
            return progress
        }
    }
    @JvmStatic @Synchronized fun generation(): Long = ++generation
    @JvmStatic fun publish(player: IsoPlayer?, item: InventoryItem?, action: Long, pickup: Boolean, recovering: Boolean,
        progress: Float, cancelled: Float, placement: CartTransitionMath.Placement?) {
        if (!Main.CART_SYNC_SUPPORTED || !CartMotionSync.connected() || !player!!.isLocalPlayer() || placement == null) return
        val pose = Pose(item!!.getID(), action, 1, (if (pickup) 1 else 0) or (if (recovering) 2 else 0), progress, cancelled,
            placement.x, placement.y, placement.z, placement.xRotation, placement.zRotation, placement.yRotation, placement.worldScale)
        if (!pose.valid() || !pose.nearby(player.getX(), player.getY(), player.getZ())) { end(player); return }
        val sender = senders.computeIfAbsent(player) { Sender() }; val now = System.nanoTime()
        if (sender.due(pose, item, now)) player.setVariable(KEY, sender.next(pose, item, now))
    }
    @JvmStatic fun end(player: IsoPlayer?) {
        if (senders.remove(player) != null && Main.CART_SYNC_SUPPORTED && CartMotionSync.connected() && player!!.isLocalPlayer()) player.setVariable(KEY, "")
    }
    @JvmStatic fun forget(player: IsoPlayer?) { remotes.remove(player) }
    @JvmStatic fun clearAll() { senders.clear(); remotes.clear() }
    @JvmStatic fun update(player: IsoPlayer?): Boolean {
        if (!Main.CART_SYNC_SUPPORTED || !Main.CART_TRANSITION_SUPPORTED || !CartMotionSync.connected() || player!!.isLocalPlayer()) return false
        val remote = remotes.computeIfAbsent(player) { Remote() }; val now = System.nanoTime()
        remote.receive(player.getVariableString(KEY), now)
        if (remote.fresh(now) && remote.pose!!.nearby(player.getX(), player.getY(), player.getZ())
            && CartTransition.remote(player, remote.pose, remote.progress(GameTime.getInstance().getRealworldSecondsSinceLastUpdate()))) return true
        CartTransition.endRemote(player)
        return false
    }
}
