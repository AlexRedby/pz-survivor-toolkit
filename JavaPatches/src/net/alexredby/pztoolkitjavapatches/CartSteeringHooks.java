package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import zombie.GameTime;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.Vector2;

/** Per-player cart steering; original movement still performs collisions. */
public final class CartSteeringHooks {
    private static final WeakHashMap<IsoPlayer, State> states = new WeakHashMap<>();
    private static final ThreadLocal<Vector2> passthrough = ThreadLocal.withInitial(Vector2::new);

    private static final class State {
        double heading, target, load, lean, wheelPhase, turnRate;
        final CartSteeringMath.Bank bank = new CartSteeringMath.Bank();
        final CartLegPace.Ramp pace = new CartLegPace.Ramp();
        final CartSteeringMath.Reversal reversal = new CartSteeringMath.Reversal();
        double brakeTarget, actualDistance, fastPoseTail, nativeSpeed, brakeLimit, brakeWait, brakePace;
        zombie.inventory.InventoryItem cart;
        float startX, startY;
        boolean moving, pending, sprintMomentum, sprintRequested, hasInput, wantsMove, braking, brakeSeen, fastMoving;
        final CartSteeringMath.Step requested = new CartSteeringMath.Step();
        final Vector2 result = new Vector2();
        final Vector2 input = new Vector2();
    }

    public static boolean supportedCart(IsoPlayer player) {
        var cart=player.getPrimaryHandItem();
        if (!(cart instanceof InventoryContainer) || player.getSecondaryHandItem()!=cart
            || cart.getContainer()!=player.getInventory() || cart.getWorldItem()!=null) return false;
        return switch(cart.getFullType()) {
            case "SaucedCarts.ShoppingCart", "SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal" -> true;
            default -> false;
        };
    }

    public static boolean enabled(IsoPlayer player) {
        return player.isLocalPlayer() && player.getVariableBoolean("ToolkitCartMotion")
                && !player.isDead() && !player.hasHitReaction() && !player.isKnockedDown()
                && !player.isGettingUp() && !player.isGrappling() && !player.isBeingGrappled()
                && !player.isRagdollSimulationActive()
                && supportedCart(player)
                // Path following needs its own corner/collision acceptance tests.
                && !player.hasPath()
                && player.getPrimaryHandItem() instanceof InventoryContainer;
    }

    private static State state(IsoPlayer player) {
        State state=states.get(player);
        if(state==null || state.cart!=player.getPrimaryHandItem()) {
            if(state!=null) reset(player);
            state=new State();
            state.cart=player.getPrimaryHandItem();
            Vector2 facing=player.getAnimForwardDirection(new Vector2());
            state.heading=Math.atan2(facing.y,facing.x);
            states.put(player,state);
        }
        return state;
    }

    public static void input(IsoPlayer player, IsoPlayer.InputState input) {
        if(!enabled(player)) {
            if(states.containsKey(player)) reset(player);
            return;
        }
        State state=state(player);
        if(wooden(player)) {
            boolean wasMoving=state.wantsMove;
            Vector2 move=player.getInputMoveVector(state.input);
            // Native input is in screen axes; steering heading is in world axes.
            double desired=Math.atan2(move.y-move.x,move.y+move.x);
            state.hasInput=true;
            state.wantsMove=move.getLengthSquared()>1e-8;
            if(state.wantsMove) {
                state.braking=false;
                player.setVariable("ToolkitCartWoodBrake",false);
            } else if(wasMoving && state.fastMoving
                && state.reversal.direction>0 && !state.reversal.active && state.actualDistance>1e-6
                && Double.isFinite(state.nativeSpeed) && state.nativeSpeed>0) {
                state.braking=true;state.brakeSeen=false;state.brakeWait=0;
                state.brakeLimit=state.nativeSpeed;
                state.brakePace=state.pace.speed;
                player.setVariable("ToolkitCartWoodBrake",true);
            }
            int intent=state.wantsMove?CartSteeringMath.directionIntent(state.heading,desired,state.reversal.requested):0;
            var stop=CartLegPace.brakeTrack(player);
            if(state.reversal.request(intent,state.pace.speed<1e-3 && state.actualDistance<1e-6
                && (stop==null || !stop.getUseDeferredMovement())))
                state.brakeTarget=state.target;
            if(state.wantsMove) state.target=desired;
            if(intent<0 || state.reversal.direction<0 || state.reversal.active) {
                input.setRunning(false);
                input.sprinting=false;
            }
        }
        state.sprintRequested=input.sprinting;
    }

