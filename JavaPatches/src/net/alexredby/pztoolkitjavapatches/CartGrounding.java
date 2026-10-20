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
import zombie.inventory.InventoryItem;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.ModelScript;

/** Keep held carts rigid and on the floor without changing shared attachments. */
public final class CartGrounding {
    // shortcut: contacts are calibrated to these eight meshes; recalibrate after their geometry changes.
    private static final Vector3fc SHOP_CONTACT=new Vector3f(110.0467f,8.371053f,.98356926f);
    private static final Vector3fc WOOD_CONTACT=new Vector3f(-2.1228965e-4f,-.004435286f,-4.0280633e-5f);
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

    private static boolean cartModel(String type,String model) {
        return switch(type) {
            case "SaucedCarts.ShoppingCart" -> contact(model)==SHOP_CONTACT;
            case "SaucedWheelbarrow.WheelbarrowWood" -> "WheelbarrowWood".equals(model);
            case "SaucedWheelbarrow.WheelbarrowMetal" -> "WheelbarrowMetal".equals(model);
            default -> false;
        };
    }

    private static boolean cartModel(String type,ModelScript model) {
        return model!=null && model.getModule()!=null && "Base".equals(model.getModule().name)
            && cartModel(type,model.getName());
    }

    static ModelScript resolvedModel(InventoryItem item) {
        String reference=item.getStaticModel();
        if(reference==null) return null;
        var model=ScriptManager.instance.getModelScript(reference);
        return cartModel(item.getFullType(),model)?model:null;
    }

    static boolean sameModel(InventoryItem item,String reference) {
        var expected=resolvedModel(item);
        return expected!=null && reference!=null && expected==ScriptManager.instance.getModelScript(reference);
    }

    /** ModData can update the remote item's fill model after native equipped models were cached. */
    static void refreshRemoteModel(IsoPlayer player) {
        if(player.isLocalPlayer() || !CartSteeringHooks.supportedCart(player)
            || player.getVariableBoolean("IsPerformingAnAction") || !player.getCharacterActions().isEmpty()
            || player.forceNullOverride || player.isHideWeaponModel() || player.isHideEquippedHandR()
            || player.overridePrimaryHandModel!=null && !player.overridePrimaryHandModel.isEmpty()
            || player.overrideSecondaryHandModel!=null && !player.overrideSecondaryHandModel.isEmpty()) return;
        var instance=player.primaryHandModel;
        if(instance==null || instance.modelScript==null) return;
        var item=player.getPrimaryHandItem();
        var expected=resolvedModel(item);
        if(expected!=null && expected!=instance.modelScript && cartModel(item.getFullType(),instance.modelScript))
            player.resetEquippedHandsModels();
    }

    private static final class Matrices {
        final Matrix4f transform=new Matrix4f(), attachment=new Matrix4f(), delta=new Matrix4f();
        final org.lwjgl.util.vector.Matrix4f reference=new org.lwjgl.util.vector.Matrix4f();
        final HelperFunctions.TransformResult_QPS bone=new HelperFunctions.TransformResult_QPS();
        final org.lwjgl.util.vector.Quaternion rotation=new org.lwjgl.util.vector.Quaternion();
    }
    private static final ThreadLocal<Matrices> matrices=ThreadLocal.withInitial(Matrices::new);

    static void lowerHandles(Matrix4f transform, String model) {
        if(!"WheelbarrowWood".equals(model) && !"WheelbarrowMetal".equals(model)) return;
        var point=contact(model);
        float x=transform.m00()*point.x()+transform.m10()*point.y()+transform.m20()*point.z()+transform.m30();
        float y=transform.m01()*point.x()+transform.m11()*point.y()+transform.m21()*point.z()+transform.m31();
        float z=transform.m02()*point.x()+transform.m12()*point.y()+transform.m22()*point.z()+transform.m32();
        // Lower the handles around the tire; do not pitch the actor's torso with the cart.
        matrices.get().attachment.translation(x,y,z).rotateX((float)Math.toRadians("WheelbarrowWood".equals(model)?7.9:8))
            .translate(-x,-y,-z).mul(transform,transform);
        // Keep the native hips fixed while leaving the wooden handles within the two arm links' reach.
        if("WheelbarrowWood".equals(model)) transform.m32(transform.m32()+.05f);
    }

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

    static float woodenLowest(Matrix4f transform) {
        return wheelbarrowLowest(transform,CartWheelbarrow.WOOD);
    }

