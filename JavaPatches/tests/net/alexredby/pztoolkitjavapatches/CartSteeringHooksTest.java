package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.lwjgl.util.vector.Vector3f;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendTriangle;
import zombie.core.skinnedmodel.advancedanimation.AnimationSet;
import zombie.core.skinnedmodel.advancedanimation.AnimState;
import zombie.core.skinnedmodel.advancedanimation.AnimTransition;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.BoneAxis;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.Vector2;
import zombie.iso.objects.IsoWorldInventoryObject;

public final class CartSteeringHooksTest {
    private static final class Keys extends zombie.characters.component.CharacterInputComponent {
        boolean forward,backward,left,right;
        @Override public boolean isForwardKeyDown() { return forward; }
        @Override public boolean isBackwardKeyDown() { return backward; }
        @Override public boolean isLeftKeyDown() { return left; }
        @Override public boolean isRightKeyDown() { return right; }
        void set(int travel,int steering) {
            forward=travel>0;backward=travel<0;left=steering<0;right=steering>0;
        }
    }

    // Skip world/renderer constructors, as the existing NativeChecks fixture does.
    private static final class Player extends IsoPlayer {
        int blocked;
        boolean pivot, brace, woodBrake, brakeSprint, moving, run, sprint, pathActive, npc;
        boolean keyboard,aim,autoWalk;
        Keys keys;
        // The existing world-direction cases describe the preserved absolute analog-input contract.
        @Override public zombie.characters.CharacterInputMode getInputMode() {
            return keyboard?zombie.characters.CharacterInputMode.KEYBOARD:zombie.characters.CharacterInputMode.GAMEPAD;
        }
        @Override public boolean isAimControlActive() { return aim; }
        @Override public boolean isAiming() { return aim; }
        @Override public boolean isAutoWalk() { return autoWalk; }
        @Override public zombie.characters.component.CharacterInputComponent getCharacterInputComponent() { return keys; }
        zombie.pathfind.PathFindBehavior2 nativePath;
        zombie.ai.astar.AStarPathFinderResult finder;
        zombie.ai.StateMachine machine;
        java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction> actions;
        @Override public java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction> getCharacterActions() {
            if(actions==null) actions=new java.util.Stack<>();
            return actions;
        }
        Runnable animationUpdate;
        float walkSpeed, slowFactor;
        @Override public float getSlowFactor() { return slowFactor; }
        float stepX, stepY, legPace;
        float actualX, actualY, inputX, inputY;
        ItemContainer inventory;
        InventoryItem primary, secondary;
        AdvancedAnimator animator;
        Player() { super(null, null, 0, 0, 0); }
        @Override public AdvancedAnimator getAdvancedAnimator() { return animator; }
        @Override public AnimationPlayer getAnimationPlayer() { return null; }
        @Override public boolean isRunning() { return run; }
        @Override public boolean isSprinting() { return sprint; }
        @Override public boolean isAllowRun() { return true; }
        @Override public boolean isAllowSprint() { return true; }
        @Override public float getVariableFloat(String name,float fallback) {
            return switch(name) {case "WalkSpeed"->walkSpeed;case "ToolkitCartStepX"->stepX;case "ToolkitCartStepY"->stepY;case "ToolkitCartLegPace"->legPace;default->fallback;};
        }
        @Override public void clearVariable(String name) {
            if(name.equals("ToolkitCartLegPace")) legPace=0;
            if(name.equals("ToolkitCartWoodBrake")) woodBrake=false;
        }
        @Override public boolean isLocalPlayer() { return blocked != 8; }
        @Override public boolean isDead() { return blocked == 1; }
        @Override public boolean hasHitReaction() { return blocked == 2; }
        @Override public boolean isKnockedDown() { return blocked == 3; }
        @Override public boolean isGettingUp() { return blocked == 4 || super.isGettingUp(); }
        @Override public zombie.ai.StateMachine getStateMachine() {
            if(machine==null) machine=new zombie.ai.StateMachine(this);
            return machine;
        }
        @Override public boolean isAnimationUpdatingThisFrame() {
            if(animationUpdate!=null) animationUpdate.run();
            return false;
        }
        @Override public void setCurrentSquareFromPosition() {}
        @Override public boolean isGrappling() { return blocked == 5; }
        @Override public boolean isBeingGrappled() { return blocked == 6; }
        @Override public boolean isRagdollSimulationActive() { return blocked == 7; }
        @Override public boolean hasPath() { return pathActive || blocked == 9; }
        @Override public boolean isNpc() { return npc; }
        @Override public zombie.pathfind.PathFindBehavior2 getPathFindBehavior2() { return nativePath; }
        @Override public zombie.ai.astar.AStarPathFinderResult getFinder() { return finder; }
        @Override public boolean getVariableBoolean(String name) {
            return switch(name) {case "ToolkitCartMotion"->blocked!=10;case "ToolkitCartPivot"->pivot;
                case "ToolkitCartBrace"->brace;case "ToolkitCartWoodBrake"->woodBrake;case "ToolkitCartBrakeSprint"->brakeSprint;default->false;};
        }
        @Override public InventoryItem getPrimaryHandItem() { return primary; }
        @Override public InventoryItem getSecondaryHandItem() { return secondary; }
        @Override public ItemContainer getInventory() { return inventory; }
        @Override public float getForwardDirectionX() { return 1; }
        @Override public float getForwardDirectionY() { return 0; }
        @Override public float getX() { return actualX; }
        @Override public float getY() { return actualY; }
        @Override public Vector2 getAnimForwardDirection(Vector2 out) { return out.set(1, 0); }
        @Override public Vector2 getInputMoveVector(Vector2 out) { return out.set(inputX,inputY); }
        @Override public boolean isJustMoved() { return moving; }
        @Override public void setTargetAndCurrentDirection(float x, float y) {}
        @Override public IAnimationVariableSlot setVariable(String name, boolean value) {
            if (name.equals("ToolkitCartPivot")) pivot = value;
            if (name.equals("ToolkitCartBrace")) brace = value;
            if (name.equals("ToolkitCartWoodBrake")) woodBrake = value;
            if (name.equals("ToolkitCartBrakeSprint")) brakeSprint = value;
            return null;
        }
        @Override public IAnimationVariableSlot setVariable(String name, float value) {
            if (name.equals("ToolkitCartStepX")) stepX = value;
            if (name.equals("ToolkitCartStepY")) stepY = value;
            if (name.equals("ToolkitCartLegPace")) legPace = value;
            return null;
        }
    }

