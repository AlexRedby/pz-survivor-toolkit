import java.nio.file.Files;
import java.nio.file.Path;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;

/** Instrumentation generation and output safety only; never connects to a game process. */
public final class ClearanceProbeCheck {
    public static void main(String[] args) throws Exception {
        var target=Class.forName("net.alexredby.pztoolkitjavapatches.CartGrounding");
        if(new ByteBuddy().redefine(target).visit(Advice.to(ClearanceProbe.Capture.class)
            .on(named("render"))).make().getBytes().length==0)throw new AssertionError("empty instrumentation");
        for(String invalid:new String[]{"", "relative-output"}) {
            try { ClearanceProbe.agentmain(invalid,null);throw new AssertionError("accepted invalid output directory"); }
            catch(IllegalArgumentException expected) { }
        }
        Path directory=Files.createTempDirectory("clearance-probe-check-");
        Path file=directory.resolve("body-clearance.jsonl");
        try {
            Files.writeString(file,"preserve me");
            try { ClearanceProbe.agentmain(directory.toString(),null);throw new AssertionError("overwrote existing capture"); }
            catch(IllegalStateException expected) { }
            if(!Files.readString(file).equals("preserve me"))throw new AssertionError("capture changed");
        } finally { Files.deleteIfExists(file);Files.delete(directory); }
        System.out.println("CLEARANCE_PROBE_CHECK_PASS (advice transform, required output path, existing capture preserved)");
    }
}