    static float fastPoseWeight(IsoPlayer player) {
        State state=states.get(player);
        if(state==null) return 0;
        float t=(float)Math.min(1,state.fastPoseTail/.1);
        return t*t*(3-2*t);
    }

    public static double lean(IsoPlayer player) {
        State state=states.get(player);
        return state!=null && enabled(player) && wheelbarrow(player) ? state.lean : 0;
    }

    public static double wheelPhase(IsoPlayer player) {
        State state=states.get(player);
        return state!=null && enabled(player) && wooden(player)
            ? CartWheelSpin.advance(state.wheelPhase,CartSteeringMath.woodenAxle((float)state.lean,CartLegPace.woodenGaitShift(player))
                -CartSteeringMath.woodenAxle(0,0)) : Double.NaN;
    }

    private static boolean wheelbarrow(IsoPlayer player) {
        return player.getPrimaryHandItem().getFullType().startsWith("SaucedWheelbarrow.");
    }

    private static boolean wooden(IsoPlayer player) {
        return "SaucedWheelbarrow.WheelbarrowWood".equals(player.getPrimaryHandItem().getFullType());
    }

    private static double axle(IsoPlayer player) {
        // Actual grounded wheel vertices; Model.vectorToWorldCoords scales model Z by -1.5.
        return switch(player.getPrimaryHandItem().getFullType()) {
            case "SaucedWheelbarrow.WheelbarrowWood" -> CartSteeringMath.woodenAxle((float)lean(player),CartLegPace.woodenGaitShift(player));
            case "SaucedWheelbarrow.WheelbarrowMetal" -> 1.1691522;
            default -> 0;
        };
    }

    private static double load(IsoPlayer player) {
        ItemContainer contents=((InventoryContainer)player.getPrimaryHandItem()).getInventory();
        if(contents==null) return 0;
        int capacity=contents.getEffectiveCapacity(player);
        double load=capacity>0?contents.getCapacityWeight()/capacity:0;
        return Double.isFinite(load)?Math.max(0,Math.min(1,load)):0;
    }

    static boolean blockedStep(CartSteeringMath.Step requested, float x, float y, double fraction) {
        // The first slow steps can round to zero in the world's float coordinates.
        return Math.hypot(requested.x(),requested.y())>2*Math.max(Math.ulp(x),Math.ulp(y)) && fraction<1e-6;
    }

    /**
     * Hook 1: at IsoPlayer.moveUnmodded(FF)V entry, replace its two arguments with
     * this returned vector. Continue the original method, including slowFactor.
     * Read result.x/y immediately; the vector belongs to this player's state.
     */
    public static Vector2 movement(IsoPlayer player, float x, float y) {
        State state = states.get(player);
        if (state == null || !enabled(player)) return passthrough.get().set(x, y);
        if(state.cart!=player.getPrimaryHandItem()) {reset(player);return passthrough.get().set(x,y);}
        // Only the native locomotion call should be redirected; do not double-plan.
        if (state.pending) return passthrough.get().set(x, y);
        state.startX = player.getX();
        state.startY = player.getY();
        double distance = Math.hypot(x, y);
        double dt=Math.max(0,Math.min(.1,GameTime.getInstance().getRealworldSecondsSinceLastUpdate()));
        if(state.braking || state.brakeLimit>0 && CartLegPace.brakeTrack(player)!=null)
            distance=Math.min(distance,state.brakeLimit*dt);
        if(dt>0) {
            // Seed a resumed Sprint from the coasting speed without changing the stop's cadence.
            if(state.braking && state.brakeLimit>0)
                state.pace.reset(state.brakePace*Math.max(0,Math.min(1,distance/(dt*state.brakeLimit))));
            else state.nativeSpeed=distance/dt;
        }
        state.load = load(player);
        if(wooden(player)) CartSteeringMath.woodenStep(state.heading,
                state.reversal.braking?state.brakeTarget:state.wantsMove?state.target:state.heading+(state.reversal.direction<0?Math.PI:0), distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate(),state.load,axle(player),
                state.turnRate,state.reversal.direction<0,state.requested);
        else CartSteeringMath.step(state.heading,
                state.moving ? state.target : state.heading, distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate(), state.load, axle(player),
                52, state.requested);
        state.pending = true;
        return state.result.set((float) state.requested.x(), (float) state.requested.y());
    }

