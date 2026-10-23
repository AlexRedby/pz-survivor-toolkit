package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException
import java.util.Arrays
import java.util.HexFormat
import java.util.WeakHashMap
import org.joml.Matrix4f
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData

/** Same-render-slot source cage fit. Native feet, root motion and network state stay native. */
internal object CartLegClearance {
    private const val MARGIN = 0.001
    private const val EPS = 1e-6

    @JvmRecord
    private data class Asset(val revision: Int, val path: String?, val profile: Int) {
        override fun toString(): String = "Asset[revision=$revision, path=$path, profile=$profile]"
    }

    private val assets = WeakHashMap<ModelMesh, Asset>()

    private class Scratch {
        @JvmField val pose = Matrix4f()
        @JvmField val inverse = Matrix4f()
        @JvmField val nativeMatrix = org.lwjgl.util.vector.Matrix4f()
        @JvmField val triangle = DoubleArray(9)
        @JvmField val range = DoubleArray(2)
        @JvmField var points = DoubleArray(0)
        @JvmField var low = DoubleArray(256)
        @JvmField var high = DoubleArray(256)
        @JvmField var primitives: Array<DoubleArray?>? = null
        @JvmField var count = 0

        fun add(a: Double, b: Double) {
            if (count == low.size) {
                low = low.copyOf(count * 2)
                high = high.copyOf(count * 2)
            }
            low[count] = a
            high[count++] = b
        }
    }

    private val scratch = ThreadLocal.withInitial { Scratch() }

    /**
     * Validate the exact calibrated source once per native mesh revision. Never parse meshes in a
     * frame.
     */
    @JvmStatic
    @Synchronized
    private fun profile(mesh: ModelMesh?): Int {
        if (mesh == null || mesh.fullPath == null) return -1
        val old = assets[mesh]
        if (
            old != null &&
                old.revision == mesh.modificationCount &&
                (old.path ?: throw NullPointerException()).equals(mesh.fullPath)
        )
            return old.profile
        var selected = -1
        try {
            val path = mesh.fullPath.replace('\\', '/')
            for (i in 0..CartLegClearanceData.SKINS.size) {
                val cart = i == CartLegClearanceData.SKINS.size
                val suffix =
                    if (cart) CartLegClearanceData.WOOD.suffix
                    else CartLegClearanceData.SKINS[i].suffix
                if (!path.endsWith(suffix ?: throw NullPointerException())) continue
                val bytes =
                    if (cart) CartLegClearanceData.WOOD.bytes
                    else CartLegClearanceData.SKINS[i].bytes
                val hash =
                    if (cart) CartLegClearanceData.WOOD.sha256
                    else CartLegClearanceData.SKINS[i].sha256
                val source = Path.of(mesh.fullPath)
                if (bytes <= 0 || bytes > 16 * 1024 * 1024 || Files.size(source) != bytes) break
                val digest = MessageDigest.getInstance("SHA-256")
                Files.newInputStream(source).use { input ->
                    val buffer = ByteArray(16384)
                    var read = 0L
                    while (true) {
                        val n = input.read(buffer)
                        if (n == -1) break
                        read += n
                        if (read > bytes) break
                        digest.update(buffer, 0, n)
                    }
                    if (read == bytes && HexFormat.of().formatHex(digest.digest()).equals(hash))
                        selected = i
                }
                break
            }
        } catch (unavailable: IOException) {
            // Unsupported/reloaded assets keep their existing presentation.
        } catch (unavailable: NoSuchAlgorithmException) {
            // Unsupported/reloaded assets keep their existing presentation.
        } catch (unavailable: RuntimeException) {
            // Unsupported/reloaded assets keep their existing presentation.
        }
        assets[mesh] = Asset(mesh.modificationCount, mesh.fullPath, selected)
        return selected
    }

