package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.util.Map;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.AnimTransition;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.Vector2;
import zombie.iso.objects.IsoWorldInventoryObject;

public final class CartSteeringHooksTest {
    // Skip world/renderer constructors, as the existing NativeChecks fixture does.
    private static final class Player extends IsoPlayer {
        int blocked;
        boolean pivot, woodBrake, moving, run, sprint;
        float walkSpeed;
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
        @Override public boolean isGettingUp() { return blocked == 4; }
        @Override public boolean isGrappling() { return blocked == 5; }
        @Override public boolean isBeingGrappled() { return blocked == 6; }
        @Override public boolean isRagdollSimulationActive() { return blocked == 7; }
        @Override public boolean hasPath() { return blocked == 9; }
        @Override public boolean getVariableBoolean(String name) {
            return switch(name) {case "ToolkitCartMotion"->blocked!=10;case "ToolkitCartPivot"->pivot;
                case "ToolkitCartWoodBrake"->woodBrake;default->false;};
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
            if (name.equals("ToolkitCartWoodBrake")) woodBrake = value;
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
                check(player.woodBrake==(kind.endsWith("Wood") && gait.equals("run")),
                    "only finalized fast wooden movement can arm a stop after the native flags reset: "+kind+"/"+gait);
                CartSteeringHooks.reset(player);
            }
        } finally {
            CartSteeringHooks.reset(player);time.fpsMultiplier=oldFps;
        }
    }

    public static void main(String[] args) throws Exception {
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
        player.blocked=1;nativeInput.sprinting=true;CartSteeringHooks.input(player,nativeInput);
        check(!states.containsKey(player),"ineligible input must release state rather than retain Sprint intent");
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
                    boolean reverse=kind.endsWith("Wood") && Math.abs(degrees)>135;
                    check(nativeInput.isRunning()!=reverse && nativeInput.sprinting!=reverse,
                        "only wooden reverse must reject Run/Sprint: "+kind+"/"+heading+"/"+degrees);
                    check(intent.getBoolean(state)==!reverse,"Sprint capture must follow the clamped native input");
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
            double axle=kind.endsWith("Wood")?1.0084944326:1.1691522;
            check(Math.abs(heading.getDouble(state)-CartSteeringMath.acceptedTurn(0,axle,player.actualX,player.actualY))<1e-10,
                  "native collision displacement must determine wheel yaw: "+kind);
            if(kind.endsWith("Wood")) {
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
            } else check(Double.isNaN(CartSteeringHooks.wheelPhase(player)),"metal wheel opted into wooden prototype");
            CartSteeringHooks.reset(player);player.actualX=player.actualY=0;
        }
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
        brakeControls(unsafe,states);
        System.out.println("CART_STEERING_HOOKS_PASS (combat, local, path, scope, cart ownership, reset)");
    }
}
