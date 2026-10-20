package net.alexredby.pztoolkitjavapatches;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import jassimp.AiPostProcessSteps;
import jassimp.Jassimp;
import org.joml.Matrix4f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.HelperFunctions;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams;
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams;

/** Dense native .x import and live IK regression for metal acquisition and rapid retry.
 * Replays both hand calibrations through actual runtime grip/restart operations.
 * It does not model native action-layer overlap, rendering, or inventory ownership.
 */
public final class CartMetalPickupReplay {
    static Object field(Object object, String name) throws Exception {
        var field = object.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(object);
    }

    static Matrix4f model(int index, SkinningData actor, Matrix4f[] local, Matrix4f[] models) {
        if (models[index] != null) return models[index];
        var bone = actor.getBoneAt(index);
        return models[index] = bone.parent == null ? new Matrix4f(local[index]) :
            new Matrix4f(model(bone.parent.index, actor, local, models)).mul(local[index]);
    }

    static Matrix4f[] sample(AnimationTrack track, SkinningData actor, float time) {
        track.setCurrentTimeValue(time);
        track.setPreviousTimeValue(time);
        track.UpdateKeyframes(0);
        var local = new Matrix4f[actor.numBones()];
        var models = new Matrix4f[local.length];
        var position = new org.lwjgl.util.vector.Vector3f();
        var rotation = new org.lwjgl.util.vector.Quaternion();
        var scale = new org.lwjgl.util.vector.Vector3f();
        var nativeMatrix = new org.lwjgl.util.vector.Matrix4f();
        for (int index = 0; index < local.length; index++) {
            track.get(index, position, rotation, scale);
            HelperFunctions.CreateFromQuaternion(rotation, nativeMatrix);
            HelperFunctions.setPosition(nativeMatrix, position);
            local[index] = PZMath.convertMatrix(nativeMatrix, new Matrix4f()).transpose();
        }
        for (int index = 0; index < local.length; index++) model(index, actor, local, models);
        return models;
    }

