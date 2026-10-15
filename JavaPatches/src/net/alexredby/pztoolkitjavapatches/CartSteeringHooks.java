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
        zombie.inventory.InventoryItem cart;
        float startX, startY;
        boolean moving, pending;
        final CartSteeringMath.Step requested = new CartSteeringMath.Step();
        final Vector2 result = new Vector2();
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

    public static double lean(IsoPlayer player) {
        State state=states.get(player);
        return state!=null && enabled(player) && wheelbarrow(player) ? state.lean : 0;
    }

    public static double wheelPhase(IsoPlayer player) {
        State state=states.get(player);
        return state!=null && enabled(player) && wooden(player)?state.wheelPhase:Double.NaN;
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
            case "SaucedWheelbarrow.WheelbarrowWood" -> 1.0224308175;
            case "SaucedWheelbarrow.WheelbarrowMetal" -> 1.1691522;
            default -> 0;
        };
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
        InventoryContainer cart = (InventoryContainer) player.getPrimaryHandItem();
        ItemContainer contents = cart.getInventory();
        int capacity = contents.getEffectiveCapacity(player);
        state.load = capacity > 0 ? contents.getCapacityWeight() / capacity : 0;
        if(wooden(player)) CartSteeringMath.woodenStep(state.heading,
                state.moving ? state.target : state.heading, distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate(),state.load,axle(player),
                state.turnRate,state.requested);
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
        if (state == null || state.cart!=player.getPrimaryHandItem()) {
            state = new State();
            state.cart=player.getPrimaryHandItem();
            Vector2 facing = player.getAnimForwardDirection(new Vector2());
            state.heading = Math.atan2(facing.y, facing.x);
            states.put(player, state);
        }
        double actualX = 0, actualY = 0;
        double fraction = 0, acceptedTurn=0;
        if (state.pending) {
            actualX = player.getX() - state.startX;
            actualY = player.getY() - state.startY;
            fraction = CartSteeringMath.acceptedFraction(state.requested,
                    actualX, actualY);
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
        double travel=actualX*Math.cos(state.heading)+actualY*Math.sin(state.heading);
        double bank=wooden(player) ? CartSteeringMath.rollingLean(acceptedTurn,travel,dt)
            : wheelbarrow(player) && dt>0 ? Math.max(-.10,Math.min(.10,Math.signum(travel)*acceptedTurn/dt*.065)) : 0;
        state.turnRate=dt>0?acceptedTurn/dt:0;
        if(wooden(player)) state.lean=state.bank.update(bank,dt);
        else state.lean+=(bank-state.lean)*(1-Math.exp(-dt/.08));
        state.moving = player.isJustMoved();
        state.target = state.moving ? desired : state.heading;
        double length = Math.hypot(actualX, actualY);
        if (state.moving && length < 1e-6) {
            // Idle/blocked clips need intent to generate their first root-motion budget.
            if(wooden(player)) CartSteeringMath.woodenStep(state.heading,state.target,0.03,1.0/60,
                                  state.load,axle(player),state.turnRate,state.requested);
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
            double pace=Math.max(0,Math.min(1,player.getVariableFloat("WalkSpeed",0.8f)));
            player.setVariable("ToolkitCartStepX", (float) (pace * (-actualX * sin + actualY * cos) / length));
            player.setVariable("ToolkitCartStepY", (float) (pace * (actualX * cos + actualY * sin) / length));
        }
        CartLegPace.apply(player,CartLegPace.scale(player,
            player.getVariableFloat("ToolkitCartStepX",0),player.getVariableFloat("ToolkitCartStepY",0)));
        // Scoped cart AnimNodes own maxTorsoTwist; native animation rewrites it.
        player.setTargetAndCurrentDirection((float) Math.cos(state.heading),
                                            (float) Math.sin(state.heading));
    }

    /** Death/menu cleanup discards pending state and releases only our own variables. */
    public static void reset(IsoPlayer player) {
        states.remove(player);
        player.clearVariable("ToolkitCartLegPace");
        player.setVariable("ToolkitCartPivot",false);
        player.setVariable("ToolkitCartStepX", 0.0f);
        player.setVariable("ToolkitCartStepY", 0.0f);
    }

    private CartSteeringHooks() {}
}
