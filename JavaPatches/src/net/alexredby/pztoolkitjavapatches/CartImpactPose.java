package net.alexredby.pztoolkitjavapatches;

import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.WeakHashMap;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.SkinningData;

/** Slot-local knee clearance during the confirmed wooden-cart release; native movement stays untouched. */
public final class CartImpactPose {
    static final float MAX_ANGLE=(float)Math.toRadians(6);
    private record Snapshot(IsoPlayer player,ModelInstance owner,Model model,AnimationPlayer animator,float angle) {}
    private record Write(FloatBuffer palette,int index,org.lwjgl.util.vector.Matrix4f[] shader,
                         org.lwjgl.util.vector.Matrix4f value) {}
    private static final WeakHashMap<ModelSlotRenderData,Snapshot> slots=new WeakHashMap<>();
    private static final String THIGH="Bip01_R_Thigh",CALF="Bip01_R_Calf",FOOT="Bip01_R_Foot";

    static float angle(long age) {
        if(age<=0 || age>=450_000_000L) return 0;
        double ms=age/1_000_000.0,u=ms<120?ms/120:ms<=280?1:(450-ms)/170;
        return MAX_ANGLE*(float)(u*u*(3-2*u));
    }

    public static synchronized void bind(ModelSlotRenderData slot,ModelManager.ModelSlot source) {
        long age=source!=null && source.character instanceof IsoPlayer player?CartImpactMotion.poseAgeNanos(player):-1;
        capture(slot,source,age);
    }

    /** Producer-only immutable snapshot; explicit age also permits isolated render-lifecycle tests. */
    static synchronized void capture(ModelSlotRenderData slot,ModelManager.ModelSlot source,long age) {
        slots.remove(slot);
        float amount=angle(age);
        if(slot==null || source==null || !(source.character instanceof IsoPlayer player) || player.isFemale()
            || slot.character!=player || slot.object!=player || source.model==null || source.model.object!=player
            || source.model.model==null || source.model.animPlayer==null || amount<=0) return;
        var owner=source.model;
        slots.put(slot,new Snapshot(player,owner,owner.model,owner.animPlayer,amount));
    }

    public static synchronized void release(ModelSlotRenderData slot) {slots.remove(slot);}

    private static boolean matrix(Matrix4f value) {
        return value!=null && value.isFinite() && Math.abs(value.m03())<1e-5 && Math.abs(value.m13())<1e-5
            && Math.abs(value.m23())<1e-5 && Math.abs(value.m33()-1)<1e-5 && Math.abs(value.determinant3x3())>1e-8;
    }

    static boolean swivel(Matrix4f thigh,Matrix4f calf,Matrix4f foot,float angle,Matrix4f outThigh,Matrix4f outCalf) {
        if(!matrix(thigh) || !matrix(calf) || !matrix(foot) || !Float.isFinite(angle) || angle<0 || angle>MAX_ANGLE) return false;
        var hip=thigh.getTranslation(new Vector3f());var knee=calf.getTranslation(new Vector3f());
        var ankle=foot.getTranslation(new Vector3f());var axis=ankle.sub(hip,new Vector3f());
        if(axis.lengthSquared()<1e-10f || knee.distanceSquared(hip)<1e-10f || knee.distanceSquared(ankle)<1e-10f) return false;
        axis.normalize();var radius=knee.sub(hip,new Vector3f());radius.fma(-radius.dot(axis),axis);
        if(radius.lengthSquared()<1e-10f) return false;
        var delta=new Matrix4f().translation(hip).rotate(angle,axis).translate(-hip.x,-hip.y,-hip.z);
        delta.mul(thigh,outThigh);delta.mul(calf,outCalf);
        return matrix(outThigh) && matrix(outCalf);
    }

    private static int index(SkinningData skin,String name,FloatBuffer palette) {
        var index=skin.boneIndices.get(name);
        return index!=null && index>=0 && index<skin.boneOffset.size() && skin.boneOffset.get(index)!=null
            && (long)(index+1)*16<=palette.limit()?index:-1;
    }

