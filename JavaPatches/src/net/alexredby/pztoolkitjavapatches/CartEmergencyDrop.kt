package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import me.zed_0xff.zombie_buddy.Accessor
import org.joml.Matrix4f
import org.joml.Vector3f
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.model.ItemModelRenderer
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.inventory.InventoryItem
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.GameClient
import zombie.network.GameServer

/** A short SP presentation handoff. Native InstantDrop owns every inventory/world change. */
internal object CartEmergencyDrop {
    const val FRESH_NANOS = 250_000_000L
    const val SETTLE_NANOS = 240_000_000L
    private class Held(val item: InventoryItem, val cart: Matrix4f, val x: Float, val y: Float, val z: Float, val angle: Float, val time: Long)
    private class Release(val player: IsoPlayer, val source: CartTransitionMath.Placement, val landing: CartTransitionMath.Placement, val model: Matrix4f, now: Long) {
        val prepared = now
        var world: IsoWorldInventoryObject? = null
        var started = 0L
    }
    private class Restore(val matrix: Matrix4f, val original: Matrix4f, val angle: Vector3f)
    private val held = WeakHashMap<IsoPlayer?, Held>()
    private val releases = HashMap<InventoryItem?, Release>()
    private val modified = WeakHashMap<ItemModelRenderer?, Restore>()

    @JvmStatic @Synchronized fun capture(player: IsoPlayer?, slot: ModelSlotRenderData?, cart: Matrix4f?) {
        if (!Main.CART_TRANSITION_SUPPORTED || GameClient.client || GameServer.server || !player!!.isLocalPlayer()) return
        val item = player.getPrimaryHandItem()
        if (!CartTransition.wheelbarrow(item) || player.getSecondaryHandItem() !== item || item.getWorldItem() != null || cart == null || !cart.isFinite) {
            held.remove(player); return
        }
        held[player] = Held(item, Matrix4f(cart), slot!!.x, slot.y, slot.z, slot.animPlayerAngle, System.nanoTime())
    }
    @JvmStatic fun fresh(now: Long, time: Long, x: Float, y: Float, z: Float, currentX: Float, currentY: Float, currentZ: Float): Boolean =
        now >= time && now - time <= FRESH_NANOS && java.lang.Float.isFinite(x + y + z + currentX + currentY + currentZ) && z == currentZ &&
            Math.hypot((x - currentX).toDouble(), (y - currentY).toDouble()) <= .5

    @LuaMethod(name = "toolkitWoodCartImpactPose", global = true)
    @JvmStatic @Synchronized fun prepare(player: IsoPlayer?, item: InventoryItem?): KahluaTable? {
        if (item != null) releases.remove(item)
        if (!Main.CART_TRANSITION_SUPPORTED || GameClient.client || GameServer.server || player == null
            || !player.isLocalPlayer() || !CartTransition.wheelbarrow(item) || player.getPrimaryHandItem() !== item
            || player.getSecondaryHandItem() !== item || item!!.getContainer() !== player.getInventory() || item.getWorldItem() != null) return null
        val source = held.remove(player); val now = System.nanoTime()
        if (source == null || source.item !== item || !fresh(now, source.time, source.x, source.y, source.z, player.getX(), player.getY(), player.getZ())) return null
        val model = CartTransition.model(item) ?: return null
        val pose = CartTransitionMath.actorToWorldPlacement(source.cart, model, source.x, source.y, source.z, source.angle)
        // Emergency release omits the normal set-down action's backward stance adjustment.
        val landing = CartTransition.dropPlacement(source.cart, model, source.x, source.y, source.z, source.angle, item.worldScale, 0f, CartWheelbarrow.forItem(item))
        if (pose == null || landing == null || Math.hypot((landing.x - player.getX()).toDouble(), (landing.y - player.getY()).toDouble()) > 1.5
            || CartTransition.target(player, landing.x, landing.y, source.z) == null) return null
        releases[item] = Release(player, pose, landing, model, now)
        return LuaManager.platform.newTable().apply {
            rawset("x", landing.x.toDouble()); rawset("y", landing.y.toDouble()); rawset("z", source.z.toDouble()); rawset("rotation", landing.zRotation.toDouble())
        }
    }
    @LuaMethod(name = "toolkitWoodCartImpactFinish", global = true)
    @JvmStatic @Synchronized fun finish(player: IsoPlayer?, item: InventoryItem?) {
        val release = releases[item] ?: return
        if (release.world != null) return
        val world = item!!.getWorldItem()
        if (GameClient.client || GameServer.server || player == null || release.player !== player || player.getPrimaryHandItem() === item
            || player.getSecondaryHandItem() === item || !worldContainer(item) || world == null || world.getSquare() == null || world.getItem() !== item
            || Math.hypot((world.getWorldPosX() - release.landing.x).toDouble(), (world.getWorldPosY() - release.landing.y).toDouble()) > .03
            || Math.abs(world.getWorldPosZ() + .00175f - release.landing.z) > .001) { releases.remove(item); return }
        val now = System.nanoTime()
        if (now < release.prepared || now - release.prepared > FRESH_NANOS) { releases.remove(item); return }
        release.world = world; release.started = now
        CartImpactMotion.begin(player, item, world)
        world.invalidateRenderChunkLevel(256)
    }
    private fun worldContainer(item: InventoryItem): Boolean {
        // Native loot UI projects the same world item into its per-player floor container.
        val container = item.getContainer()
        return container == null || "floor" == container.getType()
    }
    private fun owned(item: InventoryItem?, release: Release): Boolean =
        release.world != null && release.world!!.getSquare() != null && item!!.getWorldItem() === release.world && release.world!!.getItem() === item && worldContainer(item)

