package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.network.ByteBufferReader;
import zombie.network.IConnection;
import zombie.network.packets.ItemStatsPacket;

/** Restore omitted wire values before the connection's cached packet is parsed again. */
public final class ItemStatsDefaults {
    private record Fields(Field[] floats, Field[] integers, Field poisonDetectionLevel) { }
    private static final Fields FIELDS = load();
    public static final boolean SUPPORTED = FIELDS != null;

    private static Field[] fields(Class<?> type, String... names) throws ReflectiveOperationException {
        Field[] result = new Field[names.length];
        for (int index = 0; index < names.length; index++) {
            Field field = ItemStatsPacket.class.getDeclaredField(names[index]);
            if (field.getType() != type) throw new NoSuchFieldException(names[index] + " type");
            field.setAccessible(true);
            result[index] = field;
        }
        return result;
    }

    private static Fields load() {
        if (!BytecodeSupport.supports("zombie/network/packets/ItemStatsPacket.class",
                "1b2cd2f150e418d8266cdee8ab671210f8676bf9fd02f596eb5265f1389eaa8a")) return null;
        try {
            return new Fields(fields(float.class, "cookingTime", "minutesToCook", "minutesToBurn", "hungChange",
                    "calories", "proteins", "lipids", "carbohydrates", "thirstChange", "painReduction",
                    "endChange", "stressChange", "fatigueChange", "unhappyChange", "boredomChange", "baseHunger"),
                fields(int.class, "fluReduction", "foodSicknessChange", "fertilizedTime"),
                fields(int.class, "poisonDetectionLevel")[0]);
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.err.println("[PZToolkitJavaPatches] Disabled item-stat defaults: " + error);
            return null;
        }
    }

    public static void reset(ItemStatsPacket packet, boolean supported) {
        if (!supported || FIELDS == null || packet == null) return;
        try {
            for (Field field : FIELDS.floats()) field.setFloat(packet, 0f);
            for (Field field : FIELDS.integers()) field.setInt(packet, 0);
            // The writer omits -1 here, unlike the Java default of a fresh packet.
            FIELDS.poisonDetectionLevel().setInt(packet, -1);
        } catch (IllegalAccessException error) {
            throw new IllegalStateException("Validated item-stat fields became inaccessible", error);
        }
    }

    @Patch(className="zombie.network.packets.ItemStatsPacket", methodName="parse", warmUp=true, strictMatch=true)
    public static class Parsed {
        @Patch.OnEnter
        public static void enter(@Patch.This ItemStatsPacket packet, @Patch.Argument(0) ByteBufferReader reader,
                                 @Patch.Argument(1) IConnection connection) {
            reset(packet, SUPPORTED);
        }
    }
}