    @JvmStatic
    private fun skin(
        data: ModelInstanceRenderData?,
        source: CartLegClearanceData.Skin?,
        s: Scratch?,
        actor: SkinningData?,
        poses: Array<Matrix4f?>?,
    ): Boolean {
        val render = data ?: throw NullPointerException()
        val target = render.modelInstance.model.tag as? SkinningData ?: return false
        if (render.matrixPalette == null) return false
        val profile = source ?: throw NullPointerException()
        val required = profile.vertexCount * 3
        val work = s ?: throw NullPointerException()
        if (work.points.size < required) work.points = DoubleArray(required)
        Arrays.fill(work.points, 0, required, 0.0)
        val palette = render.matrixPalette
        val before = palette.position()
        try {
            val names = profile.bones ?: throw NullPointerException()
            for (bone in names.indices) {
                val index = target.boneIndices[names[bone]]
                if (
                    index == null ||
                        index < 0 ||
                        (index + 1).toLong() * 16 > palette.limit() ||
                        index >= target.boneOffset.size ||
                        target.boneOffset[index] == null
                )
                    return false
                palette.position(index * 16)
                work.nativeMatrix.load(palette)
                PZMath.convertMatrix(work.nativeMatrix, work.pose).transpose()
                PZMath.convertMatrix(target.boneOffset[index], work.inverse).transpose()
                if (
                    !work.pose.isFinite ||
                        !work.inverse.isFinite ||
                        Math.abs(work.inverse.determinant()) < 1e-12f
                )
                    return false
                work.pose.mul(work.inverse.invert())
                if (!validPose(work.pose)) return false
                val pending = (actor ?: throw NullPointerException()).getBone(names[bone])
                if (pending != null && CartGrip.upperBody(pending)) {
                    if (
                        pending.index < 0 ||
                            pending.index >= (poses ?: throw NullPointerException()).size ||
                            poses[pending.index] == null
                    )
                        return false
                    work.pose.set(poses[pending.index])
                    if (!validPose(work.pose)) return false
                }
                accumulate(profile, bone, work.pose, work.points)
            }
            for (i in 0 until required) if (!java.lang.Double.isFinite(work.points[i])) return false
            return true
        } finally {
            palette.position(before)
        }
    }

    @JvmStatic
    private fun validPose(pose: Matrix4f?): Boolean {
        val matrix = pose ?: throw NullPointerException()
        val determinant = matrix.determinant()
        return matrix.isFinite &&
            java.lang.Float.isFinite(determinant) &&
            Math.abs(determinant) > 1e-12f
    }

    @JvmStatic
    fun accumulate(
        source: CartLegClearanceData.Skin?,
        bone: Int,
        pose: Matrix4f?,
        points: DoubleArray?,
    ) {
        val profile = source ?: throw NullPointerException()
        val influences = profile.influenceBone ?: throw NullPointerException()
        for (j in influences.indices) if (influences[j] == bone) {
            val point = (profile.influenceVertex ?: throw NullPointerException())[j] * 3
            val k = j * 4
            val weighted = profile.weightedPoints ?: throw NullPointerException()
            val x = weighted[k].toDouble()
            val y = weighted[k + 1].toDouble()
            val z = weighted[k + 2].toDouble()
            val w = weighted[k + 3].toDouble()
            val vertices = points ?: throw NullPointerException()
            vertices[point] +=
                (pose ?: throw NullPointerException()).m00() * x +
                    pose.m10() * y +
                    pose.m20() * z +
                    pose.m30() * w
            vertices[point + 1] += pose.m01() * x + pose.m11() * y + pose.m21() * z + pose.m31() * w
            vertices[point + 2] += pose.m02() * x + pose.m12() * y + pose.m22() * z + pose.m32() * w
        }
    }

