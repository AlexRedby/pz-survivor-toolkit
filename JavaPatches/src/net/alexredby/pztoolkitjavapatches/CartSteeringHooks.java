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
        double heading, target, load;
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

    private static boolean enabled(IsoPlayer player) {
        return player.isLocalPlayer() && player.getVariableBoolean("ToolkitCartMotion")
                && !player.isDead() && !player.hasHitReaction() && !player.isKnockedDown()
                && !player.isGettingUp() && !player.isGrappling() && !player.isBeingGrappled()
                && !player.isRagdollSimulationActive()
                && supportedCart(player)
                // Path following needs its own corner/collision acceptance tests.
                && !player.hasPath()
                && player.getPrimaryHandItem() instanceof InventoryContainer;
    }

    /**
     * Hook 1: at IsoPlayer.moveUnmodded(FF)V entry, replace its two arguments with
     * this returned vector. Continue the original method, including slowFactor.
     * Read result.x/y immediately; the vector belongs to this player's state.
     */
    public static Vector2 movement(IsoPlayer player, float x, float y) {
        State state = states.get(player);
        if (state == null || !enabled(player)) return passthrough.get().set(x, y);
        // Only the native locomotion call should be redirected; do not double-plan.
        if (state.pending) return passthrough.get().set(x, y);
        state.startX = player.getX();
        state.startY = player.getY();
        double distance = Math.hypot(x, y);
        InventoryContainer cart = (InventoryContainer) player.getPrimaryHandItem();
        ItemContainer contents = cart.getInventory();
        int capacity = contents.getEffectiveCapacity(player);
        state.load = capacity > 0 ? contents.getCapacityWeight() / capacity : 0;
        CartSteeringMath.step(state.heading,
                state.moving ? state.target : state.heading, distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate(), state.load, state.requested);
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
        if (state == null) {
            state = new State();
            Vector2 facing = player.getAnimForwardDirection(new Vector2());
            state.heading = Math.atan2(facing.y, facing.x);
            states.put(player, state);
        }
        double actualX = 0, actualY = 0;
        double fraction = 0;
        if (state.pending) {
            actualX = player.getX() - state.startX;
            actualY = player.getY() - state.startY;
            fraction = CartSteeringMath.acceptedFraction(state.requested,
                    actualX, actualY);
            double turn = state.requested.turn() * fraction;
            state.heading = CartSteeringMath.wrap(state.heading + turn);
            state.pending = false;
        }
        state.moving = player.isJustMoved();
        state.target = state.moving ? desired : state.heading;
        double length = Math.hypot(actualX, actualY);
        if (state.moving && length < 1e-6) {
            // Idle/blocked clips need intent to generate their first root-motion budget.
            CartSteeringMath.step(state.heading, state.target, 0.03, 1.0 / 60,
                                  state.load, state.requested);
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
        // Scoped cart AnimNodes own maxTorsoTwist; native animation rewrites it.
        player.setTargetAndCurrentDirection((float) Math.cos(state.heading),
                                            (float) Math.sin(state.heading));
    }

    /** Death/menu cleanup discards pending state and releases only our own variables. */
    public static void reset(IsoPlayer player) {
        states.remove(player);
        player.setVariable("ToolkitCartPivot",false);
        player.setVariable("ToolkitCartStepX", 0.0f);
        player.setVariable("ToolkitCartStepY", 0.0f);
    }

    private CartSteeringHooks() {}
}
