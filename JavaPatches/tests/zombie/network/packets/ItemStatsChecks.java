package zombie.network.packets;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.Arrays;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.ItemStatsDefaults;
import sun.misc.Unsafe;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.Food;

/** Exercise the native omitted-value wire format against a reused packet, then its real apply path. */
public final class ItemStatsChecks {
    private record FloatStat(String field, String getter, float value) { }
    private record IntStat(String field, String getter, int value, int omitted) { }
    private static final FloatStat[] FLOATS = {
        new FloatStat("cookingTime", "getCookingTime", 30f),
        new FloatStat("minutesToCook", "getMinutesToCook", 31f),
        new FloatStat("minutesToBurn", "getMinutesToBurn", 60f),
        new FloatStat("hungChange", "getHungChange", -.25f),
        new FloatStat("calories", "getCalories", 123.5f),
        new FloatStat("proteins", "getProteins", 7.25f),
        new FloatStat("lipids", "getLipids", 3.75f),
        new FloatStat("carbohydrates", "getCarbohydrates", 22.5f),
        new FloatStat("thirstChange", "getThirstChangeUnmodified", -.125f),
        new FloatStat("painReduction", "getPainReduction", 1.5f),
        new FloatStat("endChange", "getEndChange", -.0625f),
        new FloatStat("stressChange", "getStressChangeUnmodified", -.375f),
        new FloatStat("fatigueChange", "getFatigueChange", -.1875f),
        new FloatStat("unhappyChange", "getUnhappyChangeUnmodified", 4.25f),
        new FloatStat("boredomChange", "getBoredomChangeUnmodified", 5.5f),
        new FloatStat("baseHunger", "getBaseHunger", -.5f)
    };
    private static final IntStat[] INTEGERS = {
        new IntStat("fluReduction", "getFluReduction", 3, 0),
        new IntStat("foodSicknessChange", "getFoodSicknessChange", 4, 0),
        new IntStat("fertilizedTime", "getFertilizedTime", 1234, 0),
        new IntStat("poisonDetectionLevel", "getPoisonDetectionLevel", 6, -1)
    };

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static Field field(String name) throws Exception {
        Field result = ItemStatsPacket.class.getDeclaredField(name);
        result.setAccessible(true);
        return result;
    }
    private static void floats(ItemStatsPacket packet, boolean nondefault) throws Exception {
        for (FloatStat stat : FLOATS) field(stat.field()).setFloat(packet, nondefault ? stat.value() : 0f);
        for (IntStat stat : INTEGERS) field(stat.field()).setInt(packet, nondefault ? stat.value() : stat.omitted());
    }
    private static ItemStatsPacket packet(boolean nondefault) throws Exception {
        ItemStatsPacket packet = new ItemStatsPacket();
        // Undefined ContainerID is a native world-free endpoint, not a replacement packet encoder.
        packet.id = nondefault ? 101 : 102;
        packet.condition = 1;
        packet.uses = 1;
        packet.heat = 1f;
        packet.isFood = true;
        packet.isCooked = nondefault;
        packet.isFrozen = nondefault;
        packet.isTainted = nondefault;
        packet.isBurnt = nondefault;
        packet.isAlcoholic = nondefault;
        packet.isFertilized = nondefault;
        packet.isWet = nondefault;
        packet.wetCooldown = nondefault ? 77f : 0f;
        packet.poisonPower = nondefault ? 9 : 0;
        packet.name = "ItemStats native regression";
        packet.actualWeight = .25f;
        floats(packet, nondefault);
        return packet;
    }
    private static byte[] wire(ItemStatsPacket packet) {
        ByteBuffer data = ByteBuffer.allocate(2048);
        packet.write(new ByteBufferWriter(data));
        return Arrays.copyOf(data.array(), data.position());
    }
    private static void parse(ItemStatsPacket receiver, byte[] data) {
        ByteBuffer input = ByteBuffer.wrap(data);
        receiver.parse(new ByteBufferReader(input), null);
        require(!input.hasRemaining(), "native parse did not consume the complete payload: " + input.remaining());
    }
    private static void packetStats(ItemStatsPacket packet, boolean nondefault, String context) throws Exception {
        for (FloatStat stat : FLOATS) {
            float expected = nondefault ? stat.value() : 0f;
            float actual = field(stat.field()).getFloat(packet);
            require(actual == expected, context + " " + stat.field() + ": " + actual + " != " + expected);
        }
        for (IntStat stat : INTEGERS) {
            int expected = nondefault ? stat.value() : stat.omitted();
            int actual = field(stat.field()).getInt(packet);
            require(actual == expected, context + " " + stat.field() + ": " + actual + " != " + expected);
        }
    }
    private static Food food(Unsafe unsafe) throws Exception {
        // Avoid starting a world or item factory. All application setters and getters remain native.
        Food food = (Food)unsafe.allocateInstance(Food.class);
        food.setConditionMax(10);
        return food;
    }
    private static void apply(ItemStatsPacket packet, InventoryItem item) throws Exception {
        Method apply = ItemStatsPacket.class.getDeclaredMethod("applyItemStats", InventoryItem.class);
        apply.setAccessible(true);
        apply.invoke(packet, item);
    }
    private static void foodStats(Food food, boolean nondefault, String context) throws Exception {
        for (FloatStat stat : FLOATS) {
            float expected = nondefault ? stat.value() : 0f;
            float actual = ((Number)Food.class.getMethod(stat.getter()).invoke(food)).floatValue();
            require(actual == expected, context + " applied " + stat.field() + ": " + actual + " != " + expected);
        }
        for (IntStat stat : INTEGERS) {
            int expected = nondefault ? stat.value() : stat.omitted();
            int actual;
            if (stat.field().equals("foodSicknessChange")) {
                // The public getter adjusts for age/cooked/burnt state; check the native setter's raw value.
                Field applied = Food.class.getDeclaredField("foodSicknessChange");
                applied.setAccessible(true);
                actual = applied.getInt(food);
            } else {
                actual = ((Number)Food.class.getMethod(stat.getter()).invoke(food)).intValue();
            }
            require(actual == expected, context + " applied " + stat.field() + ": " + actual + " != " + expected);
        }
    }
    private static void ordinaryState(ItemStatsPacket packet, boolean nondefault) {
        require(packet.id == (nondefault ? 101 : 102) && packet.isFood && packet.heat == 1f
            && packet.condition == 1 && packet.uses == 1 && packet.actualWeight == .25f,
            "native unconditional packet values changed");
        require(packet.isCooked == nondefault && packet.isFrozen == nondefault && packet.isTainted == nondefault
            && packet.isBurnt == nondefault && packet.isAlcoholic == nondefault && packet.isFertilized == nondefault
            && packet.isWet == nondefault && packet.poisonPower == (nondefault ? 9 : 0),
            "native present bits changed");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        require(ItemStatsDefaults.SUPPORTED, "unsupported ItemStats defaults baseline");
        require(BytecodeSupport.supports("zombie/network/packets/ItemStatsPacket.class",
            "1b2cd2f150e418d8266cdee8ab671210f8676bf9fd02f596eb5265f1389eaa8a"), "unsupported native ItemStats packet");
        require(!BytecodeSupport.supports("zombie/network/packets/ItemStatsPacket.class", "unknown"),
            "unknown ItemStats bytecode accepted");
        Field unsafeField = Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe)unsafeField.get(null);
        byte[] nondefault = wire(packet(true));
        byte[] defaults = wire(packet(false));
        require(nondefault.length - defaults.length == 16 * Float.BYTES + 3 * Integer.BYTES + 1 + Float.BYTES,
            "native writer did not omit the twenty defaults and guarded dry cooldown");

