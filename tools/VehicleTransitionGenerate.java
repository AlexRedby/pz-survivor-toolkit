import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import jassimp.AiPostProcessSteps;
import jassimp.Jassimp;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams;
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams;

/** Rebuild the vehicle transition from the supported native Bob skeleton and clips.
 * Compile with CartClipCheck.java and the game JAR, then run with GAME OUTPUT_PREFIX.
 * OUTPUT_PREFIX.json feeds cart_clip_bake.py --template GAME/media/anims_X/Bob/Bob_Idle.x
 * --name Bob_ToolkitVehicleEnter; OUTPUT_PREFIX.tsv is its CartClipCheck oracle.
 * Outputs are authoring intermediates; this helper never installs a mod.
 */
public final class VehicleTransitionGenerate {
    record Source(SkinningData actor, AnimationClip clip) {}

    @SuppressWarnings("unchecked")
    static Source read(Path path) throws Exception {
        var params = ProcessedAiSceneParams.create();
        params.scene = Jassimp.importFile(path.toString(), EnumSet.of(
            AiPostProcessSteps.MAKE_LEFT_HANDED, AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS));
        params.mode = JAssImpImporter.LoadMode.AnimationOnly;
        params.animBonesScaleModifier = 1;
        var imported = ImportedSkeleton.process(ImportedSkeletonParams.create(params, params.scene.getMeshes().get(0)));
        var indices = (HashMap<String, Integer>) CartClipCheck.field(imported, "boneIndices");
        var hierarchy = (ArrayList<Integer>) CartClipCheck.field(imported, "skeletonHierarchy");
        var clips = (HashMap<String, AnimationClip>) CartClipCheck.field(imported, "clips");
        if (indices.size() != 45 || clips.size() != 1)
            throw new IllegalArgumentException("expected one native 45-bone Bob clip: " + path);
        var offsets = new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for (int i = 0; i < indices.size(); i++) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        return new Source(new SkinningData(new HashMap<>(), offsets, offsets, offsets, hierarchy, indices),
            clips.values().iterator().next());
    }

    static AnimationTrack track(Source source) {
        var track = AnimationTrack.alloc();
        track.startClip(source.clip, false, 0);
        track.setUseDeferredMovement(false);
        return track;
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("GAME OUTPUT_PREFIX");
        var chair = read(Path.of(args[0], "media/anims_X/Bob/Bob_SatChairIn.x"));
        var drive = read(Path.of(args[0], "media/anims_X/Bob/Bob_IdleDriving.x"));
        if (chair.clip.getDuration() != 1f || !chair.actor.boneIndices.keySet().equals(drive.actor.boneIndices.keySet()))
            throw new IllegalArgumentException("unsupported native animation timing or skeleton");
        var chairTrack = track(chair);
        var driveTrack = track(drive);
        driveTrack.UpdateKeyframes(0);
        var json = new StringBuilder("[");
        var tsv = new StringBuilder();
        for (int frame = 0; frame <= 60; frame++) {
            float time = frame / 60f;
            // Retain the standing/bending first half, then settle limbs and root
            // into the actual driving pose instead of the floor-relative chair pose.
            float blend = Math.max(0, Math.min(1, (time - .5f) / .5f));
            blend = blend * blend * (3 - 2 * blend);
            chairTrack.setCurrentTimeValue(time);
            chairTrack.setPreviousTimeValue(time);
            chairTrack.UpdateKeyframes(0);
            var local = new Matrix4f[chair.actor.numBones()];
            var models = new Matrix4f[local.length];
            for (int i = 0; i < local.length; i++) {
                var position = new org.lwjgl.util.vector.Vector3f();
                var rotation = new org.lwjgl.util.vector.Quaternion();
                var scale = new org.lwjgl.util.vector.Vector3f();
                var drivePosition = new org.lwjgl.util.vector.Vector3f();
                var driveRotation = new org.lwjgl.util.vector.Quaternion();
                chairTrack.get(i, position, rotation, scale);
                String name = chair.actor.getBoneAt(i).name;
                driveTrack.get(drive.actor.boneIndices.get(name), drivePosition, driveRotation, scale);
                var p = new Vector3f(position.x, position.y, position.z).lerp(
                    new Vector3f(drivePosition.x, drivePosition.y, drivePosition.z), blend);
                var q = new Quaternionf(rotation.x, rotation.y, rotation.z, rotation.w).normalize().slerp(
                    new Quaternionf(driveRotation.x, driveRotation.y, driveRotation.z, driveRotation.w).normalize(), blend).normalize();
                local[i] = new Matrix4f().translationRotate(p.x, p.y, p.z, q);
            }
            for (int i = 0; i < local.length; i++) CartClipCheck.model(i, chair.actor, local, models);
            if (frame > 0) json.append(',');
            json.append("{\"time\":").append(time).append(",\"bones\":{");
            for (int i = 0; i < models.length; i++) {
                String name = chair.actor.getBoneAt(i).name;
                float[] values = models[i].get(new float[16]);
                if (i > 0) json.append(',');
                json.append('"').append(name).append("\":[");
                tsv.append(time).append('\t').append(name);
                for (int j = 0; j < 16; j++) {
                    if (j > 0) json.append(',');
                    json.append(values[j]);
                    tsv.append('\t').append(values[j]);
                }
                json.append(']');
                tsv.append('\n');
            }
            json.append("}}");
        }
        Files.writeString(Path.of(args[1] + ".json"), json.append("]\n"));
        Files.writeString(Path.of(args[1] + ".tsv"), tsv);
    }
}
