package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector3fc;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.HelperFunctions;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.SkinningData;

/** Keep held carts rigid and on the floor without changing shared attachments. */
public final class CartGrounding {
    // shortcut: contacts are calibrated to these eight meshes; recalibrate after their geometry changes.
    private static final Vector3fc SHOP_CONTACT=new Vector3f(110.0467f,8.371053f,.98356926f);
    private static final Vector3fc WOOD_CONTACT=new Vector3f(-2.1228965e-4f,-.004627711f,-1.199774e-4f);
    private static final Vector3fc METAL_CONTACT=new Vector3f(-23.5423f,-23.2973f,-2.97487f);

    static Vector3fc contact(String model) {
        if(model==null) return null;
        return switch(model) {
            case "ShoppingCartModel", "ShoppingCartPartialModel", "ShoppingCartFullModel",
                "ShoppingCartFlashlightModel", "ShoppingCartFlashlightPartialModel", "ShoppingCartFlashlightFullModel" -> SHOP_CONTACT;
            case "WheelbarrowWood" -> WOOD_CONTACT;
            case "WheelbarrowMetal" -> METAL_CONTACT;
            default -> null;
        };
    }

    private static final class Matrices {
        final Matrix4f transform=new Matrix4f(), attachment=new Matrix4f(), delta=new Matrix4f();
        final org.lwjgl.util.vector.Matrix4f reference=new org.lwjgl.util.vector.Matrix4f();
        final HelperFunctions.TransformResult_QPS bone=new HelperFunctions.TransformResult_QPS();
        final org.lwjgl.util.vector.Quaternion rotation=new org.lwjgl.util.vector.Quaternion();
    }
    private static final ThreadLocal<Matrices> matrices=ThreadLocal.withInitial(Matrices::new);

    static boolean referencePose(AnimationClip clip, SkinningData skeleton, String boneName, Matrix4f out) {
        if(clip==null || skeleton==null || boneName==null) return false;
        Integer index=skeleton.boneIndices.get(boneName);
        if(index==null) return false;
        var state=matrices.get();
        var rotation=state.rotation;
        state.reference.setIdentity();
        for(var bone=skeleton.getBoneAt(index);bone!=null;bone=bone.parent) {
            var frames=clip.getBoneFramesAt(bone.index);
            if(frames==null || frames.length==0) return false;
            var frame=frames[0];
            // Native blended bones discard FBX scale (Dummy01 is exported at 0.01).
            rotation.set(frame.rotation);
            HelperFunctions.CreateFromQuaternion(rotation,state.bone.result);
            HelperFunctions.setPosition(state.bone.result,frame.position);
            org.lwjgl.util.vector.Matrix4f.mul(state.reference,state.bone.result,state.reference);
        }
        PZMath.convertMatrix(state.reference,out).transpose();
        return out.isFinite();
    }

    static boolean rigid(ModelInstanceRenderData data, AnimationClip clip, Matrix4f out) {
        var instance=data.modelInstance;
        if(data.parent==null || instance.parent==null || instance.parent.animPlayer==null) return false;
        var parent=instance.parent;
        var attachment=parent.getAttachmentById(instance.attachmentNameParent);
        if(attachment==null) attachment=parent.getAttachmentById(instance.parentBoneName);
        String bone=attachment==null?instance.parentBoneName:attachment.getBone();
        // Use the authored cart idle pose, never an arbitrary moving arm frame.
        if(!referencePose(clip,parent.animPlayer.getSkinningData(),bone,out)) return false;
        var scratch=matrices.get().attachment;
        out.mul(scratch.set(data.parent.xfrm).transpose());
        if(attachment!=null) out.mul(ModelInstanceRenderData.makeAttachmentTransform(attachment,scratch));
        attachment=instance.getAttachmentById(instance.attachmentNameSelf);
        if(attachment==null) attachment=instance.getAttachmentById(instance.parentBoneName);
        if(attachment!=null) {
            ModelInstanceRenderData.makeAttachmentTransform(attachment,scratch);
            if(ModelInstanceRenderData.invertAttachmentSelfTransform) scratch.invert();
            out.mul(scratch);
        }
        ModelInstanceRenderData.postMultiplyMeshTransform(out,instance.model.mesh);
        out.scale(instance.scale);
        return out.isFinite();
    }