    @JvmStatic
    fun shift(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        cart: ModelMesh?,
        transform: Matrix4f?,
        pressure: Float,
        actor: SkinningData?,
        poses: Array<Matrix4f?>?,
    ): Double {
        if (
            owner == null ||
                owner.animPlayer == null ||
                actor == null ||
                poses == null ||
                !(transform ?: throw NullPointerException()).isFinite ||
                !java.lang.Float.isFinite(pressure) ||
                profile(cart) != CartLegClearanceData.SKINS.size
        )
            return Double.NaN
        val work = scratch.get()
        work.count = 0
        val raw = CartLegClearanceData.WOOD.primitives ?: throw NullPointerException()
        if (work.primitives == null) {
            work.primitives = arrayOfNulls(raw.size)
            for (i in raw.indices) (work.primitives ?: throw NullPointerException())[i] =
                DoubleArray((raw[i] ?: throw NullPointerException()).size)
        }
        for (i in raw.indices) {
            val row = raw[i] ?: throw NullPointerException()
            for (j in row.indices step 3) {
                val x = row[j].toDouble()
                val y = row[j + 1].toDouble()
                val z = row[j + 2].toDouble()
                val p =
                    (work.primitives ?: throw NullPointerException())[i]
                        ?: throw NullPointerException()
                p[j] =
                    transform.m00() * x +
                        transform.m10() * y +
                        transform.m20() * z +
                        transform.m30()
                p[j + 1] =
                    transform.m01() * x +
                        transform.m11() * y +
                        transform.m21() * z +
                        transform.m31()
                p[j + 2] =
                    transform.m02() * x +
                        transform.m12() * y +
                        transform.m22() * z +
                        transform.m32()
            }
        }
        var bodies = 0
        for (data in (slot ?: throw NullPointerException()).modelData) if (
            data.modelInstance === owner
        )
            bodies++
        if (bodies != 1) return Double.NaN
        var body = false
        for (data in slot.modelData) {
            val instance = data.modelInstance
            if (
                instance == null ||
                    instance.animPlayer !== owner.animPlayer ||
                    instance.model == null ||
                    instance.model.isStatic ||
                    data.matrixPalette == null
            )
                continue
            val id = profile(instance.model.mesh)
            if (id < 0 || id >= CartLegClearanceData.SKINS.size || instance === owner && id > 1) {
                if (instance === owner) return Double.NaN
                continue
            }
            val source = CartLegClearanceData.SKINS[id]
            if (!skin(data, source, work, actor, poses)) return Double.NaN
            if (instance === owner) body = true
            val faces = source.triangles ?: throw NullPointerException()
            for (i in faces.indices step 3) {
                for (v in 0 until 3) System.arraycopy(
                    work.points,
                    faces[i + v] * 3,
                    work.triangle,
                    v * 3,
                    3,
                )
                for (primitive in work.primitives ?: throw NullPointerException()) if (
                    intervalWithinDomain(
                        work.triangle,
                        primitive,
                        MARGIN,
                        -0.030,
                        0.030,
                        work.range,
                    )
                )
                    work.add(work.range[0], work.range[1])
            }
        }
        if (!body) return Double.NaN
        val bank = CartSteeringMath.woodenTurnAmount(pressure)
        return choose(work.low, work.high, work.count, -0.030 + 0.022 * bank, 0.030 - 0.012 * bank)
    }

    /**
     * Conservative nonzero-fit gate; unsupported fast/edge poses retain their existing placement.
     */
    @JvmStatic
    fun withinFootprint(transform: Matrix4f?): Boolean {
        val points = CartLegClearanceData.WOOD.footprintPoints ?: throw NullPointerException()
        for (i in points.indices step 3) {
            val x = points[i].toDouble()
            val y = points[i + 1].toDouble()
            val z = points[i + 2].toDouble()
            val matrix = transform ?: throw NullPointerException()
            val lateral =
                -1.5 * (matrix.m00() * x + matrix.m10() * y + matrix.m20() * z + matrix.m30())
            val forward =
                -1.5 * (matrix.m02() * x + matrix.m12() * y + matrix.m22() * z + matrix.m32())
            if (!CartFootprint.contains(forward, lateral, CartFootprint.WALK_FRONT, 0.001))
                return false
        }
        return true
    }

    /**
     * Skip cross-leg/shaft pairs that cannot touch anywhere inside the bounded lateral corridor.
     */
    @JvmStatic
    fun intervalWithinDomain(
        triangle: DoubleArray?,
        primitive: DoubleArray?,
        margin: Double,
        min: Double,
        max: Double,
        out: DoubleArray?,
    ): Boolean {
        val t = triangle ?: throw NullPointerException()
        val ta = Math.min(t[0], Math.min(t[3], t[6]))
        val tb = Math.max(t[0], Math.max(t[3], t[6]))
        var pa = Double.POSITIVE_INFINITY
        var pb = Double.NEGATIVE_INFINITY
        val p = primitive ?: throw NullPointerException()
        for (i in p.indices step 3) {
            pa = Math.min(pa, p[i])
            pb = Math.max(pb, p[i])
        }
        if (tb - min + margin + 2 * EPS < pa || ta - max - margin - 2 * EPS > pb) return false
        return interval(t, p, margin, out)
    }

