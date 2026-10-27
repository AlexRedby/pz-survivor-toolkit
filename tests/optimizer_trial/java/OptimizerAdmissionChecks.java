import java.lang.reflect.Field;
import java.util.Map;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.CutawaySouthEdge;
import net.alexredby.pztoolkitjavapatches.OptimizerCompatibility;
import net.alexredby.pztoolkitjavapatches.TranslucentSquareUnion;
import net.alexredby.pztoolkitjavapatches.WorldItemTextureDimensions;
import net.alexredby.pztoolkitjavapatches.OutlineShaderPreparation;

/** Executes admission and the actual weave against an explicit, verified optimizer classpath. */
public final class OptimizerAdmissionChecks {
    public static void main(String[] args) throws Exception {
        boolean accepted = Boolean.parseBoolean(args[0]);
        Field field = OptimizerCompatibility.class.getDeclaredField("alternatives");
        field.setAccessible(true);
        Map<?, ?> alternatives = (Map<?, ?>) field.get(null);
        if (alternatives.size() != 20) throw new AssertionError("reviewed pair count");
        int checked = 0;
        for (var entry : alternatives.entrySet()) {
            Object pair = entry.getValue();
            String expected = (String) pair.getClass().getMethod("getNativeSha256").invoke(pair);
            boolean actual = BytecodeSupport.supports((String) entry.getKey(), expected);
            if (actual != accepted) throw new AssertionError("admission: " + entry.getKey() + "=" + actual);
            checked++;
        }
        if (CutawaySouthEdge.SUPPORTED != accepted) throw new AssertionError("cutaway admission");
        if (CutawaySouthEdge.install() != accepted) throw new AssertionError("actual cutaway weave");
        if (accepted && !CutawaySouthEdge.install()) throw new AssertionError("idempotent install");
        if (TranslucentSquareUnion.SUPPORTED != accepted) throw new AssertionError("union admission");
        if (TranslucentSquareUnion.install() != accepted) throw new AssertionError("actual union weave");
        if (WorldItemTextureDimensions.SUPPORTED != accepted) throw new AssertionError("texture admission");
        if (WorldItemTextureDimensions.install() != accepted) throw new AssertionError("actual texture weave");
        if (OutlineShaderPreparation.SUPPORTED != accepted) throw new AssertionError("outline admission");
        if (accepted) {
            if (!TranslucentSquareUnion.install()) throw new AssertionError("idempotent union install");
            if (!WorldItemTextureDimensions.install()) throw new AssertionError("idempotent texture install");
            Class.forName("zombie.Lua.LuaManager$GlobalObject", false,
                    OptimizerAdmissionChecks.class.getClassLoader()).getDeclaredMethods();
            // Resolve the complete woven class, including its retained stack-map frames.
            Class.forName("zombie.iso.fboRenderChunk.FBORenderCell", false,
                    OptimizerAdmissionChecks.class.getClassLoader()).getDeclaredMethods();
        }
        System.out.println("OPTIMIZER_ADMISSION_PASS accepted=" + accepted + " pairs=" + checked);
    }
}