    private static void type(InventoryContainer cart, String fullType) {
        int dot = fullType.indexOf('.');
        cart.setModule(fullType.substring(0, dot));
        cart.setType(fullType.substring(dot + 1));
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static Field field(Object object, String name) throws Exception {
        var field=object.getClass().getDeclaredField(name);field.setAccessible(true);return field;
    }

    private static void accept(Player player, Vector2 movement) {
        player.actualX+=movement.x;player.actualY+=movement.y;
        CartSteeringHooks.heading(player);
    }

    private static void releaseAfterNativeGaitReset(Player player, IsoPlayer.InputState input) {
        // IsoPlayer clears these flags before UpdateInputState, then finalizes the new gait afterward.
        player.run=player.sprint=false;player.inputX=player.inputY=0;
        input.setRunning(false);input.sprinting=false;
        CartSteeringHooks.input(player,input);
    }

    private static LiveAnimNode brakeAnimation(Player player) throws Exception {
        player.animator=new AdvancedAnimator();
        var layer=AnimLayer.alloc(player,player.animator);
        var root=AdvancedAnimator.class.getDeclaredField("rootLayer");root.setAccessible(true);root.set(player.animator,layer);
        var source=new AnimNode();source.name="ToolkitCartIdle";
        var node=LiveAnimNode.alloc(layer,source);
        var outgoing=new AnimNode();outgoing.name="ToolkitCartPivotSprint";
        var track=AnimationTrack.alloc();
        track.startClip(new AnimationClip(2,java.util.List.of(),"Bob_SprintToStop2h_Heavy",true),false,0);
        node.startTransitionIn(outgoing,new AnimTransition(),track);
        layer.getLiveAnimNodes().add(node);
        return node;
    }

    private static void adjacentBrakeRelease(Unsafe unsafe, Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();
        var time=GameTime.getInstance();float oldFps=time.fpsMultiplier;
        try {
            for(int fps:new int[]{30,60,144}) for(boolean sprint:new boolean[]{false,true})
                for(String order:new String[]{"together","modifier-first","modifier-delayed","direction-first","walk-on"}) {
                    time.fpsMultiplier=60f/fps;double dt=time.getRealworldSecondsSinceLastUpdate();
                    CartSteeringHooks.reset(player);player.actualX=player.actualY=0;
                    player.inputX=player.inputY=.5f;player.moving=true;player.run=player.sprint=false;
                    input.setRunning(!sprint);input.sprinting=sprint;
                    CartSteeringHooks.input(player,input);player.run=!sprint;player.sprint=sprint;
                    accept(player,CartSteeringHooks.movement(player,(float)(.2*dt),0));
                    Object state=states.get(player);
                    if(order.startsWith("modifier-") || order.equals("walk-on")) {
                        int frames=order.equals("modifier-delayed") && fps==144?4:1;
                        for(int frame=0;frame<frames;frame++) {
                            player.run=player.sprint=false;input.setRunning(false);input.sprinting=false;
                            CartSteeringHooks.input(player,input);
                            check(input.isRunning()==!sprint && input.sprinting==sprint,
                                "modifier-first must retain its native fast node within 50ms: "+fps+"/"+sprint+"/"+frame);
                            player.run=input.isRunning();player.sprint=input.sprinting;
                            accept(player,CartSteeringHooks.movement(player,(float)(.2*dt),0));
                        }
                        if(order.equals("walk-on")) {
                            double elapsed=dt;
                            do {
                                player.run=player.sprint=false;input.setRunning(false);input.sprinting=false;
                                CartSteeringHooks.input(player,input);elapsed+=dt;
                                check((input.isRunning() || input.sprinting)==(elapsed<=.05) && !player.woodBrake,
                                    "holding direction after modifier release must enter Walk after at most 50ms: "+fps+"/"+elapsed);
                                player.run=input.isRunning();player.sprint=input.sprinting;
                                accept(player,CartSteeringHooks.movement(player,(float)(.1*dt),0));
                            } while(input.isRunning() || input.sprinting);
                            releaseAfterNativeGaitReset(player,input);
                            check(!player.woodBrake,"a later deliberate Walk release must not replay the fast stop");
                            continue;
                        }
                    } else if(order.equals("direction-first")) {
                        player.run=player.sprint=false;player.inputX=player.inputY=0;
                        CartSteeringHooks.input(player,input);
                        check(player.woodBrake,"direction-first must arm the stop before releasing the modifier");
                        player.moving=false;player.run=!sprint;player.sprint=sprint;
                        accept(player,CartSteeringHooks.movement(player,(float)(.2*dt),0));
                    }
                    releaseAfterNativeGaitReset(player,input);player.moving=false;
                    check(player.woodBrake && field(state,"braking").getBoolean(state),
                        "both release orders and same-frame release must retain the native heavy stop: "+fps+"/"+sprint+"/"+order);
                    var step=CartSteeringHooks.movement(player,.3f,0);
                    check(Math.abs(step.getLength()-.2*dt)<1e-7,
                        "release order must preserve the last accepted speed cap");
                    accept(player,step);
                }
            time.fpsMultiplier=6;
            CartSteeringHooks.reset(player);player.actualX=player.actualY=0;
            player.inputX=player.inputY=.5f;player.moving=true;player.run=player.sprint=false;
            input.setRunning(true);input.sprinting=false;CartSteeringHooks.input(player,input);player.run=true;
            accept(player,CartSteeringHooks.movement(player,.02f,0));
            player.run=false;input.setRunning(false);CartSteeringHooks.input(player,input);
            check(!input.isRunning() && !input.sprinting,
                "a slow frame must not extend modifier release beyond the 50ms coalescing window");
        } finally {
            CartSteeringHooks.reset(player);time.fpsMultiplier=oldFps;
        }
    }

    private static void residualBrake(Unsafe unsafe, Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();
        var time=GameTime.getInstance();float oldFps=time.fpsMultiplier;
        try {
            for(int fps:new int[]{30,60,144}) for(boolean sprint:new boolean[]{false,true})
                for(double load:new double[]{0,1}) for(double lead:new double[]{.1,.3}) {
                    time.fpsMultiplier=60f/fps;double dt=time.getRealworldSecondsSinceLastUpdate();
                    CartSteeringHooks.reset(player);player.animator=null;
                    player.actualX=player.actualY=0;player.inputX=player.inputY=.5f;player.moving=true;
                    input.setRunning(!sprint);input.sprinting=sprint;CartSteeringHooks.input(player,input);
                    player.run=!sprint;player.sprint=sprint;
                    accept(player,CartSteeringHooks.movement(player,(float)(.8*dt),0));
                    Object state=states.get(player);
                    var pace=(CartLegPace.Ramp)field(state,"pace").get(state);pace.reset(.8);
                    for(double elapsed=0;elapsed<lead;elapsed+=dt) pace.update(.3,dt,load,true);
                    // A finalized native Walk node must retain the measured residual, without fast input injection.
                    field(state,"fastMoving").setBoolean(state,false);
                    field(state,"sprintMomentum").setBoolean(state,true);
                    field(state,"momentumSprint").setBoolean(state,sprint);
                    field(state,"fastPace").setDouble(state,.8);
                    field(state,"nativeSpeed").setDouble(state,pace.speed);
                    field(state,"actualDistance").setDouble(state,pace.speed*dt);
                    field(state,"load").setDouble(state,load);
                    double speed=pace.speed;
                    releaseAfterNativeGaitReset(player,input);
                    check(player.woodBrake && player.brakeSprint==sprint,
                        "brief finalized Walk must select the residual fast stop: "+fps+"/"+sprint+"/"+lead);
                    check(Math.abs(field(state,"brakeLimit").getDouble(state)-speed)<1e-7,
                        "braking must start from remaining speed, not the old fast speed");
                    var idle=brakeAnimation(player);player.moving=false;
                    CartSteeringHooks.heading(player);
                    double duration=.65+.35*speed/.8;
                    check(Math.abs(idle.getTransitionInTrack().getSpeedDelta()-1/duration)<1e-6,
                        "lower residual speed must shorten the authored stop without restarting full-speed inertia");
                    var step=CartSteeringHooks.movement(player,1,0);
                    check(Math.abs(step.getLength()-speed*dt)<1e-7,"stop root cannot accelerate the remaining motion");
                    CartSteeringHooks.reset(player);
                    check(!player.brakeSprint && !player.woodBrake,"reset must retire both stop selectors");
                }
        } finally { CartSteeringHooks.reset(player);time.fpsMultiplier=oldFps; }
    }

    private static void residualBrakeEdges(Unsafe unsafe, Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();
        double dt=GameTime.getInstance().getRealworldSecondsSinceLastUpdate();
        for(float slowdown:new float[]{0,.5f,.9f}) {
            CartSteeringHooks.reset(player);player.slowFactor=slowdown;
            player.inputX=player.inputY=.5f;player.moving=true;input.setRunning(true);input.sprinting=false;
            CartSteeringHooks.input(player,input);player.run=true;
            Vector2 step=CartSteeringHooks.movement(player,(float)(.8*dt),0);
            step.scale(1-slowdown);accept(player,step);
            releaseAfterNativeGaitReset(player,input);player.moving=false;
            step=CartSteeringHooks.movement(player,1,0);step.scale(1-slowdown);
            check(Math.abs(step.getLength()-.8*dt*(1-slowdown))<1e-7,
                "native slowdown must not be applied twice by the release cap: "+slowdown);
        }
        CartSteeringHooks.reset(player);player.slowFactor=0;player.actualX=player.actualY=0;
        player.inputX=player.inputY=.5f;player.moving=true;input.setRunning(true);CartSteeringHooks.input(player,input);
        player.run=true;accept(player,CartSteeringHooks.movement(player,(float)(.8*dt),0));
        Object state=states.get(player);var pace=(CartLegPace.Ramp)field(state,"pace").get(state);pace.reset(.8);
        releaseAfterNativeGaitReset(player,input);player.moving=false;
        brakeAnimation(player);CartSteeringHooks.heading(player);
        var clips=new HashMap<String,AnimationClip>();
        for(String name:new String[]{"Bob_Idle","Bob_Walk","Bob_Run"}) {
            var start=new Keyframe();var end=new Keyframe();start.boneName=end.boneName="Translation_Data";
            start.position=new Vector3f();end.position=new Vector3f(0,0,name.equals("Bob_Idle")?0:-1);end.time=1;
            clips.put(name,new AnimationClip(1,List.of(start,end),name,true));
        }
        var node=new AnimNode();node.name="ToolkitCartPivotRun";node.deferredBoneName="Translation_Data";node.deferredBoneAxis=BoneAxis.Y;
        for(float[] xy:new float[][]{{0,0},{0,1},{1,0}}) {
            var blend=new Anim2DBlend();blend.animName=xy[0]==0 && xy[1]==0?"Bob_Idle":"Bob_Run";
            blend.posX=xy[0];blend.posY=xy[1];node.blends2d.add(blend);
        }
        var triangle=new Anim2DBlendTriangle();triangle.node1=node.blends2d.get(0);triangle.node2=node.blends2d.get(1);triangle.node3=node.blends2d.get(2);
        node.blendTris.add(triangle);node.blend2dPicker=new Anim2DBlendPicker();node.blend2dPicker.SetPickTriangles(node.blendTris);
        player.animator.animSet=new AnimationSet();var run=new AnimState();run.nodes.add(node);player.animator.animSet.states.put("run",run);
        var mesh=(ModelMesh)unsafe.allocateInstance(ModelMesh.class);mesh.skinningData=new SkinningData(clips,List.of(),List.of(),List.of(),List.of(),new HashMap<>());
        var model=ModelManager.class.getDeclaredField("animModel");model.setAccessible(true);Object previous=model.get(ModelManager.instance);
        try {
            model.set(ModelManager.instance,mesh);
            pace.reset(.2);player.inputX=player.inputY=.5f;player.moving=true;input.setRunning(true);
            CartSteeringHooks.input(player,input);player.run=true;
            accept(player,CartSteeringHooks.movement(player,(float)(.2*dt),0));
            check(Float.isFinite(CartLegPace.targetSpeed(player,player.stepX,player.stepY)),"Run resume must use calibrated native clips");
            check(pace.speed>.2 && pace.speed<.5,"Run resume must accelerate from remaining stop speed through heading");
            pace.reset(.8);
            Vector2 partial=CartSteeringHooks.movement(player,.04f,0);
            field(state,"cartBlocked").setBoolean(state,true);partial.scale(.5f);
            accept(player,partial);
            check(pace.speed>.75,"partial wall contact must preserve the moving gait rather than reset its pace every frame");
            float contactStartX=player.actualX,contactStartY=player.actualY;
            player.actualX=10825.5f;player.actualY=10142.5f;pace.reset(.8);
            partial=CartSteeringHooks.movement(player,.04f,0);
            field(state,"cartBlocked").setBoolean(state,true);partial.set(Math.ulp(player.actualX),0);
            accept(player,partial);
            check(pace.speed>.75,"one representable world-coordinate step is movement, not a hard collision stop");
            player.actualX=contactStartX;player.actualY=contactStartY;
            float referenceSpeed=CartLegPace.targetSpeed(player,player.stepX,player.stepY);
            field(state,"wallHeading").setDouble(state,0);field(state,"wallNormalY").setDouble(state,1);
            field(state,"target").setDouble(state,Math.PI/4);pace.reset(referenceSpeed*Math.sqrt(.5));
            for(int frame=0;frame<4;frame++) {
                field(state,"hasInput").setBoolean(state,true);
                CartSteeringHooks.heading(player);
                check(Math.abs(pace.speed-referenceSpeed*Math.sqrt(.5))<1e-6,
                    "wall guidance must remove inward speed through cadence exactly once");
            }
            field(state,"wallHeading").setDouble(state,Double.NaN);field(state,"target").setDouble(state,0);
            var walkNode=new AnimNode();walkNode.name=CartLegPace.pivotName(cart.getFullType(),false,false);
            walkNode.deferredBoneName=node.deferredBoneName;walkNode.deferredBoneAxis=node.deferredBoneAxis;
            walkNode.blends2d.addAll(node.blends2d);walkNode.blendTris.addAll(node.blendTris);walkNode.blend2dPicker=node.blend2dPicker;
            var movement=new AnimState();movement.nodes.add(walkNode);player.animator.animSet.states.put("movement",movement);
            var outgoing=new AnimNode();outgoing.name="ToolkitCartPivotSprint";
            outgoing.deferredBoneName=node.deferredBoneName;outgoing.deferredBoneAxis=node.deferredBoneAxis;
            var live=LiveAnimNode.alloc(player.animator.getRootLayer(),outgoing);
            var outgoingTrack=AnimationTrack.alloc();outgoingTrack.startClip(clips.get("Bob_Walk"),true,0);
            outgoingTrack.setBlendFieldWeight(1);live.addMainTrack(outgoingTrack);
            player.animator.getRootLayer().getLiveAnimNodes().add(live);
            for(boolean fast:new boolean[]{false,true}) {
                field(state,"brace").setDouble(state,1);pace.reset(0);player.moving=false;player.stepY=0;
                double wheel=CartSteeringHooks.wheelPhase(player);
                input.setRunning(fast);CartSteeringHooks.input(player,input);player.run=fast;CartSteeringHooks.heading(player);
                check(player.stepY>0 && player.stepY<.2 && pace.speed>0,
                    "cleared obstruction must restore a native root budget even before accepted movement");
                float visualSpeed=field(state,"visualSpeed").getFloat(state);
                check(visualSpeed>0 && visualSpeed<pace.speed && Math.abs(visualSpeed-outgoingTrack.getSpeedDelta())<1e-6,
                    "brace snapshot must retain the actual outgoing native track budget, not its unscaled ramp");
                check(CartSteeringHooks.wheelPhase(player)==wheel,"query-only brace release must not spin the wheel");
                double previousSpeed=pace.speed;
                for(int frame=0;frame<90;frame++) {
                    input.setRunning(fast);CartSteeringHooks.input(player,input);player.run=fast;player.moving=true;
                    accept(player,CartSteeringHooks.movement(player,(float)(pace.speed*player.stepY*dt),0));
                    check(pace.speed>=previousSpeed-1e-7 && pace.speed-previousSpeed<.15,
                        "Walk/Run restart must retain its acceleration ramp when brace reaches zero: "+fast);
                    previousSpeed=pace.speed;
                }
                check(field(state,"brace").getDouble(state)==0 && Math.abs(player.stepY-(fast?1:.8))<1e-5,
                    "clear travel must leave bracing and recover a full stride");
            }
            field(state,"sprintMomentum").setBoolean(state,false);
            player.run=player.sprint=false;outgoingTrack.setSpeedDelta(.37f);
            CartSteeringHooks.input(player,input);CartSteeringHooks.heading(player);
            check(field(state,"visualSpeed").getFloat(state)==-1 && outgoingTrack.getSpeedDelta()==.37f,
                "ordinary calibrated Walk must leave outgoing native cadence without a root override");
            for(String kind:new String[]{"SaucedCarts.ShoppingCart","SaucedWheelbarrow.WheelbarrowMetal"}) {
                type(cart,kind);CartSteeringHooks.heading(player);state=states.get(player);
                check(field(state,"visualSpeed").getFloat(state)==-1,
                    "legacy cart cadence must not publish a synthetic root budget: "+kind);
            }
        } finally { CartSteeringHooks.reset(player);model.set(ModelManager.instance,previous); }
    }

    private static void slalomClearance(Unsafe unsafe, Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");
        CartSteeringHooks.input(player,new IsoPlayer.InputState());
        Object state=states.get(player),bank=field(state,"bank").get(state);
        double pressure=Math.toRadians(7),before=CartSteeringHooks.wheelPhase(player);
        field(bank,"pressure").setDouble(bank,pressure);
        check(CartSteeringHooks.lean(player)==0 && CartSteeringHooks.clearanceLean(player)==pressure,
            "neutral slalom bank must retain independent handle clearance");
        double travel=CartSteeringMath.woodenAxle((float)pressure,0)-CartSteeringMath.woodenAxle(0,0);
        check(Math.abs(CartSteeringHooks.wheelPhase(player)-CartWheelSpin.advance(before,travel))<1e-6,
            "wheel roll must follow retained cart clearance through neutral bank");
        field(state,"lean").setDouble(state,-pressure/2);
        check(CartSteeringHooks.lean(player)<0 && CartSteeringHooks.clearanceLean(player)==pressure,
            "opposite bank must not change the retained pressure into a signed offset");
        CartSteeringHooks.reset(player);
        check(CartSteeringHooks.clearanceLean(player)==0,"reset must retire slalom clearance");
    }

    private static void brakeControls(Unsafe unsafe, Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();
        var time=GameTime.getInstance();float oldFps=time.fpsMultiplier;
        try {
            for(int fps:new int[]{30,60,144}) {
                time.fpsMultiplier=60f/fps;
                double dt=time.getRealworldSecondsSinceLastUpdate();
                CartSteeringHooks.reset(player);type(cart,"SaucedWheelbarrow.WheelbarrowWood");
                player.actualX=player.actualY=0;player.inputX=player.inputY=.5f;
                player.moving=true;player.run=player.sprint=false;input.sprinting=true;
                CartSteeringHooks.input(player,input);
                player.sprint=true;
                accept(player,CartSteeringHooks.movement(player,(float)(.2*dt),0));
                double phase=CartSteeringHooks.wheelPhase(player);
                releaseAfterNativeGaitReset(player,input);
                Object state=states.get(player);
                check(!player.run && !player.sprint && player.woodBrake && field(state,"braking").getBoolean(state),
                    "native input-reset ordering must arm wooden braking from the last finalized fast gait: "+fps);
                player.moving=false;player.sprint=false;
                for(int tick=0;tick<3;tick++) {
                    Vector2 step=CartSteeringHooks.movement(player,.3f,0);
                    check(Math.abs(step.getLength()-.2*dt)<1e-7 && step.x>0 && Math.abs(step.y)<1e-7,
                        "heavy stop must retain release speed cap without accelerating or compounding it: "+fps+"/"+tick);
                    accept(player,step);
                }
                check(CartSteeringHooks.wheelPhase(player)<phase,"accepted no-input coasting must spin the wooden wheel");
                player.inputX=player.inputY=.5f;player.moving=true;
                CartSteeringHooks.input(player,input);
                check(!player.woodBrake && !field(state,"braking").getBoolean(state),
                    "new movement input must release the brake guard immediately");
                Vector2 resumed=CartSteeringHooks.movement(player,.03f,0);
                check(resumed.getLength()>.02,"new input must release the previous stop movement cap");
                accept(player,resumed);
                input.sprinting=true;CartSteeringHooks.input(player,input);player.sprint=true;
                accept(player,CartSteeringHooks.movement(player,.01f,0));
                releaseAfterNativeGaitReset(player,input);
                check(player.woodBrake,"second release must be eligible for an independent stop");
                for(int tick=0;tick<Math.ceil(.35/dt);tick++)CartSteeringHooks.heading(player);
                check(!player.woodBrake && !field(state,"braking").getBoolean(state),
                    "missing native stop clip must release the brake after its creation grace");
                CartSteeringHooks.reset(player);
                check(!player.woodBrake && !states.containsKey(player),"reset must clear armed braking and its variable");
            }
            time.fpsMultiplier=1;
            for(String event:new String[]{"resume","resume-full","blocked","replace","finish","reverse-rest-frame"}) {
                CartSteeringHooks.reset(player);player.animator=null;
                type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.primary=player.secondary=cart;
                cart.setItemContainer(null);
                if(event.equals("resume-full")) {
                    var contents=new ItemContainer();contents.setType("floor");contents.setCapacity(10);
                    var ballast=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);
                    ballast.setModule("Base");ballast.setType("Ballast");ballast.setName("Ballast");ballast.setActualWeight(10);
                    contents.getItems().add(ballast);cart.setItemContainer(contents);
                }
                player.actualX=player.actualY=0;player.inputX=player.inputY=.5f;
                player.moving=true;player.run=player.sprint=false;input.sprinting=true;
                CartSteeringHooks.input(player,input);
                player.sprint=true;
                accept(player,CartSteeringHooks.movement(player,.01f,0));
                Object state=states.get(player);
                var pace=(CartLegPace.Ramp)field(state,"pace").get(state);pace.reset(.4);
                var idle=brakeAnimation(player);var stop=idle.getTransitionInTrack();
                releaseAfterNativeGaitReset(player,input);
                player.sprint=false;player.moving=false;
                for(int tick=0;tick<40;tick++)CartSteeringHooks.heading(player);
                check(player.woodBrake && CartSteeringHooks.fastPoseWeight(player)==1,
                    "live native stop must retain grip clearance beyond the old .4s tail");
                check(Math.abs(stop.getSpeedDelta()-(event.equals("resume-full")?1/1.12:1))<1e-6,
                    "full cargo must settle 12 percent longer while retaining the authored stop sequence");
                if(event.startsWith("resume")) {
                    accept(player,CartSteeringHooks.movement(player,.005f,0));
                    check(Math.abs(pace.speed-.2)<1e-6,"coasting root must seed resumed Sprint pace instead of resetting it to zero");
                    float phase=stop.getCurrentTimeValue(),cadence=stop.getSpeedDelta();
                    player.inputX=player.inputY=.5f;player.moving=true;CartSteeringHooks.input(player,input);
                    check(idle.getTransitionInTrack()==stop && stop.getUseDeferredMovement(),
                        "resume must retain native stop root and pose throughout its visual fade");
                    check(stop.getCurrentTimeValue()==phase && stop.getSpeedDelta()==cadence,
                        "resume must retain the authored stop phase and cadence");
                    Vector2 capped=CartSteeringHooks.movement(player,.05f,0);
                    check(Math.abs(capped.getLength()-.01)<1e-7,"native visual fade must retain the release-speed cap after braking ends");
                    accept(player,capped);
                    idle.stopTransitionIn();
                    Vector2 released=CartSteeringHooks.movement(player,.05f,0);
                    check(released.getLength()>.04,"completed native fade must release the old brake cap");
                    accept(player,released);
                } else if(event.equals("blocked")) {
                    CartSteeringHooks.movement(player,.05f,0);
                    CartSteeringHooks.heading(player);
                    check(!stop.getUseDeferredMovement(),"blocked collision must disable stop root without replaying its budget");
                } else if(event.equals("replace")) {
                    var replacement=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
                    type(replacement,"SaucedWheelbarrow.WheelbarrowMetal");replacement.setContainer(player.inventory);
                    player.primary=player.secondary=replacement;CartSteeringHooks.input(player,input);
                    check(idle.getTransitionInTrack()==null,"wood-to-metal identity change must hard-clean the old native stop");
                } else if(event.equals("finish")) {
                    idle.stopTransitionIn();CartSteeringHooks.heading(player);
                    check(!field(states.get(player),"braking").getBoolean(states.get(player)),
                        "a completed native transition must release the cart brake state");
                } else {
                    pace.reset(0);field(state,"actualDistance").setDouble(state,0);
                    player.inputX=player.inputY=-.5f;player.moving=true;input.setRunning(true);input.sprinting=true;
                    CartSteeringHooks.input(player,input);
                    var reversal=(CartSteeringMath.Reversal)field(state,"reversal").get(state);
                    check(reversal.active && reversal.braking && reversal.direction==1 && reversal.requested==-1,
                        "zero root frame inside a live stop must not bypass the reversal neutral phase");
                    check(!input.isRunning() && !input.sprinting,"rest-frame reverse must still clamp fast input");
                    Vector2 forward=CartSteeringHooks.movement(player,.05f,0);
                    check(forward.x>0 && Math.abs(forward.y)<1e-7,
                        "remaining stop root must keep the old forward direction until reversal actually settles");
                    accept(player,forward);
                }
                check(!player.woodBrake,"stop cancellation must clear the XML selection guard: "+event);
                CartSteeringHooks.reset(player);
                check(idle.getTransitionInTrack()==null,"reset must hard-clean any visual stop tail");
                player.primary=player.secondary=cart;player.animator=null;
            }
            cart.setItemContainer(null);
            for(String[] entry:new String[][]{{"SaucedWheelbarrow.WheelbarrowWood","walk"},
                {"SaucedWheelbarrow.WheelbarrowWood","run"},{"SaucedWheelbarrow.WheelbarrowMetal","sprint"},
                {"SaucedCarts.ShoppingCart","sprint"}}) {
                String kind=entry[0],gait=entry[1];type(cart,kind);player.inputX=player.inputY=.5f;
                player.moving=true;player.run=player.sprint=false;
                input.setRunning(gait.equals("run"));input.sprinting=gait.equals("sprint");
                CartSteeringHooks.input(player,input);player.run=gait.equals("run");player.sprint=gait.equals("sprint");
                accept(player,CartSteeringHooks.movement(player,.02f,0));
                releaseAfterNativeGaitReset(player,input);
                check(player.woodBrake==(kind.startsWith("SaucedWheelbarrow.") && !gait.equals("walk")),
                    "only finalized fast wheelbarrow movement can arm a stop after the native flags reset: "+kind+"/"+gait);
                CartSteeringHooks.reset(player);
            }
        } finally {
            CartSteeringHooks.reset(player);time.fpsMultiplier=oldFps;
        }
    }

