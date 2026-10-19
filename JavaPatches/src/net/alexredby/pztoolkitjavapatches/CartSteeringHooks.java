package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import zombie.GameTime;
import zombie.ai.states.CollideWithWallState;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterInputMode;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.Vector2;

/** Per-player cart steering; original movement still performs collisions. */
public final class CartSteeringHooks {
    private static final WeakHashMap<IsoPlayer, State> states = new WeakHashMap<>();
    private static final ThreadLocal<Vector2> passthrough = ThreadLocal.withInitial(Vector2::new);

    private static final class State {
        double heading, target, load, lean, wheelPhase, wheelOrigin, turnRate, stationaryRate;
        final CartSteeringMath.Bank bank = new CartSteeringMath.Bank();
        final CartLegPace.Ramp pace = new CartLegPace.Ramp();
        final CartSteeringMath.Reversal reversal = new CartSteeringMath.Reversal();
        double brakeTarget, actualDistance, fastPoseTail, nativeSpeed, brakeLimit, brakeWait, brakePace, fastReleaseWait;
        double fastPace, brakeDuration=1, brace;
        float visualSpeed=-1;
        float sideClearance;
        zombie.inventory.InventoryItem cart;
        float startX, startY;
        boolean wheelRendered, stationary, stationaryRoot, cartBlocked, recovering, path, relative;
        double footprintFront=CartFootprint.WALK_FRONT;
        double slideTurn=Double.NaN;
        double wallHeading=Double.NaN, wallNormalX, wallNormalY;
        boolean moving, pending, sprintMomentum, sprintRequested, hasInput, wantsMove, braking, brakeSeen, fastMoving;
        boolean sprintMoving, momentumSprint;
        final CartSteeringMath.Step requested = new CartSteeringMath.Step();
        final CartSteeringMath.Step braceProbe = new CartSteeringMath.Step();
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
        return player.isLocalPlayer() && !player.isNpc() && player.getVariableBoolean("ToolkitCartMotion")
                && !player.isDead() && !player.hasHitReaction() && !player.isKnockedDown()
                && !player.isGettingUp() && !player.isGrappling() && !player.isBeingGrappled()
                && !player.isRagdollSimulationActive()
                && !player.isCurrentState(CollideWithWallState.instance())
                && supportedCart(player)
                && (!pathMode(player) || wooden(player))
                && player.getPrimaryHandItem() instanceof InventoryContainer;
    }

    private static boolean pathMode(IsoPlayer player) {
        var path=player.getPathFindBehavior2();
        return player.hasPath() || path!=null && path.isMovingUsingPathFind();
    }

    private static State state(IsoPlayer player) {
        State state=states.get(player);
        if(state==null || state.cart!=player.getPrimaryHandItem() || state.path!=pathMode(player) && !state.pending) {
            if(state!=null) reset(player);
            state=new State();
            state.cart=player.getPrimaryHandItem();
            state.path=pathMode(player);
            state.wheelOrigin=CartWheelSpin.itemPhase(state.cart);
            Vector2 facing=player.getAnimForwardDirection(new Vector2());
            state.heading=Math.atan2(facing.y,facing.x);
            states.put(player,state);
        }
        return state;
    }

    private static boolean keyboard(IsoPlayer player) {
        return player.getInputMode()==CharacterInputMode.KEYBOARD && !player.isAimControlActive() && !player.isAutoWalk();
    }

    private static int travel(IsoPlayer player) {
        var input=player.getCharacterInputComponent();
        return (input.isForwardKeyDown()?1:0)-(input.isBackwardKeyDown()?1:0);
    }

    private static int steering(IsoPlayer player) {
        var input=player.getCharacterInputComponent();
        return (input.isRightKeyDown()?1:0)-(input.isLeftKeyDown()?1:0);
    }

    private static void relativeTarget(IsoPlayer player,State state) {
        int steering=steering(player);
        state.target=CartSteeringMath.keyboardTarget(state.heading,travel(player),steering);
        if(steering==0) {
            state.turnRate=state.stationaryRate=0;
            state.stationary=false;
        }
    }

    /** Keep native input gating and stride length, with cart-relative keyboard directions. */
    public static Vector2 keyboardMovement(IsoPlayer player, Vector2 move) {
        if(!enabled(player) || pathMode(player) || !keyboard(player)) return move;
        int travel=travel(player),steering=steering(player);
        if(travel==0 && steering==0) return move.set(0,0);
        double target=CartSteeringMath.keyboardTarget(state(player).heading,travel,steering);
        double length=move.getLength()/Math.sqrt(2);
        return move.set((float)(length*(Math.cos(target)-Math.sin(target))),
            (float)(length*(Math.cos(target)+Math.sin(target))));
    }

