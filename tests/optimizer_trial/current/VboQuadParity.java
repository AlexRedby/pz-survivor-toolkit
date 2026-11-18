import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import zombie.core.opengl.VBORenderer;

/** Compare the HUD/world vertex layouts through the game's actual addQuad entry point, without a GL context. */
public final class VboQuadParity {
    private static final List<String> FORMATS = List.of("formatPositionColor", "formatPositionColorUv",
            "formatPositionColorUvDepth", "formatPositionNormalColor", "formatPositionNormalColorUv");

    private static Field field(Class<?> owner, String name) throws ReflectiveOperationException {
        var field = owner.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static ByteBuffer sentinelBuffer(int size, byte value) {
        var buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());
        for (int i = 0; i < size; i++) buffer.put(i, value);
        return buffer;
    }

    private static void draw(MessageDigest digest, String format, int mode, int offset) throws Exception {
        var renderer = new VBORenderer();
        var layout = VBORenderer.class.getField(format).get(renderer);
        var setFormat = VBORenderer.class.getDeclaredMethod("setFormat", layout.getClass());
        setFormat.setAccessible(true);
        setFormat.invoke(renderer, layout);
        int stride = field(VBORenderer.class, "elementSize").getInt(renderer);
        var vertices = sentinelBuffer(4096, (byte) 0x5a).position(stride * offset);
        var indices = sentinelBuffer(1024, (byte) 0x36).position(2 * offset);
        field(VBORenderer.class, "elements").set(renderer, vertices);
        field(VBORenderer.class, "indices").set(renderer, indices);
        renderer.setOffset(-4.5f, 3.125f, -0.0f);
        var runField = field(VBORenderer.class, "runInProgress");
        var constructor = runField.getType().getDeclaredConstructor();
        constructor.setAccessible(true);
        var run = constructor.newInstance();
        field(run.getClass(), "mode").setInt(run, mode);
        runField.set(renderer, run);

        for (int n = 0; n < 5; n++) {
            float[] v = new float[24];
            for (int j = 0; j < v.length; j++) v[j] = (n * 3 - j) * 0.125f;
            renderer.addQuad(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9],
                    v[10], v[11], v[12], v[13], v[14], v[15], v[16], v[17], v[18], v[19],
                    v[20], v[21], v[22], v[23]);
        }
        digest.update(format.getBytes(StandardCharsets.UTF_8));
        digest.update((byte) mode);
        digest.update((byte) offset);
        digest.update(ByteBuffer.allocate(8).putInt(vertices.position()).putInt(indices.position()).array());
        digest.update(vertices.duplicate().clear());
        digest.update(indices.duplicate().clear());
        digest.update(ByteBuffer.allocate(4).putInt(field(run.getClass(), "vertexCount").getInt(run)).array());
    }

    public static void main(String[] args) throws Exception {
        boolean optimized = Boolean.parseBoolean(args[0]);
        try {
            var renderer = new VBORenderer();
            boolean fast = field(VBORenderer.class, "pzoptFastQuads").getBoolean(renderer);
            if (!optimized || !fast) throw new AssertionError("Unexpected optimizer path");
        } catch (NoSuchFieldException nativeRenderer) {
            if (optimized) throw nativeRenderer;
        }
        var digest = MessageDigest.getInstance("SHA-256");
        for (String format : FORMATS) {
            for (int mode : new int[]{4, 7}) {
                for (int offset : new int[]{0, 1}) draw(digest, format, mode, offset);
            }
        }
        System.out.println("VBO_QUAD_PARITY " + HexFormat.of().formatHex(digest.digest()) + " fast=" + optimized);
    }
}
