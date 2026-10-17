package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import org.joml.Vector3fc;

/** Presentation transforms in conventional column-vector JOML storage, before native xfrm transpose. */
final class CartTransitionMath {
    private static final float ISO_HEIGHT = 2.44949f;
    private static final float EPS = .0001f;

    // Rotation names/order follow InventoryItem: camera Rx(worldX), Ry(worldZ), Rz(worldY).
    record Placement(float x, float y, float z, float xRotation, float zRotation,
                     float yRotation, float worldScale) {}
    record Progress(double crouch, double reach, double grip, double lift, double center, double balance, double hinge, double knees) {}
    record Stance(float x, float y, float z, float slotAngle) {}
    private record Rigid(Vector3f translation, Quaternionf rotation, float scale) {}

    static double smooth(double fraction) {
        if (!Double.isFinite(fraction)) return Double.NaN;
        double t = Math.max(0, Math.min(1, fraction));
        double u = Math.min(t, 1 - t);
        double value = u * u * u * (10 + u * (-15 + 6 * u));
        return t <= .5 ? value : 1 - value;
    }

    static Progress progress(double fraction, boolean setdown) {
        if (!Double.isFinite(fraction)) return null;
        double t = Math.max(0, Math.min(1, fraction));
        if (setdown) t = 1 - t;
        // Reach while bending; fingers close over the last few millimetres before lifting.
        double crouch=phase(t,0,.44), lift=phase(t,.48,1), stance=phase(t,0,.10), knees=phase(t,0,.20);
        return new Progress(crouch,phase(t,.24,.44),phase(t,.38,.48),lift,stance*(1-lift),
            knees*Math.sqrt(1-lift),crouch*(1-lift*lift),knees);
    }

    private static double phase(double t, double start, double end) {
        return t <= start ? 0 : t >= end ? 1 : smooth((t - start) / (end - start));
    }

    private static boolean finite(float... values) {
        for (float value : values) if (!Float.isFinite(value)) return false;
        return true;
    }

    private static boolean affine(Matrix4fc matrix) {
        return matrix != null && matrix.isFinite() && Math.abs(matrix.m03()) < EPS
            && Math.abs(matrix.m13()) < EPS && Math.abs(matrix.m23()) < EPS
            && Math.abs(matrix.m33() - 1) < EPS;
    }

    private static boolean invertible(Matrix4fc matrix) {
        return affine(matrix) && Float.isFinite(matrix.determinant()) && Math.abs(matrix.determinant()) > 1e-12f;
    }

    private static boolean valid(Placement pose) {
        return pose != null && finite(pose.x, pose.y, pose.z, pose.xRotation, pose.zRotation,
            pose.yRotation, pose.worldScale) && pose.worldScale > 0;
    }

    private static Matrix4f rotation(Placement pose) {
        return new Matrix4f().rotationXYZ((float)Math.toRadians(pose.xRotation),
            (float)Math.toRadians(pose.zRotation), (float)Math.toRadians(pose.yRotation));
    }

    /** model = inverse(world attachment) * transposed native mesh transform * model script scale. */
    static boolean worldToActor(Placement pose, Matrix4fc model, float actorX, float actorY,
                                float actorZ, float slotAngle, Matrix4f out) {
        if (out == null || !valid(pose) || !invertible(model) || !finite(actorX, actorY, actorZ, slotAngle)) return false;
        Matrix4f result = new Matrix4f().rotationY(-slotAngle - (float)Math.PI)
            .translate((pose.x - actorX) / 1.5f, ISO_HEIGHT * (pose.z - actorZ) / 1.5f,
                -(pose.y - actorY) / 1.5f)
            .mul(rotation(pose)).mul(model).scale(pose.worldScale);
        if (!result.isFinite()) return false;
        out.set(result);
        return true;
    }

    private static Rigid rigid(Matrix4fc matrix) {
        if (!affine(matrix)) return null;
        Vector3f x = matrix.getColumn(0, new Vector3f()), y = matrix.getColumn(1, new Vector3f()),
            z = matrix.getColumn(2, new Vector3f());
        float sx = x.length(), sy = y.length(), sz = z.length();
        if (!finite(sx, sy, sz) || sx <= 1e-8f || Math.abs(sx - sy) > EPS * sx
            || Math.abs(sx - sz) > EPS * sx) return null;
        x.div(sx); y.div(sy); z.div(sz);
        if (Math.abs(x.dot(y)) > EPS || Math.abs(x.dot(z)) > EPS || Math.abs(y.dot(z)) > EPS
            || x.cross(y, new Vector3f()).dot(z) < 1 - EPS) return null;
        Quaternionf quaternion = new Matrix4f(matrix).scale(1 / sx).getNormalizedRotation(new Quaternionf());
        if (!quaternion.isFinite()) return null;
        return new Rigid(matrix.getTranslation(new Vector3f()), quaternion.normalize(), sx);
    }