    public static void input(IsoPlayer player, IsoPlayer.InputState input) {
        if(!enabled(player)) {
            if(states.containsKey(player)) reset(player);
            return;
        }
        State state=state(player);
        if(state.path) return;
        boolean keyboard=keyboard(player);
        if(state.relative && !keyboard) state.stationary=state.stationaryRoot=false;
        state.relative=keyboard;
        int travel=keyboard?travel(player):0,steering=keyboard?steering(player):0;
        double desired=keyboard?CartSteeringMath.keyboardTarget(state.heading,travel,steering):0;
        if(keyboard && !wooden(player)) {
            state.hasInput=true;
            state.wantsMove=travel!=0 || steering!=0;
            state.target=desired;
            state.reversal.direction=travel<0?-1:1;
            state.stationary=travel==0 && steering!=0;
            if(state.stationary && !state.stationaryRoot) state.stationaryRate=0;
            if(state.stationary) state.stationaryRoot=true;
            else if(state.wantsMove) state.stationaryRoot=false;
            if(state.stationaryRoot || travel<0) {input.setRunning(false);input.sprinting=false;}
        }
        if(wooden(player)) {
            boolean wasMoving=state.wantsMove;
            Vector2 move=player.getInputMoveVector(state.input);
            // Native input is in screen axes; steering heading is in world axes.
            if(!keyboard) desired=Math.atan2(move.y-move.x,move.y+move.x);
            state.hasInput=true;
            state.wantsMove=keyboard?travel!=0 || steering!=0:move.getLengthSquared()>1e-8;
            if(input.isRunning() || input.sprinting) state.fastReleaseWait=0;
            else {
                double dt=GameTime.getInstance().getRealworldSecondsSinceLastUpdate();
                state.fastReleaseWait+=Math.max(0,dt);
                if(wasMoving && state.wantsMove && state.fastMoving && dt>0 && state.fastReleaseWait<=.05
                    && state.reversal.direction>0 && !state.reversal.active && state.actualDistance>1e-6
                    && player.isAllowRun() && (!state.sprintMoving || player.isAllowSprint())) {
                    // Coalesce near-simultaneous key releases before the native fast node loses its stop transition.
                    input.setRunning(!state.sprintMoving);input.sprinting=state.sprintMoving;
                }
            }
            if(state.wantsMove) {
                state.braking=false;
                player.setVariable("ToolkitCartWoodBrake",false);
                player.setVariable("ToolkitCartBrakeSprint",false);
            } else if(wasMoving && (state.fastMoving || state.sprintMomentum)
                && state.reversal.direction>0 && !state.reversal.active && state.actualDistance>1e-6
                && Double.isFinite(state.nativeSpeed) && state.nativeSpeed>0) {
                state.braking=true;state.brakeSeen=false;state.brakeWait=0;
                state.brakeLimit=state.nativeSpeed;
                state.brakePace=state.pace.speed;
                double remaining=state.fastMoving || state.fastPace<=0 ? 1
                    : Math.max(0,Math.min(1,state.pace.speed/state.fastPace));
                state.brakeDuration=.65+.35*remaining;
                player.setVariable("ToolkitCartBrakeSprint",state.fastMoving?state.sprintMoving:state.momentumSprint);
                player.setVariable("ToolkitCartWoodBrake",true);
            }
            int intent=0;
            if(state.wantsMove) intent=keyboard?(travel==0?state.reversal.direction:travel)
                :CartSteeringMath.directionIntent(state.heading,desired,state.reversal.requested);
            var stop=CartLegPace.brakeTrack(player);
            boolean atRest=state.pace.speed<1e-3 && state.actualDistance<1e-6
                && (stop==null || !stop.getUseDeferredMovement());
            if(state.reversal.request(intent,atRest)) state.brakeTarget=state.target;
            if(keyboard) state.stationary=travel==0 && steering!=0 && !state.reversal.active;
            else if(!state.wantsMove || intent<0 || state.reversal.active) state.stationary=false;
            else if(!wasMoving && !state.moving && atRest
                && Math.abs(CartSteeringMath.wrap(desired-state.heading))>Math.toRadians(20))
                state.stationary=true;
            if(state.stationary && !state.stationaryRoot) state.stationaryRate=0;
            if(state.stationary) state.stationaryRoot=true;
            else if(state.wantsMove && !state.reversal.braking) state.stationaryRoot=false;
            if(state.wantsMove) state.target=desired;
            if(state.stationaryRoot || intent<0 || state.reversal.direction<0 || state.reversal.active) {
                input.setRunning(false);
                input.sprinting=false;
            }
            if((input.isRunning() || input.sprinting) && player.getCurrentSquare()!=null
                && !CartFootprint.clear(CartFootprint.world(player),player.getX(),player.getY(),state.heading,CartFootprint.FAST_FRONT)) {
                // A stopped cart must not enter a wall just because Run expands its visual clearance.
                input.setRunning(false);input.sprinting=false;
            }
        }
        state.sprintRequested=input.sprinting;
    }