        // Reproduce before weaving: cached parse keeps the preceding cookingTime=30 and every omitted scalar.
        ItemStatsPacket stale = new ItemStatsPacket();
        parse(stale, nondefault);
        packetStats(stale, true, "original nondefault");
        parse(stale, defaults);
        packetStats(stale, true, "original reused omitted");
        require(stale.cookingTime == 30f && !stale.isCooked, "original stale cookingTime=30 not reproduced");
        Food staleFood = food(unsafe);
        apply(stale, staleFood);
        foodStats(staleFood, true, "original reused omitted");
        ItemStatsPacket fresh = new ItemStatsPacket();
        require(fresh.poisonDetectionLevel == 0, "original Java constructor poison default changed");
        parse(fresh, defaults);
        require(fresh.poisonDetectionLevel == 0, "original omitted poison sentinel mismatch not reproduced");
        Food freshFood = food(unsafe);
        apply(fresh, freshFood);
        require(freshFood.getPoisonDetectionLevel() == 0, "original fresh poison mismatch not applied");
        System.out.println("ITEM_STATS_ORIGINAL_STALE cookingTime=30 poisonDetectionLevel=6; fresh omitted poison=0, wire default=-1");

        ItemStatsPacket unsupported = packet(true);
        ItemStatsDefaults.reset(unsupported, false);
        packetStats(unsupported, true, "unsupported reset");
        ItemStatsDefaults.reset(null, false);
        ItemStatsDefaults.reset(null, true);

        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemStatsChecks.class.getClassLoader());
        require(Arrays.equals(nondefault, wire(packet(true))) && Arrays.equals(defaults, wire(packet(false))),
            "woven patch changed native writer bytes");
        ItemStatsPacket reused = new ItemStatsPacket();
        Food target = food(unsafe);
        for (int iteration = 0; iteration < 3; iteration++) {
            parse(reused, nondefault);
            packetStats(reused, true, "woven nondefault");
            ordinaryState(reused, true);
            apply(reused, target);
            foodStats(target, true, "woven nondefault");
            require(target.isWet() && target.getWetCooldown() == 77f, "native wet cooldown application changed");
            parse(reused, defaults);
            packetStats(reused, false, "woven reused omitted");
            ordinaryState(reused, false);
            apply(reused, target);
            foodStats(target, false, "woven reused omitted");
            require(!target.isWet() && target.getWetCooldown() == 77f,
                "dry packet applied omitted cooldown despite the native wet guard");
        }
        ItemStatsPacket clean = new ItemStatsPacket();
        parse(clean, defaults);
        packetStats(clean, false, "woven fresh omitted");
        apply(clean, target);
        foodStats(target, false, "woven fresh omitted");

        // Native nonfood packets retain their short wire and never enter Food application.
        ItemStatsPacket nonfood = packet(false);
        nonfood.isFood = false;
        nonfood.isWet = true;
        nonfood.wetCooldown = 12.5f;
        parse(reused, wire(nonfood));
        require(!reused.isFood && reused.isWet && reused.wetCooldown == 12.5f, "nonfood parse changed");
        InventoryItem plain = (InventoryItem)unsafe.allocateInstance(InventoryItem.class);
        plain.setConditionMax(10);
        apply(reused, plain);
        require(plain.getCondition() == 1 && plain.getItemHeat() == 1f && plain.isWet() && plain.getWetCooldown() == 12.5f,
            "native nonfood application changed");
        nonfood.isWet = false;
        parse(reused, wire(nonfood));
        apply(reused, plain);
        require(!plain.isWet() && plain.getWetCooldown() == 12.5f, "native nonfood dry cooldown guard changed");
        System.out.println("ITEM_STATS_CHECKS_PASS (original stale30 and poison sentinel reproduced; native writer/parse reuse, all20 reset/applied, nondefaults, wet/dry, nonfood and unsupported guards)");
    }
}
