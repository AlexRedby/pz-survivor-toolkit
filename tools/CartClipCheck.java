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

/** Offline native .x FK check: clip.x expected.tsv [matrixTolerance].
 * TSV rows are time(seconds), bone name, 16 column-major model-space floats.
 * Import uses the game's .x defaults, with deferred movement disabled so every
 * authored matrix is compared directly, including Translation_Data.
 */
public final class CartClipCheck {
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

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        if (args.length < 2 || args.length > 3) throw new IllegalArgumentException("clip.x expected.tsv [matrixTolerance]");
        float tolerance = args.length == 3 ? Float.parseFloat(args[2]) : 2e-4f;
        if (!Float.isFinite(tolerance) || tolerance <= 0) throw new IllegalArgumentException("invalid tolerance");
        var expected = new LinkedHashMap<Float, Map<String, float[]>>();
        float previousTime = -1;
        for (String line : Files.readAllLines(Path.of(args[1]))) {
            if (line.isBlank()) continue;
            String[] columns = line.split("\t", -1);
            if (columns.length != 18) throw new IllegalArgumentException("expected 18 TSV columns");
            float time = Float.parseFloat(columns[0]);
            if (!Float.isFinite(time) || time < 0 || time < previousTime) throw new IllegalArgumentException("invalid TSV time");
            previousTime = time;
            var matrix = new float[16];
            for (int index = 0; index < 16; index++) {
                matrix[index] = Float.parseFloat(columns[index + 2]);
                if (!Float.isFinite(matrix[index])) throw new IllegalArgumentException("non-finite expected matrix");
            }
            if (expected.computeIfAbsent(time, key -> new HashMap<>()).put(columns[1], matrix) != null)
                throw new IllegalArgumentException("duplicate time/bone");
        }
        if (expected.isEmpty() || expected.size() > 3601) throw new IllegalArgumentException("expected 1..3601 sample times");
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
        float maxError = 0;
        String worst = "";
        int compared = 0;
        for (var frame : expected.entrySet()) {
            if (!frame.getValue().keySet().equals(indices.keySet())) throw new AssertionError("expected all 45 bones at " + frame.getKey());
            if (frame.getKey() > clip.getDuration() + 1e-6f) throw new AssertionError("sample past clip duration");
            var actual = sample(track, actor, frame.getKey());
            for (var bone : frame.getValue().entrySet()) {
                var values = actual[indices.get(bone.getKey())].get(new float[16]);
                for (int index = 0; index < 16; index++) {
                    float error = Math.abs(values[index] - bone.getValue()[index]);
                    if (!Float.isFinite(error)) throw new AssertionError("non-finite native matrix");
                    if (error > maxError) {
                        maxError = error;
                        worst = "time=" + frame.getKey() + " bone=" + bone.getKey() + " element=" + index +
                            " expected=" + bone.getValue()[index] + " actual=" + values[index];
                    }
                    compared++;
                }
            }
        }
        System.out.printf(Locale.ROOT, "ROUNDTRIP clip=%s duration=%.9f bones=%d samples=%d values=%d maxError=%.9g tolerance=%.9g worst=%s%n",
            clip.name, clip.getDuration(), indices.size(), expected.size(), compared, maxError, tolerance, worst);
        if (maxError > tolerance) throw new AssertionError("native model-space matrices differ: " + worst);
    }
}
