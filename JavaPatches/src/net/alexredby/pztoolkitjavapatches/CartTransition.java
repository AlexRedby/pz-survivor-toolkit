package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import java.lang.reflect.Field;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ai.states.CollideWithWallState;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.inventory.InventoryItem;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.scripting.ScriptManager;

/** Presentation only: inventory/world ownership remains with the native timed action. */
public final class CartTransition {
    private static final WeakHashMap<IsoPlayer, State> states = new WeakHashMap<>();
    // Native queue/render cleanup can run before the replacement action's first update.
    private static final WeakHashMap<IsoPlayer, State> cancelled = new WeakHashMap<>();
    private static final Field CLIP_RETIRING = clipRetiringField();
    private static final double RESTART_BLEND_NANOS = 350_000_000.0;
    // Start behind the handle ends rather than clearing the shafts with a large pelvis-only retreat.
    private static final float STANCE_BACK = .06f;
    // The grounded metal cart must rise with a restarted setdown before the old
    // crouch releases; the previous low hand path is otherwise beyond arm reach.
    static float restartCartWeight(CartWheelbarrow profile,boolean pickup,float bodyWeight) {
        return profile==CartWheelbarrow.METAL && !pickup?bodyWeight*bodyWeight:bodyWeight;
    }

    private static final class State {
        InventoryItem item;
        long action;
        boolean remote, remoteWaiting;
        boolean pickup, ik, rendered, recovering, authored, clipRetired;
        float cancelledProgress, nativeHeight, referenceHeight, movementProgress, recoveryReach, recoveryGrip;
        Matrix4f[] recoveryPose;
        Matrix4f recoveryCart;
        boolean movingRecovery;
        Matrix4f[] lastPose, restartPose;
        CartTransitionMath.Placement lastPlacement, restartPlacement;
        float lastReach, lastGrip, restartReach, restartGrip;
        long lastRender, restartStart, pendingStart, remoteModelBindStart;
        Quaternionf nativeRotation, referenceRotation;
        long recoveryStart;
        String visualModel;
        float progress;
        long updated;
        IsoWorldInventoryObject world;
        IsoGridSquare cancelSquare;
        CartTransitionMath.Placement placement;
    }

    public static boolean wooden(InventoryItem item) {
        return item != null && "SaucedWheelbarrow.WheelbarrowWood".equals(item.getFullType());
    }

    public static boolean wheelbarrow(InventoryItem item) {
        return CartWheelbarrow.forItem(item)!=null;
    }

    public static boolean supported(InventoryItem item) {
        return wheelbarrow(item) || CartShopping.item(item);
    }

    static float worldScale(InventoryItem item) {return item.worldScale*(wheelbarrow(item)?.85f:1);}
    private static Matrix4f held(InventoryItem item,Matrix4f out) {
        var profile=CartWheelbarrow.forItem(item);
        return profile==null?CartShopping.held(out):profile.held(out);
    }
    private static String modelName(InventoryItem item) {
        var profile=CartWheelbarrow.forItem(item);
        var script=CartGrounding.resolvedModel(item);
        return profile!=null?profile.model():script==null?null:script.getName();
    }
    private static CartTransitionMath.Progress phase(State state) {
        return CartShopping.item(state.item)?CartShopping.progress(state.progress,!state.pickup)
            :CartTransitionMath.progress(state.progress,!state.pickup);
    }
    private static boolean blend(InventoryItem item,Matrix4f from,Matrix4f to,Matrix4f model,double weight,Matrix4f out) {
        return CartShopping.item(item)?CartTransitionMath.blendModel(from,to,model,weight,out)
            :CartTransitionMath.blend(from,to,weight,out);
    }

    static Matrix4f model(InventoryItem item) {
        var script = ScriptManager.instance.getModelScript(item.getWorldStaticModel());
        if (script == null) return null;
        var model = ModelManager.instance.tryGetLoadedModel(script, true);
        if (model == null || model.mesh == null || !model.mesh.isReady()) return null;
        var result = new Matrix4f();
        var attachment = script.getAttachmentById("world");
        if (attachment != null) ModelInstanceRenderData.makeAttachmentTransform(attachment,result).invert();
        ModelInstanceRenderData.postMultiplyMeshTransform(result,model.mesh);
        result.scale(script.scale);
        CartWorldSupport.apply(item.getFullType(),result,worldScale(item));
        return result;
    }

    static CartTransitionMath.Placement placement(InventoryItem item, IsoWorldInventoryObject world) {
        return new CartTransitionMath.Placement(world.getWorldPosX(),world.getWorldPosY(),world.getWorldPosZ()+.00175f,
            item.getWorldXRotation(),item.getWorldZRotation(),item.getWorldYRotation(),worldScale(item));
    }

