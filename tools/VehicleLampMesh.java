import jassimp.AiBuiltInWrapperProvider;
import jassimp.AiMatrix4f;
import jassimp.AiMesh;
import jassimp.AiNode;
import jassimp.AiPostProcessSteps;
import jassimp.AiScene;
import jassimp.Jassimp;
import java.util.EnumSet;

/**
 * Offline FBX geometry export using the installed game's Jassimp importer.
 *
 * Run with the game's Contents/Java directory as java.library.path and its
 * projectzomboid.jar on the classpath. Arguments: FBX path, optional mesh name.
 * JSON contains the single mesh selected by ProcessedAiScene.findMesh,
 * raw vertices [x,y,z,u,1-v], native triangle winding, and a
 * row-major 4x4 node transform (apply it to column vectors [x,y,z,1]).
 *
 * Matches FileTask_LoadMesh.loadFBX's default import flags, the parent-node
 * composition in ProcessedAiScene.initMeshTransform, and ImportedStaticMesh's
 * UV flip and winding. No GL context, game launch, or game-file writes occur.
 * ModelScript scale/invertX and VehicleScript model scale/offset/rotation are
 * deliberately separate from this mesh export. For a transformed mesh point q,
 * the corresponding native vehicle-local point is:
 *   offset + F * Rxyz * diag(invertX ? -1 : 1, 1, 1) * q * vehicleScale * meshScale
 * where F=diag(-1,1,1), Rxyz is VehicleScript model rotation, and offset is
 * runtime VehicleScript.getModelOffset() (already scaled by Loaded()). This
 * follows BaseVehicle.updateTransform and ModelInstanceRenderData.initModel;
 * the renderer mirrors vehicle rotation about X before applying this matrix.
 */
public final class VehicleLampMesh {
    private static final AiBuiltInWrapperProvider WRAPPER = new AiBuiltInWrapperProvider();

    private static double[][] identity() {
        double[][] matrix = new double[4][4];
        for (int i = 0; i < 4; i++) matrix[i][i] = 1;
        return matrix;
    }

    private static double[][] multiply(double[][] left, AiMatrix4f right) {
        double[][] result = new double[4][4];
        for (int r = 0; r < 4; r++) {
            for (int c = 0; c < 4; c++) {
                for (int k = 0; k < 4; k++) result[r][c] += left[r][k] * right.get(k, c);
            }
        }
        return result;
    }

    private static double[][] findTransform(AiNode node, int meshIndex, double[][] parent) {
        double[][] composed = multiply(parent, node.getTransform(WRAPPER));
        for (int index : node.getMeshes()) if (index == meshIndex) return composed;
        for (AiNode child : node.getChildren()) {
            double[][] result = findTransform(child, meshIndex, composed);
            if (result != null) return result;
        }
        return null;
    }

    // JAssImpImporter.FindNode searches descendants with exact case, whereas
    // ProcessedAiScene.findMesh first tries mesh names ignoring case.
    private static AiNode findNode(AiNode parent, String name) {
        for (AiNode child : parent.getChildren()) {
            if (name.equals(child.getName())) return child;
            AiNode result = findNode(child, name);
            if (result != null) return result;
        }
        return null;
    }

    private static int selectMesh(AiScene scene, AiNode root, String name) {
        if (scene.getNumMeshes() == 0) throw new IllegalArgumentException("Scene contains no meshes");
        if (name == null || name.isBlank()) {
            for (int i = 0; i < scene.getNumMeshes(); i++) {
                if (scene.getMeshes().get(i).hasBones()) return i;
            }
            return 0;
        }
        for (int i = 0; i < scene.getNumMeshes(); i++) {
            if (name.equalsIgnoreCase(scene.getMeshes().get(i).getName())) return i;
        }
        AiNode node = findNode(root, name);
        if (node != null && node.getNumMeshes() == 1) return node.getMeshes()[0];
        throw new IllegalArgumentException("No matching mesh or single-mesh node: " + name);
    }