    /**
     * Hook 2: IsoGameCharacter.postUpdateAnimating()V ENTRY. Its caller already
     * ran IsoMovingObject.postupdate() collisions. Capture native input-facing
     * before overriding it, then animate only the accepted part of the arc.
     */
    public static void heading(IsoGameCharacter character) {
        if (!(character instanceof IsoPlayer player)) return;
        State state = states.get(player);
        if (!enabled(player)) {
            if (state != null) reset(player);
            return;
        }
        player.setVariable("ToolkitCartPivot",true);
        double desired = Math.atan2(player.getForwardDirectionY(), player.getForwardDirectionX());
        state=state(player);
        // Native clears the gait flags before UpdateInputState; retain the last finalized gait for release.
        state.fastMoving=player.isRunning() || player.isSprinting();
        boolean sprintRequested=state.sprintRequested;
        state.sprintRequested=false;
        state.load=load(player);
        double actualX = 0, actualY = 0;
        double fraction = 0, acceptedTurn=0;
        boolean blocked=false;
        if (state.pending) {
            actualX = player.getX() - state.startX;
            actualY = player.getY() - state.startY;
            fraction = CartSteeringMath.acceptedFraction(state.requested,
                    actualX, actualY);
            blocked=blockedStep(state.requested,state.startX,state.startY,fraction);
            double turn = wheelbarrow(player)
                ? CartSteeringMath.acceptedTurn(state.heading,axle(player),actualX,actualY)
                : state.requested.turn() * fraction;
            if(wooden(player)) {
                double mid=state.heading+turn/2;
                double rolling=actualX*Math.cos(mid)+actualY*Math.sin(mid)-2*.00984276836*Math.sin(turn/2);
                state.wheelPhase=CartWheelSpin.advance(state.wheelPhase,rolling);
            }
            acceptedTurn=turn;
            state.heading = CartSteeringMath.wrap(state.heading + turn);
            state.pending = false;
        }
        double dt=Math.max(0,Math.min(.1,GameTime.getInstance().getRealworldSecondsSinceLastUpdate()));
        var stop=wooden(player)?CartLegPace.brakeTrack(player):null;
        if(state.braking) {
            state.brakeWait+=dt;
            if(stop!=null && !state.brakeSeen) {
                // A loaded cart takes slightly longer to settle, with the same authored foot sequence.
                stop.setSpeedDelta((float)(1/(1+.12*state.load)));
                state.brakeSeen=true;
            }
            if(blocked || state.brakeSeen && stop==null || !state.brakeSeen && state.brakeWait>.3) {
                if(blocked) {
                    CartLegPace.cancelBrake(player,false);
                    CartLegPace.applySpeed(player,0,0,0);
                }
                state.braking=false;
                player.setVariable("ToolkitCartWoodBrake",false);
            }
        }
        // The native start/stop pose can outlive the last running track; release its clearance gradually.
        if(wooden(player)) state.fastPoseTail=player.isRunning() || player.isSprinting() || stop!=null?.4:Math.max(0,state.fastPoseTail-dt);
        state.actualDistance=Math.hypot(actualX,actualY);
        double travel=actualX*Math.cos(state.heading)+actualY*Math.sin(state.heading);
        double bank=wooden(player) ? CartSteeringMath.rollingLean(acceptedTurn,travel,dt)
            : wheelbarrow(player) && dt>0 ? Math.max(-.10,Math.min(.10,Math.signum(travel)*acceptedTurn/dt*.065)) : 0;
        state.turnRate=dt>0?acceptedTurn/dt:0;
        if(wooden(player)) state.lean=state.bank.update(bank,dt);
        else state.lean+=(bank-state.lean)*(1-Math.exp(-dt/.08));
        state.moving = player.isJustMoved();
        if(!wooden(player) || !state.hasInput) state.target = state.moving ? desired : state.heading;
        state.hasInput=false;
        double length = Math.hypot(actualX, actualY);
        if (state.moving && length < 1e-6) {
            // Idle/blocked clips need intent to generate their first root-motion budget.
            if(wooden(player)) CartSteeringMath.woodenStep(state.heading,state.reversal.braking?state.brakeTarget:state.target,0.03,1.0/60,
                                  state.load,axle(player),state.turnRate,state.reversal.direction<0,state.requested);
            else CartSteeringMath.step(state.heading, state.target, 0.03, 1.0 / 60,
                                  state.load, axle(player),52,state.requested);
            actualX = state.requested.x(); actualY = state.requested.y();
            length = Math.hypot(actualX, actualY);
        }
        if (!state.moving || length < 1e-6) {
            player.setVariable("ToolkitCartStepX", 0.0f);
            player.setVariable("ToolkitCartStepY", 0.0f);
        } else {
            double cos = Math.cos(state.heading), sin = Math.sin(state.heading);
            // Run/Sprint WalkSpeed blends two moving gaits; it is not an idle weight.
            double pace=player.isRunning() || player.isSprinting() ? 1
                : Math.max(0,Math.min(1,player.getVariableFloat("WalkSpeed",0.8f)));
            player.setVariable("ToolkitCartStepX", (float) (pace * (-actualX * sin + actualY * cos) / length));
            player.setVariable("ToolkitCartStepY", (float) (pace * (actualX * cos + actualY * sin) / length));
        }
        float stepX=player.getVariableFloat("ToolkitCartStepX",0),stepY=player.getVariableFloat("ToolkitCartStepY",0);
        float target=wooden(player)?CartLegPace.targetSpeed(player,stepX,stepY):Float.NaN;
        if(state.braking) {
            // The authored stop owns deceleration; freezing its outgoing gait would break the blend.
            state.sprintMomentum=false;
        } else if(Float.isFinite(target)) {
            if(blocked) state.pace.reset(0);
            // Native uses Run for the first Sprint frame, before isSprinting becomes true.
            if(player.isSprinting() || sprintRequested && state.moving) state.sprintMomentum=true;
            if(state.reversal.active) {
                state.sprintMomentum=false;
                double speed=state.pace.update(state.reversal.braking?0:target,dt,state.load);
                if(state.reversal.braking && state.pace.settled(0)) { state.pace.reset(0);speed=0; }
                float radius=target>1e-6?Math.min(1,(float)(speed/target)):0;
                stepX*=radius;stepY*=radius;
                player.setVariable("ToolkitCartStepX",stepX);
                player.setVariable("ToolkitCartStepY",stepY);
                CartLegPace.applySpeed(player,(float)speed,stepX,stepY);
                if(state.reversal.braking) state.reversal.stopped(dt,speed==0,state.actualDistance<1e-6);
                else if(state.pace.settled(target)) state.reversal.active=false;
            } else if(state.sprintMomentum) {
                double speed=state.pace.update(target,dt,state.load);
                CartLegPace.applySpeed(player,(float)speed,stepX,stepY);
                if(!player.isSprinting() && state.pace.settled(target)) state.sprintMomentum=false;
            } else {
                state.pace.reset(target);
                CartLegPace.apply(player,CartLegPace.scale(player,stepX,stepY));
            }
        } else {
            state.sprintMomentum=false;
            state.pace.reset(0);
            // Without calibrated clips, fall back without trapping the old travel direction.
            state.reversal.active=state.reversal.braking=false;
            state.reversal.neutral=0;
            if(state.reversal.requested!=0) state.reversal.direction=state.reversal.requested;
            CartLegPace.apply(player,CartLegPace.scale(player,stepX,stepY));
        }
        // Scoped cart AnimNodes own maxTorsoTwist; native animation rewrites it.
        player.setTargetAndCurrentDirection((float) Math.cos(state.heading),
                                            (float) Math.sin(state.heading));
    }

    /** Death/menu cleanup discards pending state and releases only our own variables. */
    public static void reset(IsoPlayer player) {
        CartLegPace.cancelBrake(player,true);
        states.remove(player);
        player.setVariable("ToolkitCartWoodBrake",false);
        player.clearVariable("ToolkitCartLegPace");
        player.setVariable("ToolkitCartPivot",false);
        player.setVariable("ToolkitCartStepX", 0.0f);
        player.setVariable("ToolkitCartStepY", 0.0f);
    }

    private CartSteeringHooks() {}
}