    @LuaMethod(name="toolkitWoodCartStance", global=true)
    public static KahluaTable stance(IsoPlayer player, IsoWorldInventoryObject world) {
        if (!Main.CART_TRANSITION_SUPPORTED || world == null || !supported(world.getItem())) return null;
        var item=world.getItem();var model=model(item);
        var profile=CartWheelbarrow.forItem(item);var held=held(item,new Matrix4f());
        if(model==null) return null;
        var ground=new Matrix4f();
        var pose=placement(item,world);
        var left=new Vector3f();var right=new Vector3f();
        CartGrip.handle(modelName(item),true,left);CartGrip.handle(modelName(item),false,right);
        var target=CartTransitionMath.stance(pose,model,held,left,right);
        if(target==null) return null;
        if(!CartTransitionMath.worldToActor(pose,model,target.x(),target.y(),player.getZ(),target.slotAngle(),ground)) return null;
        var axle=profile==null?new Vector3f():profile.center(new Vector3f());
        var difference=profile==null?new Vector3f():ground.transformPosition(axle,new Vector3f()).sub(held.transformPosition(axle,new Vector3f()));
        if(profile!=null) difference.z+=profile.pickupStanceBack();
        float c=(float)Math.cos(target.slotAngle()),s=(float)Math.sin(target.slotAngle());
        float x=target.x()-1.5f*(c*difference.x+s*difference.z);
        float y=target.y()+1.5f*(-s*difference.x+c*difference.z);
        var result=LuaManager.platform.newTable();
        result.rawset("x",(double)x);result.rawset("y",(double)y);result.rawset("angle",(double)target.slotAngle());
        double heading=target.slotAngle()-Math.PI/2;
        result.rawset("faceX",player.getX()+Math.cos(heading));
        result.rawset("faceY",player.getY()+Math.sin(heading));
        var animation=player.getAnimationPlayer();
        result.rawset("aligned",animation!=null && !player.isTurning()
            && Math.abs(CartSteeringMath.wrap(animation.getRenderedAngle()-target.slotAngle()))<Math.toRadians(1));
        return result;
    }

    @LuaMethod(name="toolkitWoodCartFace", global=true)
    public static boolean face(IsoPlayer player,IsoWorldInventoryObject world) {
        if(player==null) return false;
        var target=stance(player,world);
        return target!=null && CartPickupApproach.face(player,world,((Number)target.rawget("x")).floatValue(),
            ((Number)target.rawget("y")).floatValue(),((Number)target.rawget("angle")).floatValue());
    }

    static boolean authoredClip(IsoPlayer player, boolean retirementSupported) {
        if(!player.containsVariable("ToolkitWoodCartClipPilot"))
            player.setVariable("ToolkitWoodCartClipPilot",retirementSupported && !GameClient.client && !GameServer.server);
        boolean selected=player.getVariableBoolean("ToolkitWoodCartClipPilot");
        if(selected && !retirementSupported)
            throw new IllegalStateException("Authored cart clips require native node retirement support");
        return selected;
    }

    @LuaMethod(name="toolkitWoodCartUpdate", global=true)
    public static synchronized boolean update(IsoPlayer player, InventoryItem item, boolean pickup, double progress) {
        if(!Main.CART_TRANSITION_SUPPORTED || player==null || !player.isLocalPlayer() || !supported(item)
            || !Double.isFinite(progress) || player.isDead()) return false;
        State state=states.get(player);
        if(state==null || state.recovering || state.item!=item || state.pickup!=pickup) {
            var previous=cancelled.remove(player);
            end(player);state=new State();state.item=item;state.pickup=pickup;
            state.action=CartActionSync.generation();
            state.authored=authoredClip(player,CLIP_RETIRING!=null);
            if(pickup) {
                state.world=item.getWorldItem();
                if(state.world==null) return false;
                state.placement=placement(item,state.world);
            }
            if(state.authored && previous!=null && previous.item==item && previous.pickup==pickup
                && previous.lastPose!=null && previous.lastPlacement!=null
                && System.nanoTime()-previous.lastRender<=200_000_000L
                && !pendingExpired(previous,System.nanoTime()) && !protectedState(player)
                && (pickup?previous.world==state.world && state.world.getItem()==item
                    && state.world.getSquare()!=null && state.world.getSquare()==previous.cancelSquare
                    && previous.placement.equals(state.placement)
                    && player.getPrimaryHandItem()==null && player.getSecondaryHandItem()==null
                    :item.getWorldItem()==null && item.getContainer()==player.getInventory()
                        && player.getPrimaryHandItem()==item && player.getSecondaryHandItem()==item)) {
                state.restartPose=previous.lastPose;state.restartPlacement=previous.lastPlacement;
                state.restartReach=previous.lastReach;state.restartGrip=previous.lastGrip;
                state.restartStart=System.nanoTime();
                state.rendered=previous.rendered;
            }
            states.put(player,state);
        }
        state.progress=(float)Math.max(0,Math.min(1,progress));state.updated=System.nanoTime();
        poseVariables(player,state);
        publish(player,state);
        return true;
    }

    private static void poseVariables(IsoPlayer player, State state) {
        var phase=phase(state);
        player.setVariable("ToolkitWoodCartPoseX",(float)(phase.lift()+.10*phase.crouch()*(1-phase.lift())));
        player.setVariable("ToolkitWoodCartPoseY",(float)phase.lift());
        if(state.authored) {
            player.setVariable("ToolkitWoodCartClipTime",state.progress);
            player.setVariable("ToolkitWoodCartClipPickup",state.pickup);
            player.setVariable("ToolkitMetalCartClip",CartWheelbarrow.forItem(state.item)==CartWheelbarrow.METAL);
            player.setVariable("ToolkitShoppingCartClip",CartShopping.item(state.item));
        }
    }

    private static Field clipRetiringField() {
        try {
            var field=LiveAnimNode.class.getDeclaredField("transitioningOut");
            field.setAccessible(true);return field;
        } catch(ReflectiveOperationException | RuntimeException unsupported) {return null;}
    }

