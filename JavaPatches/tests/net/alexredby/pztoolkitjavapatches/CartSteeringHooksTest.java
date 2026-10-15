package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.util.Map;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.Vector2;
import zombie.iso.objects.IsoWorldInventoryObject;

public final class CartSteeringHooksTest {
    // Skip world/renderer constructors, as the existing NativeChecks fixture does.
    private static final class Player extends IsoPlayer {
        int blocked;
        boolean pivot;
        float stepX, stepY;
        ItemContainer inventory;
        InventoryItem primary, secondary;
        Player() { super(null, null, 0, 0, 0); }
        @Override public boolean isLocalPlayer() { return blocked != 8; }
        @Override public boolean isDead() { return blocked == 1; }
        @Override public boolean hasHitReaction() { return blocked == 2; }
        @Override public boolean isKnockedDown() { return blocked == 3; }
        @Override public boolean isGettingUp() { return blocked == 4; }
        @Override public boolean isGrappling() { return blocked == 5; }
        @Override public boolean isBeingGrappled() { return blocked == 6; }
        @Override public boolean isRagdollSimulationActive() { return blocked == 7; }
        @Override public boolean hasPath() { return blocked == 9; }
        @Override public boolean getVariableBoolean(String name) { return blocked != 10; }
        @Override public InventoryItem getPrimaryHandItem() { return primary; }
        @Override public InventoryItem getSecondaryHandItem() { return secondary; }
        @Override public ItemContainer getInventory() { return inventory; }
        @Override public float getForwardDirectionX() { return 1; }
        @Override public float getForwardDirectionY() { return 0; }
        @Override public Vector2 getAnimForwardDirection(Vector2 out) { return out.set(1, 0); }
        @Override public boolean isJustMoved() { return false; }
        @Override public void setTargetAndCurrentDirection(float x, float y) {}
        @Override public IAnimationVariableSlot setVariable(String name, boolean value) {
            if (name.equals("ToolkitCartPivot")) pivot = value;
            return null;
        }
        @Override public IAnimationVariableSlot setVariable(String name, float value) {
            if (name.equals("ToolkitCartStepX")) stepX = value;
            if (name.equals("ToolkitCartStepY")) stepY = value;
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

    public static void main(String[] args) throws Exception {
        Field unsafeField = Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe) unsafeField.get(null);
        Player player = (Player) unsafe.allocateInstance(Player.class);
        InventoryContainer cart = (InventoryContainer) unsafe.allocateInstance(InventoryContainer.class);
        player.inventory = new ItemContainer();
        player.primary = player.secondary = cart;
        cart.setContainer(player.inventory);
        Field stateField = CartSteeringHooks.class.getDeclaredField("states");
        stateField.setAccessible(true);
        Map<?, ?> states = (Map<?, ?>) stateField.get(null);
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
            check(!player.pivot && player.stepX == 0 && player.stepY == 0 && !states.containsKey(player),
                  gates[gate - 1] + " retained steering state");
        }
        CartSteeringHooks.reset(player);
        check(!states.containsKey(player), "repeated reset retained state");
        System.out.println("CART_STEERING_HOOKS_PASS (combat, local, path, scope, cart ownership, reset)");
    }
}
