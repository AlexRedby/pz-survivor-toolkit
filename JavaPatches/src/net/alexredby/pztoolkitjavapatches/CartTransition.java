package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import java.lang.reflect.Field;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.inventory.InventoryItem;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.scripting.ScriptManager;

/** Presentation only: inventory/world ownership remains with the native timed action. */
public final class CartTransition {
    private static final WeakHashMap<IsoPlayer, State> states = new WeakHashMap<>();
    private static final Field CLIP_RETIRING = clipRetiringField();
    // Start behind the handle ends rather than clearing the shafts with a large pelvis-only retreat.
    private static final float STANCE_BACK = .06f;
    // shortcut: the supported wooden attachment and Bob_Cart_Idle reference; recalibrate after either asset changes.
    private static final Matrix4f HELD = new Matrix4f().set(
        76.5f,-3.9394883e-5f,-1.4673389e-5f,0,2.8023098e-5f,20.771942f,73.62592f,0,
        -2.4333809e-5f,-73.625916f,20.771938f,0,-.0060535767f,.097179376f,-.34652624f,1);

    private static final class State {
        InventoryItem item;
        boolean pickup, ik, rendered, recovering, authored, clipRetired;
        float cancelledProgress, nativeHeight, referenceHeight, movementProgress, recoveryReach, recoveryGrip;
        Matrix4f[] recoveryPose;
        Matrix4f recoveryCart;
        boolean movingRecovery;
        Quaternionf nativeRotation, referenceRotation;
        long recoveryStart;
        String visualModel;
        float progress;
        long updated;
        IsoWorldInventoryObject world;
        CartTransitionMath.Placement placement;
    }

    public static boolean wooden(InventoryItem item) {
        return item != null && "SaucedWheelbarrow.WheelbarrowWood".equals(item.getFullType());
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
        return result.scale(script.scale);
    }

    static CartTransitionMath.Placement placement(InventoryItem item, IsoWorldInventoryObject world) {
        return new CartTransitionMath.Placement(world.getWorldPosX(),world.getWorldPosY(),world.getWorldPosZ()+.00175f,
            item.getWorldXRotation(),item.getWorldZRotation(),item.getWorldYRotation(),item.worldScale*.85f);
    }