    static boolean retireAuthoredNode(LiveAnimNode node, boolean pickup) {
        String direction=pickup?"Pickup":"Setdown",name=node.getSourceNode().name;
        if(!("ToolkitWoodCartClip"+direction).equals(name) && !("ToolkitMetalCartClip"+direction).equals(name) && !("ToolkitShoppingCartClip"+direction).equals(name)) return false;
        try {
            if(CLIP_RETIRING==null) throw new IllegalStateException("Native cart clip retirement unavailable");
            if(CLIP_RETIRING.getBoolean(node)) return false;
            // Native selection must create a new clock-bound node while this one fades at its final pose.
            CLIP_RETIRING.setBoolean(node,true);
            for(var track:node.getMainAnimationTracks()) {
                track.trackTimeToVariable=null;track.setSpeedDelta(0);
            }
            return true;
        } catch(IllegalAccessException unsupported) {throw new IllegalStateException(unsupported);}
    }

    private static void retireAuthoredLayer(AnimLayer layer, boolean pickup) {
        if(layer!=null) for(var node:layer.getLiveAnimNodes()) retireAuthoredNode(node,pickup);
    }

    private static void retireAuthored(IsoPlayer player, State state) {
        if(!state.authored || state.clipRetired) return;
        var animator=player.getAdvancedAnimator();
        if(animator!=null) {
            retireAuthoredLayer(animator.getRootLayer(),state.pickup);
            for(int i=0;i<animator.getSubLayerCount();i++) retireAuthoredLayer(animator.getSubLayerAt(i),state.pickup);
        }
        state.clipRetired=true;
    }

    private static boolean protectedState(IsoPlayer player) {
        return !player.isLocalPlayer() || unsafeState(player);
    }

    private static boolean unsafeState(IsoPlayer player) {
        return player.isDead() || player.isAiming() || player.hasHitReaction()
            || player.isKnockedDown() || player.isGettingUp() || player.getVehicle()!=null
            || player.isCurrentState(CollideWithWallState.instance())
            || player.isGrappling() || player.isBeingGrappled() || player.isRagdollSimulationActive();
    }

    private static void publish(IsoPlayer player,State state) {
        if(!state.remote) CartActionSync.publish(player,state.item,state.action,state.pickup,state.recovering,
            state.progress,state.cancelledProgress,state.placement);
    }

    private static InventoryItem remoteItem(IsoPlayer player,CartActionSync.Pose pose) {
        if(!pose.pickup()) {
            var item=player.getPrimaryHandItem();
            return supported(item) && item.getID()==pose.cart() && player.getSecondaryHandItem()==item
                && item.getContainer()==player.getInventory() && item.getWorldItem()==null?item:null;
        }
        if(player.getPrimaryHandItem()!=null || player.getSecondaryHandItem()!=null
            || IsoWorld.instance==null || IsoWorld.instance.currentCell==null) return null;
        var square=IsoWorld.instance.currentCell.getGridSquare((int)Math.floor(pose.x()),(int)Math.floor(pose.y()),(int)Math.floor(pose.z()));
        if(square==null) return null;
        for(var world:square.getWorldObjects()) {
            var item=world.getItem();
            if(supported(item) && item.getID()==pose.cart() && item.getWorldItem()==world
                && Math.abs(world.getWorldPosX()-pose.x())<.03 && Math.abs(world.getWorldPosY()-pose.y())<.03) return item;
        }
        return null;
    }

    private static boolean remoteOwner(IsoPlayer player,State state) {
        if(state.pickup) return state.world!=null && state.item.getWorldItem()==state.world
            && state.world.getItem()==state.item && state.world.getSquare()!=null
            && player.getPrimaryHandItem()==null && player.getSecondaryHandItem()==null;
        return state.item.getWorldItem()==null && state.item.getContainer()==player.getInventory()
            && player.getPrimaryHandItem()==state.item && player.getSecondaryHandItem()==state.item;
    }

    private static boolean emptyRemoteModel(String model) {return model==null || model.isEmpty();}

    /** Populate only presentation state; native actions retain hands, items and world ownership. */
    static synchronized boolean remote(IsoPlayer player,CartActionSync.Pose pose,float progress) {
        if(!Main.CART_SYNC_SUPPORTED || !GameClient.client || player.isLocalPlayer() || unsafeState(player)
            || !pose.valid() || !pose.nearby(player.getX(),player.getY(),player.getZ())) return false;
        var item=remoteItem(player,pose);
        if(item==null) return false;
        var state=states.get(player);
        boolean same=state!=null && state.remote && state.item==item && state.action==pose.action() && state.pickup==pose.pickup();
        boolean performing=player.getVariableBoolean("IsPerformingAnAction");
        boolean nativeAction=performing && "ToolkitWoodCart".equals(player.getVariableString("PerformingAction"))
            && CartGrounding.sameModel(item,player.overridePrimaryHandModel)
            && emptyRemoteModel(player.overrideSecondaryHandModel);
        if(performing && !nativeAction) return false;
        if(!nativeAction && !same) return false;
        if(!same) {
            endRemote(player);state=new State();state.remote=true;state.item=item;state.action=pose.action();state.pickup=pose.pickup();
            state.world=pose.pickup()?item.getWorldItem():null;
            states.put(player,state);
        }
        state.placement=pose.placement();
        long now=System.nanoTime();
        if(!nativeAction) {
            if(!state.recovering) {
                if(!state.rendered || !CartGrip.validPosture(state.nativeHeight,state.nativeRotation)
                    || !CartGrip.validPosture(state.referenceHeight,state.referenceRotation)
                    || !emptyRemoteModel(player.overridePrimaryHandModel) || !emptyRemoteModel(player.overrideSecondaryHandModel)) return false;
                state.visualModel=new String(item.getStaticModel());
                player.overridePrimaryHandModel=state.visualModel;player.resetEquippedHandsModels();
                state.recovering=true;state.cancelledProgress=pose.recovering()?pose.cancelled():state.progress;
                state.recoveryStart=now;state.pendingStart=now;state.remoteModelBindStart=now;
            }
            rebindRemoteRecovery(player,state,now);
            state.remoteWaiting=!pose.recovering();
            if(state.remoteWaiting && now-state.pendingStart>300_000_000L || !recoveryOwner(player,state)) return false;
            if(pose.recovering()) {state.cancelledProgress=pose.cancelled();state.progress=Math.min(progress,pose.cancelled());}
        } else {
            // A recovery snapshot can precede the native action-exit packet on the other reliable channel.
            if(state.recovering) return false;
            state.progress=pose.recovering()?Math.min(progress,pose.cancelled()):progress;
            // Native approach catch-up may leave current animation yaw facing away from the world handles.
            if(state.pickup) {
                var network=player.getNetworkCharacterAI();
                if(network!=null && network.prediction!=null && Float.isFinite(network.prediction.direction)) {
                    float heading=network.prediction.direction;
                    player.setTargetAndCurrentDirection((float)Math.cos(heading),(float)Math.sin(heading));
                }
            }
        }
        state.updated=now;
        player.setVariable("ToolkitWoodCartClipPilot",false);
        poseVariables(player,state);
        return true;
    }