    @LuaMethod(name = "toolkitWoodCartImpactTick", global = true)
    @JvmStatic @Synchronized fun tick() {
        CartImpactMotion.tick(); val now = System.nanoTime()
        held.entries.removeIf { now - it.value.time > FRESH_NANOS }
        val entries = releases.entries.iterator()
        while (entries.hasNext()) {
            val entry = entries.next(); val item = entry.key; val release = entry.value
            if (release.world == null) { if (now - release.prepared > FRESH_NANOS) entries.remove(); continue }
            val valid = owned(item, release)
            if (!valid || now - release.started >= SETTLE_NANOS || GameClient.client || GameServer.server) entries.remove()
            // Invalidate again at the endpoint, including removal/pickup, so no intermediate FBO remains cached.
            if (release.world!!.getSquare() != null) release.world!!.invalidateRenderChunkLevel(256)
        }
    }
    @JvmStatic fun settle(source: Matrix4f?, ground: Matrix4f?, fraction: Double, out: Matrix4f?): Boolean = settle(source, ground, fraction, out, CartWheelbarrow.WOOD)
    @JvmStatic fun settle(source: Matrix4f?, ground: Matrix4f?, fraction: Double, out: Matrix4f?, profile: CartWheelbarrow?): Boolean {
        if (!java.lang.Double.isFinite(fraction)) return false
        val blend = CartTransitionMath.smooth(fraction)
        if (!CartTransitionMath.blend(source, ground, blend, out)) return false
        if (fraction <= 0 || fraction >= 1) return true
        val axle = profile!!.center(Vector3f())
        val start = source!!.transformPosition(axle, Vector3f()); val end = ground!!.transformPosition(axle, Vector3f()); val current = out!!.transformPosition(axle, Vector3f())
        // A rigid rotation's interpolated translation otherwise sweeps the wheel through a small arc.
        out.m30(out.m30() + start.x + (end.x - start.x) * blend.toFloat() - current.x)
        out.m32(out.m32() + start.z + (end.z - start.z) * blend.toFloat() - current.z)
        val low = CartGrounding.wheelbarrowLowest(source, profile) + (CartGrounding.wheelbarrowLowest(ground, profile) - CartGrounding.wheelbarrowLowest(source, profile)) * blend.toFloat()
        out.m31(out.m31() + low - CartGrounding.wheelbarrowLowest(out, profile))
        return out.isFinite
    }
    @JvmStatic @Synchronized fun reset() {
        for (renderer in ArrayList(modified.keys)) clear(renderer)
        held.clear(); releases.clear(); CartImpactMotion.reset()
    }
    @JvmStatic @Synchronized fun clear(renderer: ItemModelRenderer?) {
        val previous = modified.remove(renderer)
        if (previous != null && Accessor.tryGet(renderer, "transform", null as Matrix4f?) === previous.matrix) {
            previous.matrix.set(previous.original); renderer!!.angle.set(previous.angle)
        }
    }
    @JvmStatic @Synchronized fun render(renderer: ItemModelRenderer?, item: InventoryItem?) {
        clear(renderer)
        val release = releases[item] ?: return
        if (!owned(item, release) || GameClient.client || GameServer.server) return
        val elapsed = System.nanoTime() - release.started
        if (elapsed < 0 || elapsed >= SETTLE_NANOS) return
        val transform = Accessor.tryGet(renderer, "transform", null as Matrix4f?)
        if (transform == null || !transform.isFinite) return
        val source = Matrix4f()
        if (!CartTransitionMath.worldToActor(release.source, release.model, renderer!!.x, renderer.y, renderer.z, Math.PI.toFloat(), source)) return
        val ground = CartWheelWorld.worldTransform(renderer, transform, Matrix4f()); val output = Matrix4f()
        if (!settle(source, ground, elapsed.toDouble() / SETTLE_NANOS, output, CartWheelbarrow.forItem(item))) return
        modified[renderer] = Restore(transform, Matrix4f(transform), Vector3f(renderer.angle))
        transform.set(output); renderer.angle.set(0f, 0f, 0f)
    }
}