    /** Rejects shear, reflection and nonuniform residual scale instead of inventing a world pose. */
    static Placement actorToWorldPlacement(Matrix4fc transform, Matrix4fc model, float actorX,
                                           float actorY, float actorZ, float slotAngle) {
        if (!affine(transform) || !invertible(model) || !finite(actorX, actorY, actorZ, slotAngle)) return null;
        Matrix4f local = new Matrix4f().rotationY(slotAngle + (float)Math.PI)
            .mul(transform).mul(new Matrix4f(model).invert());
        Rigid parts = rigid(local);
        if (parts == null) return null;
        Matrix4f r = new Matrix4f().rotation(parts.rotation);
        Vector3f translation = new Vector3f(parts.translation).fma(parts.scale - 1,
            r.transformDirection(model.getTranslation(new Vector3f()), new Vector3f()));
        double cosBeta = Math.hypot(r.m00(), r.m10());
        double beta = Math.atan2(r.m20(), cosBeta);
        double alpha, gamma;
        if (cosBeta > .000001) {
            alpha = Math.atan2(-r.m21(), r.m22());
            gamma = Math.atan2(-r.m10(), r.m00());
        } else {
            alpha = Math.atan2(Math.signum(beta) * r.m01(), r.m11());
            gamma = 0;
        }
        Placement result = new Placement(actorX + translation.x * 1.5f,
            actorY - translation.z * 1.5f, actorZ + translation.y * 1.5f / ISO_HEIGHT,
            (float)Math.toDegrees(alpha), (float)Math.toDegrees(beta), (float)Math.toDegrees(gamma), parts.scale);
        Matrix4f check = rotation(result);
        if (!valid(result) || !check.equals(r, .0005f)) return null;
        return result;
    }

    static boolean blend(Matrix4fc from, Matrix4fc to, double fraction, Matrix4f out) {
        if (out == null || !Double.isFinite(fraction)) return false;
        Rigid a = rigid(from), b = rigid(to);
        if (a == null || b == null) return false;
        if (fraction <= 0) {out.set(from); return true;}
        if (fraction >= 1) {out.set(to); return true;}
        float t = (float)fraction;
        Matrix4f result = new Matrix4f().translationRotateScale(
            a.translation.lerp(b.translation, t, new Vector3f()),
            a.rotation.slerp(b.rotation, t, new Quaternionf()), a.scale + (b.scale - a.scale) * t);
        if (!result.isFinite()) return false;
        out.set(result);
        return true;
    }

    /** Match ordered handle spacing/direction horizontally; differing handle heights belong to the reach animation. */
    static Stance stance(Placement pose, Matrix4fc model, Matrix4fc held,
                         Vector3fc leftHandle, Vector3fc rightHandle) {
        if (!valid(pose) || !invertible(model) || rigid(held) == null || leftHandle == null
            || rightHandle == null || !leftHandle.isFinite() || !rightHandle.isFinite()) return null;
        Matrix4f ground = rotation(pose).mul(model).scale(pose.worldScale);
        Vector3f worldLeft = ground.transformPosition(leftHandle, new Vector3f());
        Vector3f worldRight = ground.transformPosition(rightHandle, new Vector3f());
        Vector3f heldLeft = held.transformPosition(leftHandle, new Vector3f());
        Vector3f heldRight = held.transformPosition(rightHandle, new Vector3f());
        float worldDx = 1.5f * (worldLeft.x - worldRight.x), worldDy = -1.5f * (worldLeft.z - worldRight.z);
        float heldDx = heldLeft.x - heldRight.x, heldDz = heldLeft.z - heldRight.z;
        if (Math.hypot(worldDx, worldDy) < 1e-8 || Math.hypot(heldDx, heldDz) < 1e-8) return null;
        float angle = (float)(Math.atan2(worldDy, worldDx) - Math.PI + Math.atan2(heldDz, heldDx));
        float c = (float)Math.cos(angle), s = (float)Math.sin(angle);
        float hx = (heldLeft.x + heldRight.x) * .5f, hz = (heldLeft.z + heldRight.z) * .5f;
        float x = pose.x + 1.5f * (worldLeft.x + worldRight.x) * .5f + 1.5f * (c * hx + s * hz);
        float y = pose.y - 1.5f * (worldLeft.z + worldRight.z) * .5f + 1.5f * (s * hx - c * hz);
        return finite(x, y, angle) ? new Stance(x, y, pose.z, angle) : null;
    }

    private CartTransitionMath() {}
}