    static synchronized void endRemote(IsoPlayer player) {
        var state=states.get(player);
        if(state!=null && state.remote) end(player);
    }

    private static boolean recoveryOwner(IsoPlayer player, State state) {
        if(state.remote) return !unsafeState(player) && remoteOwner(player,state)
            && state.visualModel!=null && state.visualModel==player.overridePrimaryHandModel
            && emptyRemoteModel(player.overrideSecondaryHandModel);
        if(state.visualModel==null || protectedState(player)) return false;
        if(state.pickup) return state.world!=null && state.item.getWorldItem()==state.world
            && state.world.getItem()==state.item && state.world.getSquare()!=null
            && player.getPrimaryHandItem()==null && player.getSecondaryHandItem()==null
            && Math.abs(player.getZ()-state.placement.z())<.25f
            && state.visualModel==player.overridePrimaryHandModel && player.overrideSecondaryHandModel==null;
        return state.item.getWorldItem()==null && state.item.getContainer()==player.getInventory()
            && player.getPrimaryHandItem()==state.item && player.getSecondaryHandItem()==state.item
            && state.visualModel==player.overridePrimaryHandModel && player.overrideSecondaryHandModel==null;
    }

    private static void rebindRemoteRecovery(IsoPlayer player,State state,long now) {
        // ActionContext.update follows our animation-entry hook. Its native exit can clear
        // the leased override again before rendering, even after the recovery aggregate arrived.
        if(!state.remote || !state.recovering || state.visualModel==null
            || now-state.recoveryStart>300_000_000L || unsafeState(player) || !remoteOwner(player,state)
            || player.getVariableBoolean("IsPerformingAnAction")
            || !emptyRemoteModel(player.overridePrimaryHandModel) || !emptyRemoteModel(player.overrideSecondaryHandModel)) return;
        player.overridePrimaryHandModel=state.visualModel;
        player.resetEquippedHandsModels();
        state.remoteModelBindStart=state.recoveryStart;
    }

    private static boolean pendingExpired(State state, long now) {
        return now-state.recoveryStart>=(.4+.2*state.cancelledProgress)*1_000_000_000.0
            || state.pendingStart!=0 && now-state.pendingStart>200_000_000L;
    }

    private static boolean recoveryActions(IsoPlayer player, State state, long now) {
        if(state.remote) return !player.getVariableBoolean("IsPerformingAnAction")
            && (!state.remoteWaiting || now-state.pendingStart<=300_000_000L);
        if(pendingExpired(state,now)) return false;
        var actions=player.getCharacterActions();
        if(actions.isEmpty()) return !player.getVariableBoolean("IsPerformingAnAction");
        if(!state.authored || actions.size()!=1 || !(actions.get(0) instanceof LuaTimedActionNew action)
            || action.chr!=player || action.forceStop || action.forceComplete || action.finished()) return false;
        var table=action.getTable();
        if(table==null || table.rawget("character")!=player) return false;
        String type=action.getMetaType();
        boolean owned=state.pickup
            ?"ISWalkToTimedActionF".equals(type) && table.rawget("toolkitWoodCartItem")==state.item
                || "ToolkitWoodCartPickup".equals(type) && table.rawget("itemId") instanceof Number id
                    && id.doubleValue()==state.item.getID()
            :("ToolkitWoodCartSetdown".equals(type) || "ToolkitWoodCartDrop".equals(type))
                && table.rawget("item")==state.item;
        if(owned && state.pickup && (state.world.getSquare()!=state.cancelSquare
            || !state.placement.equals(placement(state.item,state.world)))) return false;
        if(owned && state.pendingStart==0) state.pendingStart=now;
        return owned;
    }

    public static synchronized boolean suppressHeldModel(zombie.characters.IsoGameCharacter character) {
        if(!(character instanceof IsoPlayer player)) return false;
        var state=states.get(player);
        return state!=null && state.recovering && !state.pickup && recoveryOwner(player,state)
            && recoveryActions(player,state,System.nanoTime());
    }

