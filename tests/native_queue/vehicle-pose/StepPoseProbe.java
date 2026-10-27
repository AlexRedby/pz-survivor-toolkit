package net.alexredby.vehicleposefixture;

import java.nio.FloatBuffer;
import java.util.Collections;
import java.util.Map;
import java.util.WeakHashMap;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.SkinningData;

/** Test-only reader of the exact immutable draw palette, including clothes. */
public final class StepPoseProbe {
    public record Phase(String label, String clip, float fraction) {}
    public static final Map<ModelSlotRenderData,Phase> phases=Collections.synchronizedMap(new WeakHashMap<>());
    public static final String[] BONES={"Bip01_Head", "Bip01_Pelvis", "Bip01_L_Thigh", "Bip01_L_Calf", "Bip01_L_Foot", "Bip01_L_Toe0",
                                       "Bip01_R_Thigh", "Bip01_R_Calf", "Bip01_R_Foot", "Bip01_R_Toe0"};

    public static final ThreadLocal<ModelSlotRenderData> capturing=new ThreadLocal<>();
    @me.zed_0xff.zombie_buddy.Patch(className="net.alexredby.pztoolkitjavapatches.VehicleTransitionRender", methodName="capture", strictMatch=true)
    public static class CaptureSlot {
        @me.zed_0xff.zombie_buddy.Patch.OnEnter
        public static void enter(@me.zed_0xff.zombie_buddy.Patch.Argument(0) ModelSlotRenderData slot) {
            capturing.set(slot);
            if (slot!=null) phases.remove(slot);
        }
        @me.zed_0xff.zombie_buddy.Patch.OnExit
        public static void exit() { capturing.remove(); }
    }
    // The solver argument labels the immutable palette being solved. Reading the live
    // AnimationTrack later can attach next update's time to this render's pose.
    @me.zed_0xff.zombie_buddy.Patch(className="net.alexredby.pztoolkitjavapatches.VehicleStepPose", methodName="solve", strictMatch=true)
    public static class SolvePhase {
        @me.zed_0xff.zombie_buddy.Patch.OnEnter
        public static void enter(@me.zed_0xff.zombie_buddy.Patch.Argument(5) float phase,
                                 @me.zed_0xff.zombie_buddy.Patch.Argument(6) boolean exiting) {
            ModelSlotRenderData slot=capturing.get();
            if (slot!=null && Main.label!=null)
                phases.put(slot,new Phase(Main.label,exiting?"Bob_ToolkitVehicleExit":"Bob_ToolkitVehicleEnter",phase));
        }
    }

    public static Matrix4f pose(ModelInstanceRenderData data,String name) {
        if (!(data.modelInstance.model.tag instanceof SkinningData skin) || data.matrixPalette==null) return null;
        Integer index=skin.boneIndices.get(name);
        if (index==null || (index+1)*16>data.matrixPalette.limit()) return null;
        FloatBuffer b=data.matrixPalette.duplicate();b.position(index*16);
        var raw=new org.lwjgl.util.vector.Matrix4f();raw.load(b);
        return PZMath.convertMatrix(raw,new Matrix4f()).transpose()
            .mul(PZMath.convertMatrix(skin.boneOffset.get(index),new Matrix4f()).transpose().invert());
    }

    public static Vector3f vehicle(ModelSlotRenderData slot,Matrix4f pose) {
        return new Vector3f(slot.inVehicleX+1.5f*pose.m30(),slot.inVehicleY+1.5f*pose.m31(),slot.inVehicleZ-1.5f*pose.m32());
    }

    public static void render(ModelSlotRenderData slot,String current,long now) {
        Phase phase=phases.get(slot);
        if (!slot.inVehicle || phase==null || !phase.label().equals(current)) return;
        ModelInstanceRenderData body=null;
        for (var data:slot.modelData) {
            if (data.modelInstance!=null && data.modelInstance.animPlayer==slot.animPlayer && pose(data,"Bip01_L_Foot")!=null) {body=data;break;}
        }
        if (body==null) throw new IllegalStateException("Missing rendered body palette");
        var poses=new Matrix4f[BONES.length];
        var result=new StringBuilder("[VEHICLE_POSE] BONES ").append(current).append(" ms=").append(now)
            .append(" clip=").append(phase.clip()).append(" phase=").append(phase.fraction())
            .append(" origin=").append(slot.inVehicleX).append(',').append(slot.inVehicleY).append(',').append(slot.inVehicleZ);
        for (int i=0;i<BONES.length;i++) {
            poses[i]=pose(body,BONES[i]);
            if (poses[i]==null) throw new IllegalStateException("Missing rendered bone "+BONES[i]);
            Vector3f v=vehicle(slot,poses[i]);
            result.append(' ').append(BONES[i]).append('=').append(v.x).append(',').append(v.y).append(',').append(v.z);
        }
        int skins=0;float error=0;
        for (var data:slot.modelData) {
            if (data.modelInstance==null || data.modelInstance.animPlayer!=slot.animPlayer || pose(data,"Bip01_L_Foot")==null) continue;
            skins++;
            for(int i=0;i<BONES.length;i++) {
                Matrix4f p=pose(data,BONES[i]);
                if (p==null) throw new IllegalStateException("Clothing omitted "+BONES[i]);
                error=Math.max(error,p.getTranslation(new Vector3f()).distance(poses[i].getTranslation(new Vector3f())));
            }
        }
        System.out.println(result.append(" skins=").append(skins).append(" skinError=").append(error));
    }
}
