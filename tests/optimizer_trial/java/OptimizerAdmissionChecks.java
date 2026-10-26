import java.lang.reflect.Field;
import java.util.Map;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.CutawaySouthEdge;
import net.alexredby.pztoolkitjavapatches.OptimizerCompatibility;

/** Executes admission and the actual weave against an explicit, verified optimizer classpath. */
public final class OptimizerAdmissionChecks {
    public static void main(String[] args) throws Exception {
        boolean accepted = Boolean.parseBoolean(args[0]);
        Field field = OptimizerCompatibility.class.getDeclaredField("alternatives");
        field.setAccessible(true);
        Map<?, ?> alternatives = (Map<?, ?>) field.get(null);
        if (alternatives.size() != 18) throw new AssertionError("reviewed pair count");
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
        System.out.println("OPTIMIZER_ADMISSION_PASS accepted=" + accepted + " pairs=" + checked);
    }
}