    static float wheelbarrowLowest(Matrix4f transform, CartWheelbarrow profile) {
        float centerY=transform.m01()*profile.centerX()+transform.m11()*profile.centerY()
            +transform.m21()*profile.centerZ()+transform.m31();
        return centerY-profile.radius()*(float)Math.hypot(transform.m11(),transform.m21())
            -profile.halfWidth()*Math.abs(transform.m01());
    }

    static boolean alignWood(Matrix4f transform, float lean, float gaitShift, Matrix4f delta) {
        return alignWood(transform,lean,Math.abs(lean),gaitShift,delta);
    }

    static boolean alignWood(Matrix4f transform, float lean, float pressure, float gaitShift, Matrix4f delta) {
        return alignWheelbarrow(transform,CartWheelbarrow.WOOD,lean,pressure,gaitShift,delta);
    }

    static boolean alignWheelbarrow(Matrix4f transform, CartWheelbarrow profile, float lean, float pressure, float gaitShift, Matrix4f delta) {
        if(!Float.isFinite(lean) || !Float.isFinite(pressure) || pressure<Math.abs(lean)
            || !Float.isFinite(gaitShift) || gaitShift<-.24f || gaitShift>0) return false;
        // The running torso moves forward; follow its native blend without lifting the handles.
        transform.m32(transform.m32()+CartSteeringMath.woodenShift(pressure,gaitShift));
        float height=transform.m31();
        if(!ground(transform,wheelbarrowLowest(transform,profile))) return false;
        delta.translation(0,transform.m31()-height,0);
        float centerX=transform.m00()*profile.centerX()+transform.m10()*profile.centerY()
            +transform.m20()*profile.centerZ()+transform.m30();
        var roll=matrices.get().attachment;
        roll.translation(centerX,.008f,0).rotateZ(lean).translate(-centerX,-.008f,0);
        roll.mul(transform,transform);roll.mul(delta,delta);
        // The rotating tire is a cylinder, not one fixed polygon vertex; its rim must clear the floor at every phase.
        height=transform.m31();
        if(!ground(transform,wheelbarrowLowest(transform,profile))) return false;
        delta.m31(delta.m31()+transform.m31()-height);
        return true;
    }

    public static void render(ModelSlotRenderData slot) {
        if(Main.CART_TRANSITION_SUPPORTED) CartImpactPose.render(slot);
        CartWheelSpin.prepare(slot,Double.NaN);
        if(CartTransition.render(slot)) return;
        if(!(slot.character instanceof IsoPlayer player) || !CartMotionSync.visualEnabled(player)) return;
        var expected=resolvedModel(player.getPrimaryHandItem());
        if(expected==null) return;
        String name=expected.getName();
        var profile=CartWheelbarrow.forModel(name);
        var clip=ModelManager.instance.getAnimationClip("Bob_Cart_Idle");
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.parent==null || instance.modelScript!=expected
                || instance.model==null || instance.model.mesh==null) continue;
            var state=matrices.get();
            Matrix4f transform=state.transform;
            boolean rigid=rigid(data,clip,transform);
            if(rigid) lowerHandles(transform,name);
            float lean=(float)(player.isLocalPlayer()?CartSteeringHooks.lean(player):CartMotionSync.lean(player));
            float pressure=(float)(player.isLocalPlayer()?CartSteeringHooks.clearanceLean(player):CartMotionSync.pressure(player));
            if(rigid
                && (profile!=null?alignWheelbarrow(transform,profile,lean,pressure,CartLegPace.woodenGaitShift(player),state.delta)
                    :align(transform,instance.model.mesh.minXyz,instance.model.mesh.maxXyz,
                        contact(instance.modelScript.getName()),lean,state.delta))) {
                // A failed arm solve must not replace the grounded cart with the moving hand attachment.
                CartGrip.render(slot,instance.parent,clip,state.delta,name,transform);
                data.xfrm.set(transform).transpose();
                if(profile!=null) CartEmergencyDrop.capture(player,slot,transform);
                CartWheelSpin.prepare(slot,player.isLocalPlayer()?CartSteeringHooks.wheelPhase(player,slot,transform)
                    :CartWheelSpin.follow(player.getPrimaryHandItem(),slot.x,slot.y,slot.animPlayerAngle,transform));
            } else {
                transform.set(data.xfrm).transpose();
                if(ground(transform,instance.model.mesh.minXyz,instance.model.mesh.maxXyz)) data.xfrm.set(transform).transpose();
            }
        }
    }

    private CartGrounding() {}
}
