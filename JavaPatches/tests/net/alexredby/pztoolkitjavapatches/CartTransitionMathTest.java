package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public final class CartTransitionMathTest {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void close(double a, double b, double epsilon, String message) {
        check(Math.abs(a - b) <= epsilon, message + ": " + a + " != " + b);
    }
    private static CartTransitionMath.Placement pose(float yaw) {
        return new CartTransitionMath.Placement(10.23f, -7.68f, 2.00475f, 0, yaw, 0, .8503f);
    }
    private static Matrix4f model() {
        // Mesh axes/scale need not already match actor axes; the world attachment may translate.
        return new Matrix4f().translation(.04f, -.02f, .03f).rotateX((float)Math.toRadians(90)).scale(90);
    }
    private static void roundtrips() {
        Matrix4f model = model(), before = new Matrix4f(model);
        float[] angles = {0, 45, 90, 135, 180, 225, 270, 315, 17.3f, -53.2f, 359.99f};
        for (float yaw : angles) for (float actorAngle : new float[]{0, .17f, 1.7f, -2.3f})
            for (float[] tilt : new float[][]{{0,0}, {13,-21}, {-34,72}}) {
                var pose = new CartTransitionMath.Placement(10.23f, -7.68f, 2.00475f,
                    tilt[0], yaw, tilt[1], .8503f);
                Matrix4f actor = new Matrix4f();
                check(CartTransitionMath.worldToActor(pose, model, 9.8f, -8.4f, 2, actorAngle, actor), "world pose accepted");
                Matrix4f actorBefore = new Matrix4f(actor);
                var result = CartTransitionMath.actorToWorldPlacement(actor, model, 9.8f, -8.4f, 2, actorAngle);
                check(result != null, "uniform pose decomposed at " + yaw);
                close(result.x(), pose.x(), .00001, "world X roundtrip");
                close(result.y(), pose.y(), .00001, "world Y roundtrip");
                close(result.z(), pose.z(), .00001, "world Z roundtrip");
                close(result.worldScale(), pose.worldScale(), .00001, "scale roundtrip");
                Matrix4f second = new Matrix4f();
                check(CartTransitionMath.worldToActor(result, model, 9.8f, -8.4f, 2, actorAngle, second), "reverse pose accepted");
                check(actor.equals(second, .0001f), "native X/Z/Y Euler roundtrip at " + yaw + " tilt " + tilt[0]);
                check(actor.equals(actorBefore), "inverse does not mutate transform");

                Vector3f point = new Vector3f(.002f, -.003f, .004f);
                Vector3f local = actor.transformPosition(point, new Vector3f());
                double c = Math.cos(actorAngle), s = Math.sin(actorAngle);
                double actualX = 9.8 - 1.5 * (c * local.x + s * local.z);
                double actualY = -8.4 + 1.5 * (-s * local.x + c * local.z);
                Matrix4f world = new Matrix4f().rotationXYZ((float)Math.toRadians(pose.xRotation()),
                    (float)Math.toRadians(pose.zRotation()), (float)Math.toRadians(pose.yRotation()))
                    .mul(model).scale(pose.worldScale());
                Vector3f expected = world.transformPosition(point, new Vector3f());
                close(actualX, pose.x() + 1.5 * expected.x, .00001, "same native world X");
                close(actualY, pose.y() - 1.5 * expected.z, .00001, "same native world Y");
                close(2 + local.y * 1.5 / 2.44949, pose.z() + expected.y * 1.5 / 2.44949,
                    .00001, "same native world height");
            }
        check(model.equals(before), "world conversion does not mutate mesh/attachment matrix");
    }
    private static void timingAndBlend() {
        Matrix4f from = new Matrix4f().translation(.1f, .2f, -.3f).rotateX(.2f).scale(76.5f);
        Matrix4f to = new Matrix4f().translation(-.4f, .8f, .7f).rotateY(2.8f).scale(90);
        Matrix4f fromBefore = new Matrix4f(from), toBefore = new Matrix4f(to), actual = new Matrix4f();
        double previous = -1;
        var last = CartTransitionMath.progress(0, false);
        for (int i = 0; i <= 1000; i++) {
            double p = i / 1000.0, amount = CartTransitionMath.smooth(p);
            check(amount >= previous && amount >= 0 && amount <= 1, "monotonic bounded easing");
            previous = amount;
            var phase = CartTransitionMath.progress(p, false);
            check(phase.crouch() >= last.crouch(), "continuous body lowering");
            check(phase.center()>=0 && phase.center()<=1 && phase.balance()>=0 && phase.balance()<=1
                && phase.hinge()>=0 && phase.hinge()<=1 && phase.knees()>=0 && phase.knees()<=1, "bounded stance correction");
            check(phase.reach() >= last.reach() && phase.grip() >= last.grip() && phase.lift() >= last.lift(), "monotonic phases");
            check(phase.grip() == 0 || CartTransitionMath.smooth(phase.reach()) > .95,
                "fingers close only within the final few millimetres of reach");
            check(phase.lift() == 0 || phase.grip() == 1, "grip finishes before lift");
            var inverse = CartTransitionMath.progress(1 - p, true);
            close(phase.crouch(), inverse.crouch(), 1e-12, "setdown standing reverses crouch");
            close(phase.center(), inverse.center(), 1e-12, "setdown reverses centering");
            close(phase.balance(), inverse.balance(), 1e-12, "setdown reverses weight shift");
            close(phase.hinge(), inverse.hinge(), 1e-12, "setdown reverses hip hinge");
            close(phase.knees(), inverse.knees(), 1e-12, "setdown reverses knee bend");
            close(phase.reach(), inverse.reach(), 1e-12, "setdown reach reverses pickup");
            close(phase.grip(), inverse.grip(), 1e-12, "setdown release reverses grip");
            close(phase.lift(), inverse.lift(), 1e-12, "setdown lower reverses lift");
            check(CartTransitionMath.blend(from, to, p, actual), "rigid blend accepted");
            close(actual.getColumn(0, new Vector3f()).length(), 76.5 + (90 - 76.5) * p, .00004, "uniform blended scale");
            Vector3f x = actual.getColumn(0, new Vector3f()).normalize(), y = actual.getColumn(1, new Vector3f()).normalize();
            close(x.dot(y), 0, .00001, "slerp adds no shear");
            last = phase;
        }
        check(CartTransitionMath.blend(from, to, 0, actual) && actual.equals(from), "exact first endpoint");
        check(CartTransitionMath.blend(from, to, 1, actual) && actual.equals(to), "exact final endpoint");
        close(CartTransitionMath.smooth(.00001) / .00001, 0, .00000001, "zero starting velocity");
        close((1 - CartTransitionMath.smooth(.99999)) / .00001, 0, .00000001, "zero finishing velocity");
        check(from.equals(fromBefore) && to.equals(toBefore), "blend does not mutate endpoints");
        for(double t=.24;t<.44;t+=.001) {
            var before=CartTransitionMath.progress(t,false);var after=CartTransitionMath.progress(t+.0001,false);
            check(after.crouch()>before.crouch() && after.reach()>before.reach(), "body bending and reaching must move together without a crouch wait");
        }
        check(CartTransitionMath.progress(.44,false).grip()>0 && CartTransitionMath.progress(.48,false).grip()==1,
            "only final finger closure remains once the body has reached the handles");
        check(CartTransitionMath.progress(0, true).equals(new CartTransitionMath.Progress(1,1,1,1,0,0,0,1)), "setdown starts holding");
        check(CartTransitionMath.progress(1, true).equals(new CartTransitionMath.Progress(0,0,0,0,0,0,0,0)), "setdown ends released");
        for (double t=0;t<=.44;t+=.001) {
            var phase=CartTransitionMath.progress(t,false);
            close(phase.knees(),phase.crouch(),1e-12,"knees and torso descend together");
            close(phase.balance(),phase.crouch(),1e-12,"pelvis must not finish retreating before the torso bends");
        }
        check(CartTransitionMath.progress(.20,false).balance()<.5,"no early full pelvis retreat");
        check(CartTransitionMath.progress(.10,false).center()==1 && CartTransitionMath.progress(.44,false).balance()==1, "centering leads the bend and weight shift follows it");
        close(CartTransitionMath.progress(.000001,false).balance()/.000001,0,.000001,"zero starting weight-shift velocity");
        double coarseVelocity=CartTransitionMath.progress(.9999,false).balance()/.0001;
        double fineVelocity=CartTransitionMath.progress(.999999,false).balance()/.000001;
        check(fineVelocity<coarseVelocity*.2,"weight-shift velocity tends to zero at the endpoint");
    }
    private static void stances() {
        Vector3f left = new Vector3f(.00172237f, .00541905f, -.00342593f);
        Vector3f right = new Vector3f(-.00172238f, .00541905f, -.00342593f);
        Matrix4f held = new Matrix4f().translation(-.0060535767f, .097179376f, -.34652624f)
            .rotateX((float)Math.toRadians(74.24)).scale(76.5f);
        Matrix4f model = model(), modelBefore = new Matrix4f(model), heldBefore = new Matrix4f(held);
        Vector3f leftBefore = new Vector3f(left), rightBefore = new Vector3f(right);
        for (float yaw : new float[]{0,45,90,135,180,225,270,315,23.7f}) {
            var pose = pose(yaw);
            var stance = CartTransitionMath.stance(pose, model, held, left, right);
            check(stance != null, "stance exists");
            Matrix4f ground = new Matrix4f();
            check(CartTransitionMath.worldToActor(pose, model, stance.x(), stance.y(), stance.z(), stance.slotAngle(), ground), "stance projection");
            Vector3f a = ground.transformPosition(left, new Vector3f()), b = ground.transformPosition(right, new Vector3f());
            Vector3f hA = held.transformPosition(left, new Vector3f()), hB = held.transformPosition(right, new Vector3f());
            close((a.x+b.x)*.5, (hA.x+hB.x)*.5, .00001, "handle center aligned horizontally X");
            close((a.z+b.z)*.5, (hA.z+hB.z)*.5, .00001, "handle center aligned horizontally Z");
            Vector3f d = a.sub(b).normalize(), hD = hA.sub(hB).normalize();
            close(d.x, hD.x, .00001, "ordered handles preserve facing X");
            close(d.z, hD.z, .00001, "ordered handles preserve facing Z");
        }
        check(model.equals(modelBefore) && held.equals(heldBefore) && left.equals(leftBefore) && right.equals(rightBefore), "stance has no input mutation");
    }
    private static void recovery() {
        for(boolean setdown:new boolean[]{false,true}) for(double start:new double[]{0,.001,.15,.38,.44,.48,.55,.88,1}) {
            double duration=.4+.2*start;
            close(CartTransitionMath.recover(start,0,setdown),start,0,"recovery starts at the interrupted pose");
            close(CartTransitionMath.recover(start,-1,setdown),start,0,"early clock cannot advance recovery");
            close(CartTransitionMath.recover(start,duration,setdown),0,0,"recovery reaches the exact native endpoint");
            close(CartTransitionMath.recover(start,.600001,setdown),0,0,"recovery always ends within 600 ms");
            double previous=start;
            for(int i=0;i<=1000;i++) {
                double current=CartTransitionMath.recover(start,duration*i/1000,setdown);
                check(Double.isFinite(current) && current>=0 && current<=previous,"recovery is finite, bounded and monotonic");
                for(boolean direction:new boolean[]{false,true}) {
                    var phase=CartTransitionMath.progress(current,direction);
                    for(double value:new double[]{phase.crouch(),phase.reach(),phase.grip(),phase.lift(),
                            phase.center(),phase.balance(),phase.hinge(),phase.knees()})
                        check(Double.isFinite(value) && value>=0 && value<=1,"reverse pose dimensions remain finite and bounded");
                    check(phase.lift()==0 || phase.grip()==1,"recovery preserves grip before moving the cart");
                    check(phase.grip()==0 || CartTransitionMath.smooth(phase.reach())>.95,
                        "recovery preserves reach before finger contact");
                }
                previous=current;
            }
            double step=duration*.00001;
            close((start-CartTransitionMath.recover(start,step,setdown))/step,0,.000001,"recovery starts without a velocity jump");
            close(CartTransitionMath.recover(start,duration-step,setdown)/step,0,.000001,"recovery settles without endpoint velocity");
        }
        close(CartTransitionMath.recover(-1,0,false),0,0,"negative recovery progress clamps to released");
        close(CartTransitionMath.recover(2,0,false),1,0,"overshot recovery progress clamps to held");
        for(double invalid:new double[]{Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY}) {
            check(Double.isNaN(CartTransitionMath.recover(invalid,.1,false)),"nonfinite recovery origin rejected");
            check(Double.isNaN(CartTransitionMath.recover(.5,invalid,false)),"nonfinite recovery clock rejected");
        }
    }
    private static void recoveryRelease() {
        close(CartTransitionMath.recoveryRelease(.8,.88,true),10.0/11,1e-12,
            "late pickup releases the hip with recovered progress instead of freezing it through a second easing");
        close(CartTransitionMath.recoveryRelease(.8,.88,false),160000.0/161051,1e-12,
            "setdown preserves the existing eased recovery weight");
        for(boolean pickup:new boolean[]{true,false}) for(double start:new double[]{.15,.55,.88}) {
            double duration=.4+.2*start,previous=1;
            close(CartTransitionMath.recoveryRelease(start,start,pickup),1,0,"body recovery preserves the captured first frame");
            close(CartTransitionMath.recoveryRelease(0,start,pickup),0,0,"body recovery reaches the native endpoint");
            for(int frame=0;frame<=Math.ceil(duration*60);frame++) {
                double progress=CartTransitionMath.recover(start,frame/60.0,!pickup);
                double weight=CartTransitionMath.recoveryRelease(progress,start,pickup);
                check(Double.isFinite(weight) && weight>=0 && weight<=1 && weight<=previous,
                    "60 Hz body recovery weights must remain finite, bounded and monotonic");
                previous=weight;
            }
            close(previous,0,0,"60 Hz body recovery finishes within the existing duration");
            close(CartTransitionMath.recoveryRelease(CartTransitionMath.recover(start,.600001,!pickup),start,pickup),0,0,
                "body recovery cannot extend the 600 ms lifetime");
            double step=duration*.00001;
            close((1-CartTransitionMath.recoveryRelease(CartTransitionMath.recover(start,step,!pickup),start,pickup))/step,
                0,.00001,"body recovery starts without a velocity jump");
            close(CartTransitionMath.recoveryRelease(CartTransitionMath.recover(start,duration-step,!pickup),start,pickup)/step,
                0,.00001,"body recovery finishes without endpoint velocity");
            close(CartTransitionMath.recoveryRelease(-1,start,pickup),0,0,"negative body progress clamps to native endpoint");
            close(CartTransitionMath.recoveryRelease(start+1,start,pickup),1,0,"overshot body progress clamps to captured pose");
        }
        for(boolean pickup:new boolean[]{true,false}) {
            for(double invalid:new double[]{0,-1,Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY})
                check(Double.isNaN(CartTransitionMath.recoveryRelease(.5,invalid,pickup)),"invalid body recovery origin rejected");
            for(double invalid:new double[]{Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY})
                check(Double.isNaN(CartTransitionMath.recoveryRelease(invalid,.5,pickup)),"nonfinite body recovery progress rejected");
        }
    }
    private static void recoveryClearance() {
        for(double start:new double[]{0,.15,.48,.55,.88,1}) {
            double duration=.4+.2*start,lift=CartTransitionMath.progress(start,false).lift();
            close(CartTransitionMath.recoveryClearance(start,0),0,0,"clearance preserves the captured first pose");
            close(CartTransitionMath.recoveryClearance(start,duration),0,0,"clearance reaches the native endpoint on time");
            close(CartTransitionMath.recoveryClearance(start,duration/2),lift/4,1e-12,"clearance is bounded by the captured lift");
            close(CartTransitionMath.recoveryClearance(start,-1),0,0,"clearance cannot start before cancellation");
            close(CartTransitionMath.recoveryClearance(start,.600001),0,0,"clearance cannot extend the recovery lifetime");
            double previous=0;
            for(int frame=0;frame<=Math.ceil(duration*60);frame++) {
                double weight=CartTransitionMath.recoveryClearance(start,frame/60.0);
                check(Double.isFinite(weight) && weight>=0 && weight<=lift/4+1e-12,"60 Hz clearance must remain finite and bounded");
                check(Math.abs(weight-previous)<=lift/(60*duration)+1e-12,"clearance moved farther than one frame of its bounded trajectory");
                if(lift==0) close(weight,0,0,"grounded pickup cannot acquire a clearance detour");
                previous=weight;
            }
            close(previous,0,0,"60 Hz clearance finishes within the existing deadline");
        }
        for(double invalid:new double[]{Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY}) {
            check(Double.isNaN(CartTransitionMath.recoveryClearance(invalid,.1)),"nonfinite clearance origin rejected");
            check(Double.isNaN(CartTransitionMath.recoveryClearance(.88,invalid)),"nonfinite clearance clock rejected");
        }
        close(CartTransitionMath.recoveryClearance(-1,.1),0,0,"negative clearance origin clamps to grounded pickup");
        close(CartTransitionMath.recoveryClearance(2,.3),.25,1e-12,"overshot clearance origin clamps to full lift");
    }
    private static void recoveryPoseSteps() {
        for(boolean setdown:new boolean[]{false,true}) for(double start:new double[]{.15,.55,.88,1}) {
            double duration=.4+.2*start;
            for(double elapsed=0;elapsed<duration;elapsed+=.001) {
                var before=CartTransitionMath.progress(CartTransitionMath.recover(start,elapsed,setdown),setdown);
                var after=CartTransitionMath.progress(CartTransitionMath.recover(start,elapsed+1.0/30,setdown),setdown);
                double balance=after.balance()-before.balance();
                double height=CartTransitionMath.nativeHeight(after,.5566668,.26,.561988)
                    -CartTransitionMath.nativeHeight(before,.5566668,.26,.561988)-.03*balance;
                double spineStep=Math.hypot(height,.16*balance);
                check(spineStep<.05,"late recovery bunched the squat into one 33 ms pose step: "+spineStep);
                check(recoveryWrist(before).distance(recoveryWrist(after))<.07,
                    "late setdown bunched reaching or wheel lift into one 33 ms wrist step");
                check(Math.abs(CartTransitionMath.smooth(after.reach())-CartTransitionMath.smooth(before.reach()))<.30,
                    "late37 advanced over a third of hand contact in one frame");
            }
        }
    }
    private static Vector3f recoveryWrist(CartTransitionMath.Progress phase) {
        // Native36 open-hand/floor/held wrist anchors: a pacing proxy, not a full rendered-frame replay.
        double reach=CartTransitionMath.smooth(phase.reach()),balance=phase.balance(),lift=phase.lift();
        return new Vector3f((float)(.11+.055*reach),
            (float)((.50-.03*balance)*(1-reach)+(.315+.199*lift)*reach),
            (float)((-.13+.04*balance)*(1-reach)+(.013-.031*lift)*reach));
    }
    private static void nativeHeight() {
        double idle=.56,low=.02,cart=.57;
        close(CartTransitionMath.nativeHeight(CartTransitionMath.progress(0,false),idle,low,cart),idle,0,"released height is native idle");
        close(CartTransitionMath.nativeHeight(CartTransitionMath.progress(1,false),idle,low,cart),cart,0,"held height is native cart idle");
        close(CartTransitionMath.nativeHeight(CartTransitionMath.progress(.44,false),idle,low,cart),.9*idle+.1*low,1e-12,
            "grounded crouch uses only the authored tenth of the low pose");
        var mixed=new CartTransitionMath.Progress(1,1,1,.5,0,0,0,0);
        close(CartTransitionMath.nativeHeight(mixed,idle,low,cart),.45*idle+.05*low+.5*cart,1e-12,
            "lift reduces low and idle weights together in the 2D blend triangle");
        for(boolean setdown:new boolean[]{false,true}) for(double start:new double[]{.55,.88}) {
            double offset=.008;
            double first=CartTransitionMath.nativeHeight(CartTransitionMath.progress(start,setdown),idle,low,cart)+offset;
            double endpoint=CartTransitionMath.nativeHeight(CartTransitionMath.progress(0,setdown),idle,low,cart);
            double previous=first;
            for(int i=0;i<=1000;i++) {
                double elapsed=.601*i/1000,progress=CartTransitionMath.recover(start,elapsed,setdown);
                double target=CartTransitionMath.nativeHeight(CartTransitionMath.progress(progress,setdown),idle,low,cart)+offset*progress/start;
                // Native action fades out in 200 ms while the canonical reverse can remain gripped longer.
                double live=first+(endpoint-first)*CartTransitionMath.smooth(elapsed/.2);
                check(Double.isFinite(target) && Math.abs(target-live)<.2,"native blend-out compensation stays within its safe correction bound");
                check(Math.abs(target-previous)<.001,"native blend-out does not introduce a recovery height jump");
                if(i==0) close(target,first,1e-12,"height recovery starts at the measured native pose");
                if(i==1000) close(target,endpoint,1e-12,"calibration offset fades completely at the native endpoint");
                previous=target;
            }
        }
    }
    private static void invalid() {
        Matrix4f sentinel = new Matrix4f().translation(9,8,7), out = new Matrix4f(sentinel);
        for (Matrix4f invalid : new Matrix4f[]{new Matrix4f().scale(0), new Matrix4f().m00(Float.NaN),
                new Matrix4f().m03(.1f), new Matrix4f().scale(-1,1,1), new Matrix4f().scale(1,2,1), new Matrix4f().m10(.1f)}) {
            check(!CartTransitionMath.blend(invalid, new Matrix4f(), .4, out), "invalid rigid transform rejected");
            check(out.equals(sentinel), "failure preserves output");
            check(CartTransitionMath.actorToWorldPlacement(invalid, new Matrix4f(), 0,0,0,0) == null, "inverse rejects invalid residual");
        }
        check(!CartTransitionMath.worldToActor(pose(0), new Matrix4f().scale(0),0,0,0,0,out), "singular model rejected");
        check(!CartTransitionMath.worldToActor(pose(0), model(),Float.NaN,0,0,0,out), "nonfinite actor rejected");
        check(!CartTransitionMath.worldToActor(new CartTransitionMath.Placement(0,0,0,0,0,0,-1), model(),0,0,0,0,out), "negative scale rejected");
        check(!CartTransitionMath.blend(new Matrix4f(), new Matrix4f(), Double.NaN, out), "nonfinite blend rejected");
        check(Double.isNaN(CartTransitionMath.smooth(Double.NaN)) && CartTransitionMath.progress(Double.NaN, false) == null, "nonfinite timing rejected");
        check(CartTransitionMath.stance(pose(0),model(),new Matrix4f(),new Vector3f(),new Vector3f()) == null, "coincident handles rejected");
        check(out.equals(sentinel), "all validation failures preserve output");
    }
    public static void main(String[] args) {
        roundtrips(); timingAndBlend(); stances(); recovery(); recoveryRelease(); recoveryClearance(); recoveryPoseSteps(); nativeHeight(); invalid();
        System.out.println("PASS cart transition world/actor roundtrips, native Euler order, rigid interpolation, phase reversal and handle stance");
    }
}