    /** Continuous triangle/convex primitive SAT: cart +X is body -X. Includes coplanar braces. */
    @JvmStatic
    fun interval(
        triangle: DoubleArray?,
        primitive: DoubleArray?,
        margin: Double,
        out: DoubleArray?,
    ): Boolean {
        if (
            triangle == null ||
                primitive == null ||
                out == null ||
                out.size < 2 ||
                triangle.size != 9 ||
                primitive.size != 9 && primitive.size != 12 ||
                !java.lang.Double.isFinite(margin) ||
                margin < 0
        )
            return false
        for (v in triangle) if (!java.lang.Double.isFinite(v)) return false
        for (v in primitive) if (!java.lang.Double.isFinite(v)) return false
        for (axis in 1 until 3) {
            var ta = Double.POSITIVE_INFINITY
            var tb = -ta
            var pa = ta
            var pb = -ta
            for (i in axis until 9 step 3) {
                ta = Math.min(ta, triangle[i])
                tb = Math.max(tb, triangle[i])
            }
            for (i in axis until primitive.size step 3) {
                pa = Math.min(pa, primitive[i])
                pb = Math.max(pb, primitive[i])
            }
            if (tb + margin < pa || pb + margin < ta) return false
        }
        val px = primitive[3] - primitive[0]
        val py = primitive[4] - primitive[1]
        val pz = primitive[5] - primitive[2]
        val qx = primitive[6] - primitive[0]
        val qy = primitive[7] - primitive[1]
        val qz = primitive[8] - primitive[2]
        val crossX = py * qz - pz * qy
        val crossY = pz * qx - px * qz
        val crossZ = px * qy - py * qx
        if (primitive.size == 9) {
            if (crossX * crossX + crossY * crossY + crossZ * crossZ < 1e-24) return false
        } else if (
            Math.abs(
                crossX * (primitive[9] - primitive[0]) +
                    crossY * (primitive[10] - primitive[1]) +
                    crossZ * (primitive[11] - primitive[2]),
            ) < 1e-24
        )
            return false
        out[0] = Double.NEGATIVE_INFINITY
        out[1] = Double.POSITIVE_INFINITY
        // Face normals, then cross products of every pair of edges. For triangles, also in-plane
        // edge normals.
        val tx = triangle[3] - triangle[0]
        val ty = triangle[4] - triangle[1]
        val tz = triangle[5] - triangle[2]
        val ux = triangle[6] - triangle[0]
        val uy = triangle[7] - triangle[1]
        val uz = triangle[8] - triangle[2]
        val nx = ty * uz - tz * uy
        val ny = tz * ux - tx * uz
        val nz = tx * uy - ty * ux
        if (
            nx * nx + ny * ny + nz * nz < 1e-24 ||
                !axis(triangle, primitive, margin, nx, ny, nz, out)
        )
            return false
        for (a in 0 until primitive.size / 3 - 2) for (b in
            a + 1 until primitive.size / 3 - 1) for (c in b + 1 until primitive.size / 3) {
            val ia = a * 3
            val ib = b * 3
            val ic = c * 3
            val ax = primitive[ib] - primitive[ia]
            val ay = primitive[ib + 1] - primitive[ia + 1]
            val az = primitive[ib + 2] - primitive[ia + 2]
            val bx = primitive[ic] - primitive[ia]
            val by = primitive[ic + 1] - primitive[ia + 1]
            val bz = primitive[ic + 2] - primitive[ia + 2]
            val fx = ay * bz - az * by
            val fy = az * bx - ax * bz
            val fz = ax * by - ay * bx
            if (!axis(triangle, primitive, margin, fx, fy, fz, out)) return false
            if (primitive.size == 9)
                for (edge in 0 until 3) {
                    val j = edge * 3
                    val k = (edge + 1) % 3 * 3
                    val ex = primitive[k] - primitive[j]
                    val ey = primitive[k + 1] - primitive[j + 1]
                    val ez = primitive[k + 2] - primitive[j + 2]
                    if (
                        !axis(
                            triangle,
                            primitive,
                            margin,
                            fy * ez - fz * ey,
                            fz * ex - fx * ez,
                            fx * ey - fy * ex,
                            out,
                        )
                    )
                        return false
                }
        }
        for (edge in 0 until 3) {
            val j = edge * 3
            val k = (edge + 1) % 3 * 3
            val ax = triangle[k] - triangle[j]
            val ay = triangle[k + 1] - triangle[j + 1]
            val az = triangle[k + 2] - triangle[j + 2]
            if (
                primitive.size == 9 &&
                    !axis(
                        triangle,
                        primitive,
                        margin,
                        ny * az - nz * ay,
                        nz * ax - nx * az,
                        nx * ay - ny * ax,
                        out,
                    )
            )
                return false
            for (a in 0 until primitive.size / 3) for (b in a + 1 until primitive.size / 3) {
                val ia = a * 3
                val ib = b * 3
                val bx = primitive[ib] - primitive[ia]
                val by = primitive[ib + 1] - primitive[ia + 1]
                val bz = primitive[ib + 2] - primitive[ia + 2]
                if (
                    !axis(
                        triangle,
                        primitive,
                        margin,
                        ay * bz - az * by,
                        az * bx - ax * bz,
                        ax * by - ay * bx,
                        out,
                    )
                )
                    return false
            }
        }
        return out[0] <= out[1]
    }

