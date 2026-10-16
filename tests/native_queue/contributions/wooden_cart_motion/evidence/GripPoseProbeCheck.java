import java.io.BufferedWriter;
import java.io.StringWriter;
import java.lang.reflect.Field;
import org.joml.Matrix4f;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
public final class GripPoseProbeCheck {
    public static void main(String[] args) throws Exception {
        var transformed=new ByteBuddy().redefine(Class.forName("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .visit(Advice.to(GripPoseProbe.GripAdvice.class).on(named("grip").and(takesArguments(6)))).make();
        if(transformed.getBytes().length==0)throw new AssertionError("empty instrumentation");
        var text=new StringWriter();var writer=new BufferedWriter(text);
        Field output=GripPoseProbe.class.getDeclaredField("output");output.setAccessible(true);output.set(null,writer);
        var cart=new Matrix4f().translation(1,2,3);var delta=new Matrix4f().translation(4,5,6);
        String snapshot=GripPoseProbe.before(null,null,"WheelbarrowWood",false,delta,cart);
        cart.translation(7,8,9);delta.zero();GripPoseProbe.after(snapshot,false,null);
        String failed=text.toString();
        if(!failed.contains("\"result\":false") || !failed.contains("1.0,2.0,3.0,1.0]"))
            throw new AssertionError("failed capture omitted or input matrix was not copied: "+failed);
        if(GripPoseProbe.before(null,null,"WheelbarrowMetal",false,delta,cart)!=null)
            throw new AssertionError("nonwood model captured");
        writer.close();output.set(null,null);
        System.err.println("GRIP_POSE_PROBE_CHECK_PASS (advice transform, immutable entry copy, false result, wood scope)");
    }
}
