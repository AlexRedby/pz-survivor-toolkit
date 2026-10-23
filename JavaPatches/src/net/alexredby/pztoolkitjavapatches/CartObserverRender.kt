package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import me.zed_0xff.zombie_buddy.Accessor
import zombie.GameTime
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelCamera
import zombie.core.skinnedmodel.ModelCameraRenderData
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.inventory.InventoryItem
import zombie.network.GameClient

/** Keep the remote wooden cart's camera and model snapshots on one validated cosmetic pose. */
internal object CartObserverRender {
    private class Visual {
        val pose = CartObserverPose.State()
        var item: InventoryItem? = null
        var itemId = 0; var z = 0
        var connection: Any? = null
        fun bind(next: InventoryItem?, floor: Int, peer: Any?) {
            if (item !== next || itemId != next!!.getID() || z != floor || connection !== peer) pose.clear()
            item = next; itemId = next!!.getID(); z = floor; connection = peer
        }
    }
    private val visuals = WeakHashMap<IsoPlayer?, Visual>()
    // Only the producer uses pending. initRenderData may run in TextureDraw's slot-init executor.
    private val pending = ThreadLocal<DrawPose>()
    private val slots = WeakHashMap<ModelSlotRenderData?, DrawPose>()
    private var disabled = false

    @JvmRecord data class DrawPose(val source: ModelManager.ModelSlot?, val player: IsoPlayer?, val nativeX: Float, val nativeY: Float,
        val nativeZ: Float, val x: Float, val y: Float, val z: Float, val angle: Float) {
        override fun toString(): String = "DrawPose[source=$source, player=$player, nativeX=$nativeX, nativeY=$nativeY, nativeZ=$nativeZ, x=$x, y=$y, z=$z, angle=$angle]"
    }
    /** Exact two-argument camera init exit, on the producer before drawModel/initModel. */
    @JvmStatic @Synchronized fun capture(data: ModelCameraRenderData?, camera: ModelCamera?, source: ModelManager.ModelSlot?) {
        pending.remove()
        if (disabled || source == null) return
        val player = source.character as? IsoPlayer ?: return
        try {
            if (player.isLocalPlayer() || !CartMotionSync.connected() || !CartMotionSync.visualEnabled(player)
                || !CartSteeringHooks.supportedCart(player) || !CartTransition.wheelbarrow(player.getPrimaryHandItem())
                || source.model == null || source.model.`object` !== player || player.getCell() == null
                || player.getCurrentSquare() == null || player.isSittingOnFurniture()) { forget(player); return }
            val x = Accessor.tryGet(data, "x", Float.NaN); val y = Accessor.tryGet(data, "y", Float.NaN)
            val z = Accessor.tryGet(data, "z", Float.NaN); val angle = Accessor.tryGet(data, "angle", Float.NaN)
            if (!x.isFinite() || !y.isFinite() || !z.isFinite() || !angle.isFinite()
                || player.getCell().getGridSquare(Math.floor(x.toDouble()).toInt(), Math.floor(y.toDouble()).toInt(), Math.floor(z.toDouble()).toInt()) == null) { forget(player); return }
            val state = visuals.computeIfAbsent(player) { Visual() }
            state.bind(player.getPrimaryHandItem(), Math.floor(z.toDouble()).toInt(), GameClient.connection)
            val front = if (player.isRunning() || player.isSprinting() || CartMotionSync.fastWeight(player) > 1e-3f || CartLegPace.woodenFastShift(player) < 0)
                CartWheelbarrow.forItem(player.getPrimaryHandItem())!!.fastFront() else CartWheelbarrow.forItem(player.getPrimaryHandItem())!!.front()
            val accepted = state.pose.update(CartFootprint.world(player), x.toDouble(), y.toDouble(), angle - Math.PI / 2, front,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()) ?: return
            queue(data, camera, DrawPose(source, player, x, y, z, accepted.x.toFloat(), accepted.y.toFloat(), z, (accepted.heading + Math.PI / 2).toFloat()))
        } catch (error: RuntimeException) {
            disabled = true; clearAll()
            System.err.println("[PZToolkitJavaPatches] Remote cart visual clearance disabled: $error")
        }
    }
    @JvmStatic fun queue(data: ModelCameraRenderData?, camera: ModelCamera?, pose: DrawPose?) {
        data!!.init(camera, pose!!.angle, true, pose.x, pose.y, pose.z, false)
        pending.set(pose)
    }
    /** Bind on the producer before native init calculates depth or hands data to its worker. */
    @JvmStatic @Synchronized fun bind(slot: ModelSlotRenderData?, source: ModelManager.ModelSlot?) {
        slots.remove(slot)
        val pose = pending.get(); pending.remove()
        if (pose == null || pose.source !== source || slot!!.character !== pose.player || slot.`object` !== pose.player) return
        slots[slot] = pose
        slot.x = pose.x; slot.y = pose.y; slot.z = pose.z
    }
    /** Native init overwrites angle after initModel; restore before grounding, grip and wheel snapshots. */
    @JvmStatic @Synchronized fun prepare(slot: ModelSlotRenderData?) {
        val pose = slots[slot]
        if (pose != null) slot!!.animPlayerAngle = pose.angle
    }
    @JvmStatic @Synchronized fun release(slot: ModelSlotRenderData?) { slots.remove(slot) }
    @JvmStatic @Synchronized fun forget(player: IsoPlayer?) {
        val visual = visuals.remove(player)
        visual?.pose?.clear()
        // Queued camera/slot snapshots retain their matching pose until postRender.
    }
    @JvmStatic @Synchronized fun clearAll() {
        for (visual in visuals.values) visual.pose.clear()
        visuals.clear()
    }
}