    @LuaMethod(name="toolkitWoodCartCancel", global=true)
    public static synchronized boolean cancel(IsoPlayer player, InventoryItem item, boolean pickup, BaseAction stoppedAction) {
        var state=states.get(player);
        if(!Main.CART_TRANSITION_SUPPORTED || state==null || state.item!=item || state.pickup!=pickup
            || state.recovering || !state.rendered || state.progress<=0
            || state.authored && (state.recoveryPose==null || state.recoveryCart==null)
            || !CartGrip.validPosture(state.nativeHeight,state.nativeRotation)
            || !CartGrip.validPosture(state.referenceHeight,state.referenceRotation) || protectedState(player)
            || player.getVariableBoolean("IsPerformingAnAction")) return false;
        var actions=player.getCharacterActions();
        if(!actions.isEmpty() && (actions.size()!=1 || actions.get(0)!=stoppedAction)) return false;
        // Keep the same visual model through native stop's same-frame override removal, including held setdown.
        String model=item.getStaticModel();
        if(model==null || model.isBlank() || player.overridePrimaryHandModel!=null
            || player.overrideSecondaryHandModel!=null) return false;
        // Its identity is the lease token; another writer may select the very same model name.
        state.visualModel=new String(model);
        player.overridePrimaryHandModel=state.visualModel;
        if(!recoveryOwner(player,state)) {
            if(player.overridePrimaryHandModel==state.visualModel) player.overridePrimaryHandModel=null;
            state.visualModel=null;return false;
        }
        player.resetEquippedHandsModels();
        state.recovering=true;state.cancelledProgress=state.progress;state.recoveryStart=System.nanoTime();
        if(state.authored) {
            retireAuthored(player,state);state.movingRecovery=true;state.movementProgress=state.progress;
            state.restartPose=null;state.restartPlacement=null;
            state.cancelSquare=state.world==null?null:state.world.getSquare();
            cancelled.put(player,state);
        }
        publish(player,state);
        return true;
    }

    @LuaMethod(name="toolkitWoodCartTick", global=true)
    public static synchronized void tick(IsoPlayer player) {tick(player,System.nanoTime());}

    static void tick(IsoPlayer player, long now) {
        var previous=cancelled.get(player);
        if(previous!=null && (protectedState(player) || now-previous.lastRender>200_000_000L)) cancelled.remove(player);
        var state=states.get(player);
        if(state!=null && state.remote) return;
        if(state==null || !state.recovering) return;
        if(!recoveryOwner(player,state) || !recoveryActions(player,state,now)) {
            end(player,!protectedState(player) && !pendingExpired(state,now));return;
        }
        if(!player.getCharacterActions().isEmpty()) {state.updated=now;return;}
        state.progress=(float)CartTransitionMath.recover(state.cancelledProgress,(now-state.recoveryStart)*1e-9,!state.pickup);
        state.updated=now;
        if(state.progress<=0) end(player);
        else {poseVariables(player,state);publish(player,state);}
    }

    @LuaMethod(name="toolkitWoodCartStatus", global=true)
    public static synchronized KahluaTable status(IsoPlayer player) {
        var result=LuaManager.platform.newTable();var state=states.get(player);
        result.rawset("active",state!=null && !state.recovering);
        result.rawset("recovering",state!=null && state.recovering);
        if(state!=null) {
            result.rawset("rendered",state.rendered);result.rawset("ik",state.ik);
            result.rawset("progress",(double)state.progress);result.rawset("pickup",state.pickup);
            result.rawset("authored",state.authored);
        }
        return result;
    }

    @LuaMethod(name="toolkitWoodCartSetdownPose", global=true)
    public static synchronized void setdownPose(IsoPlayer player, InventoryItem item, double x, double y, double z, double rotation) {
        var state=states.get(player);
        if(state!=null && state.item==item && !state.pickup && Double.isFinite(x+y+z+rotation)) {
            state.placement=new CartTransitionMath.Placement((float)x,(float)y,(float)z+.00175f,0,(float)rotation,0,worldScale(item));
            publish(player,state);
        }
    }

    @LuaMethod(name="toolkitWoodCartEnd", global=true)
    public static synchronized void end(IsoPlayer player) {
        end(player,false);
    }

    private static void end(IsoPlayer player, boolean preserveCancelled) {
        if(player==null) {
            CartMotionSync.clearAll();CartActionSync.clearAll();CartEmergencyDrop.reset();
            for(var owner:new java.util.ArrayList<>(states.keySet())) end(owner);
            cancelled.clear();
            return;
        }
        if(!preserveCancelled) cancelled.remove(player);
        if(player.isLocalPlayer()) CartActionSync.end(player);
        var state=states.remove(player);
        if(state!=null) retireAuthored(player,state);
        player.clearVariable("ToolkitWoodCartPoseX");player.clearVariable("ToolkitWoodCartPoseY");
        player.clearVariable("ToolkitWoodCartClipTime");player.clearVariable("ToolkitWoodCartClipPickup");
        player.clearVariable("ToolkitMetalCartClip");player.clearVariable("ToolkitShoppingCartClip");
        if(state!=null && state.visualModel!=null && state.visualModel==player.overridePrimaryHandModel) {
            player.overridePrimaryHandModel=null;player.resetEquippedHandsModels();
        }
        if(state!=null && state.world!=null) {
            state.world.invalidateRenderChunkLevel(256);
        }
    }

