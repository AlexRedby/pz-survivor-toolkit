package zombie.characters;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import sun.misc.Unsafe;
import zombie.core.Core;
import zombie.entity.Component;
import zombie.entity.GameEntity;
import zombie.entity.components.fluids.FluidContainer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.util.flags.ShortFlags;

/** Native packet flag and autoDrink guards, without creating a world, GUI or network connection. */
public final class FoodAutoDrinkChecks {
    private static final class DrinkReached extends RuntimeException {
        DrinkReached() { super("native autoDrink reached DrinkFluid", null, false, false); }
    }
    private static final DrinkReached DRINK_REACHED = new DrinkReached();

    public static final class Player extends IsoPlayer {
        NetworkPlayerAI ai;
        InventoryItem anchor;
        int waterLookups, drinks;
        float fraction;
        Player() { super(null); }
        // The remaining packet fields are unrelated to this test and need a live world normally.
        @Override public void setSneaking(boolean value) { }
        @Override public void StopBurning() { }
        @Override public void setAsleep(boolean value) { }
        @Override public void setRunning(boolean value) { }
        @Override public void setSprinting(boolean value) { }
        @Override public boolean isDoShove() { return false; }
        @Override public void setDoShove(boolean value) { }
        @Override public void setDoGrapple(boolean value) { }
        @Override public void setDoContinueGrapple(boolean value) { }
        @Override public void setOnFloor(boolean value) { }
        @Override public void setPerformingAnAction(boolean value) { }
        @Override public NetworkPlayerAI getNetworkCharacterAI() { return ai; }
        @Override public boolean isAsleep() { return false; }
        @Override public boolean isPerformingGrappleAnimation() { return false; }
        @Override public boolean isKnockedDown() { return false; }
        @Override public boolean isbFalling() { return false; }
        @Override public boolean isAiming() { return false; }
        @Override public boolean isClimbing() { return false; }
        @Override public InventoryItem getWaterSource(ArrayList<InventoryItem> items) {
            waterLookups++;
            require(items.contains(anchor), "native autoDrink did not inspect the fixture inventory");
            return anchor;
        }
        @Override public boolean DrinkFluid(InventoryItem item, float amount, boolean useUtensil) {
            require(item == anchor && !useUtensil, "native autoDrink selected an unexpected consumption target");
            drinks++;
            fraction = amount;
            // Stop before stats/body-damage processing and server packet emission. This spy
            // proves the native call and fraction, not actual fluid removal or replication.
            throw DRINK_REACHED;
        }
        void init(Unsafe unsafe) throws Exception {
            FoodAutoDrinkChecks.set(IsoGameCharacter.class, this, "stats", new Stats());
            stats.set(CharacterStat.THIRST, .8f);
            inventory = new ItemContainer();
            ai = (NetworkPlayerAI)unsafe.allocateInstance(NetworkPlayerAI.class);
            anchor = (InventoryItem)unsafe.allocateInstance(InventoryItem.class);
            FluidContainer fluid = FluidContainer.CreateContainer();
            // Only read-only native getAmount is used before the DrinkFluid spy. An inert
            // 1 L cache avoids loading scripts, fluid definitions or a game world.
            FoodAutoDrinkChecks.set(FluidContainer.class, fluid, "cacheInvalidated", false);
            FoodAutoDrinkChecks.set(FluidContainer.class, fluid, "amountCache", 1f);
            Method add = GameEntity.class.getDeclaredMethod("addComponent", Component.class);
            add.setAccessible(true);
            require(Boolean.TRUE.equals(add.invoke(anchor, fluid)), "could not attach the inert native fluid component");
            inventory.getItems().add(anchor);
        }
    }

    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }
    private static void set(Class<?> owner, Object target, String name, Object value) throws Exception {
        Field field = owner.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }
    private static void packet(Player player, boolean enabled) {
        var flags = ShortFlags.alloc();
        flags.set(NetworkPlayerVariables.Flags.isAutoDrinkEnabled, enabled);
        // Exercise the actual short-payload decoder, not a replacement setAutoDrink stub.
        NetworkPlayerVariables.setBooleanVariables(player, flags.asShort());
        require(player.getAutoDrink() == enabled, "native packet did not apply the auto-drink flag");
    }
    private static void noDrink(Player player, String reason) {
        int lookups = player.waterLookups, drinks = player.drinks;
        player.autoDrink();
        require(player.waterLookups == lookups && player.drinks == drinks, reason);
        require(player.getStats().get(CharacterStat.THIRST) == .8f, "guarded autoDrink changed thirst");
        require(player.anchor.getFluidContainer().getAmount() == 1f, "guarded autoDrink changed the fixture amount");
    }

    public static void main(String[] args) throws Exception {
        Field field = Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        Unsafe unsafe = (Unsafe)field.get(null);
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Core core = Core.getInstance();
        boolean oldCore = core.getOptionAutoDrink(), oldClient = GameClient.client, oldServer = GameServer.server;
        try {
            GameClient.client = false;
            GameServer.server = true;
            Player player = (Player)unsafe.allocateInstance(Player.class);
            player.init(unsafe);
            core.setOptionAutoDrink(true);
            player.setAutoDrink(false);
            noDrink(player, "player-only guard did not block the server before a packet");
            packet(player, true);
            try {
                player.autoDrink();
                throw new AssertionError("incoming packet did not bypass the old player-only guard");
            } catch (DrinkReached expected) {
                require(expected == DRINK_REACHED, "unexpected consumption boundary failure");
            }
            require(player.waterLookups == 1 && player.drinks == 1 && player.fraction == 1f,
                "thirst .8 with a 1 L anchor did not request full native consumption");
            core.setOptionAutoDrink(false);
            for (boolean enabled : new boolean[]{false, true, true}) {
                player.setAutoDrink(false);
                packet(player, enabled);
                noDrink(player, "Core guard was bypassed by an incoming player flag");
            }
            System.out.println("FOOD_AUTO_DRINK_CHECKS_PASS nativeBooleanPacket=true nativeAutoDrink=true "
                + "playerOnlyGuardBypassed=true fullOneLiterFraction=1.0 coreGuardSurvivesPacket=true "
                + "drinkBoundarySpy=true actualFluidRemoval=false");
        } finally {
            core.setOptionAutoDrink(oldCore);
            GameClient.client = oldClient;
            GameServer.server = oldServer;
        }
    }
}
