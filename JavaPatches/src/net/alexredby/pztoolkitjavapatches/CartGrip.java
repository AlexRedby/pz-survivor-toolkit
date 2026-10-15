package net.alexredby.pztoolkitjavapatches;

import java.nio.FloatBuffer;
import org.joml.Matrix4f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.SkinningBone;
import zombie.core.skinnedmodel.model.SkinningData;

/** Keep the authored cart grip in this render instance while the native legs keep walking. */
public final class CartGrip {
    private static final class Matrices {
        final Matrix4f[] poses=new Matrix4f[60];
        final Matrix4f attachment=new Matrix4f();
        final org.lwjgl.util.vector.Matrix4f model=new org.lwjgl.util.vector.Matrix4f();
        final org.lwjgl.util.vector.Matrix4f skin=new org.lwjgl.util.vector.Matrix4f();
    }
    private static final ThreadLocal<Matrices> matrices=ThreadLocal.withInitial(Matrices::new);

    private static boolean upperBody(SkinningBone bone) {
        for(;bone!=null;bone=bone.parent) {
            // Native thighs branch from Spine too; keep their entire walking chains live.
            if("Bip01_L_Thigh".equals(bone.name) || "Bip01_R_Thigh".equals(bone.name)) return false;
            if("Bip01_Spine".equals(bone.name)) return true;
        }
        return false;
    }

    static Matrix4f[] poses(AnimationClip clip, SkinningData actor, Matrix4f delta) {
        var poses=matrices.get().poses;
        if(actor==null || actor.numBones()>poses.length) return null;
        if(actor.getBone("Bip01_Spine")==null || actor.getBone("Bip01_L_Hand")==null
            || actor.getBone("Bip01_R_Hand")==null) return null;
        for(int i=0;i<actor.numBones();i++) {
            var bone=actor.getBoneAt(i);
            if(!upperBody(bone)) continue;
            if(poses[i]==null) poses[i]=new Matrix4f();
            if(!CartGrounding.referencePose(clip,actor,bone.name,poses[i])) return null;
            delta.mul(poses[i],poses[i]);
        }
        return poses;
    }

    static int skin(FloatBuffer palette, org.lwjgl.util.vector.Matrix4f[] shaderPalette,
        SkinningData target, SkinningData actor, Matrix4f[] poses) {
        var state=matrices.get();
        int position=palette.position(), changed=0;
        try {
            for(var entry:target.boneIndices.entrySet()) {
                var bone=actor.getBone(entry.getKey());
                int index=entry.getValue();
                if(!upperBody(bone) || index<0 || (index+1)*16>palette.limit()
                    || index>=target.boneOffset.size() || target.boneOffset.get(index)==null) continue;
                PZMath.convertMatrix(poses[bone.index],state.model).transpose();
                // Native skin matrices are inverse-bind * model-pose in transposed LWJGL storage.
                org.lwjgl.util.vector.Matrix4f.mul(target.boneOffset.get(index),state.model,state.skin);
                palette.position(index*16);state.skin.store(palette);
                if(shaderPalette!=null && index<shaderPalette.length) {
                    if(shaderPalette[index]==null) shaderPalette[index]=new org.lwjgl.util.vector.Matrix4f();
                    shaderPalette[index].load(state.skin);
                }
                changed++;
            }
        } finally {palette.position(position);}
        return changed;
    }

    static boolean render(ModelSlotRenderData slot, ModelInstance owner, AnimationClip clip, Matrix4f delta) {
        ModelInstanceRenderData body=null;
        for(var data:slot.modelData) if(data.modelInstance==owner) {body=data;break;}
        if(body==null || body.matrixPalette==null || !(owner.model.tag instanceof SkinningData bodySkin)) return false;
        for(String hand:new String[]{"Bip01_L_Hand","Bip01_R_Hand"}) {
            Integer index=bodySkin.boneIndices.get(hand);
            if(index==null || index<0 || (index+1)*16>body.matrixPalette.limit()
                || index>=bodySkin.boneOffset.size() || bodySkin.boneOffset.get(index)==null) return false;
        }
        var actor=owner.animPlayer.getSkinningData();
        var poses=poses(clip,actor,delta);
        if(poses==null) return false;
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.animPlayer==owner.animPlayer && instance.model!=null && !instance.model.isStatic
                && data.matrixPalette!=null && instance.model.tag instanceof SkinningData target) {
                var parameter=data.properties.GetParameter("MatrixPalette");
                var shaderPalette=parameter!=null && parameter.GetValue() instanceof org.lwjgl.util.vector.Matrix4f[] value?value:null;
                skin(data.matrixPalette,shaderPalette,target,actor,poses);
            } else if(instance.parent==owner && instance.model!=null && instance.model.isStatic) {
                var attachment=owner.getAttachmentById(instance.attachmentNameParent);
                if(attachment==null) attachment=owner.getAttachmentById(instance.parentBoneName);
                String bone=attachment==null?instance.parentBoneName:attachment.getBone();
                if(bone!=null && upperBody(actor.getBone(bone))) {
                    var transform=matrices.get().attachment;
                    if(CartGrounding.rigid(data,clip,transform)) {
                        delta.mul(transform,transform);data.xfrm.set(transform).transpose();
                    }
                }
            }
        }
        return true;
    }

    private CartGrip() {}
}