    private static void number(StringBuilder output, double value) {
        if (!Double.isFinite(value)) throw new IllegalArgumentException("Non-finite mesh coordinate");
        output.append(value == 0 ? "0" : Double.toString(value));
    }

    private static void string(StringBuilder output, String value) {
        output.append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"' -> output.append("\\\"");
                case '\\' -> output.append("\\\\");
                case '\n' -> output.append("\\n");
                case '\r' -> output.append("\\r");
                case '\t' -> output.append("\\t");
                default -> {
                    if (c < 32) output.append(String.format("\\u%04x", (int)c));
                    else output.append(c);
                }
            }
        }
        output.append('"');
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1 || args.length > 2) {
            throw new IllegalArgumentException("Usage: VehicleLampMesh.java FBX_PATH [MESH_NAME]");
        }
        // Keep this list aligned with FileTask_LoadMesh.loadFBX, not generic
        // Assimp defaults. FBX postProcess overrides are not used by vanilla cars.
        AiScene scene = Jassimp.importFile(args[0], EnumSet.of(
            AiPostProcessSteps.FIND_INSTANCES,
            AiPostProcessSteps.MAKE_LEFT_HANDED,
            AiPostProcessSteps.LIMIT_BONE_WEIGHTS,
            AiPostProcessSteps.TRIANGULATE,
            AiPostProcessSteps.OPTIMIZE_MESHES,
            AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS,
            AiPostProcessSteps.JOIN_IDENTICAL_VERTICES));
        AiNode root = scene.getSceneRoot(WRAPPER);
        int selected = selectMesh(scene, root, args.length == 2 ? args[1] : null);
        StringBuilder output = new StringBuilder(128 * 1024);
        output.append("{\"meshes\":[");
        int exported = 0;
        for (int meshIndex = 0; meshIndex < scene.getNumMeshes(); meshIndex++) {
            AiMesh mesh = scene.getMeshes().get(meshIndex);
            if (meshIndex != selected) continue;
            if (!mesh.hasTexCoords(0)) throw new IllegalArgumentException("Mesh has no UV0: " + mesh.getName());
            if (mesh.hasBones()) throw new IllegalArgumentException("Skinned mesh needs a separate bone transform: " + mesh.getName());
            double[][] transform = findTransform(root, meshIndex, identity());
            if (transform == null) throw new IllegalArgumentException("Mesh has no scene node: " + mesh.getName());
            if (exported++ > 0) output.append(',');
            output.append("{\"name\":");
            string(output, mesh.getName());
            output.append(",\"transform\":[");
            for (int r = 0; r < 4; r++) {
                if (r > 0) output.append(',');
                output.append('[');
                for (int c = 0; c < 4; c++) {
                    if (c > 0) output.append(',');
                    number(output, transform[r][c]);
                }
                output.append(']');
            }
            output.append("],\"vertices\":[");
            for (int i = 0; i < mesh.getNumVertices(); i++) {
                if (i > 0) output.append(',');
                output.append('[');
                number(output, mesh.getPositionX(i)); output.append(',');
                number(output, mesh.getPositionY(i)); output.append(',');
                number(output, mesh.getPositionZ(i)); output.append(',');
                number(output, mesh.getTexCoordU(i, 0)); output.append(',');
                number(output, 1.0f - mesh.getTexCoordV(i, 0));
                output.append(']');
            }
            output.append("],\"triangles\":[");
            for (int i = 0; i < mesh.getNumFaces(); i++) {
                if (mesh.getFaceNumIndices(i) != 3) throw new IllegalArgumentException("Non-triangle face after triangulation");
                if (i > 0) output.append(',');
                output.append('[').append(mesh.getFaceVertex(i, 2)).append(',')
                    .append(mesh.getFaceVertex(i, 1)).append(',')
                    .append(mesh.getFaceVertex(i, 0)).append(']');
            }
            output.append("]}");
        }
        if (exported == 0) throw new IllegalArgumentException("No matching meshes in " + args[0]);
        System.out.println(output.append("]}"));
    }
}
