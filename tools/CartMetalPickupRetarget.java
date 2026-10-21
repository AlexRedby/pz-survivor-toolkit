package net.alexredby.pztoolkitjavapatches;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.Map;
import jassimp.AiPostProcessSteps;
import jassimp.Jassimp;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams;
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams;
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

    private record Sample(double time,Matrix4f[] poses) {}

    private static Object field(Object owner,String name) throws Exception {
        var field=owner.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(owner);
    }

    @SuppressWarnings("unchecked")
    private static Map<String,Matrix4f> idleFeet(Path path) throws Exception {
        var params=ProcessedAiSceneParams.create();
        params.scene=Jassimp.importFile(path.toString(),EnumSet.of(AiPostProcessSteps.MAKE_LEFT_HANDED,
            AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS));
        params.mode=JAssImpImporter.LoadMode.AnimationOnly;
        params.animBonesScaleModifier=1;params.animBonesRotateModifier=null;
        var imported=ImportedSkeleton.process(ImportedSkeletonParams.create(params,params.scene.getMeshes().get(0)));
        var indices=(HashMap<String,Integer>)field(imported,"boneIndices");
        var parents=(ArrayList<Integer>)field(imported,"skeletonHierarchy");
        var clips=(HashMap<String,AnimationClip>)field(imported,"clips");
        if(indices.size()!=45 || clips.size()!=1) throw new IllegalArgumentException("expected native Bob_Idle rig/clip");
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(int i=0;i<indices.size();i++) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        var actor=new SkinningData(new HashMap<>(),offsets,offsets,offsets,parents,indices);
        var clip=clips.values().iterator().next();var targets=new LinkedHashMap<String,Matrix4f>();
        for(String side:new String[]{"L","R"}) for(String part:new String[]{"Foot","Toe0","Toe0Nub"}) {
            String name="Bip01_"+side+"_"+part;var pose=new Matrix4f();
            if(!CartGrounding.referencePose(clip,actor,name,pose)) throw new IllegalArgumentException("missing idle "+name);
            targets.put(name,pose);
        }
        return targets;
    }

    private static Map<String,Matrix4f> footTargets(Sample sample,SkinningData actor) {
        var phase=CartTransitionMath.progress(sample.time(),false);
        float lowering=(float)(.05*phase.balance());
        float shiftX=(float)(((.216849-.21714664)-(-.005859375+.0060535767))*phase.center());
        var targets=new LinkedHashMap<String,Matrix4f>();
        for(String side:new String[]{"L","R"}) for(String part:new String[]{"Foot","Toe0","Toe0Nub"}) {
            String name="Bip01_"+side+"_"+part;
            targets.put(name,new Matrix4f(sample.poses()[actor.getBone(name).index]).translateLocal(-shiftX,lowering,0));
        }
        return targets;
    }

    private static Matrix4f childTarget(Matrix4f firstParent,Matrix4f first,Matrix4f lastParent,Matrix4f last,
        Matrix4f parent,double weight) {
        var from=new Matrix4f(firstParent).invert().mul(first);var to=new Matrix4f(lastParent).invert().mul(last);
        var local=new Matrix4f();
        if(!CartTransitionMath.blend(from,to,weight,local)) throw new AssertionError("foot child blend rejected");
        var position=local.getTranslation(new Vector3f());
        float length=from.getTranslation(new Vector3f()).length()*(1-(float)weight)
            +to.getTranslation(new Vector3f()).length()*(float)weight;
        if(length>0) local.setTranslation(position.normalize(length));
        return new Matrix4f(parent).mul(local);
    }

    private static void idleEndTargets(Map<String,Matrix4f> targets,Map<String,Matrix4f> idle,
        Map<String,Matrix4f> handover,double weight) {
        for(String side:new String[]{"L","R"}) {
            String foot="Bip01_"+side+"_Foot",toe="Bip01_"+side+"_Toe0",nub="Bip01_"+side+"_Toe0Nub";
            var footGoal=new Matrix4f();
            if(!CartTransitionMath.blend(idle.get(foot),handover.get(foot),weight,footGoal))
                throw new AssertionError("idle foot blend rejected");
            var toeGoal=childTarget(idle.get(foot),idle.get(toe),handover.get(foot),handover.get(toe),footGoal,weight);
            var nubGoal=childTarget(idle.get(toe),idle.get(nub),handover.get(toe),handover.get(nub),toeGoal,weight);
            targets.put(foot,footGoal);targets.put(toe,toeGoal);targets.put(nub,nubGoal);
        }
    }

    public static void main(String[] args) throws Exception {
        if(args.length!=3) throw new IllegalArgumentException("input.bin output.bin Bob_Idle.x");
        var idle=idleFeet(Path.of(args[2]));
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
            var samples=new ArrayList<Sample>();
            for(int frame=0;frame<frames;frame++) {
                double time=input.readDouble();var poses=new Matrix4f[count];
                for(int i=0;i<count;i++) {var values=new float[16];for(int j=0;j<16;j++) values[j]=(float)input.readDouble();poses[i]=new Matrix4f().set(values);}
                samples.add(new Sample(time,poses));
            }
            // The original first keys retained an arriving character's splayed feet.
            // Replace only that idle end, joining the first settled key after .10s
            // (currently .118182s); the grounded squat and cart end stay unchanged.
            var join=samples.stream().filter(sample->sample.time()>=.10).findFirst().orElseThrow();
            if(join.time()>.16) throw new IllegalArgumentException("missing settled idle-end key");
            var handover=footTargets(join,actor);
            for(int frame=0;frame<frames;frame++) {
                var sample=samples.get(frame);double time=sample.time();var poses=sample.poses();
                var phase=CartTransitionMath.progress(time,false);var targets=footTargets(sample,actor);
                if(time<join.time()) idleEndTargets(targets,idle,handover,CartTransitionMath.smooth(time/join.time()));
                if(time<1) for(String side:new String[]{"L","R"}) {
                    var foot=actor.getBone("Bip01_"+side+"_Foot");var toe=actor.getBone("Bip01_"+side+"_Toe0");
                    var target=targets.get(foot.name);var toeTarget=targets.get(toe.name);
                    // The leg solver's signed knee pole must follow the desired toes,
                    // rather than the discarded arrival pose's sideways toe direction.
                    var direction=toeTarget.getTranslation(new Vector3f()).sub(target.getTranslation(new Vector3f()));
                    poses[toe.index].setTranslation(poses[foot.index].getTranslation(new Vector3f()).add(direction));
                    if(!CartGrip.reach(poses,actor,foot.name,target,null,false))
                        throw new AssertionError("metal squat refused frame="+frame+" time="+time);
                    poses[toe.index].set(toeTarget);
                    poses[actor.getBone("Bip01_"+side+"_Toe0Nub").index].set(targets.get("Bip01_"+side+"_Toe0Nub"));
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
                        var target=new Matrix4f();CartGrip.transitionTarget("WheelbarrowMetal",side.equals("L"),false,new Matrix4f(),cart,target);
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