    public static boolean ground(Matrix4f transform, Vector3fc low, Vector3fc high) {
        float lowest=Float.POSITIVE_INFINITY;
        for(int i=0;i<8;i++) {
            float x=(i&1)==0?low.x():high.x(), y=(i&2)==0?low.y():high.y(), z=(i&4)==0?low.z():high.z();
            lowest=Math.min(lowest,transform.m01()*x+transform.m11()*y+transform.m21()*z+transform.m31());
        }
        return ground(transform,lowest);
    }

    static boolean ground(Matrix4f transform, Vector3fc low, Vector3fc high, Vector3fc contact) {
        if(!validContact(low,high,contact)) return ground(transform,low,high);
        return ground(transform,transform.m01()*contact.x()+transform.m11()*contact.y()+transform.m21()*contact.z()+transform.m31());
    }

    private static boolean validContact(Vector3fc low, Vector3fc high, Vector3fc contact) {
        return contact!=null && Float.isFinite(contact.x()) && Float.isFinite(contact.y()) && Float.isFinite(contact.z())
            && contact.x()>=low.x() && contact.x()<=high.x() && contact.y()>=low.y() && contact.y()<=high.y()
            && contact.z()>=low.z() && contact.z()<=high.z();
    }

    private static boolean ground(Matrix4f transform, float lowest) {
        if(!Float.isFinite(lowest) || Math.abs(lowest)>=1) return false;
        transform.m31(transform.m31()-lowest+0.008f);
        return true;
    }

    static boolean align(Matrix4f transform, Vector3fc low, Vector3fc high, float lean, Matrix4f delta) {
        return align(transform,low,high,null,lean,delta);
    }

    static boolean align(Matrix4f transform, Vector3fc low, Vector3fc high, Vector3fc contact, float lean, Matrix4f delta) {
        if(!Float.isFinite(lean)) return false;
        float height=transform.m31();
        if(!ground(transform,low,high,contact)) return false;
        delta.translation(0,transform.m31()-height,0);
        if(lean!=0) {
            float centerX=validContact(low,high,contact)
                ? transform.m00()*contact.x()+transform.m10()*contact.y()+transform.m20()*contact.z()+transform.m30()
                : transform.m00()*(low.x()+high.x())*.5f+transform.m10()*(low.y()+high.y())*.5f
                    +transform.m20()*(low.z()+high.z())*.5f+transform.m30();
            var roll=matrices.get().attachment;
            // Bank around the measured contact, not a box center that moves the tire sideways.
            roll.translation(centerX,.008f,0).rotateZ(lean).translate(-centerX,-.008f,0);
            roll.mul(transform,transform);roll.mul(delta,delta);
        }
        return true;
    }

    public static void render(ModelSlotRenderData slot) {
        if(!(slot.character instanceof IsoPlayer player) || !CartSteeringHooks.enabled(player)) return;
        String name=player.getPrimaryHandItem().getStaticModel();
        var clip=ModelManager.instance.getAnimationClip("Bob_Cart_Idle");
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.parent==null || instance.modelScript==null || !instance.modelScript.getName().equals(name)
                || instance.model==null || instance.model.mesh==null) continue;
            var state=matrices.get();
            Matrix4f transform=state.transform;
            if(rigid(data,clip,transform)
                && align(transform,instance.model.mesh.minXyz,instance.model.mesh.maxXyz,
                    contact(instance.modelScript.getName()),(float)CartSteeringHooks.lean(player),state.delta)
                && CartGrip.render(slot,instance.parent,clip,state.delta,name,transform)) {
                data.xfrm.set(transform).transpose();
            } else {
                transform.set(data.xfrm).transpose();
                if(ground(transform,instance.model.mesh.minXyz,instance.model.mesh.maxXyz)) data.xfrm.set(transform).transpose();
            }
        }
    }

    private CartGrounding() {}
}