    static synchronized boolean render(ModelSlotRenderData slot) {
        if(!(slot.character instanceof IsoPlayer player)) return false;
        var state=states.get(player);
        if(state==null) return false;
        if((state.remote?unsafeState(player):protectedState(player)) || System.nanoTime()-state.updated>1_000_000_000L) {
            end(player);return false;
        }
        rebindRemoteRecovery(player,state,System.nanoTime());
        if(state.recovering && (!recoveryOwner(player,state) || !recoveryActions(player,state,System.nanoTime()))) {
            end(player,!pendingExpired(state,System.nanoTime()));return false;
        }
        var clip=ModelManager.instance.getAnimationClip("Bob_Cart_Idle");
        if(clip==null) return false;
        if(state.recovering && !state.movingRecovery && player.isJustMoved() && state.recoveryPose!=null) {
            state.movingRecovery=true;state.movementProgress=state.progress;
        }
        boolean cartModelPresent=false;
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            var profile=CartWheelbarrow.forItem(state.item);
            String modelName=modelName(state.item);
            if(instance.modelScript==null || !instance.modelScript.getName().equals(modelName)) continue;
            cartModelPresent=true;
            var held=new Matrix4f();var delta=new Matrix4f();
            if(!CartGrounding.rigid(data,clip,held)) continue;
            CartGrounding.lowerHandles(held,modelName);
            // Follow native gait clearance so ordinary rendering does not shift both handles after recovery.
            // Keep the captured neutral bank/grip policy; changing it needs a separate source-pose blend.
            float gait=profile!=null && state.movingRecovery && !state.pickup?CartLegPace.woodenGaitShift(player):0;
            if(!(profile!=null?CartGrounding.alignWheelbarrow(held,profile,0,0,gait,delta)
                :CartGrounding.align(held,instance.model.mesh.minXyz,instance.model.mesh.maxXyz,CartGrounding.contact(modelName),0,delta))) continue;
            var model=model(state.item);
            if(model==null) continue;
            if(state.placement==null) state.placement=dropPlacement(slot,held,model,state.item);
            if(state.placement==null) continue;
            var ground=new Matrix4f();
            if(!CartTransitionMath.worldToActor(state.placement,model,slot.x,slot.y,slot.z,slot.animPlayerAngle,ground)) continue;
            var phase=phase(state);
            float release=state.movingRecovery?(float)CartTransitionMath.recoveryRelease(state.progress,state.movementProgress,state.authored && state.pickup):1;
            var transform=new Matrix4f();
            if(!blend(state.item,ground,held,model,phase.lift(),transform)) continue;
            var axle=profile==null?new Vector3f(CartGrounding.contact(modelName)):profile.center(new Vector3f());
            var center=ground.transformPosition(axle,new Vector3f()).lerp(held.transformPosition(axle,new Vector3f()),
                (float)phase.lift());
            transform.translateLocal(center.sub(transform.transformPosition(axle,new Vector3f())));
            // A cancelled setdown still owns the held cart; carry its return path with the walking actor.
            if(state.movingRecovery && !state.pickup
                && !blend(state.item,held,state.recoveryCart,model,release,transform)) {end(player);return false;}
            double restartAge=System.nanoTime()-state.restartStart;
            float restart=state.restartPose==null?0:1-(float)CartTransitionMath.smooth(restartAge/RESTART_BLEND_NANOS);
            float cartRestart=restartCartWeight(profile,state.pickup,restart);
            if(profile!=null && state.pickup && state.restartPose!=null) {
                // Let the hip clear the shafts before lowering the cart after an interrupted pickup.
                double u=Math.max(0,Math.min(1,restartAge/400_000_000.0));
                cartRestart=1-(float)CartTransitionMath.smooth(u-.7*u*(1-u));
            }
            if(cartRestart>0) {
                var from=new Matrix4f();
                if(!CartTransitionMath.worldToActor(state.restartPlacement,model,slot.x,slot.y,slot.z,slot.animPlayerAngle,from))
                    {end(player);return false;}
                var target=new Matrix4f(transform);
                if(!blend(state.item,target,from,model,cartRestart,transform)) {end(player);return false;}
                var pivot=from.transformPosition(axle,new Vector3f()).lerp(target.transformPosition(axle,new Vector3f()),1-cartRestart);
                transform.translateLocal(pivot.sub(transform.transformPosition(axle,new Vector3f())));
            } else {state.restartPose=null;state.restartPlacement=null;}
            var reference=CartGrip.referencePosture(instance.parent.animPlayer.getSkinningData(),phase);
            float baseHeight=Float.NaN;Quaternionf baseRotation=null;
            if(state.recovering && !state.movingRecovery) {
                // Native stop fades the action layer into cart idle; retain its calibrated height and chest posture.
                var posture=CartGrip.recoverPosture(new CartGrip.Posture(state.nativeHeight,state.nativeRotation),
                    new CartGrip.Posture(state.referenceHeight,state.referenceRotation),reference,state.progress/state.cancelledProgress);
                if(posture==null) {end(player);return false;}
                baseHeight=posture.height();baseRotation=posture.rotation();
            } else if(!state.recovering) {
                var posture=CartGrip.nativePosture(slot,instance.parent);
                state.nativeHeight=posture==null?Float.NaN:posture.height();
                state.referenceHeight=reference==null?Float.NaN:reference.height();
                state.nativeRotation=posture==null?null:new Quaternionf(posture.rotation());
                state.referenceRotation=reference==null?null:new Quaternionf(reference.rotation());
            }
            // Keep the knee bend and hip hinge in one continuous descent, without an early sink/rebound.
            float lowering=profile==null?0:(float)(-profile.pickupLowering()*phase.balance());
            // A restarted pickup releases the old grip while its clip begins the approach again.
            float reach=state.pickup?(float)phase.reach():(float)phase.reach()*(1-restart)+state.restartReach*restart;
            float grip=state.pickup?(float)phase.grip():(float)phase.grip()*(1-restart)+state.restartGrip*restart;
            float clearance=profile!=null && state.authored && state.movingRecovery && state.pickup
                ?(float)CartTransitionMath.recoveryClearance(state.cancelledProgress,(System.nanoTime()-state.recoveryStart)*1e-9):0;
            state.ik=state.movingRecovery
                ?CartGrip.movingRecovery(slot,instance.parent,clip,delta,transform,held,state.recoveryPose,release,!state.pickup,
                    state.recoveryReach,state.recoveryGrip,clearance,modelName)
                :state.authored?CartGrip.authoredTransition(slot,instance.parent,clip,delta,transform,
                    reach,grip,state.restartPose,restart,modelName)
                :CartGrip.transition(slot,instance.parent,delta,transform,(float)phase.reach(),(float)phase.grip(),
                    (float)phase.lift(),(ground.m30()-held.m30())*(float)phase.center(),lowering,.16f*(float)phase.balance(),
                    (float)Math.toRadians(profile==null?0:profile.pickupHingeDegrees()*phase.hinge()),baseHeight,baseRotation,modelName);
            if(state.recovering && !state.ik) {end(player);return false;}
            if(state.ik && !state.movingRecovery) {
                state.recoveryPose=CartGrip.capture(instance.parent.animPlayer.getSkinningData(),state.recoveryPose);
                if(state.recoveryCart==null) state.recoveryCart=new Matrix4f();
                state.recoveryCart.set(transform);
                state.recoveryReach=reach;state.recoveryGrip=grip;
            }
            if(state.ik && state.authored) {
                state.lastPose=CartGrip.capture(instance.parent.animPlayer.getSkinningData(),state.lastPose);
                state.lastPlacement=CartTransitionMath.actorToWorldPlacement(transform,model,slot.x,slot.y,slot.z,slot.animPlayerAngle);
                state.lastReach=state.movingRecovery?(state.pickup?state.recoveryReach*release:1-release*(1-state.recoveryReach)):reach;
                state.lastGrip=state.movingRecovery?(state.pickup?state.recoveryGrip*release:1-release*(1-state.recoveryGrip)):grip;
                state.lastRender=System.nanoTime();
            }
            data.xfrm.set(transform).transpose();
            CartWheelSpin.prepare(slot,CartWheelSpin.follow(state.item,slot.x,slot.y,slot.animPlayerAngle,transform));
            if(state.world!=null && !state.rendered) state.world.invalidateRenderChunkLevel(256);
            state.rendered=true;
            state.remoteModelBindStart=0;
            return true;
        }
        // Native action exit removes pickup's hand model; our exact lease binds on the next model rebuild.
        // Retain the previously rendered pose only through that initial bounded gap, never a failed cart solve.
        if(state.recovering && !(state.remote && !cartModelPresent && state.remoteModelBindStart!=0
            && System.nanoTime()-state.remoteModelBindStart<=300_000_000L)) end(player);
        return false;
    }

    public static synchronized boolean hidden(InventoryItem item) {
        for(var state:states.values()) if(state.item==item && state.world!=null && state.rendered) return true;
        return false;
    }

    static CartTransitionMath.Placement dropPlacement(ModelSlotRenderData slot, Matrix4f held, Matrix4f model, InventoryItem item) {
        var profile=CartWheelbarrow.forItem(item);
        return profile==null?shoppingDropPlacement(held,model,slot.x,slot.y,slot.z,slot.animPlayerAngle,item.worldScale)
            :dropPlacement(held,model,slot.x,slot.y,slot.z,slot.animPlayerAngle,item.worldScale,profile.pickupStanceBack(),profile);
    }

    static CartTransitionMath.Placement dropPlacement(Matrix4f held, Matrix4f model, float x, float y, float z, float angle, float scale) {
        return dropPlacement(held,model,x,y,z,angle,scale,STANCE_BACK);
    }

    static CartTransitionMath.Placement dropPlacement(Matrix4f held, Matrix4f model, float x, float y, float z, float angle, float scale, float stanceBack) {
        return dropPlacement(held,model,x,y,z,angle,scale,stanceBack,CartWheelbarrow.WOOD);
    }

    static CartTransitionMath.Placement dropPlacement(Matrix4f held, Matrix4f model, float x, float y, float z, float angle, float scale, float stanceBack, CartWheelbarrow profile) {
        var pose=CartTransitionMath.actorToWorldPlacement(held,model,x,y,z,angle);
        if(pose==null) return null;
        var relative=new Matrix4f().rotationY(angle+(float)Math.PI).mul(held).mul(new Matrix4f(model).invert());
        float yaw=(float)Math.toDegrees(Math.atan2(-relative.m02(),relative.m00()));
        yaw=(yaw%360+360)%360;
        var groundPose=new CartTransitionMath.Placement(pose.x(),pose.y(),z+.00175f,0,yaw,0,scale*.85f);
        var ground=new Matrix4f();
        if(!CartTransitionMath.worldToActor(groundPose,model,x,y,z,angle,ground)) return null;
        var axle=profile.center(new Vector3f());
        var difference=held.transformPosition(axle,new Vector3f()).sub(ground.transformPosition(axle,new Vector3f()));
        difference.z-=stanceBack;
        float c=(float)Math.cos(angle),s=(float)Math.sin(angle);
        return new CartTransitionMath.Placement(pose.x()-1.5f*(c*difference.x+s*difference.z),
            pose.y()+1.5f*(-s*difference.x+c*difference.z),z+.00175f,0,yaw,0,scale*.85f);
    }

    static CartTransitionMath.Placement shoppingDropPlacement(Matrix4f held,Matrix4f model,float x,float y,float z,float angle,float scale) {
        var pose=CartTransitionMath.actorToWorldPlacement(held,model,x,y,z,angle);
        if(pose==null) return null;
        // Euler decomposition has two yaw branches; keep native world yaw in [0,360).
        var relative=new Matrix4f().rotationY(angle+(float)Math.PI).mul(held).mul(new Matrix4f(model).invert());
        float yaw=(float)Math.toDegrees(Math.atan2(-relative.m02(),relative.m00()));
        yaw=(yaw%360+360)%360;
        var groundPose=new CartTransitionMath.Placement(pose.x(),pose.y(),z+.00175f,0,yaw,0,scale);
        var ground=new Matrix4f();
        if(!CartTransitionMath.worldToActor(groundPose,model,x,y,z,angle,ground)) return null;
        var left=new Vector3f();var right=new Vector3f();
        CartGrip.handle("ShoppingCartModel",true,left);CartGrip.handle("ShoppingCartModel",false,right);
        var center=left.add(right).mul(.5f);
        var difference=held.transformPosition(center,new Vector3f()).sub(ground.transformPosition(center,new Vector3f()));
        float c=(float)Math.cos(angle),s=(float)Math.sin(angle);
        return new CartTransitionMath.Placement(pose.x()-1.5f*(c*difference.x+s*difference.z),
            pose.y()+1.5f*(-s*difference.x+c*difference.z),z+.00175f,0,yaw,0,scale);
    }

    @LuaMethod(name="toolkitWoodCartDropPose", global=true)
    public static KahluaTable dropPose(IsoPlayer player, InventoryItem item) {
        if(!Main.CART_TRANSITION_SUPPORTED || player==null || !supported(item)) return null;
        var model=model(item);
        if(model==null) return null;
        var direction=player.getForwardDirection();
        var profile=CartWheelbarrow.forItem(item);
        var pose=profile==null?shoppingDropPlacement(held(item,new Matrix4f()),model,player.getX(),player.getY(),player.getZ(),
            direction.getDirection()+(float)Math.PI/2,item.worldScale)
            :dropPlacement(profile.held(new Matrix4f()),model,player.getX(),player.getY(),player.getZ(),
                direction.getDirection()+(float)Math.PI/2,item.worldScale,profile.pickupStanceBack(),profile);
        if(pose==null || target(player,pose.x(),pose.y(),player.getZ())==null) return null;
        var result=LuaManager.platform.newTable();
        result.rawset("x",(double)pose.x());result.rawset("y",(double)pose.y());
        result.rawset("z",(double)player.getZ());result.rawset("rotation",(double)pose.zRotation());
        return result;
    }

    private record Drop(IsoPlayer player, InventoryItem item, float x, float y, float z, float rotation) {}
    private static final ThreadLocal<Drop> drop=new ThreadLocal<>();

    @LuaMethod(name="toolkitWoodCartDropBegin", global=true)
    public static boolean beginDrop(IsoPlayer player, InventoryItem item, double x, double y, double z, double rotation) {
        drop.remove();
        if(!Main.CART_TRANSITION_SUPPORTED || player==null || !supported(item) || item.getWorldItem()!=null
            || item.getContainer()!=player.getInventory() || player.getPrimaryHandItem()!=item
            || player.getSecondaryHandItem()!=item || !Double.isFinite(x+y+z+rotation)
            || Math.hypot(x-player.getX(),y-player.getY())>1.5 || z!=player.getZ() || rotation<0 || rotation>=360) return false;
        drop.set(new Drop(player,item,(float)x,(float)y,(float)z,(float)rotation));
        return true;
    }

    @LuaMethod(name="toolkitWoodCartDropEnd", global=true)
    public static void endDrop() {drop.remove();}

    public static InventoryItem place(IsoGridSquare square, InventoryItem item) {
        var pending=drop.get();
        if(pending==null || pending.item!=item || square!=pending.player.getCurrentSquare()) return null;
        var target=target(pending.player,pending.x,pending.y,pending.z);
        if(target==null) return null;
        float ox=pending.x-target.getX(),oy=pending.y-target.getY();
        // The native constructor randomizes exact zero offsets.
        if(ox==0) ox=.00001f;if(oy==0) oy=.00001f;
        drop.remove();
        item.setWorldZRotation(pending.rotation);
        return target.AddWorldInventoryItem(item,ox,oy,0,true);
    }

    static IsoGridSquare target(IsoPlayer player, float x, float y, float z) {
        var square=player.getCurrentSquare();
        if(square==null || square.HasStairs() || IsoWorld.instance==null || IsoWorld.instance.currentCell==null) return null;
        var target=IsoWorld.instance.currentCell.getGridSquare((int)Math.floor(x),(int)Math.floor(y),(int)z);
        return target!=null && target.TreatAsSolidFloor() && square.canReachTo(target)
            && !target.HasStairs() && !target.isSolid() && !target.isSolidTrans()?target:null;
    }

    private CartTransition() {}
}