    static Matrix4f ground=new Matrix4f().set(.009175257f,0,-2.7708507e-9f,0,0,.009175259f,0,0,2.770851e-9f,0,.009175259f,0,.216849f,.28893805f,-.8419868f,1);
    static Matrix4f held=CartWheelbarrow.METAL.held(new Matrix4f());
    static Matrix4f cart(double t,boolean drop) {
        var phase=CartTransitionMath.progress(t,drop);var out=new Matrix4f();CartTransitionMath.blend(ground,held,phase.lift(),out);
        var axle=CartWheelbarrow.METAL.center(new org.joml.Vector3f());
        var center=ground.transformPosition(axle,new org.joml.Vector3f()).lerp(held.transformPosition(axle,new org.joml.Vector3f()),(float)phase.lift());
        return out.translateLocal(center.sub(out.transformPosition(axle,new org.joml.Vector3f())));
    }
    record Result(Matrix4f[] poses,Matrix4f cart,float reach,float grip,boolean pass) {}
    static Result solve(AnimationTrack track,SkinningData actor,AnimationClip clip,boolean female,double time,boolean drop,Result prior) {
        var phase=CartTransitionMath.progress(time,drop);var poses=sample(track,actor,(float)(drop?1-time:time));var transform=cart(time,drop);
        float restart=prior==null?0:1-(float)CartTransitionMath.smooth(time*1.85/.35);
        float cartRestart=CartTransition.restartCartWeight(CartWheelbarrow.METAL,!drop,restart);
        if(!drop && prior!=null) {double u=Math.min(1,time*1.85/.4);cartRestart=1-(float)CartTransitionMath.smooth(u-.7*u*(1-u));}
        if(cartRestart>0) {
            var axle=CartWheelbarrow.METAL.center(new org.joml.Vector3f());var target=new Matrix4f(transform);
            CartTransitionMath.blend(target,prior.cart(),cartRestart,transform);
            var center=prior.cart().transformPosition(axle,new org.joml.Vector3f()).lerp(target.transformPosition(axle,new org.joml.Vector3f()),1-cartRestart);
            transform.translateLocal(center.sub(transform.transformPosition(axle,new org.joml.Vector3f())));
        }
        float reach=drop?(float)phase.reach()*(1-restart)+(prior==null?0:prior.reach())*restart:(float)phase.reach();
        float grip=drop?(float)phase.grip()*(1-restart)+(prior==null?0:prior.grip())*restart:(float)phase.grip();
        boolean pass=prior==null || restart<=0 || CartGrip.releasePose(poses,actor,prior.poses(),restart);
        if(pass && reach>0) pass=CartGrip.transitionGrip(poses,actor,female,new Matrix4f(),transform,reach,grip,clip,"WheelbarrowMetal");
        return new Result(poses,transform,reach,grip,pass);
    }
    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        if(args.length!=1) throw new IllegalArgumentException("clip.x");
        var params = ProcessedAiSceneParams.create();
        params.scene = Jassimp.importFile(args[0], EnumSet.of(AiPostProcessSteps.MAKE_LEFT_HANDED,
            AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS));
        params.mode = JAssImpImporter.LoadMode.AnimationOnly;
        params.animBonesScaleModifier = 1;
        params.animBonesRotateModifier = null;
        var imported = ImportedSkeleton.process(ImportedSkeletonParams.create(params, params.scene.getMeshes().get(0)));
        var indices = (HashMap<String, Integer>) field(imported, "boneIndices");
        var hierarchy = (ArrayList<Integer>) field(imported, "skeletonHierarchy");
        var clips = (HashMap<String, AnimationClip>) field(imported, "clips");
        if (indices.size() != 45 || clips.size() != 1) throw new AssertionError("expected 45 bones/one clip: " + indices.size() + "/" + clips.keySet());
        var offsets = new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for (int index = 0; index < indices.size(); index++) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        var actor = new SkinningData(new HashMap<>(), offsets, offsets, offsets, hierarchy, indices);
        var clip = clips.values().iterator().next();
        var track = AnimationTrack.alloc();
        track.startClip(clip, false, 0);
        track.setUseDeferredMovement(false);
        CartWorldSupport.apply("SaucedWheelbarrow.WheelbarrowMetal",ground,1);
        ground.translateLocal(0,.00175f*2.44949f/1.5f,.06f-CartWheelbarrow.METAL.pickupStanceBack());
        int fails=0,solves=0;
        for(boolean female:new boolean[]{false,true}) for(boolean drop:new boolean[]{false,true}) {
            int bad=0;String first="";
            for(int i=0;i<=600;i++) {double t=i/600.0;var result=solve(track,actor,clip,female,t,drop,null);solves++;if(!result.pass()){bad++;if(first.isEmpty())first=String.valueOf(t);}}
            fails+=bad;if(bad>0)System.out.printf("ORDINARY female=%s drop=%s fail=%d first=%s%n",female,drop,bad,first);
            Result prior=null;
            for(double cancel:new double[]{.55,.88,1}) {
                int retryBad=0;String retryFirst="";Result last=null;
                for(int i=0;i<=Math.round(cancel*600);i++) {double t=i/600.0;last=solve(track,actor,clip,female,t,drop,prior);solves++;if(!last.pass()){retryBad++;if(retryFirst.isEmpty())retryFirst=String.valueOf(t);}}
                fails+=retryBad;if(retryBad>0)System.out.printf("RETRY female=%s drop=%s cancel=%s fail=%d first=%s%n",female,drop,cancel,retryBad,retryFirst);prior=last;
            }
        }
        System.out.printf("NATIVE_REPLAY solves=%d failures=%d%n",solves,fails);
        if(fails>0)throw new AssertionError("native authored reach refused");
    }
}
