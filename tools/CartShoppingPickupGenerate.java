package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import jassimp.AiPostProcessSteps;
import jassimp.Jassimp;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams;
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams;

/** Offline standing acquisition: native idle/cart-idle joints, no borrowed looting crouch. */
public final class CartShoppingPickupGenerate {
    record Source(SkinningData actor,AnimationClip clip) {}
    private static Object field(Object value,String name) throws Exception {
        var field=value.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(value);
    }
    @SuppressWarnings("unchecked")
    static Source read(Path path) throws Exception {
        var params=ProcessedAiSceneParams.create();
        params.scene=Jassimp.importFile(path.toString(),EnumSet.of(AiPostProcessSteps.MAKE_LEFT_HANDED,
            AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS));
        params.mode=JAssImpImporter.LoadMode.AnimationOnly;params.animBonesScaleModifier=1;
        if(path.toString().toLowerCase().endsWith(".fbx")) {
            // FileTask_LoadAnimation.loadFBX in the supported B42.21 importer.
            params.animBonesScaleModifier=.01f;
            params.animBonesRotateModifier=new org.lwjgl.util.vector.Quaternion();
            params.animBonesRotateModifier.setFromAxisAngle(new org.lwjgl.util.vector.Vector4f(1,0,0,-(float)Math.PI/2));
        }
        var imported=ImportedSkeleton.process(ImportedSkeletonParams.create(params,params.scene.getMeshes().get(0)));
        var indices=(HashMap<String,Integer>)field(imported,"boneIndices");
        var parents=(ArrayList<Integer>)field(imported,"skeletonHierarchy");
        var clips=(HashMap<String,AnimationClip>)field(imported,"clips");
        if(indices.size()!=45 || clips.size()!=1) throw new IllegalArgumentException("expected native 45-bone Bob clip");
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(int i=0;i<indices.size();i++) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        return new Source(new SkinningData(new HashMap<>(),offsets,offsets,offsets,parents,indices),clips.values().iterator().next());
    }
    private static Matrix4f[] reference(Source source,SkinningData order) {
        var poses=new Matrix4f[order.numBones()];
        for(int i=0;i<poses.length;i++) {
            poses[i]=new Matrix4f();
            if(!CartGrounding.referencePose(source.clip,source.actor,order.getBoneAt(i).name,poses[i]))
                throw new AssertionError("missing native bone "+order.getBoneAt(i).name);
        }
        return poses;
    }
    private static Matrix4f local(Matrix4f[] poses,SkinningData actor,int index) {
        var parent=actor.getBoneAt(index).parent;
        return parent==null?new Matrix4f(poses[index]):new Matrix4f(poses[parent.index]).invert().mul(poses[index]);
    }
    private static Matrix4f model(Matrix4f[] local,Matrix4f[] models,SkinningData actor,int index) {
        if(models[index]!=null) return models[index];
        var parent=actor.getBoneAt(index).parent;
        return models[index]=parent==null?new Matrix4f(local[index]):new Matrix4f(model(local,models,actor,parent.index)).mul(local[index]);
    }
    public static void main(String[] args) throws Exception {
        if(args.length!=3) throw new IllegalArgumentException("Bob_Idle.x Bob_Cart_Idle.x output.json");
        var idle=read(Path.of(args[0]));var cart=read(Path.of(args[1]));var actor=idle.actor;
        var from=reference(idle,actor);var to=reference(cart,actor);var json=new StringBuilder("[");
        for(int frame=0;frame<=40;frame++) {
            double time=frame/40.0,weight=CartShopping.progress(time,false).lift();
            var locals=new Matrix4f[actor.numBones()];var poses=new Matrix4f[actor.numBones()];
            for(int i=0;i<locals.length;i++) {
                var a=local(from,actor,i);var b=local(to,actor,i);locals[i]=new Matrix4f();
                if(!CartTransitionMath.blend(a,b,weight,locals[i])) throw new AssertionError("nonrigid native joint");
                var parent=actor.getBoneAt(i).parent;String name=actor.getBoneAt(i).name;
                if(parent!=null && !name.equals("Bip01") && !name.equals("Bip01_Pelvis")) {
                    float length=(float)(a.getTranslation(new Vector3f()).length()*(1-weight)+b.getTranslation(new Vector3f()).length()*weight);
                    var offset=locals[i].getTranslation(new Vector3f());
                    if(length>0) locals[i].setTranslation(offset.normalize(length));
                }
            }
            if(frame>0) json.append(',');json.append("{\"time\":").append(time).append(",\"bones\":{");
            for(int i=0;i<poses.length;i++) {
                if(i>0) json.append(',');json.append('"').append(actor.getBoneAt(i).name).append("\":[");
                float[] values=model(locals,poses,actor,i).get(new float[16]);
                for(int j=0;j<16;j++) {if(j>0) json.append(',');json.append(values[j]);}
                json.append(']');
            }
            json.append("}}");
        }
        Files.writeString(Path.of(args[2]),json.append("]\n").toString());
    }
}