    @JvmStatic
    private fun axis(
        t: DoubleArray,
        p: DoubleArray,
        margin: Double,
        x: Double,
        y: Double,
        z: Double,
        out: DoubleArray,
    ): Boolean {
        val length = Math.sqrt(x * x + y * y + z * z)
        if (length < 1e-12) return true
        val nx = x / length
        val ny = y / length
        val nz = z / length
        var ta = Double.POSITIVE_INFINITY
        var tb = -ta
        var pa = ta
        var pb = -ta
        for (i in t.indices step 3) {
            val v = t[i] * nx + t[i + 1] * ny + t[i + 2] * nz
            ta = Math.min(ta, v)
            tb = Math.max(tb, v)
        }
        for (i in p.indices step 3) {
            val v = p[i] * nx + p[i + 1] * ny + p[i + 2] * nz
            pa = Math.min(pa, v)
            pb = Math.max(pb, v)
        }
        val low = pa - tb - margin
        val high = pb - ta + margin
        if (Math.abs(nx) < 1e-12) return low <= 1e-10 && high >= -1e-10
        val a = low / -nx
        val b = high / -nx
        out[0] = Math.max(out[0], Math.min(a, b))
        out[1] = Math.min(out[1], Math.max(a, b))
        return out[0] <= out[1] + 1e-10
    }

    /**
     * Only the connected forbidden component containing zero matters. No sorting/allocation per
     * frame.
     */
    @JvmStatic
    fun choose(
        low: DoubleArray?,
        high: DoubleArray?,
        count: Int,
        min: Double,
        max: Double,
    ): Double {
        if (
            low == null ||
                high == null ||
                !java.lang.Double.isFinite(min) ||
                !java.lang.Double.isFinite(max) ||
                min > 0 ||
                max < 0 ||
                min > max ||
                count < 0 ||
                count > low.size ||
                count > high.size
        )
            return Double.NaN
        var a = 0.0
        var b = 0.0
        var collision = false
        for (i in 0 until count) {
            if (low[i].isNaN() || high[i].isNaN() || low[i] > high[i]) return Double.NaN
            if (low[i] <= 0 && high[i] >= 0) {
                collision = true
                a = Math.min(a, low[i])
                b = Math.max(b, high[i])
            }
        }
        if (!collision) return 0.0
        var changed: Boolean
        do {
            changed = false
            for (i in 0 until count) {
                if (low[i].isNaN() || high[i].isNaN() || low[i] > high[i]) return Double.NaN
                if (low[i] <= b + 2 * EPS && high[i] >= a - 2 * EPS) {
                    collision = true
                    val nextA = Math.min(a, low[i])
                    val nextB = Math.max(b, high[i])
                    if (nextA < a || nextB > b) {
                        a = nextA
                        b = nextB
                        changed = true
                    }
                }
            }
        } while (changed)
        if (!collision) return 0.0
        a -= EPS
        b += EPS
        if (a < min) return if (b <= max) b else Double.NaN
        if (b > max) return a
        return if (Math.abs(a) < Math.abs(b)) a else b
    }
}
