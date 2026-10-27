import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;
import net.alexredby.lotstreamingfixture.Main;
import zombie.characters.animals.AnimalZone;
import zombie.iso.IsoWorld;
import zombie.iso.zones.Zone;
import zombie.iso.zones.ZoneGeometryType;

/** Memory-only regression using actual native AnimalZone serialization and fixture canonicalization. */
public final class LotGeometryChecks {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void guard(Class<?> type, String expected) throws Exception {
        try (var in = type.getClassLoader().getResourceAsStream(type.getName().replace('.', '/') + ".class")) {
            require(in != null && HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(in.readAllBytes())).equals(expected), "Unsupported native " + type.getName());
        }
    }
    @SuppressWarnings("unchecked")
    private static Map<String, Object> geometry(AnimalZone zone) throws Exception {
        Method method = Main.class.getDeclaredMethod("geometry", AnimalZone.class);
        method.setAccessible(true);
        return (Map<String, Object>)method.invoke(null, zone);
    }
    public static void main(String[] args) throws Exception {
        guard(Zone.class, "41faa20ceed9764ba0aa32d8fa81f0329d40a1f5da575beb65601e077346e91c");
        guard(AnimalZone.class, "5a1c6187008dd4c4671361bce367aef99010716e1ff518c418440e8abb4b93a2");
        // Actual authored Eat endpoint pair in Muldraugh objects.lua; AnimalType is omitted.
        AnimalZone source = new AnimalZone("", "Animal", 10330, 8729, 0, 14, 2, "Eat", null, true);
        source.geometryType = ZoneGeometryType.Polyline;
        source.points.add(10343); source.points.add(8730); source.points.add(10330); source.points.add(8729);
        Field animalType = AnimalZone.class.getDeclaredField("animalType"); animalType.setAccessible(true);
        Map<String, Object> before = geometry(source);
        require(animalType.get(source) == null && before.get("animalType").equals(""),
            "Canonicalization must leave the native null field untouched");
        ByteBuffer buffer = ByteBuffer.allocate(4096);
        source.save(buffer);
        int bytes = buffer.position(); buffer.flip();
        AnimalZone restored = new AnimalZone().load(buffer, IsoWorld.getWorldVersion());
        require(buffer.position() == bytes && animalType.get(restored).equals(""),
            "Native roundtrip must demonstrate null-to-empty optional AnimalType");
        require(before.equals(geometry(restored)), "Persistence-equivalent canonical geometry changed");
        restored.action = "Sleep";
        require(!before.equals(geometry(restored)), "Canonicalization hid an action change");
        restored.action = "Eat"; restored.points.set(0, 10344);
        require(!before.equals(geometry(restored)), "Canonicalization hid a physical geometry change");
        System.out.println("LOT_GEOMETRY_NATIVE_CHECKS_OK bytes=" + bytes + " animalType=null->empty canonical=true controls=true");
    }
}