    static float fastPoseWeight(IsoPlayer player) {
        if(!player.isLocalPlayer()) return CartMotionSync.fastWeight(player);
        State state=states.get(player);
        if(state==null) return 0;
        float t=(float)Math.min(1,state.fastPoseTail/.1);
        return t*t*(3-2*t);
    }

    static float sideClearance(IsoPlayer player) {
        if(!player.isLocalPlayer()) return CartMotionSync.sideClearance(player);
        State state=states.get(player);
        return state==null?0:state.sideClearance;
    }

    private static double footprintFront(IsoPlayer player,State state) {
        return player.isRunning() || player.isSprinting() || state.fastPoseTail>0
            || CartLegPace.woodenFastShift(player)<0?CartFootprint.FAST_FRONT:CartFootprint.WALK_FRONT;
    }

    public static double lean(IsoPlayer player) {
        if(!player.isLocalPlayer()) return CartMotionSync.lean(player);
        State state=states.get(player);
        return state!=null && enabled(player) && wheelbarrow(player) ? state.lean : 0;
    }

    public static double clearanceLean(IsoPlayer player) {
        if(!player.isLocalPlayer()) return CartMotionSync.pressure(player);
        State state=states.get(player);
        return state!=null && enabled(player) && wooden(player)
            ? Math.max(Math.abs(state.lean),state.bank.pressure):0;
    }

    public static double wheelPhase(IsoPlayer player) {
        State state=states.get(player);
        return state!=null && enabled(player) && wooden(player)
            ? state.path?CartWheelSpin.itemPhase(state.cart):CartWheelSpin.advance(state.wheelOrigin+state.wheelPhase,CartSteeringMath.woodenAxle((float)clearanceLean(player),CartLegPace.woodenGaitShift(player))
                -CartSteeringMath.woodenAxle(0,0)) : Double.NaN;
    }

