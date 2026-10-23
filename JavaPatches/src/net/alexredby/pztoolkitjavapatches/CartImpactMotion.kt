package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import zombie.ai.states.CollideWithWallState
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.iso.Vector2
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.GameClient
import zombie.network.GameServer

/** The released cart stops only inward native root motion during this SP wall-impact episode. */
internal object CartImpactMotion {
    const val MAX_NANOS = 4_000_000_000L
    @JvmRecord private data class Contact(val item: InventoryItem, val world: IsoWorldInventoryObject, val x: Float, val y: Float, val z: Float,
        val worldX: Float, val worldY: Float, val worldZ: Float, val rotation: Float, val nx: Double, val ny: Double, val started: Long) {
        override fun toString(): String = "Contact[item=$item, world=$world, x=$x, y=$y, z=$z, worldX=$worldX, worldY=$worldY, worldZ=$worldZ, rotation=$rotation, nx=$nx, ny=$ny, started=$started]"
    }
    private val contacts = WeakHashMap<IsoPlayer?, Contact>()
    private val result = ThreadLocal.withInitial(::Vector2)

    private fun actor(player: IsoPlayer?): Boolean =
        Main.CART_SUPPORTED && Main.CART_TRANSITION_SUPPORTED && !GameClient.client && !GameServer.server
            && player != null && player.isLocalPlayer() && !player.isNpc() && !player.isDead()
            && player.isCurrentState(CollideWithWallState.instance()) && !player.isGettingUp()
            && !player.isGrappling() && !player.isBeingGrappled() && !player.isRagdollSimulationActive() && player.getVehicle() == null

    @JvmStatic @Synchronized fun begin(player: IsoPlayer?, item: InventoryItem?, world: IsoWorldInventoryObject?) {
        contacts.remove(player)
        if (!actor(player) || !CartTransition.wheelbarrow(item) || world == null || world.getSquare() == null
            || item!!.getWorldItem() !== world || world.getItem() !== item || player!!.getPrimaryHandItem() != null || player.getSecondaryHandItem() != null) return
        val x = player.getNextX(); val y = player.getNextY(); val z = player.getZ()
        val dx = (world.getWorldPosX() - player.getX()).toDouble(); val dy = (world.getWorldPosY() - player.getY()).toDouble(); val distance = Math.hypot(dx, dy)
        if (!java.lang.Float.isFinite(x + y + z) || !java.lang.Double.isFinite(distance) || distance < .15 || distance > 1.5
            || Math.hypot((x - player.getX()).toDouble(), (y - player.getY()).toDouble()) > .5) return
        // Include already requested movement; never undo a step or teleport the actor backwards.
        contacts[player] = Contact(item, world, x, y, z, world.getWorldPosX(), world.getWorldPosY(), world.getWorldPosZ(), item.getWorldZRotation(), dx / distance, dy / distance, System.nanoTime())
    }
    private fun valid(player: IsoPlayer, contact: Contact, now: Long): Boolean {
        val container = contact.item.getContainer(); val slow = player.getSlowFactor()
        return actor(player) && java.lang.Float.isFinite(slow) && slow >= 0 && slow <= 1 && now >= contact.started && now - contact.started < MAX_NANOS
            && player.getPrimaryHandItem() == null && player.getSecondaryHandItem() == null
            && player.getZ() == contact.z && Math.hypot((player.getX() - contact.x).toDouble(), (player.getY() - contact.y).toDouble()) < 2
            && contact.item.getWorldItem() === contact.world && contact.world.getItem() === contact.item
            && contact.world.getSquare() != null && (container == null || "floor" == container.getType())
            && Math.abs(contact.world.getWorldPosX() - contact.worldX) < .001
            && Math.abs(contact.world.getWorldPosY() - contact.worldY) < .001
            && Math.abs(contact.world.getWorldPosZ() - contact.worldZ) < .001 && contact.item.getWorldZRotation() == contact.rotation
    }
    @JvmStatic fun clip(x: Float, y: Float, nextX: Double, nextY: Double, originX: Double, originY: Double, nx: Double, ny: Double, out: Vector2): Vector2 {
        out.set(x, y)
        if (!java.lang.Double.isFinite(x + y + nextX + nextY + originX + originY + nx + ny)) return out
        val inward = x * nx + y * ny; val available = Math.max(0.0, (originX - nextX) * nx + (originY - nextY) * ny)
        if (inward > available) out.set((x - (inward - available) * nx).toFloat(), (y - (inward - available) * ny).toFloat())
        return out
    }
    @JvmStatic @Synchronized fun movement(player: IsoPlayer?, x: Float, y: Float): Vector2 {
        val out = result.get().set(x, y); val contact = contacts[player] ?: return out
        if (!valid(player!!, contact, System.nanoTime())) { contacts.remove(player); return out }
        return clip(x, y, player.getNextX().toDouble(), player.getNextY().toDouble(), contact.x.toDouble(), contact.y.toDouble(), contact.nx, contact.ny, out)
    }
    // Producer-only snapshot; render workers must not inspect mutable player or world state.
    @JvmStatic @Synchronized fun poseAgeNanos(player: IsoPlayer?): Long {
        val contact = contacts[player]; val now = System.nanoTime()
        return if (contact != null && CartTransition.wooden(contact.item) && valid(player!!, contact, now)) now - contact.started else -1
    }
    @JvmStatic @Synchronized fun tick() {
        val now = System.nanoTime()
        contacts.entries.removeIf { !valid(it.key!!, it.value, now) }
    }
    @JvmStatic @Synchronized fun reset() { contacts.clear() }
}
