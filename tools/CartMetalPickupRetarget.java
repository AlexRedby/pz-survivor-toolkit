package net.alexredby.pztoolkitjavapatches;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.SkinningBone;
import zombie.core.skinnedmodel.model.SkinningData;

/** Offline adapter for the current runtime IK; binary input/output belongs to retarget_metal_cart_pickup.py. */
public final class CartMetalPickupRetarget {
    // Native01 actor-space ground capture before the shared tire/feet correction.
    private static final Matrix4f GROUND=new Matrix4f().set(.009175257f,0,-2.7708507e-9f,0,
        0,.009175259f,0,0,2.770851e-9f,0,.009175259f,0,.216849f,.28893805f,-.8419868f,1);
    // Native Bob_Cart_Idle thumb bases relative to Hand, from the retained native05 full-closure capture.
    // Knuckle translation is supplied by each source pose, not replaced by these measurements.
    private static final float[][] THUMBS={{0.829255161f,-0.514256197f,0.218806646f,0f,0.558537616f,0.749099525f,-0.356209638f,0f,0.0192748753f,0.417600422f,0.908426128f,0f,0.0576812932f,-0.0236050595f,-0.000272059844f,1f},{0.829255579f,0.514254922f,0.218806972f,0f,-0.558536677f,0.749100569f,0.356209029f,0f,0.019273795f,-0.417600137f,0.908426338f,0f,0.0576811166f,0.0236049754f,-0.000271883361f,1f}};

    private static boolean descendant(SkinningBone bone,SkinningBone root) {
        for(;bone!=null;bone=bone.parent) if(bone==root) return true;
        return false;
    }

    private static void nativeThumb(Matrix4f[] poses,SkinningData actor,String side,double weight) {
        var hand=actor.getBone("Bip01_"+side+"_Hand");var thumb=actor.getBone("Bip01_"+side+"_Finger0");
        var local=new Matrix4f(poses[hand.index]).invert().mul(poses[thumb.index]);
        var reference=new Matrix4f().set(THUMBS[side.equals("L")?0:1])
            .setTranslation(local.m30(),local.m31(),local.m32());
        if(!CartTransitionMath.blend(local,reference,weight,reference)) throw new AssertionError("thumb blend rejected");
        var change=new Matrix4f(poses[hand.index]).mul(reference).mul(new Matrix4f(poses[thumb.index]).invert());
        for(int i=0;i<poses.length;i++) if(descendant(actor.getBoneAt(i),thumb)) change.mul(poses[i],poses[i]);
    }

    public static void main(String[] args) throws Exception {
        if(args.length!=2) throw new IllegalArgumentException("input.bin output.bin");
        try(var input=new DataInputStream(Files.newInputStream(Path.of(args[0])));
            var output=new DataOutputStream(Files.newOutputStream(Path.of(args[1])))) {
            if(input.readInt()!=0x434d5052) throw new IllegalArgumentException("bad retarget input");
            int count=input.readInt();if(count!=45) throw new IllegalArgumentException("expected native45-bone Bob rig");
            var indices=new HashMap<String,Integer>();var parents=new ArrayList<Integer>();
            var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
            for(int i=0;i<count;i++) {indices.put(input.readUTF(),i);parents.add(input.readInt());offsets.add(new org.lwjgl.util.vector.Matrix4f());}
            var actor=new SkinningData(new HashMap<>(),offsets,offsets,offsets,parents,indices);
            // Profile HELD already includes8deg lowering and cylindrical floor alignment.
            // It matches native01 y=.22126661; lowering/alignment must not run twice.
            var profile=CartWheelbarrow.METAL;var held=profile.held(new Matrix4f());
            // GROUND was captured with the original .06 stance; move its actor-relative
            // position by the exact approach delta without moving the world cart.
            var ground=new Matrix4f(GROUND);
            if(!CartWorldSupport.apply("SaucedWheelbarrow.WheelbarrowMetal",ground,1))
                throw new AssertionError("metal ground support rejected");
            // Actor-space capture includes native item placement height after model calibration.
            ground.translateLocal(0,.00175f*2.44949f/1.5f,.06f-profile.pickupStanceBack());
            int frames=input.readInt();output.writeInt(frames);int contacts=0;
            for(int frame=0;frame<frames;frame++) {
                double time=input.readDouble();var phase=CartTransitionMath.progress(time,false);
                var poses=new Matrix4f[count];
                for(int i=0;i<count;i++) {var values=new float[16];for(int j=0;j<16;j++) values[j]=(float)input.readDouble();poses[i]=new Matrix4f().set(values);}
                // Match groundFeet: keep the source foot targets and solve each rigid
                // leg after the additional metal lowering and exact center correction.
                float lowering=(float)(.05*phase.balance());
                float shiftX=(float)(((.216849-.21714664)-(-.005859375+.0060535767))*phase.center());
                if(lowering>0 || shiftX!=0) for(String side:new String[]{"L","R"}) {
                    var foot=actor.getBone("Bip01_"+side+"_Foot");
                    var target=new Matrix4f(poses[foot.index]).translateLocal(-shiftX,lowering,0);
                    if(!CartGrip.reach(poses,actor,foot.name,target,null,false))
                        throw new AssertionError("metal squat refused frame="+frame+" time="+time);
                }
                var cart=new Matrix4f();
                if(!CartTransitionMath.blend(ground,held,phase.lift(),cart)) throw new AssertionError("cart blend rejected");
                var axle=profile.center(new Vector3f());
                var center=ground.transformPosition(axle,new Vector3f()).lerp(held.transformPosition(axle,new Vector3f()),(float)phase.lift());
                cart.translateLocal(center.sub(cart.transformPosition(axle,new Vector3f())));
                // The live authored path applies acquisition once for the actual
                // body/sex. Baking partial reach here would apply it a second time.
                if(phase.reach()==1) {
                    for(String side:new String[]{"L","R"}) nativeThumb(poses,actor,side,CartTransitionMath.smooth(phase.grip()));
                    if(!CartGrip.transitionGrip(poses,actor,false,new Matrix4f(),cart,(float)phase.reach(),(float)phase.grip(),null,"WheelbarrowMetal"))
                        throw new AssertionError("metal IK refused frame="+frame+" time="+time);
                    if(phase.reach()==1) for(String side:new String[]{"L","R"}) {
                        var target=new Matrix4f();CartGrip.target("WheelbarrowMetal",side.equals("L"),false,new Matrix4f(),cart,target);
                        if(!poses[actor.getBone("Bip01_"+side+"_Hand").index].equals(target,.000002f))
                            throw new AssertionError("metal contact missed at "+time);
                        contacts++;
                    }
                }
                for(var pose:poses) for(float value:pose.get(new float[16])) output.writeFloat(value);
            }
            if(input.read()!=-1) throw new IllegalArgumentException("trailing input");
            System.err.println("METAL_RETARGET frames="+frames+" fullHandContacts="+contacts+" runtimeIK=true");
        }
    }
}