    static double wheelPhase(IsoPlayer player, zombie.core.skinnedmodel.model.ModelSlotRenderData slot, org.joml.Matrix4f cart) {
        var state=states.get(player);
        if(state!=null && state.path && enabled(player))
            return CartWheelSpin.follow(state.cart,slot.x,slot.y,slot.animPlayerAngle,cart);
        double phase=wheelPhase(player);
        if(state==null || !Double.isFinite(phase)) return phase;
        if(!state.wheelRendered) {
            double followed=CartWheelSpin.follow(state.cart,slot.x,slot.y,slot.animPlayerAngle,cart);
            if(!Double.isFinite(followed)) return Double.NaN;
            state.wheelOrigin+=Math.IEEEremainder(followed-phase,Math.PI*2);
            state.wheelRendered=true;
            phase=followed;
        }
        CartWheelSpin.record(state.cart,slot.x,slot.y,slot.animPlayerAngle,cart,phase);
        return phase;
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
            case "SaucedWheelbarrow.WheelbarrowWood" -> CartSteeringMath.woodenAxle((float)clearanceLean(player),CartLegPace.woodenGaitShift(player));
            case "SaucedWheelbarrow.WheelbarrowMetal" -> 1.1691522;
            default -> 0;
        };
    }

    private static double pivotAxle(IsoPlayer player) {
        double axle=axle(player);
        return axle>0?axle:CartSteeringMath.AXLE_DISTANCE;
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

    static boolean blockedProbe(CartFootprint.Query query,float x,float y,double heading,
                                double dx,double dy,double axle,double front) {
        if(!Double.isFinite(dx+dy+heading)) return true;
        if(!CartFootprint.clear(query,x,y,heading,front))
            return dx*Math.cos(heading)+dy*Math.sin(heading)>=0;
        double fraction=CartFootprint.limit(query,x,y,heading,dx,dy,axle,front);
        var slide=CartFootprint.slide(query,x,y,heading,dx,dy,front,fraction,-.04,.04);
        double distance=slide==null?Math.hypot(dx,dy)*fraction:Math.hypot(slide.x(),slide.y());
        return distance<=Math.max(1e-6,2*Math.max(Math.ulp(x),Math.ulp(y)));
    }

    /**
     * Hook 1: at IsoPlayer.moveUnmodded(FF)V entry, replace its two arguments with
     * this returned vector. Continue the original method, including slowFactor.
     * Read result.x/y immediately; the vector belongs to this player's state.
     */
    public static Vector2 movement(IsoPlayer player, float x, float y) {
        State state = states.get(player);
        if (!enabled(player)) return passthrough.get().set(x, y);
        if(pathMode(player) || state!=null && state.path) state=state(player);
        if(state==null) return passthrough.get().set(x,y);
        if(state.cart!=player.getPrimaryHandItem()) {reset(player);return passthrough.get().set(x,y);}
        // Only the native locomotion call should be redirected; do not double-plan.
        if (state.pending) return passthrough.get().set(x, y);
        state.startX = player.getX();
        state.startY = player.getY();
        double distance = Math.hypot(x, y);
        if(state.path) return pathMovement(player,state,x,y);
        // Relative intent follows the accepted yaw, even between native input updates.
        if(state.relative && keyboard(player)) relativeTarget(player,state);
        double dt=Math.max(0,Math.min(.1,GameTime.getInstance().getRealworldSecondsSinceLastUpdate()));
        if(state.braking || state.brakeLimit>0 && CartLegPace.brakeTrack(player)!=null)
            distance=Math.min(distance,state.brakeLimit*dt);
        if(dt>0) {
            // Seed a resumed Sprint from the coasting speed without changing the stop's cadence.
            if(state.braking && state.brakeLimit>0)
                state.pace.reset(state.brakePace*Math.max(0,Math.min(1,distance/(dt*state.brakeLimit))));
        }
        state.load = load(player);
        CartFootprint.Query query=wooden(player) && player.getCurrentSquare()!=null?CartFootprint.world(player):null;
        if(query!=null) state.footprintFront=footprintFront(player,state);
        boolean footprintClear=query!=null && CartFootprint.clear(query,state.startX,state.startY,state.heading,state.footprintFront);
        boolean guided=Double.isFinite(state.wallHeading) && state.wantsMove && !state.braking
            && !state.stationaryRoot && !state.reversal.active && state.reversal.direction>0 && footprintClear
            && CartFootprint.followWall(query,state.startX,state.startY,state.heading,state.target,state.wallHeading,
                state.wallNormalX,state.wallNormalY,state.footprintFront);
        if(!guided) state.wallHeading=Double.NaN;
        double rollingTarget=guided?state.wallHeading:state.reversal.braking?state.brakeTarget
            :state.wantsMove?state.target:state.heading+(state.reversal.direction<0?Math.PI:0);
        if(state.stationaryRoot) {
            CartSteeringMath.stationaryStep(state.heading,state.stationary?state.target:state.heading,
                distance,dt,state.load,pivotAxle(player),state.stationaryRate,state.requested);
            // Retain planned cadence across sub-ULP coordinates; only accepted movement changes heading.
            state.stationaryRate=dt>0?state.requested.turn()/dt:0;
        } else if(wooden(player)) CartSteeringMath.woodenStep(state.heading,
                rollingTarget, distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate(),state.load,axle(player),
                state.turnRate,state.reversal.direction<0,state.requested);
        else CartSteeringMath.step(state.heading,
                state.relative || state.moving ? state.target : state.heading, distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate(), state.load, axle(player),
                52, state.relative?state.reversal.direction<0:state.moving && CartSteeringMath.reversing(state.heading,state.target),state.requested);
        state.pending = true;
        state.result.set((float)state.requested.x(),(float)state.requested.y());
        state.cartBlocked=guided;state.recovering=false;
        state.slideTurn=Double.NaN;
        if(query!=null) {
            if(!footprintClear) {
                // An equipped/door-overlapped cart may back out, without sweeping its nose sideways.
                state.recovering=true;
                double reverse=Math.min(0,state.result.x*Math.cos(state.heading)+state.result.y*Math.sin(state.heading));
                state.result.set((float)(reverse*Math.cos(state.heading)),(float)(reverse*Math.sin(state.heading)));
                state.cartBlocked=reverse==0;
            } else {
                double fraction=CartFootprint.limit(query,state.startX,state.startY,state.heading,
                    state.result.x,state.result.y,axle(player),state.footprintFront);
                double guideCap=Math.min((1.6-.3*state.load)*dt,distance/axle(player));
                double guideBase=Math.max(-guideCap,Math.min(guideCap,state.turnRate*dt));
                var slide=CartFootprint.slide(query,state.startX,state.startY,state.heading,
                    state.result.x,state.result.y,state.footprintFront,fraction,
                    Math.max(-guideCap,guideBase-6*dt*dt),Math.min(guideCap,guideBase+6*dt*dt));
                if(slide==null) state.result.scale((float)fraction);
                else {
                    double nx=slide.normalX(),ny=slide.normalY();
                    if(state.wantsMove && !state.braking && !state.stationaryRoot && !state.reversal.active
                        && state.reversal.direction>0 && CartFootprint.pressingWall(state.target,slide.target(),nx,ny)) {
                        state.wallHeading=slide.target();state.wallNormalX=nx;state.wallNormalY=ny;
                    }
                    state.result.set((float)slide.x(),(float)slide.y());state.slideTurn=slide.turn();
                }
                state.cartBlocked|=fraction<1;
            }
        }
        return state.result;
    }

    private static Vector2 pathMovement(IsoPlayer player,State state,float x,float y) {
        state.wallHeading=Double.NaN;
        Vector2 facing=player.getAnimForwardDirection(state.input);
        state.heading=Math.atan2(facing.y,facing.x);
        state.pending=true;state.result.set(x,y);
        state.footprintFront=footprintFront(player,state);
        state.cartBlocked=state.recovering=false;
        if(player.getCurrentSquare()!=null) {
            var query=CartFootprint.world(player);
            if(!CartFootprint.clear(query,state.startX,state.startY,state.heading,state.footprintFront)) {
                state.recovering=true;
                double reverse=Math.min(0,x*Math.cos(state.heading)+y*Math.sin(state.heading));
                state.result.set((float)(reverse*Math.cos(state.heading)),(float)(reverse*Math.sin(state.heading)));
                state.cartBlocked=reverse==0;
            } else {
                double allowed=CartFootprint.rigidLimit(query,state.startX,state.startY,state.heading,
                    x,y,state.heading,state.footprintFront);
                state.result.scale((float)allowed);state.cartBlocked=allowed<1;
            }
        }
        if(state.cartBlocked) failPath(player);
        return state.result;
    }

    public static void beginPath(IsoGameCharacter character) {
        if(character instanceof IsoPlayer player && enabled(player) && pathMode(player))
            state(player).cartBlocked=false;
    }

    private static void failPath(IsoPlayer player) {
        var path=player.getPathFindBehavior2();
        if(path!=null && pathMode(player)) path.Failed(player);
    }

    public static zombie.pathfind.PathFindBehavior2.BehaviorResult pathResult(IsoGameCharacter character,
            zombie.pathfind.PathFindBehavior2.BehaviorResult result) {
        if(!(character instanceof IsoPlayer player) || !enabled(player) || !pathMode(player)) return result;
        State state=state(player);
        state.footprintFront=footprintFront(player,state);
        boolean blocked=state.cartBlocked;
        if(result==zombie.pathfind.PathFindBehavior2.BehaviorResult.Succeeded && player.getCurrentSquare()!=null) {
            Vector2 facing=player.getAnimForwardDirection(state.input);
            double heading=Math.atan2(facing.y,facing.x);
            double target=Math.atan2(player.getForwardDirectionY(),player.getForwardDirectionX());
            blocked|=CartFootprint.rigidLimit(CartFootprint.world(player),player.getX(),player.getY(),heading,
                0,0,target,state.footprintFront)<1;
            if(blocked) player.setTargetAndCurrentDirection((float)Math.cos(heading),(float)Math.sin(heading));
        }
        if(blocked) {
            failPath(player);
            return zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed;
        }
        return result;
    }

    private static void pathHeading(IsoPlayer player,State state) {
        Vector2 facing=player.getAnimForwardDirection(state.input);
        double heading=state.pending?state.heading:Math.atan2(facing.y,facing.x);
        double target=Math.atan2(player.getForwardDirectionY(),player.getForwardDirectionX());
        double dt=Math.max(0,Math.min(.1,GameTime.getInstance().getRealworldSecondsSinceLastUpdate()));
        state.sideClearance=CartLegPace.releaseSideShift(state.sideClearance,CartLegPace.woodenSideShift(player),dt);
        state.fastPoseTail=player.isRunning() || player.isSprinting() || CartLegPace.brakeTrack(player)!=null
            ?.4:Math.max(0,state.fastPoseTail-dt);
        state.footprintFront=footprintFront(player,state);
        if(player.getCurrentSquare()!=null) {
            var query=CartFootprint.world(player);
            if(state.pending && !state.recovering) {
                double dx=player.getX()-state.startX,dy=player.getY()-state.startY;
                double allowed=CartFootprint.rigidLimit(query,state.startX,state.startY,heading,dx,dy,heading,state.footprintFront);
                if(allowed<1) {
                    player.setX((float)(state.startX+dx*allowed));player.setY((float)(state.startY+dy*allowed));
                    player.setNextX(player.getX());player.setNextY(player.getY());
                    player.setCurrentSquareFromPosition();player.setMovingSquareNow();
                    state.cartBlocked=true;
                }
            }
            boolean rotation=CartFootprint.rigidLimit(query,player.getX(),player.getY(),heading,0,0,target,state.footprintFront)<1;
            if(rotation) {
                // Restore the clear pose before native animation can rotate its nose through an obstacle.
                player.setTargetAndCurrentDirection((float)Math.cos(heading),(float)Math.sin(heading));
                state.cartBlocked=true;
            }
        }
        if(state.cartBlocked) failPath(player);
        state.pending=false;
    }

    /**
     * Hook 2: IsoGameCharacter.postUpdateAnimating()V ENTRY. Its caller already
     * ran IsoMovingObject.postupdate() collisions. Capture native input-facing
     * before overriding it, then animate only the accepted part of the arc.
     */
    public static void heading(IsoGameCharacter character) {
        if (!(character instanceof IsoPlayer player)) return;
        if(!player.isLocalPlayer() && states.containsKey(player)) reset(player);
        if(CartMotionSync.update(player)) return;
        State state = states.get(player);
        if (!enabled(player)) {
            if (state != null) reset(player);
            return;
        }
        state=state(player);
        state.visualSpeed=-1;
        if(state.path) { pathHeading(player,state);publish(player,state);return; }
        player.setVariable("ToolkitCartPivot",true);
        double desired = Math.atan2(player.getForwardDirectionY(), player.getForwardDirectionX());
        state=state(player);
        // Native clears the gait flags before UpdateInputState; retain the last finalized gait for release.
        state.fastMoving=player.isRunning() || player.isSprinting();
        state.sprintMoving=player.isSprinting();
        boolean sprintRequested=state.sprintRequested;
        state.sprintRequested=false;
        state.load=load(player);
        double actualX = 0, actualY = 0;
        double fraction = 0, acceptedTurn=0;
        boolean blocked=false;
        if (state.pending) {
            actualX = player.getX() - state.startX;
            actualY = player.getY() - state.startY;
            double slideTurn=state.slideTurn;
            if(Double.isFinite(slideTurn)) {
                double planned=state.result.x*state.result.x+state.result.y*state.result.y;
                slideTurn*=planned>0?Math.max(0,Math.min(1,(actualX*state.result.x+actualY*state.result.y)/planned)):0;
            }
            if(wooden(player) && !state.recovering && player.getCurrentSquare()!=null) {
                var query=CartFootprint.world(player);
                double allowed=Double.isFinite(slideTurn)
                    ?CartFootprint.rigidLimit(query,state.startX,state.startY,state.heading,actualX,actualY,
                        state.heading+slideTurn,state.footprintFront)
                    :CartFootprint.limit(query,state.startX,state.startY,state.heading,actualX,actualY,axle(player),state.footprintFront);
                if(allowed<1) {
                    player.setX((float)(state.startX+actualX*allowed));player.setY((float)(state.startY+actualY*allowed));
                    player.setNextX(player.getX());player.setNextY(player.getY());
                    player.setCurrentSquareFromPosition();player.setMovingSquareNow();
                    actualX=player.getX()-state.startX;actualY=player.getY()-state.startY;
                    state.cartBlocked=true;
                }
                slideTurn*=allowed;
            }
            fraction = CartSteeringMath.acceptedFraction(state.requested,
                    actualX, actualY);
            blocked=state.cartBlocked && actualX==0 && actualY==0
                || blockedStep(state.requested,state.startX,state.startY,fraction);
            double turn = state.recovering?0:Double.isFinite(slideTurn)?slideTurn:wheelbarrow(player)
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
        if(wooden(player)) state.sideClearance=CartLegPace.releaseSideShift(state.sideClearance,CartLegPace.woodenSideShift(player),dt);
        var stop=wooden(player)?CartLegPace.brakeTrack(player):null;
        if(state.braking) {
            state.brakeWait+=dt;
            if(stop!=null && !state.brakeSeen) {
                // A loaded cart takes slightly longer to settle, with the same authored foot sequence.
                stop.setSpeedDelta((float)(1/(state.brakeDuration*(1+.12*state.load))));
                state.brakeSeen=true;
            }
            if(blocked || state.brakeSeen && stop==null || !state.brakeSeen && state.brakeWait>.3) {
                if(blocked) {
                    CartLegPace.cancelBrake(player,false);
                    CartLegPace.applySpeed(player,0,0,0);
                    state.visualSpeed=0;
                }
                state.braking=false;
                player.setVariable("ToolkitCartWoodBrake",false);
            }
        }
        // The native start/stop pose can outlive the last running track; release its clearance gradually.
        if(wooden(player)) state.fastPoseTail=player.isRunning() || player.isSprinting() || stop!=null?.4:Math.max(0,state.fastPoseTail-dt);
        state.actualDistance=Math.hypot(actualX,actualY);
        if(dt>0 && !state.braking) {
            // Native applies slowdown after this hook's budget; do not count it twice in the stop cap.
            double factor=1-player.getSlowFactor();
            state.nativeSpeed=factor>0?state.actualDistance/(dt*factor):0;
        }
        double travel=actualX*Math.cos(state.heading)+actualY*Math.sin(state.heading);
        double bank=state.stationaryRoot ? 0 : wooden(player) ? CartSteeringMath.rollingLean(acceptedTurn,travel,dt)
            : wheelbarrow(player) && dt>0 ? Math.max(-.10,Math.min(.10,Math.signum(travel)*acceptedTurn/dt*.065)) : 0;
        state.turnRate=dt>0?acceptedTurn/dt:0;
        if(blocked) state.stationaryRate=0;
        if(wooden(player)) state.lean=state.bank.update(bank,dt);
        else state.lean+=(bank-state.lean)*(1-Math.exp(-dt/.08));
        state.moving = player.isJustMoved();
        if(state.relative && keyboard(player)) relativeTarget(player,state);
        else if(!state.hasInput && (!wooden(player) || !state.stationaryRoot)) state.target = state.moving ? desired : state.heading;
        state.hasInput=false;
        boolean hardStop=false;
        if(wooden(player) && state.wantsMove && !state.stationaryRoot && !state.reversal.active
            && !state.braking && state.actualDistance<1e-6 && (blocked || state.brace>0)
            && player.getCurrentSquare()!=null) {
            // Query the intended step even at zero root speed; this never moves the player or wheel.
            CartSteeringMath.woodenStep(state.heading,state.target,.03,1.0/60,state.load,axle(player),
                state.turnRate,state.reversal.direction<0,state.braceProbe);
            hardStop=blockedProbe(CartFootprint.world(player),player.getX(),player.getY(),state.heading,
                state.braceProbe.x(),state.braceProbe.y(),axle(player),state.footprintFront);
        }
        state.brace=Math.max(0,Math.min(1,state.brace+(hardStop?dt:-dt)/.16));
        boolean bracePose=state.brace>0 && state.wantsMove && !state.stationaryRoot && !state.reversal.active;
        double length = Math.hypot(actualX, actualY);
        if(state.stationary && Math.abs(CartSteeringMath.wrap(state.target-state.heading))<Math.toRadians(.5))
            state.stationary=state.stationaryRoot=false;
        if ((state.moving || bracePose) && length < 1e-6) {
            // Idle/blocked clips need intent to generate their first root-motion budget.
            if(wooden(player)) CartSteeringMath.woodenStep(state.heading,state.reversal.braking?state.brakeTarget:state.target,0.03,1.0/60,
                                  state.load,axle(player),state.turnRate,state.reversal.direction<0,state.requested);
            else CartSteeringMath.step(state.heading, state.target, 0.03, 1.0 / 60,
                                  state.load, axle(player),52,state.relative?state.reversal.direction<0
                                      :CartSteeringMath.reversing(state.heading,state.target),state.requested);
            actualX = state.requested.x(); actualY = state.requested.y();
            length = Math.hypot(actualX, actualY);
        }
        if(state.stationaryRoot) {
            // Keep the full native stride; idle blending shortens it into rapid shuffling.
            CartSteeringMath.stationaryStep(state.heading,state.stationary?state.target:state.heading,
                1,dt,state.load,pivotAxle(player),state.stationaryRate,state.requested);
            player.setVariable("ToolkitCartStepX",state.moving && state.stationary?(float)(-Math.signum(state.requested.turn())):0);
            player.setVariable("ToolkitCartStepY",0.0f);
        } else if ((!state.moving && !bracePose) || length < 1e-6) {
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
        // Drop inward input through native cadence once, preserving full strides and the movement budget.
        float wallScale=Double.isFinite(state.wallHeading) && state.wantsMove && !state.reversal.active
            && !state.stationaryRoot && CartFootprint.pressingWall(state.target,state.wallHeading,state.wallNormalX,state.wallNormalY)
            ?(float)Math.max(0,Math.cos(state.target-state.wallHeading)):1;
        target*=wallScale;
        if(state.stationaryRoot) {
            // Cargo slows the full stride's cadence instead of reducing its spatial amplitude.
            target*=Math.max(0,Math.min(1,player.getVariableFloat("WalkSpeed",.8f)));
            state.sprintMomentum=false;
            if(Float.isFinite(target)) {
                // Feed next frame's native cadence, rather than moving planted feet with a synthetic budget.
                double speed=dt>0?Math.min(target,Math.hypot(state.requested.x(),state.requested.y())/dt):0;
                state.pace.reset(speed);
                CartLegPace.applySpeed(player,(float)speed,stepX,stepY);
                state.visualSpeed=(float)speed;
                if(state.reversal.braking) state.reversal.stopped(dt,speed==0,state.actualDistance<1e-6);
            } else {
                state.pace.reset(0);
                CartLegPace.apply(player,CartLegPace.scale(player,stepX,stepY));
                if(state.reversal.braking) state.reversal.stopped(dt,true,state.actualDistance<1e-6);
            }
        } else if(state.braking) {
            // The authored stop owns deceleration; freezing its outgoing gait would break the blend.
            state.sprintMomentum=false;
        } else if(bracePose && Float.isFinite(target)) {
            state.sprintMomentum=!hardStop;
            if(hardStop) state.pace.reset(0);
            else target=(float)state.pace.update(target,dt,state.load,true);
            state.visualSpeed=CartLegPace.brace(player,target,stepX,stepY,state.brace,hardStop);
        } else if(Float.isFinite(target)) {
            if(blocked) state.pace.reset(0);
            // Native uses Run for the first Sprint frame, before isSprinting becomes true.
            if(state.fastMoving || sprintRequested && state.moving) {
                if(player.isRunning() && !sprintRequested && !state.sprintMomentum && CartLegPace.brakeTrack(player)==null)
                    state.pace.reset(target);
                state.sprintMomentum=true;
                state.momentumSprint=player.isSprinting() || sprintRequested;
            }
            if(state.reversal.active) {
                state.sprintMomentum=false;
                double speed=state.pace.update(state.reversal.braking?0:target,dt,state.load);
                if(state.reversal.braking && state.pace.settled(0)) { state.pace.reset(0);speed=0; }
                float radius=target>1e-6?Math.min(1,(float)(speed/target)):0;
                stepX*=radius;stepY*=radius;
                player.setVariable("ToolkitCartStepX",stepX);
                player.setVariable("ToolkitCartStepY",stepY);
                CartLegPace.applySpeed(player,(float)speed,stepX,stepY);
                state.visualSpeed=(float)speed;
                if(state.reversal.braking) state.reversal.stopped(dt,speed==0,state.actualDistance<1e-6);
                else if(state.pace.settled(target)) state.reversal.active=false;
            } else if(state.sprintMomentum) {
                double speed=state.pace.update(target,dt,state.load,true);
                CartLegPace.applySpeed(player,(float)speed,stepX,stepY);
                state.visualSpeed=(float)speed;
                if(state.fastMoving) state.fastPace=speed;
                else if(Math.abs(speed-target)<=Math.max(1e-3,target*.02)) state.sprintMomentum=false;
            } else {
                state.pace.reset(target);
                if(wallScale<1) {
                    CartLegPace.applySpeed(player,target,stepX,stepY);
                    state.visualSpeed=target;
                }
                else CartLegPace.apply(player,CartLegPace.scale(player,stepX,stepY));
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
        publish(player,state);
    }

    private static void publish(IsoPlayer player,State state) {
        CartMotionSync.publish(player,state.lean,Math.max(Math.abs(state.lean),state.bank.pressure),
            state.sideClearance,fastPoseWeight(player),state.visualSpeed);
    }

    /** Native player packets are built before postUpdateAnimating restores the accepted cart yaw. */
    public static float networkHeading(IsoPlayer player) {
        var state=states.get(player);
        return state!=null && enabled(player) && state.cart==player.getPrimaryHandItem()
            ?(float)state.heading:Float.NaN;
    }

    /** Native animation updates can enter a protected state after the heading entry hook. */
    public static void finish(IsoGameCharacter character) {
        if(character instanceof IsoPlayer player && states.containsKey(player) && !enabled(player)) reset(player);
    }

    /** Death/menu cleanup discards pending state and releases only our own variables. */
    public static void reset(IsoPlayer player) {
        CartMotionSync.reset(player);
        CartLegPace.cancelBrake(player,true);
        states.remove(player);
        player.setVariable("ToolkitCartWoodBrake",false);
        player.setVariable("ToolkitCartBrakeSprint",false);
        player.clearVariable("ToolkitCartLegPace");
        player.setVariable("ToolkitCartPivot",false);
        player.setVariable("ToolkitCartStepX", 0.0f);
        player.setVariable("ToolkitCartStepY", 0.0f);
    }

    private CartSteeringHooks() {}
}