    private static void pathControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;
        player.nativePath=new zombie.pathfind.PathFindBehavior2(player);
        player.finder=new zombie.ai.astar.AStarPathFinderResult();
        var input=new IsoPlayer.InputState();
        CartSteeringHooks.heading(player);
        Object manual=states.get(player);
        check(field(manual,"visualSpeed").getFloat(manual)==-1,
            "missing native clips must leave cadence without a root override");
        field(manual,"braking").setBoolean(manual,true);
        field(manual,"stationaryRoot").setBoolean(manual,true);
        player.brace=true;
        var reversal=(CartSteeringMath.Reversal)field(manual,"reversal").get(manual);
        reversal.request(-1,false);
        player.pathActive=true;player.inputX=-.5f;player.inputY=.5f;
        input.setRunning(true);input.sprinting=true;
        CartSteeringHooks.input(player,input);
        Object path=states.get(player);
        check(path!=manual && field(path,"path").getBoolean(path)
            && !field(path,"braking").getBoolean(path) && !field(path,"stationaryRoot").getBoolean(path),
            "native path must discard manual brake, stationary turn and reversal state");
        check(!player.brace,"native path handoff retained a manual effort stance");
        check(input.isRunning() && input.sprinting && !field(path,"hasInput").getBoolean(path),
            "path mode must leave native gait untouched and ignore keyboard steering");
        player.moving=true;
        field(path,"visualSpeed").setFloat(path,.7f);
        var step=CartSteeringHooks.movement(player,.02f,0);
        check(step.x>.019 && Math.abs(step.y)<1e-6,"native path delta must own intent despite opposing keyboard input");
        accept(player,step);
        double before=field(path,"heading").getDouble(path);
        step=CartSteeringHooks.movement(player,0,.02f);
        check(step.x==0 && step.y==.02f,"native path must preserve its exact world delta instead of creating a pursuit arc");
        accept(player,step);
        check(field(path,"heading").getDouble(path)==before && !player.pivot && player.legPace==0,
            "path following must retain native yaw/cadence and leave manual pivot variables released");
        check(field(path,"visualSpeed").getFloat(path)==-1,"native path must release the prior root override");
        for(double gx:new double[]{-2,0,2}) for(double gy:new double[]{-2,0,2}) {
            player.actualX=player.actualY=0;
            for(int tick=0;tick<500 && Math.hypot(gx-player.actualX,gy-player.actualY)>.01;tick++) {
                double dx=gx-player.actualX,dy=gy-player.actualY,distance=Math.hypot(dx,dy);
                double budget=Math.min(.02,distance);
                step=CartSteeringHooks.movement(player,(float)(dx/distance*budget),(float)(dy/distance*budget));
                accept(player,step);
            }
            check(Math.hypot(gx-player.actualX,gy-player.actualY)<.01,
                "native route endpoint convergence must survive every open-space target direction: "+gx+"/"+gy);
        }
        CartSteeringHooks.beginPath(player);
        field(path,"cartBlocked").setBoolean(path,true);
        check(CartSteeringHooks.pathResult(player,zombie.pathfind.PathFindBehavior2.BehaviorResult.Succeeded)
            ==zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed,
            "native same-call success must not bypass a cart-blocked step");
        check(player.finder.progress==zombie.ai.astar.AStarPathFinder.PathFindProgress.failed,
            "cart obstruction must reach native Failed, not silently cancel a waiting queue");
        CartSteeringHooks.beginPath(player);
        check(CartSteeringHooks.pathResult(player,zombie.pathfind.PathFindBehavior2.BehaviorResult.Working)
            ==zombie.pathfind.PathFindBehavior2.BehaviorResult.Working,"new native update must release old per-call obstruction");
        type(cart,"SaucedWheelbarrow.WheelbarrowMetal");
        check(CartSteeringHooks.enabled(player),"metal native path lost wheelbarrow clearance");
        for(String kind:new String[]{"SaucedCarts.ShoppingCart"}) {
            type(cart,kind);check(!CartSteeringHooks.enabled(player),
                "other carts must retain native path behavior: "+kind);
        }
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.npc=true;
        check(!CartSteeringHooks.enabled(player),"NPC movement must remain native");player.npc=false;
        player.blocked=8;check(!CartSteeringHooks.enabled(player),"remote path must remain native");player.blocked=0;
        player.pathActive=false;player.nativePath.cancel();
        field(path,"pending").setBoolean(path,true);
        CartSteeringHooks.input(player,input);
        check(states.get(player)==path,"same-call path stop must retain its last pending collision acceptance");
        CartSteeringHooks.heading(player);CartSteeringHooks.input(player,input);
        check(states.get(player)!=path && !field(states.get(player),"path").getBoolean(states.get(player)),
            "path cancellation must discard native target and restore fresh manual input ownership");
        CartSteeringHooks.reset(player);
    }

    private static void wovenPathControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        Main.main(new String[0]);
        check(Main.CART_SUPPORTED,"woven path regression requires the supported native fingerprint");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",
            CartSteeringHooksTest.class.getClassLoader());
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;player.pathActive=true;
        player.nativePath=new zombie.pathfind.PathFindBehavior2(player);
        player.finder=new zombie.ai.astar.AStarPathFinderResult();
        player.finder.progress=zombie.ai.astar.AStarPathFinder.PathFindProgress.failed;
        check(player.nativePath.update()==zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed,
            "real woven update() must reach both public path advice hooks without an access error");
        Object state=states.get(player);
        check(state!=null && field(state,"path").getBoolean(state),
            "real woven path entry must acquire the local wooden cart state");
        field(state,"cartBlocked").setBoolean(state,true);
        check(player.nativePath.update(1)==zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed
            && !field(state,"cartBlocked").getBoolean(state),
            "real woven update(float) must reset per-call obstruction and preserve native failure");
        CartSteeringHooks.reset(player);player.blocked=8;
        check(player.nativePath.update()==zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed
            && player.nativePath.update(1)==zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed
            && !states.containsKey(player),"woven path advice must leave remote native failure/state untouched");
    }

    private static void wovenProtectedControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;player.reqMovement=new Vector2();
        CartWheelSpin.record(cart,0,0,0,new org.joml.Matrix4f().scale(76.5f),.7);
        var heading=zombie.characters.IsoGameCharacter.class.getDeclaredMethod("postUpdateAnimating");
        heading.setAccessible(true);heading.invoke(player);
        Object previous=states.get(player);
        check(previous!=null && player.pivot,"woven heading must acquire the held cart before impact");
        field(previous,"brace").setDouble(previous,1);
        player.stepX=player.stepY=.5f;player.legPace=1;player.woodBrake=player.brakeSprint=true;
        var current=field(player.getStateMachine(),"currentState");
        player.animationUpdate=()-> {
            try {current.set(player.getStateMachine(),zombie.ai.states.CollideWithWallState.instance());}
            catch(IllegalAccessException error) {throw new AssertionError(error);}
        };
        heading.invoke(player);player.animationUpdate=null;
        check(!states.containsKey(player) && !player.pivot && player.stepX==0 && player.stepY==0
            && player.legPace==0 && !player.woodBrake && !player.brakeSprint,
            "woven exit must clear cart variables when native animation enters collision after the entry hook");
        for(var state:List.of(zombie.ai.states.CollideWithWallState.instance(),zombie.ai.states.PlayerGetUpState.instance())) {
            current.set(player.getStateMachine(),state);
            check(!CartSteeringHooks.enabled(player),"native collision/getup states must retain animation ownership");
            check(!player.hasHitReaction() && !player.isKnockedDown() && !player.isRagdollSimulationActive(),
                "collision/getup regression must exercise the explicit native state guards");
            player.setNextX(0);player.setNextY(0);player.moveUnmodded(.02f,-.01f);
            check(player.reqMovement.x==.02f && player.reqMovement.y==-.01f
                && player.getNextX()==.02f && player.getNextY()==-.01f,
                "woven movement must preserve the native collision/getup root vector");
            heading.invoke(player);
            check(!states.containsKey(player) && !player.pivot && player.stepX==0 && player.stepY==0
                && player.legPace==0 && !player.woodBrake && !player.brakeSprint,
                "woven heading must release cart steering and brake variables during native recovery");
            check(Double.isNaN(CartSteeringHooks.wheelPhase(player)),"native recovery must suspend held wheel preparation");
        }
        current.set(player.getStateMachine(),null);heading.invoke(player);
        Object resumed=states.get(player);
        check(CartSteeringHooks.enabled(player) && resumed!=null && resumed!=previous && player.pivot
            && field(resumed,"brace").getDouble(resumed)==0 && !field(resumed,"pending").getBoolean(resumed),
            "native recovery exit must acquire fresh steering without the old brace or pending step");
        check(Math.abs(CartSteeringHooks.wheelPhase(player)-.7)<1e-6,
            "native recovery must retain the same cart item's recorded wheel phase");
        CartSteeringHooks.finish(player);
        check(states.get(player)==resumed,"eligible frame exit must preserve the existing cart state");
        CartSteeringHooks.reset(player);
        player.stepX=.25f;CartSteeringHooks.finish(player);
        check(player.stepX==.25f && !states.containsKey(player),"unowned frame exit must not clear presentation variables");
    }

    private static void direction(Player player,double heading) {
        player.inputX=(float)((Math.cos(heading)-Math.sin(heading))/2);
        player.inputY=(float)((Math.cos(heading)+Math.sin(heading))/2);
    }

    private static void keyboardControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        player.keyboard=true;player.keys=new Keys();player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();var time=GameTime.getInstance();float old=time.fpsMultiplier;
        try {
            time.fpsMultiplier=1;
            for(String kind:new String[]{"SaucedCarts.ShoppingCart","SaucedWheelbarrow.WheelbarrowWood",
                    "SaucedWheelbarrow.WheelbarrowMetal"}) {
                type(cart,kind);
                for(double initial:new double[]{0,.7,-2.4}) for(int travel:new int[]{-1,0,1}) for(int sign:new int[]{-1,0,1}) {
                    CartSteeringHooks.reset(player);player.actualX=player.actualY=0;player.moving=false;
                    player.keys.set(travel,sign);CartSteeringHooks.heading(player);
                    Object state=states.get(player);field(state,"heading").setDouble(state,initial);
                    Vector2 move=CartSteeringHooks.keyboardMovement(player,new Vector2(0,-1.95f));
                    if(travel==0 && sign==0) {
                        check(move.getLengthSquared()==0,"idle keyboard has no native movement intent");
                        continue;
                    }
                    double desired=CartSteeringMath.keyboardTarget(initial,travel,sign);
                    check(Math.abs(CartSteeringMath.wrap(Math.atan2(move.y-move.x,move.y+move.x)-desired))<1e-6,
                        "native movement must follow relative keyboard intent: "+kind+"/"+travel+"/"+sign);
                    check(Math.abs(move.getLength()-1.95)<1e-6,"relative keys retain the native input magnitude");
                    input.setRunning(true);input.sprinting=true;CartSteeringHooks.input(player,input);
                    if(travel<=0) check(!input.isRunning() && !input.sprinting,"reverse and pivot must use walking: "+kind);
                    player.moving=true;CartSteeringHooks.heading(player);
                    CartSteeringHooks.movement(player,.02f,0);CartSteeringHooks.heading(player);
                    check(field(state,"heading").getDouble(state)==initial,
                        "native refused keyboard movement must not rotate the cart");
                    double turned=0;
                    for(int frame=0;frame<360;frame++) {
                        CartSteeringHooks.input(player,input);
                        double before=field(state,"heading").getDouble(state);
                        Vector2 step=CartSteeringHooks.movement(player,.02f,0);
                        check(step.getLength()<=.020001,"keyboard cannot invent a native stride budget");
                        if(travel!=0) {
                            double forward=step.x*Math.cos(before)+step.y*Math.sin(before);
                            check(forward*travel>0,"forward/reverse travel sign must remain explicit: "+kind+"/"+travel+"/"+sign);
                        }
                        accept(player,step);
                        turned+=CartSteeringMath.wrap(field(state,"heading").getDouble(state)-before);
                    }
                    int yaw=sign*(travel<0?-1:1);
                    check(sign==0?Math.abs(turned)<1e-5:turned*yaw>Math.PI,
                        "held steering must keep turning beyond a fixed world direction: "+kind+"/"+travel+"/"+sign+"/"+turned);
                    player.keys.set(travel,0);CartSteeringHooks.input(player,input);
                    if(travel==0) player.moving=false;
                    double before=field(state,"heading").getDouble(state);
                    accept(player,CartSteeringHooks.movement(player,.02f,0));
                    double after=field(state,"heading").getDouble(state);
                    check(Math.abs(CartSteeringMath.wrap(after-before))<.03,"steering release must settle without a world-direction snap");
                    if(travel==0) check(player.stepX==0 && player.stepY==0,"released pivot must return to idle");
                }
                player.keys.forward=player.keys.backward=player.keys.left=player.keys.right=true;
                check(CartSteeringHooks.keyboardMovement(player,new Vector2(0,-1.95f)).getLengthSquared()==0,
                    "opposite keys cancel instead of inheriting native key priority");
                CartSteeringHooks.input(player,input);
                check(!field(states.get(player),"wantsMove").getBoolean(states.get(player)),"opposite keys release cart intent");
                player.keys.set(1,1);
                for(String gate:new String[]{"controller","aim","autowalk","path","remote","disabled"}) {
                    player.keyboard=!gate.equals("controller");player.aim=gate.equals("aim");player.pathActive=gate.equals("path");
                    player.autoWalk=gate.equals("autowalk");
                    player.blocked=gate.equals("remote")?8:gate.equals("disabled")?10:0;
                    Vector2 original=new Vector2(.3f,-.4f);
                    check(CartSteeringHooks.keyboardMovement(player,original)==original && original.x==.3f && original.y==-.4f,
                        "relative keyboard must leave native input untouched: "+gate);
                }
                player.keyboard=true;player.aim=player.autoWalk=player.pathActive=false;player.blocked=0;
            }
        } finally {CartSteeringHooks.reset(player);time.fpsMultiplier=old;}
    }

    private static void keyboardReleaseControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.keyboard=true;player.keys=new Keys();player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();var time=GameTime.getInstance();float old=time.fpsMultiplier;
        try {
            for(int fps:new int[]{30,60,144}) for(int travel:new int[]{-1,0,1}) for(int sign:new int[]{-1,1})
                for(boolean opposite:new boolean[]{false,true}) {
                    time.fpsMultiplier=60f/fps;CartSteeringHooks.reset(player);
                    player.actualX=player.actualY=0;player.moving=true;player.keys.set(travel,sign);
                    CartSteeringHooks.input(player,input);
                    Object state=states.get(player);
                    // Native animation may plan several frames between fresh input callbacks.
                    for(int frame=0;frame<fps;frame++) accept(player,CartSteeringHooks.movement(player,.02f,0));
                    double before=field(state,"heading").getDouble(state),lean=CartSteeringHooks.lean(player);
                    check(Math.abs(before)>.1,"held relative steering must survive sparse native input updates");
                    player.keys.set(travel,0);
                    if(opposite) player.keys.left=player.keys.right=true;
                    for(int frame=0;frame<fps/2;frame++) {
                        accept(player,CartSteeringHooks.movement(player,.02f,0));
                        check(Math.abs(CartSteeringMath.wrap(field(state,"heading").getDouble(state)-before))<1e-5,
                            "released/cancelled relative steering retained accepted yaw: "+fps+"/"+travel+"/"+sign+"/"+opposite);
                        if(frame==0 && travel!=0 && Math.abs(lean)>1e-6)
                            check(Math.abs(CartSteeringHooks.lean(player))>0 && Math.abs(CartSteeringHooks.lean(player))<Math.abs(lean),
                                "keyboard yaw release must preserve the smooth bank return");
                    }
                }
            CartSteeringHooks.reset(player);player.keyboard=false;player.inputX=player.inputY=.5f;
            CartSteeringHooks.input(player,input);
            Object state=states.get(player);field(state,"turnRate").setDouble(state,1);
            field(state,"target").setDouble(state,-.01);
            CartSteeringHooks.movement(player,.02f,0);
            var requested=(CartSteeringMath.Step)field(state,"requested").get(state);
            check(requested.turn()>0,"absolute/gamepad steering must retain its existing angular smoothing");
        } finally {CartSteeringHooks.reset(player);time.fpsMultiplier=old;}
    }

    private static void keyboardWorldReleaseControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.keyboard=true;player.keys=new Keys();player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();var time=GameTime.getInstance();float old=time.fpsMultiplier;
        try {
            time.fpsMultiplier=1;
            for(float origin:new float[]{8192,10825.5f,16384}) for(double initial:new double[]{-.7,.7,-1.3,1.3})
                for(float budget:new float[]{.002f,.005f,.02f}) {
                    CartSteeringHooks.reset(player);player.actualX=player.actualY=origin;
                    player.moving=true;player.keys.set(-1,1);CartSteeringHooks.input(player,input);
                    Object state=states.get(player);field(state,"heading").setDouble(state,initial);
                    field(state,"turnRate").setDouble(state,-1);
                    // Release steering between input callbacks, retaining deliberate reverse travel.
                    player.keys.set(-1,0);
                    for(int frame=0;frame<240;frame++) {
                        Vector2 step=CartSteeringHooks.movement(player,budget,0);
                        check(step.getLength()<=budget+1e-7,"released reverse cannot invent a native stride budget");
                        accept(player,step);
                        double drift=Math.abs(CartSteeringMath.wrap(field(state,"heading").getDouble(state)-initial));
                        check(drift<=.025,"released reverse must retain yaw at native world precision: "
                            +origin+"/"+initial+"/"+budget+"/"+frame+" drift="+drift);
                    }
                    check(Math.hypot(player.actualX-origin,player.actualY-origin)>budget*100,
                        "yaw stability must preserve deliberate reverse progress");
                }
            // Collision-displaced analog movement retains its existing rolling-yaw contract.
            for(String gate:new String[]{"controller","aim","autowalk"}) {
                CartSteeringHooks.reset(player);player.keyboard=!gate.equals("controller");
                player.aim=gate.equals("aim");player.autoWalk=gate.equals("autowalk");
                player.actualX=player.actualY=10825.5f;player.moving=true;player.keys.set(-1,0);
                CartSteeringHooks.heading(player);Object state=states.get(player);
                double initial=.7;field(state,"heading").setDouble(state,initial);
                direction(player,initial);CartSteeringHooks.input(player,input);
                double axle=CartSteeringMath.woodenAxle((float)CartSteeringHooks.clearanceLean(player),
                    CartLegPace.woodenGaitShift(player));
                CartSteeringHooks.movement(player,.02f,0);
                float x=player.actualX,y=player.actualY;
                player.actualX+=.015f;player.actualY+=.003f;
                double expected=CartSteeringMath.acceptedTurn(initial,axle,player.actualX-x,player.actualY-y);
                CartSteeringHooks.heading(player);
                check(Math.abs(CartSteeringMath.wrap(field(state,"heading").getDouble(state)-initial)-expected)<1e-9,
                    "relative release correction must retain native collision yaw for "+gate);
            }
        } finally {CartSteeringHooks.reset(player);time.fpsMultiplier=old;}
    }

    private static void stationaryControls(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;
        var input=new IsoPlayer.InputState();var time=GameTime.getInstance();float old=time.fpsMultiplier;
        try {
            for(int fps:new int[]{30,60,144}) for(int sign:new int[]{-1,1}) {
                time.fpsMultiplier=60f/fps;
                CartSteeringHooks.reset(player);player.moving=false;player.inputX=player.inputY=0;
                player.actualX=player.actualY=0;CartSteeringHooks.heading(player);
                Object state=states.get(player);direction(player,sign*Math.PI/2);
                input.setRunning(true);input.sprinting=true;CartSteeringHooks.input(player,input);
                check(field(state,"stationary").getBoolean(state) && !input.isRunning() && !input.sprinting,
                    "side input from rest must select walking-only stationary turn");
                player.moving=true;CartSteeringHooks.heading(player);
                check(sign*player.stepX<0 && player.stepY==0,"stationary bootstrap must select a native pure lateral step");
                // Native collision refuses a whole step: yaw and wheel phase must remain unchanged.
                CartSteeringHooks.movement(player,.02f,0);CartSteeringHooks.heading(player);
                check(field(state,"heading").getDouble(state)==0 && CartSteeringHooks.wheelPhase(player)==0,
                    "blocked stationary movement cannot rotate or spin the cart");
                for(int frame=0;frame<fps*4 && field(state,"stationary").getBoolean(state);frame++) {
                    CartSteeringHooks.input(player,input);
                    accept(player,CartSteeringHooks.movement(player,(float)(1.1/fps),0));
                    double h=field(state,"heading").getDouble(state);
                    check(Math.hypot(player.actualX+1.0084944326*Math.cos(h)-1.0084944326,
                        player.actualY+1.0084944326*Math.sin(h))<1e-5,"accepted stationary steps must orbit the front axle");
                }
                check(!field(state,"stationary").getBoolean(state),"held side input must complete the turn");
                check(Math.abs(CartSteeringMath.wrap(field(state,"heading").getDouble(state)-sign*Math.PI/2))<Math.toRadians(.5),
                    "stationary exit must face the requested direction");
                input.setRunning(true);input.sprinting=true;CartSteeringHooks.input(player,input);
                check(input.isRunning() && input.sprinting,"aligned exit must release native fast-gait input");
                var forward=CartSteeringHooks.movement(player,.02f,0);
                check(Math.hypot(forward.x,forward.y)>.019,"held input must resume rolling after the pivot");
                accept(player,forward);
                // A new side input while already moving remains the existing rolling arc.
                direction(player,0);CartSteeringHooks.input(player,input);
                check(!field(state,"stationary").getBoolean(state),"moving turns must not park the wheel");
                CartSteeringHooks.reset(player);player.moving=false;direction(player,sign*Math.PI/2);
                CartSteeringHooks.input(player,input);player.moving=true;CartSteeringHooks.heading(player);
                accept(player,CartSteeringHooks.movement(player,.02f,0));
                player.inputX=player.inputY=0;CartSteeringHooks.input(player,input);player.moving=false;
                double before=field(states.get(player),"heading").getDouble(states.get(player));
                var tail=CartSteeringHooks.movement(player,.02f,0);
                check(tail.getLength()==0,"released strafe root must not become an unwanted forward step");
                accept(player,tail);
                check(field(states.get(player),"heading").getDouble(states.get(player))==before && player.stepX==0 && player.stepY==0,
                    "released stationary turn must return to planted idle");
                direction(player,before+Math.PI);CartSteeringHooks.input(player,input);
                var reverse=CartSteeringHooks.movement(player,.02f,0);
                check(reverse.x*Math.cos(before)+reverse.y*Math.sin(before)<-.019,
                    "backward input after release must preserve existing reverse travel");
                accept(player,reverse);
            }
        } finally {CartSteeringHooks.reset(player);time.fpsMultiplier=old;}
    }

    private static double nativeBudget(Player player, AnimNode node, Map<String,AnimationClip> clips, double dt) {
        var pick=node.blend2dPicker.Pick(player.stepX,player.stepY,new Anim2DBlendPicker.PickResults());
        double rootX=0,rootY=0;
        for(int i=0;i<pick.numNodes;i++) {
            var blend=i==0?pick.node1:i==1?pick.node2:pick.node3;
            float weight=i==0?pick.scale1:i==1?pick.scale2:pick.scale3;
            if(weight<1e-4f) continue;
            var clip=clips.get(blend.animName);
            var root=clip.getTotalTranslation("Translation_Data",BoneAxis.Y,new Vector2());
            rootX+=Math.min(1,weight)*root.x/clip.getDuration();rootY+=Math.min(1,weight)*root.y/clip.getDuration();
        }
        return player.legPace*Math.hypot(rootX,rootY)*dt;
    }

    private static Object nativeStart(Player player, Map<?,?> states, IsoPlayer.InputState input, double target) throws Exception {
        CartSteeringHooks.reset(player);player.moving=false;player.inputX=player.inputY=0;
        player.actualX=10825.5f;player.actualY=10142.5f;CartSteeringHooks.heading(player);
        Object state=states.get(player);double initial=Math.PI/4;
        field(state,"heading").setDouble(state,initial);field(state,"target").setDouble(state,initial);
        direction(player,target);CartSteeringHooks.input(player,input);player.moving=true;CartSteeringHooks.heading(player);
        return state;
    }

    private static void nativeFrame(Player player, IsoPlayer.InputState input, AnimNode node,
                                    Map<String,AnimationClip> clips, double dt) {
        CartSteeringHooks.input(player,input);
        check(Float.isFinite(CartLegPace.targetSpeed(player,player.stepX,player.stepY)),
            "direction transitions must retain native clip calibration");
        double budget=nativeBudget(player,node,clips,dt);
        var step=CartSteeringHooks.movement(player,(float)budget,0);
        check(step.getLength()<=budget+1e-7,"direction transitions cannot invent native root distance");
        accept(player,step);
    }

    private static void nativeDirectionChanges(Player player, Map<?,?> states, IsoPlayer.InputState input,
                                                AnimNode node, Map<String,AnimationClip> clips) throws Exception {
        double initial=Math.PI/4;
        for(float walkSpeed:new float[]{.56f,.3575f}) for(int fps:new int[]{30,60,144}) for(int sign:new int[]{-1,1}) {
            player.walkSpeed=walkSpeed;GameTime.getInstance().fpsMultiplier=60f/fps;
            double dt=GameTime.getInstance().getRealworldSecondsSinceLastUpdate();
            String context=fps+"/"+sign+"/"+walkSpeed;
            Object state=nativeStart(player,states,input,initial+sign*Math.PI/2);
            for(int frame=0;frame<fps/3;frame++) nativeFrame(player,input,node,clips,dt);
            double halfway=field(state,"heading").getDouble(state);
            check(sign*CartSteeringMath.wrap(halfway-initial)>0,"mid-turn fixture must actually turn: "+context);
            direction(player,initial-sign*Math.PI/2);
            boolean changed=false;
            for(int frame=0;frame<fps*6 && field(state,"stationary").getBoolean(state);frame++) {
                nativeFrame(player,input,node,clips,dt);
                if(Math.signum(player.stepX)==sign) changed=true;
                if(field(state,"stationary").getBoolean(state))
                    check(Math.abs(player.stepX)==1 && player.stepY==0,"mid-turn changes must retain full lateral strides: "+context);
            }
            check(changed && !field(state,"stationary").getBoolean(state)
                && Math.abs(CartSteeringMath.wrap(initial-sign*Math.PI/2-field(state,"heading").getDouble(state)))<Math.toRadians(.5),
                "left/right mid-turn change must finish at the new heading: "+context);

            state=nativeStart(player,states,input,initial+sign*Math.PI/2);
            for(int frame=0;frame<fps/3;frame++) nativeFrame(player,input,node,clips,dt);
            player.inputX=player.inputY=0;CartSteeringHooks.input(player,input);player.moving=false;
            double released=field(state,"heading").getDouble(state);
            for(int frame=0;frame<fps/4;frame++) nativeFrame(player,input,node,clips,dt);
            check(field(state,"heading").getDouble(state)==released && player.stepX==0 && player.stepY==0,
                "released native strafe must stay planted: "+context);
            direction(player,released+sign*Math.PI/2);CartSteeringHooks.input(player,input);
            player.moving=true;CartSteeringHooks.heading(player);
            check(field(state,"stationary").getBoolean(state),"restart must reacquire a stationary turn: "+context);
            for(int frame=0;frame<fps*6 && field(state,"stationary").getBoolean(state);frame++) nativeFrame(player,input,node,clips,dt);
            check(!field(state,"stationary").getBoolean(state)
                && Math.abs(CartSteeringMath.wrap(released+sign*Math.PI/2-field(state,"heading").getDouble(state)))<Math.toRadians(.5),
                "released turn must restart and finish with native root: "+context);

            state=nativeStart(player,states,input,initial+sign*Math.PI/2);
            for(int quarter=1;quarter<=2;quarter++) {
                for(int frame=0;frame<fps*6 && field(state,"stationary").getBoolean(state);frame++) nativeFrame(player,input,node,clips,dt);
                check(!field(state,"stationary").getBoolean(state)
                    && Math.abs(CartSteeringMath.wrap(initial+sign*quarter*Math.PI/2-field(state,"heading").getDouble(state)))<Math.toRadians(.5),
                    "two native quarter-turns must reach 180 degrees: "+context+"/"+quarter);
                player.inputX=player.inputY=0;CartSteeringHooks.input(player,input);player.moving=false;CartSteeringHooks.heading(player);
                if(quarter==1) {
                    direction(player,initial+sign*Math.PI);CartSteeringHooks.input(player,input);
                    player.moving=true;CartSteeringHooks.heading(player);
                    check(field(state,"stationary").getBoolean(state),"second quarter-turn must pivot from rest: "+context);
                }
            }

            state=nativeStart(player,states,input,initial+sign*Math.PI/2);
            for(int frame=0;frame<fps/3;frame++) nativeFrame(player,input,node,clips,dt);
            double pivotHeading=field(state,"heading").getDouble(state);
            direction(player,pivotHeading+Math.PI);
            var reversal=(CartSteeringMath.Reversal)field(state,"reversal").get(state);
            var pace=(CartLegPace.Ramp)field(state,"pace").get(state);
            for(int desired:new int[]{-1,1}) {
                direction(player,pivotHeading+(desired<0?Math.PI:0));
                double neutral=0;boolean switched=false;
                for(int frame=0;frame<fps*4;frame++) {
                    int old=reversal.direction;
                    nativeFrame(player,input,node,clips,dt);
                    if(pace.speed==0 && field(state,"actualDistance").getDouble(state)<1e-6) neutral+=dt;
                    else neutral=0;
                    if(reversal.direction!=old) {
                        check(neutral>=.08-1e-7 && pace.speed==0 && field(state,"actualDistance").getDouble(state)<1e-6,
                            "stationary pivot sign flip must pass through a full native stop: "+context+"/"+desired);
                        switched=true;
                    }
                    if(reversal.direction==desired && !reversal.active && Math.abs(player.stepY)>.1) break;
                }
                check(switched && reversal.direction==desired && !reversal.active && Math.signum(player.stepY)==desired,
                    "pivot/reverse/forward must restart the requested native gait: "+context+"/"+desired);
            }
            direction(player,pivotHeading+Math.PI);CartSteeringHooks.input(player,input);
            check(reversal.braking,"moving reversal cancellation fixture must be braking: "+context);
            nativeFrame(player,input,node,clips,dt);
            direction(player,pivotHeading);CartSteeringHooks.input(player,input);
            check(!reversal.braking && reversal.direction==1,"returning to outgoing input must cancel the sign flip: "+context);
            for(int frame=0;frame<fps*2 && reversal.active;frame++) {
                nativeFrame(player,input,node,clips,dt);
                check(reversal.direction==1 && player.stepY>=0,"cancelled reversal cannot leak a backward stride: "+context);
            }
            check(!reversal.active && reversal.direction==1 && player.stepY>0,
                "cancelled reversal must recover the outgoing native gait: "+context);
        }
    }

    @SuppressWarnings("unchecked")
    private static AnimationClip importClip(java.nio.file.Path path) throws Exception {
        check(java.nio.file.Files.isRegularFile(path),"missing animation clip: "+path);
        var params=zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams.create();
        params.scene=jassimp.Jassimp.importFile(path.toString(),java.util.EnumSet.of(
            jassimp.AiPostProcessSteps.MAKE_LEFT_HANDED,jassimp.AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS));
        params.mode=zombie.core.skinnedmodel.model.jassimp.JAssImpImporter.LoadMode.AnimationOnly;
        params.animBonesScaleModifier=1;params.animBonesRotateModifier=null;
        var skeleton=zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton.process(
            zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams.create(params,params.scene.getMeshes().get(0)));
        var clips=(Map<String,AnimationClip>)field(skeleton,"clips").get(skeleton);
        check(clips.size()==1,"fixture animation must contain exactly one clip: "+path);
        return clips.values().iterator().next();
    }

    private static void stationaryCadence(Unsafe unsafe,Map<?,?> states) throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        player.inventory=new ItemContainer();player.primary=player.secondary=cart;cart.setContainer(player.inventory);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");player.walkSpeed=.8f;
        var project=java.nio.file.Path.of(System.getProperty("pz.test.project","."));
        var media=project.resolve("PZSurvivorToolkit/42/media");
        var node=AnimNode.Parse(media.resolve("AnimSets/player/movement/toolkit_cart_wood_pivot_walk.xml").toString());
        check(node!=null && node.name.equals(CartLegPace.pivotName(cart.getFullType(),false,false))
            && node.blend2dPicker!=null,"stationary regression must load the current production wooden walking node");
        var clips=new HashMap<String,AnimationClip>();
        var nativeFolder=java.nio.file.Path.of("media/anims_X/Bob");
        for(var blend:node.blends2d) {
            var folder=blend.animName.startsWith("Toolkit_")?media.resolve("anims_X/Bob"):nativeFolder;
            clips.put(blend.animName,importClip(folder.resolve(blend.animName+".x")));
        }
        var nativeSide=importClip(nativeFolder.resolve("Bob_StrafeNoAim_Left.x"));
        double nativeSideSpeed=nativeSide.getTranslationLength("Translation_Data",BoneAxis.Y)/nativeSide.getDuration();
        check(nativeSideSpeed>0,"native reference must contain measured lateral root motion");
        player.animator=new AdvancedAnimator();player.animator.animSet=new AnimationSet();
        var movement=new AnimState();movement.nodes.add(node);player.animator.animSet.states.put("movement",movement);
        var mesh=(ModelMesh)unsafe.allocateInstance(ModelMesh.class);
        mesh.skinningData=new SkinningData(clips,List.of(),List.of(),List.of(),List.of(),new HashMap<>());
        var model=ModelManager.class.getDeclaredField("animModel");model.setAccessible(true);
        Object oldModel=model.get(ModelManager.instance);
        var input=new IsoPlayer.InputState();var time=GameTime.getInstance();float oldFps=time.fpsMultiplier;
        try {
            model.set(ModelManager.instance,mesh);
            for(float walkSpeed:new float[]{.56f,.3575f}) for(int fps:new int[]{30,60,144}) for(int sign:new int[]{-1,1}) {
                player.walkSpeed=walkSpeed;
                time.fpsMultiplier=60f/fps;double dt=time.getRealworldSecondsSinceLastUpdate();
                CartSteeringHooks.reset(player);player.moving=false;player.inputX=player.inputY=0;
                player.actualX=10825.5f;player.actualY=10142.5f;CartSteeringHooks.heading(player);
                Object state=states.get(player);double initial=Math.PI/4,target=initial+sign*Math.PI/2;
                field(state,"heading").setDouble(state,initial);field(state,"target").setDouble(state,initial);
                direction(player,target);CartSteeringHooks.input(player,input);player.moving=true;CartSteeringHooks.heading(player);
                check(Float.isFinite(CartLegPace.targetSpeed(player,player.stepX,player.stepY)),
                    "stationary feedback regression must use calibrated native animation clips");
                boolean rounded=false;float maxPace=0;
                for(int frame=0;frame<fps*6 && field(state,"stationary").getBoolean(state);frame++) {
                    CartSteeringHooks.input(player,input);
                    check(Math.abs(player.stepX)==1 && player.stepY==0,
                        "stationary turns must retain the full native lateral stride");
                    double budget=nativeBudget(player,node,clips,dt);
                    // Compare the same native movement budget after the authored stride changed length.
                    // Raw cadence must decrease for a longer step while cargo and response stay identical.
                    float nativeEquivalentPace=(float)(budget/dt/nativeSideSpeed);
                    maxPace=Math.max(maxPace,nativeEquivalentPace);
                    check(nativeEquivalentPace<(walkSpeed>.5?1.35:.86),
                        "cargo must affect full-stride cadence instead of fast idle-blended shuffling");
                    double before=field(state,"heading").getDouble(state);float x=player.actualX,y=player.actualY;
                    Vector2 step=CartSteeringHooks.movement(player,(float)budget,0);
                    check(step.getLength()<=budget+1e-7,"stationary steering cannot invent native root distance");
                    accept(player,step);
                    double after=field(state,"heading").getDouble(state);
                    if(player.actualX==x && player.actualY==y) {
                        rounded=true;check(after==before,"rounded native root cannot rotate the cart");
                    }
                    check(Double.isFinite(after),"native stationary feedback must retain a finite heading");
                }
                check(!field(state,"stationary").getBoolean(state)
                    && Math.abs(CartSteeringMath.wrap(target-field(state,"heading").getDouble(state)))<Math.toRadians(.5),
                    "calibrated stationary root must finish at world coordinates: "+fps+"/"+sign);
                check(maxPace>(walkSpeed>.5?1.2:.78),"larger full steps must preserve the responsive native turn budget");
                if(fps==144) check(rounded,"high-FPS regression must exercise sub-ULP native root frames");
                player.inputX=player.inputY=0;CartSteeringHooks.input(player,input);player.moving=false;
                CartSteeringHooks.heading(player);
            }
            nativeDirectionChanges(player,states,input,node,clips);
        } finally {
            CartSteeringHooks.reset(player);time.fpsMultiplier=oldFps;model.set(ModelManager.instance,oldModel);
        }
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var tiny=CartSteeringMath.step(0,0,.0002,1.0/60,0);
        check(!CartSteeringHooks.blockedStep(tiny,10825.5f,10142.5f,0),
            "float-rounded first Sprint step must not restart its acceleration forever");
        var wall=CartSteeringMath.step(0,0,.02,1.0/60,0);
        check(CartSteeringHooks.blockedStep(wall,10825.5f,10142.5f,0),"a real blocked budget must release Sprint momentum");
        check(!CartSteeringHooks.blockedStep(wall,10825.5f,10142.5f,.5),"accepted movement must retain its momentum");
        Field unsafeField = Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe) unsafeField.get(null);
        Player player = (Player) unsafe.allocateInstance(Player.class);
        player.walkSpeed=.8f;
        InventoryContainer cart = (InventoryContainer) unsafe.allocateInstance(InventoryContainer.class);
        player.inventory = new ItemContainer();
        player.primary = player.secondary = cart;
        cart.setContainer(player.inventory);
        Field stateField = CartSteeringHooks.class.getDeclaredField("states");
        stateField.setAccessible(true);
        Map<?, ?> states = (Map<?, ?>) stateField.get(null);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");
        var nativeInput=new IsoPlayer.InputState();nativeInput.sprinting=true;
        CartSteeringHooks.input(player,nativeInput);
        Object captured=states.get(player);
        Field intent=captured.getClass().getDeclaredField("sprintRequested");intent.setAccessible(true);
        Field identity=captured.getClass().getDeclaredField("cart");identity.setAccessible(true);
        check(intent.getBoolean(captured) && identity.get(captured)==cart,
            "first Sprint intent must acquire the correct cart before native Run fallback");
        CartSteeringHooks.heading(player);
        check(states.get(player)==captured && !intent.getBoolean(captured),
            "heading must consume intent without replacing the newly acquired state");
        nativeInput.sprinting=false;CartSteeringHooks.input(player,nativeInput);
        check(!intent.getBoolean(captured),"native eligibility denial must clear Sprint intent");
        player.brace=true;player.blocked=1;nativeInput.sprinting=true;CartSteeringHooks.input(player,nativeInput);
        check(!states.containsKey(player),"ineligible input must release state rather than retain Sprint intent");
        check(!player.brace,"death/protected reset retained the effort animation gate");
        player.blocked=0;
        for(String kind:new String[]{"SaucedWheelbarrow.WheelbarrowWood","SaucedWheelbarrow.WheelbarrowMetal","SaucedCarts.ShoppingCart"}) {
            type(cart,kind);
            for(double heading:new double[]{0,Math.PI/2,-Math.PI/2,Math.PI}) {
                for(int degrees:new int[]{0,45,90,134,136,180,-45,-90,-134,-136}) {
                    CartSteeringHooks.reset(player);CartSteeringHooks.heading(player);
                    Object state=states.get(player);Field yaw=state.getClass().getDeclaredField("heading");yaw.setAccessible(true);yaw.setDouble(state,heading);
                    double world=heading+Math.toRadians(degrees);
                    // Inverse of native world=(input.y+input.x,input.y-input.x).
                    player.inputX=(float)((Math.cos(world)-Math.sin(world))/2);
                    player.inputY=(float)((Math.cos(world)+Math.sin(world))/2);
                    nativeInput.setRunning(true);nativeInput.sprinting=true;
                    CartSteeringHooks.input(player,nativeInput);
                    boolean reverse=kind.startsWith("SaucedWheelbarrow.") && Math.abs(degrees)>135;
                    boolean stationary=kind.startsWith("SaucedWheelbarrow.") && Math.abs(degrees)>20 && !reverse;
                    boolean clamped=reverse || stationary;
                    check(nativeInput.isRunning()!=clamped && nativeInput.sprinting!=clamped,
                        "wooden reverse and stationary turns must reject Run/Sprint: "+kind+"/"+heading+"/"+degrees);
                    check(intent.getBoolean(state)==!clamped,"Sprint capture must follow the clamped native input");
                }
            }
        }
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");
        for(int oldDirection:new int[]{1,-1}) {
            CartSteeringHooks.reset(player);CartSteeringHooks.heading(player);
            Object state=states.get(player);
            Field reversalField=state.getClass().getDeclaredField("reversal");reversalField.setAccessible(true);
            var reversal=(CartSteeringMath.Reversal)reversalField.get(state);
            Field paceField=state.getClass().getDeclaredField("pace");paceField.setAccessible(true);
            ((CartLegPace.Ramp)paceField.get(state)).reset(1);
            Field target=state.getClass().getDeclaredField("target");target.setAccessible(true);
            target.setDouble(state,oldDirection<0?Math.PI:0);
            reversal.direction=oldDirection;reversal.requested=oldDirection;
            double desired=oldDirection>0?Math.PI:0;
            player.inputX=(float)((Math.cos(desired)-Math.sin(desired))/2);
            player.inputY=(float)((Math.cos(desired)+Math.sin(desired))/2);
            nativeInput.setRunning(true);nativeInput.sprinting=true;
            CartSteeringHooks.input(player,nativeInput);
            check(reversal.active && reversal.braking && reversal.direction==oldDirection && reversal.requested==-oldDirection,
                "moving reversal must retain the outgoing direction until braking finishes");
            check(!nativeInput.isRunning() && !nativeInput.sprinting,"pending reversal must reject fast gait in both directions");
            Vector2 braking=CartSteeringHooks.movement(player,.02f,0);
            check(braking.x*oldDirection>0 && Math.abs(braking.y)<1e-6,"braking must preserve outgoing rolling direction");
            player.moving=true;
            // This fixture deliberately has no native animation calibration.
            CartSteeringHooks.heading(player);
            check(!reversal.active && !reversal.braking && reversal.direction==-oldDirection,
                "missing clip calibration must release the outgoing direction rather than trap braking");
            ((CartLegPace.Ramp)paceField.get(state)).reset(1);
            reversal.request(oldDirection,false);
            player.inputX=player.inputY=0;CartSteeringHooks.input(player,nativeInput);
            check(!reversal.active && !reversal.braking && reversal.requested==0,"release must cancel a pending sign flip");
            CartSteeringHooks.reset(player);CartSteeringHooks.heading(player);
            Object fresh=states.get(player);
            var resetReversal=(CartSteeringMath.Reversal)reversalField.get(fresh);
            check(fresh!=state && !resetReversal.active && resetReversal.direction==1,"reset must discard reversal state");
        }
        CartSteeringHooks.reset(player);player.inputX=player.inputY=0;player.moving=false;
        String[] gates = {"dead", "hit reaction", "knocked down", "getting up", "grappling",
                          "being grappled", "ragdoll", "remote", "path", "motion disabled",
                          "unsupported cart", "one hand", "other inventory", "world item"};
        for (String type : new String[]{"SaucedCarts.ShoppingCart", "SaucedWheelbarrow.WheelbarrowWood",
                                      "SaucedWheelbarrow.WheelbarrowMetal"}) {
            type(cart, type);
            check(CartSteeringHooks.supportedCart(player), "supported cart rejected: " + type);
        }
        for (int gate = 1; gate <= gates.length; gate++) {
            player.blocked = 0; type(cart, "SaucedCarts.ShoppingCart");
            player.secondary = cart; cart.setContainer(player.inventory); cart.setWorldItem(null);
            CartSteeringHooks.heading(player);
            check(player.pivot && states.containsKey(player), "eligible cart did not acquire steering");
            player.stepX = 0.5f; player.stepY = 0.5f;
            player.blocked = gate;
            if (gate == 11) type(cart, "Base.Bag_Schoolbag");
            if (gate == 12) player.secondary = null;
            if (gate == 13) cart.setContainer(new ItemContainer());
            if (gate == 14) cart.setWorldItem((IsoWorldInventoryObject) unsafe.allocateInstance(IsoWorldInventoryObject.class));
            Vector2 actual = CartSteeringHooks.movement(player, 0.02f, -0.01f);
            check(actual.x == 0.02f && actual.y == -0.01f, gates[gate - 1] + " redirected movement");
            CartSteeringHooks.heading(player);
            check(!player.pivot && player.stepX == 0 && player.stepY == 0 && player.legPace==0 && !states.containsKey(player),
                  gates[gate - 1] + " retained steering state");
        }
        CartSteeringHooks.reset(player);
        check(!states.containsKey(player), "repeated reset retained state");
        player.blocked=0;player.secondary=cart;cart.setContainer(player.inventory);cart.setWorldItem(null);
        for(String kind:new String[]{"SaucedWheelbarrow.WheelbarrowWood","SaucedWheelbarrow.WheelbarrowMetal"}) {
            type(cart,kind);CartSteeringHooks.heading(player);
            Object state=states.get(player);
            Field pending=state.getClass().getDeclaredField("pending");pending.setAccessible(true);pending.setBoolean(state,true);
            player.actualX=.02f;player.actualY=.01f;
            CartSteeringHooks.heading(player);
            Field heading=state.getClass().getDeclaredField("heading");heading.setAccessible(true);
            double axle=kind.endsWith("Wood")?1.0084944326:1.002699624;
            check(Math.abs(heading.getDouble(state)-CartSteeringMath.acceptedTurn(0,axle,player.actualX,player.actualY))<1e-10,
                  "native collision displacement must determine wheel yaw: "+kind);
            {
                double before=CartSteeringHooks.wheelPhase(player);
                check(before<0,"accepted forward travel spins the wooden wheel");
                Field rawPhase=state.getClass().getDeclaredField("wheelPhase");rawPhase.setAccessible(true);
                double acceptedPhase=rawPhase.getDouble(state);
                CartSteeringHooks.heading(player);
                check(rawPhase.getDouble(state)==acceptedPhase,"heading without accepted movement cannot spin the wheel twice");
                var replacement=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
                type(replacement,kind);replacement.setContainer(player.inventory);
                player.primary=player.secondary=replacement;
                CartSteeringHooks.heading(player);
                check(CartSteeringHooks.wheelPhase(player)==0,"new wooden cart inherited the old cart phase");
                player.primary=player.secondary=cart;
            }
            CartSteeringHooks.reset(player);player.actualX=player.actualY=0;
        }
        var continuityPlayer=(Player)unsafe.allocateInstance(Player.class);
        continuityPlayer.inventory=new ItemContainer();
        var continuityCart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        type(continuityCart,"SaucedWheelbarrow.WheelbarrowWood");continuityCart.setContainer(continuityPlayer.inventory);
        continuityPlayer.primary=continuityPlayer.secondary=continuityCart;
        var wheelPose=new org.joml.Matrix4f().scale(76.5f);
        CartWheelSpin.record(continuityCart,0,0,0,wheelPose,.8);
        CartSteeringHooks.heading(continuityPlayer);
        check(Math.abs(CartSteeringHooks.wheelPhase(continuityPlayer)-.8)<1e-6,"steering lost the same item's world phase");
        var wheelSlot=new zombie.core.skinnedmodel.model.ModelSlotRenderData();wheelSlot.y=-.02f;
        double followed=CartSteeringHooks.wheelPhase(continuityPlayer,wheelSlot,wheelPose);
        double expected=.8-.02/CartWheelSpin.WORLD_RADIUS;
        check(Math.abs(followed-expected)<1e-6 && Math.abs(CartSteeringHooks.wheelPhase(continuityPlayer)-expected)<1e-6,
            "first held render did not rebase the exact final handoff travel");
        check(CartSteeringHooks.wheelPhase(continuityPlayer,wheelSlot,wheelPose)==followed,"repeated render spun wheel twice");
        CartSteeringHooks.reset(continuityPlayer);CartSteeringHooks.heading(continuityPlayer);
        check(Math.abs(CartSteeringHooks.wheelPhase(continuityPlayer)-expected)<1e-6,"state reset discarded rendered item phase");
        CartSteeringHooks.reset(continuityPlayer);
        type(cart,"SaucedWheelbarrow.WheelbarrowWood");
        player.moving=true;player.walkSpeed=.25f;
        for(int gait=0;gait<3;gait++) {
            player.run=gait==1;player.sprint=gait==2;
            CartSteeringHooks.heading(player);
            Object state=states.get(player);
            Field pending=state.getClass().getDeclaredField("pending");pending.setAccessible(true);pending.setBoolean(state,true);
            player.actualX=.02f;player.actualY=0;
            CartSteeringHooks.heading(player);
            check(Math.abs(Math.hypot(player.stepX,player.stepY)-(gait==0?.25:1))<1e-6,
                  "native run speed was incorrectly reused as an idle blend: gait="+gait);
            CartSteeringHooks.reset(player);player.actualX=0;
        }
        CartSteeringHooks.reset(player);type(cart,"SaucedWheelbarrow.WheelbarrowWood");
        player.moving=false;player.run=true;player.sprint=false;
        CartSteeringHooks.heading(player);
        check(CartSteeringHooks.fastPoseWeight(player)==1,"running must acquire clearance through its native pose fade");
        player.run=false;
        for(int tick=0;tick<12;tick++)CartSteeringHooks.heading(player);
        check(CartSteeringHooks.fastPoseWeight(player)==1,"stop clearance must survive the outgoing running track");
        for(int tick=0;tick<9;tick++)CartSteeringHooks.heading(player);
        float fading=CartSteeringHooks.fastPoseWeight(player);
        check(fading>0 && fading<1,"clearance must fade smoothly after the native handoff");
        for(int tick=0;tick<6;tick++)CartSteeringHooks.heading(player);
        check(CartSteeringHooks.fastPoseWeight(player)==0,"ordinary walking must release fast-pose clearance");
        player.run=true;CartSteeringHooks.heading(player);CartSteeringHooks.reset(player);
        check(CartSteeringHooks.fastPoseWeight(player)==0,"reset must release delayed pose clearance");
        player.run=false;
        CartSteeringHooks.heading(player);
        var side=field(states.get(player),"sideClearance");side.setFloat(states.get(player),-.06f);
        CartSteeringHooks.heading(player);
        float sideFade=CartSteeringHooks.sideClearance(player);
        check(sideFade>-.06 && sideFade<0,"native heading must release side clearance gradually once per update");
        CartSteeringHooks.reset(player);
        check(CartSteeringHooks.sideClearance(player)==0,"reset cannot leak side clearance into the next cart");
        pathControls(unsafe,states);
        keyboardControls(unsafe,states);
        keyboardReleaseControls(unsafe,states);
        keyboardWorldReleaseControls(unsafe,states);
        stationaryControls(unsafe,states);
        stationaryCadence(unsafe,states);
        brakeControls(unsafe,states);
        residualBrake(unsafe,states);
        residualBrakeEdges(unsafe,states);
        adjacentBrakeRelease(unsafe,states);
        slalomClearance(unsafe,states);
        wovenPathControls(unsafe,states);
        wovenProtectedControls(unsafe,states);
        System.out.println("CART_STEERING_HOOKS_PASS (combat, local, path, scope, ownership, reset, native direction transitions)");
    }
}
