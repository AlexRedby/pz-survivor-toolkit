package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import org.joml.Vector3f
import zombie.GameTime
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.pathfind.PathFindBehavior2
import zombie.pathfind.PathFindBehavior2.BehaviorResult

/** Finish the native approach at the wooden handles without residual walking translation. */
internal object CartPickupApproach {
    private data class Progress(val distance: Float, val stalled: Int)

    private val progress = WeakHashMap<LuaTimedActionNew, Progress>()

    private fun action(actor: IsoGameCharacter?): LuaTimedActionNew? {
        val player = actor as? IsoPlayer ?: return null
        if (
            !player.isLocalPlayer() ||
                player.isDead() ||
                player.isAiming() ||
                player.hasHitReaction() ||
                player.isKnockedDown() ||
                player.isGettingUp() ||
                player.getVehicle() != null ||
                player.isGrappling() ||
                player.isBeingGrappled() ||
                player.isRagdollSimulationActive()
        )
            return null
        val actions = player.getCharacterActions()
        if (actions.size != 1) return null
        val action = actions[0] as? LuaTimedActionNew ?: return null
        if (
            action.chr !== player ||
                action.forceStop ||
                action.forceComplete ||
                action.finished() ||
                action.getTable() == null ||
                action.getTable().rawget("character") !== player
        )
            return null
        return action
    }

    private fun location(action: LuaTimedActionNew?, path: PathFindBehavior2?): Vector3f? {
        if (
            action == null ||
                path == null ||
                !path.isGoalLocation() ||
                "ISWalkToTimedActionF" != action.getMetaType()
        )
            return null
        val table = action.getTable()
        val item = table.rawget("toolkitWoodCartItem") as? InventoryItem ?: return null
        if (
            !CartTransition.supported(item) ||
                item.getWorldItem() == null ||
                item.getWorldItem().getItem() !== item ||
                item.getWorldItem().getSquare() == null
        )
            return null
        val location = table.rawget("location") as? Vector3f ?: return null
        if (
            !location.isFinite ||
                location.x != path.getTargetX() ||
                location.y != path.getTargetY() ||
                location.z != path.getTargetZ()
        )
            return null
        return location
    }

    /** Finish a small idle torso-only turn after the exact pickup walk has arrived. */
    @JvmStatic
    fun face(
        player: IsoPlayer?,
        world: IsoWorldInventoryObject?,
        x: Float,
        y: Float,
        renderedAngle: Float,
    ): Boolean {
        val action = action(player) ?: return false
        if (
            action.isStarted() ||
                "ToolkitWoodCartPickup" != action.getMetaType() ||
                world == null ||
                world.getSquare() == null ||
                world.getItem() == null ||
                world.getItem().getWorldItem() !== world ||
                !CartTransition.supported(world.getItem())
        )
            return false
        val id = action.getTable().rawget("itemId") as? Number ?: return false
        if (
            id.toDouble() != world.getItem().getID().toDouble() ||
                !java.lang.Float.isFinite(x + y + renderedAngle) ||
                Math.hypot((player!!.getX() - x).toDouble(), (player.getY() - y).toDouble()) >
                    .002 ||
                Math.abs(player.getZ() - world.getSquare().getZ()) > .002 ||
                player.isTurning() ||
                player.shouldBeTurning()
        )
            return false
        val animation = player.getAnimationPlayer() ?: return false
        val difference =
            CartSteeringMath.wrap((renderedAngle - animation.getRenderedAngle()).toDouble())
                .toFloat()
        if (!java.lang.Float.isFinite(difference)) return false
        if (Math.abs(difference) < Math.toRadians(1.0)) return true
        // Larger turns belong to native turning clips. Idle can accept small facing changes
        // as twist while leaving its body angle behind; native permits one degree of excess twist.
        if (Math.abs(difference) > animation.getMaxTwistAngle() + Math.toRadians(1.0)) return false
        val multiplier = GameTime.getInstance().getMultiplier()
        if (!java.lang.Float.isFinite(multiplier) || multiplier <= 0) return false
        val step = Math.min(Math.abs(difference), Math.min(.03f, .015f * multiplier))
        var heading =
            animation.getRenderedAngle() + Math.copySign(step, difference) - Math.PI.toFloat() / 2
        player.setTargetAndCurrentDirection(
            Math.cos(heading.toDouble()).toFloat(),
            Math.sin(heading.toDouble()).toFloat(),
        )
        // Retain the full native facing request while bounded body completion advances.
        heading = renderedAngle - Math.PI.toFloat() / 2
        player.setForwardDirection(
            Math.cos(heading.toDouble()).toFloat(),
            Math.sin(heading.toDouble()).toFloat(),
        )
        return Math.abs(
            CartSteeringMath.wrap((renderedAngle - animation.getRenderedAngle()).toDouble()),
        ) < Math.toRadians(1.0)
    }

    @JvmStatic
    fun suppressDeferred(actor: IsoGameCharacter?): Boolean {
        val action = action(actor)
        return action != null && "ToolkitWoodCartPickup" == action.getMetaType()
    }

    @JvmStatic
    fun result(
        actor: IsoGameCharacter?,
        path: PathFindBehavior2?,
        result: BehaviorResult?,
    ): BehaviorResult? {
        val action = action(actor)
        if (action == null || actor!!.getPathFindBehavior2() !== path) return result
        val target = location(action, path)
        if (target == null || result != BehaviorResult.Succeeded) return result
        val dx = target.x - actor.getX()
        val dy = target.y - actor.getY()
        val distance = Math.hypot(dx.toDouble(), dy.toDouble()).toFloat()
        if (distance <= .002f) {
            progress.remove(action)
            return result
        }
        if (!java.lang.Float.isFinite(distance) || distance > .06f) {
            progress.remove(action)
            return BehaviorResult.Failed
        }
        val previous = progress[action]
        val stalled =
            if (previous == null || distance < previous.distance - .001f) 0
            else previous.stalled + 1
        // Count attempted updates rather than wall time so pausing cannot fail the approach.
        if (stalled >= 45) {
            progress.remove(action)
            return BehaviorResult.Failed
        }
        progress[action] = Progress(if (stalled == 0) distance else previous!!.distance, stalled)
        // Native arrival accepts .05 tiles; let normal collision resolve each remaining step before
        // success.
        val step =
            Math.min(distance, Math.min(.02f, .005f * GameTime.getInstance().getMultiplier()))
        actor.moveUnmodded(dx * step / distance, dy * step / distance)
        return BehaviorResult.Working
    }
}