    @LuaMethod(name="toolkitWoodCartStance", global=true)
    public static KahluaTable stance(IsoPlayer player, IsoWorldInventoryObject world) {
        if (!Main.CART_TRANSITION_SUPPORTED || world == null || !wooden(world.getItem())) return null;
        var item=world.getItem();var model=model(item);
        if(model==null) return null;
        var ground=new Matrix4f();
        var pose=placement(item,world);
        var left=new Vector3f();var right=new Vector3f();
        CartGrip.handle("WheelbarrowWood",true,left);CartGrip.handle("WheelbarrowWood",false,right);
        var target=CartTransitionMath.stance(pose,model,HELD,left,right);
        if(target==null) return null;
        if(!CartTransitionMath.worldToActor(pose,model,target.x(),target.y(),player.getZ(),target.slotAngle(),ground)) return null;
        var axle=new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z);
        var difference=ground.transformPosition(axle,new Vector3f()).sub(HELD.transformPosition(axle,new Vector3f()));
        difference.z+=STANCE_BACK;
        float c=(float)Math.cos(target.slotAngle()),s=(float)Math.sin(target.slotAngle());
        float x=target.x()-1.5f*(c*difference.x+s*difference.z);
        float y=target.y()+1.5f*(-s*difference.x+c*difference.z);
        var result=LuaManager.platform.newTable();
        result.rawset("x",(double)x);result.rawset("y",(double)y);
        double heading=target.slotAngle()-Math.PI/2;
        result.rawset("faceX",player.getX()+Math.cos(heading));
        result.rawset("faceY",player.getY()+Math.sin(heading));
        var animation=player.getAnimationPlayer();
        result.rawset("aligned",animation!=null && !player.isTurning()
            && Math.abs(CartSteeringMath.wrap(animation.getRenderedAngle()-target.slotAngle()))<Math.toRadians(1));
        return result;
    }

    @LuaMethod(name="toolkitWoodCartUpdate", global=true)
    public static synchronized boolean update(IsoPlayer player, InventoryItem item, boolean pickup, double progress) {
        if(!Main.CART_TRANSITION_SUPPORTED || player==null || !player.isLocalPlayer() || !wooden(item)
            || !Double.isFinite(progress) || player.isDead()) return false;
        State state=states.get(player);
        if(state==null || state.recovering || state.item!=item || state.pickup!=pickup) {
            end(player);state=new State();state.item=item;state.pickup=pickup;
            state.authored=player.getVariableBoolean("ToolkitWoodCartClipPilot");
            if(state.authored && CLIP_RETIRING==null)
                throw new IllegalStateException("Authored cart clips require native node retirement support");
            if(pickup) {
                state.world=item.getWorldItem();
                if(state.world==null) return false;
                state.placement=placement(item,state.world);
            }
            states.put(player,state);
        }
        state.progress=(float)Math.max(0,Math.min(1,progress));state.updated=System.nanoTime();
        poseVariables(player,state);
        return true;
    }

    private static void poseVariables(IsoPlayer player, State state) {
        var phase=CartTransitionMath.progress(state.progress,!state.pickup);
        player.setVariable("ToolkitWoodCartPoseX",(float)(phase.lift()+.10*phase.crouch()*(1-phase.lift())));
        player.setVariable("ToolkitWoodCartPoseY",(float)phase.lift());
        if(state.authored) {
            player.setVariable("ToolkitWoodCartClipTime",state.progress);
            player.setVariable("ToolkitWoodCartClipPickup",state.pickup);
        }
    }

    private static Field clipRetiringField() {
        try {
            var field=LiveAnimNode.class.getDeclaredField("transitioningOut");
            field.setAccessible(true);return field;
        } catch(ReflectiveOperationException | RuntimeException unsupported) {return null;}
    }

    static boolean retireAuthoredNode(LiveAnimNode node, boolean pickup) {
        if(!("ToolkitWoodCartClip"+(pickup?"Pickup":"Setdown")).equals(node.getSourceNode().name)) return false;
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
        return !player.isLocalPlayer() || player.isDead() || player.isAiming() || player.hasHitReaction()
            || player.isKnockedDown() || player.isGettingUp() || player.getVehicle()!=null
            || player.isGrappling() || player.isBeingGrappled() || player.isRagdollSimulationActive();
    }

    private static boolean recoveryOwner(IsoPlayer player, State state) {
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

    public static synchronized boolean suppressHeldModel(zombie.characters.IsoGameCharacter character) {
        if(!(character instanceof IsoPlayer player)) return false;
        var state=states.get(player);
        return state!=null && state.recovering && !state.pickup && recoveryOwner(player,state)
            && player.getCharacterActions().isEmpty() && !player.getVariableBoolean("IsPerformingAnAction");
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
        }
        return true;
    }

    @LuaMethod(name="toolkitWoodCartTick", global=true)
    public static synchronized void tick(IsoPlayer player) {tick(player,System.nanoTime());}

    static void tick(IsoPlayer player, long now) {
        var state=states.get(player);
        if(state==null || !state.recovering) return;
        if(!recoveryOwner(player,state) || !player.getCharacterActions().isEmpty()
            || player.getVariableBoolean("IsPerformingAnAction")) {end(player);return;}
        state.progress=(float)CartTransitionMath.recover(state.cancelledProgress,(now-state.recoveryStart)*1e-9,!state.pickup);
        state.updated=now;
        if(state.progress<=0) end(player);
        else poseVariables(player,state);
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
        if(state!=null && state.item==item && !state.pickup && Double.isFinite(x+y+z+rotation))
            state.placement=new CartTransitionMath.Placement((float)x,(float)y,(float)z+.00175f,0,(float)rotation,0,item.worldScale*.85f);
    }

    @LuaMethod(name="toolkitWoodCartEnd", global=true)
    public static synchronized void end(IsoPlayer player) {
        if(player==null) {
            for(var owner:new java.util.ArrayList<>(states.keySet())) end(owner);
            return;
        }
        var state=states.remove(player);
        if(state!=null) retireAuthored(player,state);
        player.clearVariable("ToolkitWoodCartPoseX");player.clearVariable("ToolkitWoodCartPoseY");
        player.clearVariable("ToolkitWoodCartClipTime");player.clearVariable("ToolkitWoodCartClipPickup");
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
        if(protectedState(player) || state.recovering && !recoveryOwner(player,state)
            || System.nanoTime()-state.updated>1_000_000_000L) {
            end(player);return false;
        }
        var clip=ModelManager.instance.getAnimationClip("Bob_Cart_Idle");
        if(clip==null) return false;
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.modelScript==null || !"WheelbarrowWood".equals(instance.modelScript.getName())) continue;
            var held=new Matrix4f();var delta=new Matrix4f();
            if(!CartGrounding.rigid(data,clip,held)) continue;
            CartGrounding.lowerHandles(held,"WheelbarrowWood");
            if(!CartGrounding.alignWood(held,0,0,delta)) continue;
            var model=model(state.item);
            if(model==null) continue;
            if(state.placement==null) state.placement=dropPlacement(slot,held,model,state.item);
            if(state.placement==null) continue;
            var ground=new Matrix4f();
            if(!CartTransitionMath.worldToActor(state.placement,model,slot.x,slot.y,slot.z,slot.animPlayerAngle,ground)) continue;
            var phase=CartTransitionMath.progress(state.progress,!state.pickup);
            if(state.recovering && !state.movingRecovery && player.isJustMoved() && state.recoveryPose!=null) {
                state.movingRecovery=true;state.movementProgress=state.progress;
            }
            float release=state.movingRecovery?(float)CartTransitionMath.smooth(state.progress/state.movementProgress):1;
            var transform=new Matrix4f();
            if(!CartTransitionMath.blend(ground,held,phase.lift(),transform)) continue;
            var axle=new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z);
            var center=ground.transformPosition(axle,new Vector3f()).lerp(held.transformPosition(axle,new Vector3f()),
                (float)phase.lift());
            transform.translateLocal(center.sub(transform.transformPosition(axle,new Vector3f())));
            // A cancelled setdown still owns the held cart; carry its return path with the walking actor.
            if(state.movingRecovery && !state.pickup
                && !CartTransitionMath.blend(held,state.recoveryCart,release,transform)) {end(player);return false;}
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
            float lowering=(float)(-.03*phase.balance());
            state.ik=state.movingRecovery
                ?CartGrip.movingRecovery(slot,instance.parent,clip,delta,transform,held,state.recoveryPose,release,!state.pickup,
                    state.recoveryReach,state.recoveryGrip)
                :state.authored?CartGrip.authoredTransition(slot,instance.parent,clip,delta,transform,
                    (float)phase.reach(),(float)phase.grip())
                :CartGrip.transition(slot,instance.parent,delta,transform,(float)phase.reach(),(float)phase.grip(),
                    (float)phase.lift(),(ground.m30()-held.m30())*(float)phase.center(),lowering,.16f*(float)phase.balance(),
                    (float)Math.toRadians(60*phase.hinge()),baseHeight,baseRotation);
            if(state.recovering && !state.ik) {end(player);return false;}
            if(state.ik && !state.movingRecovery) {
                state.recoveryPose=CartGrip.capture(instance.parent.animPlayer.getSkinningData(),state.recoveryPose);
                if(state.recoveryCart==null) state.recoveryCart=new Matrix4f();
                state.recoveryCart.set(transform);
                state.recoveryReach=(float)phase.reach();state.recoveryGrip=(float)phase.grip();
            }
            data.xfrm.set(transform).transpose();
            CartWheelSpin.prepare(slot,CartWheelSpin.follow(state.item,slot.x,slot.y,slot.animPlayerAngle,transform));
            if(state.world!=null && !state.rendered) state.world.invalidateRenderChunkLevel(256);
            state.rendered=true;
            return true;
        }
        if(state.recovering) end(player);
        return false;
    }

    public static synchronized boolean hidden(InventoryItem item) {
        for(var state:states.values()) if(state.item==item && state.world!=null && state.rendered) return true;
        return false;
    }

    static CartTransitionMath.Placement dropPlacement(ModelSlotRenderData slot, Matrix4f held, Matrix4f model, InventoryItem item) {
        return dropPlacement(held,model,slot.x,slot.y,slot.z,slot.animPlayerAngle,item.worldScale);
    }

    static CartTransitionMath.Placement dropPlacement(Matrix4f held, Matrix4f model, float x, float y, float z, float angle, float scale) {
        var pose=CartTransitionMath.actorToWorldPlacement(held,model,x,y,z,angle);
        if(pose==null) return null;
        var relative=new Matrix4f().rotationY(angle+(float)Math.PI).mul(held).mul(new Matrix4f(model).invert());
        float yaw=(float)Math.toDegrees(Math.atan2(-relative.m02(),relative.m00()));
        yaw=(yaw%360+360)%360;
        var groundPose=new CartTransitionMath.Placement(pose.x(),pose.y(),z+.00175f,0,yaw,0,scale*.85f);
        var ground=new Matrix4f();
        if(!CartTransitionMath.worldToActor(groundPose,model,x,y,z,angle,ground)) return null;
        var axle=new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z);
        var difference=held.transformPosition(axle,new Vector3f()).sub(ground.transformPosition(axle,new Vector3f()));
        difference.z-=STANCE_BACK;
        float c=(float)Math.cos(angle),s=(float)Math.sin(angle);
        return new CartTransitionMath.Placement(pose.x()-1.5f*(c*difference.x+s*difference.z),
            pose.y()+1.5f*(-s*difference.x+c*difference.z),z+.00175f,0,yaw,0,scale*.85f);
    }

    @LuaMethod(name="toolkitWoodCartDropPose", global=true)
    public static KahluaTable dropPose(IsoPlayer player, InventoryItem item) {
        if(!Main.CART_TRANSITION_SUPPORTED || player==null || !wooden(item)) return null;
        var model=model(item);
        if(model==null) return null;
        var direction=player.getForwardDirection();
        var pose=dropPlacement(HELD,model,player.getX(),player.getY(),player.getZ(),
            direction.getDirection()+(float)Math.PI/2,item.worldScale);
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
        if(!Main.CART_TRANSITION_SUPPORTED || player==null || !wooden(item) || item.getWorldItem()!=null
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

    private static IsoGridSquare target(IsoPlayer player, float x, float y, float z) {
        var square=player.getCurrentSquare();
        if(square==null || square.HasStairs() || IsoWorld.instance==null || IsoWorld.instance.currentCell==null) return null;
        var target=IsoWorld.instance.currentCell.getGridSquare((int)Math.floor(x),(int)Math.floor(y),(int)z);
        return target!=null && target.TreatAsSolidFloor() && square.canReachTo(target)
            && !target.HasStairs() && !target.isSolid() && !target.isSolidTrans()?target:null;
    }

    private CartTransition() {}
}
