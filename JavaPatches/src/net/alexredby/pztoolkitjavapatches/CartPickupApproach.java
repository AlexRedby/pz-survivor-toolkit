package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import zombie.GameTime;
import zombie.pathfind.PathFindBehavior2.BehaviorResult;
import org.joml.Vector3f;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.inventory.InventoryItem;
import zombie.pathfind.PathFindBehavior2;

/** Finish the native approach at the wooden handles without residual walking translation. */
public final class CartPickupApproach {
    private record Progress(float distance,int stalled) {}
    private static final WeakHashMap<LuaTimedActionNew,Progress> progress=new WeakHashMap<>();
    private static LuaTimedActionNew action(IsoGameCharacter actor) {
        if(!(actor instanceof IsoPlayer player) || !player.isLocalPlayer() || player.isDead()
            || player.isAiming() || player.hasHitReaction() || player.isKnockedDown() || player.isGettingUp()
            || player.getVehicle()!=null || player.isGrappling() || player.isBeingGrappled() || player.isRagdollSimulationActive())return null;
        var actions=player.getCharacterActions();
        if(actions.size()!=1 || !(actions.get(0) instanceof LuaTimedActionNew action)
            || action.chr!=player || action.forceStop || action.forceComplete || action.finished()
            || action.getTable()==null || action.getTable().rawget("character")!=player)return null;
        return action;
    }

    private static Vector3f location(LuaTimedActionNew action,PathFindBehavior2 path) {
        if(action==null || path==null || !path.isGoalLocation() || !"ISWalkToTimedActionF".equals(action.getMetaType()))return null;
        var table=action.getTable();
        if(!(table.rawget("toolkitWoodCartItem") instanceof InventoryItem item) || !CartTransition.supported(item)
            || item.getWorldItem()==null || item.getWorldItem().getItem()!=item || item.getWorldItem().getSquare()==null
            || !(table.rawget("location") instanceof Vector3f location) || !location.isFinite()
            || location.x!=path.getTargetX() || location.y!=path.getTargetY() || location.z!=path.getTargetZ())return null;
        return location;
    }

    /** Finish a small idle torso-only turn after the exact pickup walk has arrived. */
    public static boolean face(IsoPlayer player,zombie.iso.objects.IsoWorldInventoryObject world,
        float x,float y,float renderedAngle) {
        var action=action(player);
        if(action==null || action.isStarted() || !"ToolkitWoodCartPickup".equals(action.getMetaType())
            || world==null || world.getSquare()==null || world.getItem()==null
            || world.getItem().getWorldItem()!=world || !CartTransition.supported(world.getItem())
            || !(action.getTable().rawget("itemId") instanceof Number id) || id.doubleValue()!=world.getItem().getID()
            || !Float.isFinite(x+y+renderedAngle) || Math.hypot(player.getX()-x,player.getY()-y)>.002
            || Math.abs(player.getZ()-world.getSquare().getZ())>.002
            || player.isTurning() || player.shouldBeTurning()) return false;
        var animation=player.getAnimationPlayer();
        if(animation==null) return false;
        float difference=(float)CartSteeringMath.wrap(renderedAngle-animation.getRenderedAngle());
        if(!Float.isFinite(difference)) return false;
        if(Math.abs(difference)<Math.toRadians(1)) return true;
        // Larger turns belong to native turning clips. Idle can accept a small
        // facing change as twist while leaving its body angle permanently behind.
        // Native shouldBeTurning also accepts up to one degree of excess twist.
        if(Math.abs(difference)>animation.getMaxTwistAngle()+Math.toRadians(1)) return false;
        float multiplier=GameTime.getInstance().getMultiplier();
        if(!Float.isFinite(multiplier) || multiplier<=0) return false;
        float step=Math.min(Math.abs(difference),Math.min(.03f,.015f*multiplier));
        float heading=animation.getRenderedAngle()+(float)Math.copySign(step,difference)-(float)Math.PI/2;
        player.setTargetAndCurrentDirection((float)Math.cos(heading),(float)Math.sin(heading));
        // Retain the full native facing request while the bounded body completion advances.
        heading=renderedAngle-(float)Math.PI/2;
        player.setForwardDirection((float)Math.cos(heading),(float)Math.sin(heading));
        return Math.abs(CartSteeringMath.wrap(renderedAngle-animation.getRenderedAngle()))<Math.toRadians(1);
    }

    public static boolean suppressDeferred(IsoGameCharacter actor) {
        var action=action(actor);
        return action!=null && "ToolkitWoodCartPickup".equals(action.getMetaType());
    }

    public static BehaviorResult result(IsoGameCharacter actor,PathFindBehavior2 path,BehaviorResult result) {
        var action=action(actor);
        if(action==null || actor.getPathFindBehavior2()!=path)return result;
        var target=location(action,path);
        if(target==null || result!=BehaviorResult.Succeeded)return result;
        float dx=target.x-actor.getX(),dy=target.y-actor.getY(),distance=(float)Math.hypot(dx,dy);
        if(distance<=.002f) {progress.remove(action);return result;}
        if(!Float.isFinite(distance) || distance>.06f) {progress.remove(action);return BehaviorResult.Failed;}
        var previous=progress.get(action);
        int stalled=previous==null || distance<previous.distance-.001f?0:previous.stalled+1;
        // Count attempted updates rather than wall time so pausing cannot fail the approach.
        if(stalled>=45) {progress.remove(action);return BehaviorResult.Failed;}
        progress.put(action,new Progress(stalled==0?distance:previous.distance,stalled));
        // Native arrival accepts .05 tiles; let normal collision resolve each remaining step before success.
        float step=Math.min(distance,Math.min(.02f,.005f*GameTime.getInstance().getMultiplier()));
        actor.moveUnmodded(dx*step/distance,dy*step/distance);
        return BehaviorResult.Working;
    }

    private CartPickupApproach() {}
}
