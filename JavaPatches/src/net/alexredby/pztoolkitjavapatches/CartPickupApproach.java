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
        if(!(table.rawget("toolkitWoodCartItem") instanceof InventoryItem item) || !CartTransition.wooden(item)
            || item.getWorldItem()==null || item.getWorldItem().getItem()!=item || item.getWorldItem().getSquare()==null
            || !(table.rawget("location") instanceof Vector3f location) || !location.isFinite()
            || location.x!=path.getTargetX() || location.y!=path.getTargetY() || location.z!=path.getTargetZ())return null;
        return location;
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