    private static Matrix4f pose(SkinningData skin,String name,FloatBuffer palette) {
        int index=index(skin,name,palette);
        if(index<0) return null;
        var raw=new org.lwjgl.util.vector.Matrix4f();var view=palette.duplicate();view.position(index*16);raw.load(view);
        var offset=PZMath.convertMatrix(skin.boneOffset.get(index),new Matrix4f()).transpose();
        var model=PZMath.convertMatrix(raw,new Matrix4f()).transpose();
        if(!matrix(offset) || !matrix(model)) return null;
        model.mul(offset.invert());return matrix(model)?model:null;
    }

    private static boolean stage(ModelInstanceRenderData data,SkinningData skin,String name,Matrix4f pose,ArrayList<Write> writes) {
        if(data.matrixPalette==null || data.matrixPalette.isReadOnly()) return false;
        int index=index(skin,name,data.matrixPalette);
        var property=data.properties.GetParameter("MatrixPalette");
        if(index<0 || property==null || !(property.GetValue() instanceof org.lwjgl.util.vector.Matrix4f[] shader)
            || index>=shader.length) return false;
        var offset=PZMath.convertMatrix(skin.boneOffset.get(index),new Matrix4f()).transpose();
        if(!matrix(offset) || pose(skin,name,data.matrixPalette)==null) return false;
        var raw=PZMath.convertMatrix(new Matrix4f(pose).transpose(),new org.lwjgl.util.vector.Matrix4f());
        org.lwjgl.util.vector.Matrix4f.mul(skin.boneOffset.get(index),raw,raw);
        if(!matrix(PZMath.convertMatrix(raw,new Matrix4f()).transpose())) return false;
        writes.add(new Write(data.matrixPalette,index,shader,raw));return true;
    }

    /** Worker uses only the bound identity/angle and this slot's prepared matrices, never actor state. */
    public static synchronized void render(ModelSlotRenderData slot) {
        var snapshot=slots.remove(slot);
        if(snapshot==null || slot.character!=snapshot.player || slot.object!=snapshot.player
            || snapshot.owner.model!=snapshot.model || snapshot.owner.animPlayer!=snapshot.animator
            || !(snapshot.model.tag instanceof SkinningData skin)) return;
        var writes=new ArrayList<Write>();
        try {
            ModelInstanceRenderData body=null;
            for(var data:slot.modelData) if(data.modelInstance==snapshot.owner) {body=data;break;}
            if(body==null || body.matrixPalette==null) return;
            var thigh=skin.getBone(THIGH);var calf=skin.getBone(CALF);var foot=skin.getBone(FOOT);
            if(thigh==null || calf==null || foot==null || calf.parent!=thigh || foot.parent!=calf) return;
            var fromThigh=pose(skin,THIGH,body.matrixPalette);var fromCalf=pose(skin,CALF,body.matrixPalette);
            var fromFoot=pose(skin,FOOT,body.matrixPalette);var toThigh=new Matrix4f();var toCalf=new Matrix4f();
            if(!swivel(fromThigh,fromCalf,fromFoot,snapshot.angle,toThigh,toCalf)) return;
            for(var data:slot.modelData) {
                var instance=data.modelInstance;
                if(instance==null || instance.animPlayer!=snapshot.animator || instance.model==null || instance.model.isStatic) continue;
                if(!(instance.model.tag instanceof SkinningData target)
                    || !stage(data,target,THIGH,toThigh,writes) || !stage(data,target,CALF,toCalf,writes)) return;
            }
        } catch(RuntimeException invalid) {return;}
        // All affected meshes passed validation before the first palette write.
        for(var write:writes) {
            var view=write.palette.duplicate();view.position(write.index*16);write.value.store(view);
            write.shader[write.index]=write.value;
        }
    }

    private CartImpactPose() {}
}
