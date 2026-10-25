import java.io.BufferedWriter;
import java.io.StringWriter;
import java.lang.reflect.Field;
import org.joml.Matrix4f;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
public final class GripPoseProbeCheck {
    public static void main(String[] args) throws Exception {
        if(new net.bytebuddy.description.type.TypeDescription.ForLoadedType(Class.forName("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .getDeclaredMethods().filter(named("grip").and(takesArguments(7))).size()!=1)
            throw new AssertionError("pressure-aware grip diagnostic target changed");
        if(new net.bytebuddy.description.type.TypeDescription.ForLoadedType(Class.forName("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .getDeclaredMethods().filter(named("transitionGrip").and(takesArguments(9))).size()!=1)
            throw new AssertionError("authored transition grip diagnostic target changed");
        if(new net.bytebuddy.description.type.TypeDescription.ForLoadedType(Class.forName("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .getDeclaredMethods().filter(named("reach").and(takesArguments(10))).size()!=1)
            throw new AssertionError("weighted reach diagnostic target changed");
        if(new net.bytebuddy.description.type.TypeDescription.ForLoadedType(Class.forName("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .getDeclaredMethods().filter(named("injuryTorso").and(takesArguments(9))).size()!=1)
            throw new AssertionError("injury torso diagnostic target changed");
        var transformed=new ByteBuddy().redefine(Class.forName("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .visit(Advice.to(GripPoseProbe.GripAdvice.class).on(named("grip").and(takesArguments(7))))
            .visit(Advice.to(GripPoseProbe.TransitionGripAdvice.class).on(named("transitionGrip").and(takesArguments(9))))
            .visit(Advice.to(GripPoseProbe.ReachAdvice.class).on(named("reach").and(takesArguments(10))))
            .visit(Advice.to(GripPoseProbe.InjuryAdvice.class).on(named("injuryTorso").and(takesArguments(9)))).make();
        if(transformed.getBytes().length==0)throw new AssertionError("empty instrumentation");
        var text=new StringWriter();var writer=new BufferedWriter(text);
        Field output=GripPoseProbe.class.getDeclaredField("output");output.setAccessible(true);output.set(null,writer);
        var cart=new Matrix4f().translation(1,2,3);var delta=new Matrix4f().translation(4,5,6);
        String snapshot=GripPoseProbe.before(null,null,"WheelbarrowWood",false,delta,cart);
        cart.translation(7,8,9);delta.zero();GripPoseProbe.after(snapshot,false,null);
        String failed=text.toString();
        if(!failed.contains("\"result\":false") || !failed.contains("1.0,2.0,3.0,1.0]"))
            throw new AssertionError("failed capture omitted or input matrix was not copied: "+failed);
        if(GripPoseProbe.before(null,null,"UnrelatedModel",false,delta,cart)!=null)
            throw new AssertionError("unrelated model captured");
        writer.close();output.set(null,null);
        var failures=new StringWriter();var failureWriter=new BufferedWriter(failures);
        Field reach=GripPoseProbe.class.getDeclaredField("reachFailures");reach.setAccessible(true);reach.set(null,failureWriter);
        GripPoseProbe.reachAfter("{\"bone\":\"Bip01_L_Foot\"}",true);
        if(!failures.toString().isEmpty())throw new AssertionError("successful reach logged as failure");
        GripPoseProbe.reachAfter("{\"bone\":\"Bip01_L_Foot\"}",false);
        if(!failures.toString().contains("Bip01_L_Foot"))throw new AssertionError("failed leg reach omitted");
        failureWriter.close();reach.set(null,null);
        var torsoText=new StringWriter();var torsoWriter=new BufferedWriter(torsoText);
        Field torso=GripPoseProbe.class.getDeclaredField("injuryPoses");torso.setAccessible(true);torso.set(null,torsoWriter);
        cart.translation(1,2,3);delta.translation(4,5,6);var idle=new Matrix4f().translation(7,8,9);
        String torsoSnapshot=GripPoseProbe.injuryBefore(null,null,false,delta,cart,.1f,.5f,idle,"WheelbarrowMetal");
        cart.zero();delta.zero();idle.zero();GripPoseProbe.injuryAfter(torsoSnapshot,0);
        String torsoRow=torsoText.toString();
        if(!torsoRow.contains("\"amount\":0.0") || !torsoRow.contains("\"injuryWeight\":0.5")
            || !torsoRow.contains("7.0,8.0,9.0,1.0]") || !torsoRow.contains("Bip01_R_Foot"))
            throw new AssertionError("pre-torso copy, reference, weight or complete skeleton omitted: "+torsoRow);
        torsoWriter.close();torso.set(null,null);
        System.err.println("GRIP_POSE_PROBE_CHECK_PASS (current advice targets, immutable pre-IK/pre-torso inputs, false result, complete skeleton)");
    }
}
