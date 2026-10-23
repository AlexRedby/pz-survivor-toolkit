package net.alexredby.pztoolkitjavapatches

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.HexFormat
import java.util.TreeSet
import java.util.WeakHashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import org.lwjgl.BufferUtils
import org.lwjgl.opengl.GL11
import org.lwjgl.opengl.GL15
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.model.*
import zombie.core.skinnedmodel.shader.Shader
import zombie.core.skinnedmodel.shader.ShaderManager
import zombie.inventory.InventoryItem

/**
 * Cosmetic four-wheel motion follows the exact rendered cart, without changing shared GPU geometry.
 */
object CartShoppingWheels {
    class Frame(
        @JvmField val item: InventoryItem?,
        @JvmField val relative: Array<out Matrix4f?>?,
        @JvmField val phases: DoubleArray?,
        @JvmField val casters: DoubleArray?,
    )

    private class State {
        val phase = DoubleArray(4)
        val x = DoubleArray(4)
        val y = DoubleArray(4)
        val heading = DoubleArray(4)
        val pivotX = DoubleArray(2)
        val pivotY = DoubleArray(2)
        val caster = DoubleArray(2)
        var x0 = 0.0
        var y0 = 0.0
        var time = 0L
    }

    private class Mesh(val runs: Array<IntArray>?)

    private data class Point(val x: Int, val y: Int, val z: Int) : Comparable<Point> {
        constructor(
            x: Float,
            y: Float,
            z: Float,
        ) : this(
            java.lang.Float.floatToIntBits(x),
            java.lang.Float.floatToIntBits(y),
            java.lang.Float.floatToIntBits(z),
        )

        override fun compareTo(other: Point): Int {
            var c = Integer.compareUnsigned(x, other.x)
            if (c == 0) c = Integer.compareUnsigned(y, other.y)
            return if (c == 0) Integer.compareUnsigned(z, other.z) else c
        }
    }

    private data class Part(val part: Int, val vertex: Int)

    private val states = WeakHashMap<InventoryItem, State>()
    private val frames = WeakHashMap<ModelInstanceRenderData?, Frame>()
    private val meshes = WeakHashMap<VertexBufferObject, Mesh>()
    private val BASIS = CartShopping.worldModel(Matrix4f())!!
    private val NORMAL = normalization()
    private var errorLogged = false

    private fun normalization(): Matrix4f {
        val b = Matrix4f(BASIS).setTranslation(0f, 0f, 0f)
        val w =
            Matrix4f()
                .m00(CartShoppingWheelMesh.NORMALIZE[0])
                .m10(CartShoppingWheelMesh.NORMALIZE[1])
                .m01(CartShoppingWheelMesh.NORMALIZE[2])
                .m11(CartShoppingWheelMesh.NORMALIZE[3])
        return Matrix4f(b).invert().mul(w).mul(b)
    }

    private fun point(v: FloatArray): Vector3f = Vector3f(v[0], v[1], v[2])

    private fun around(c: Vector3f, linear: Matrix4f): Matrix4f =
        Matrix4f().translation(c).mul(linear).translate(-c.x, -c.y, -c.z)

    private fun world(x: Float, y: Float, angle: Float, p: Vector3f): DoubleArray {
        val c = Math.cos(angle.toDouble())
        val s = Math.sin(angle.toDouble())
        return doubleArrayOf(x - 1.5 * (c * p.x + s * p.z), y + 1.5 * (-s * p.x + c * p.z))
    }

    private fun wrap(v: Double): Double = Math.IEEEremainder(v, Math.PI * 2)

    @JvmStatic
    @Synchronized
    fun follow(
        item: InventoryItem?,
        x: Float,
        y: Float,
        angle: Float,
        cart: Matrix4f?,
        now: Long,
    ): Frame? {
        if (
            !CartShopping.item(item) ||
                !java.lang.Float.isFinite(x + y + angle) ||
                cart == null ||
                !cart.isFinite ||
                now < 0
        )
            return null
        val residual = Matrix4f(cart).mul(Matrix4f(BASIS).invert())
        if (!CartTransitionMath.blend(residual, residual, 0.0, Matrix4f())) return null
        val radius = CartShoppingWheelMesh.RADIUS * residual.getColumn(0, Vector3f()).length() * 1.5
        if (!java.lang.Double.isFinite(radius) || radius < 1e-6) return null
        val axle = cart.transformDirection(Vector3f(0f, 0f, 1f)).normalize()
        val forward = Vector3f(0f, 1f, 0f).cross(axle).normalize()
        if (!axle.isFinite || !forward.isFinite) return null
        val direction = world(0f, 0f, angle, forward)
        val heading = Math.atan2(direction[1], direction[0])
        val old = states[item]
        val reset = old == null || Math.hypot(x - old.x0, y - old.y0) > 1
        val next = State()
        next.x0 = x.toDouble()
        next.y0 = y.toDouble()
        next.time = now
        val dt = if (old == null) 0.0 else Math.max(0.0, Math.min(.1, (now - old.time) / 1e9))
        val transforms = arrayOfNulls<Matrix4f>(7)
        transforms[0] = Matrix4f()
        val inverse = Matrix4f(cart).invert()
        for (i in 0 until 4) {
            val raw = point(CartShoppingWheelMesh.CENTERS[i])
            var center = cart.transformPosition(raw, Vector3f())
            var swivel = Matrix4f()
            var rollingHeading = heading
            if (i >= 2) {
                val front = i - 2
                val pivot =
                    cart.transformPosition(point(CartShoppingWheelMesh.SWIVELS[front]), Vector3f())
                val p = world(x, y, angle, pivot)
                next.pivotX[front] = p[0]
                next.pivotY[front] = p[1]
                rollingHeading =
                    if (reset) heading + (old?.caster?.get(front) ?: 0.0) else old.heading[i]
                if (!reset) {
                    val dx = p[0] - old.pivotX[front]
                    val dy = p[1] - old.pivotY[front]
                    val distance = Math.hypot(dx, dy)
                    if (distance > 1e-7 && distance <= 1) {
                        val change =
                            wrap(Math.atan2(dy, dx) - rollingHeading) *
                                (1 - Math.exp(-distance / .035))
                        rollingHeading += Math.max(-10 * dt, Math.min(10 * dt, change))
                    }
                }
                next.caster[front] = wrap(rollingHeading - heading)
                swivel = around(pivot, Matrix4f().rotationY(next.caster[front].toFloat()))
            }
            center = swivel.transformPosition(center)
            val p = world(x, y, angle, center)
            next.x[i] = p[0]
            next.y[i] = p[1]
            next.heading[i] = rollingHeading
            var phase = old?.phase?.get(i) ?: 0.0
            if (!reset) {
                val dx = p[0] - old.x[i]
                val dy = p[1] - old.y[i]
                val fx = Math.cos(old.heading[i]) + Math.cos(rollingHeading)
                val fy = Math.sin(old.heading[i]) + Math.sin(rollingHeading)
                val length = Math.hypot(fx, fy)
                if (Math.hypot(dx, dy) <= 1 && length > 1e-6)
                    phase = wrap(phase - (dx * fx + dy * fy) / length / radius)
            }
            next.phase[i] = phase
            // Round the imported ellipse once, then rotate a rigid tire around its own axle.
            val baseCenter = cart.transformPosition(raw, Vector3f())
            val roll = around(baseCenter, Matrix4f().rotation(phase.toFloat(), axle))
            val shape = around(raw, NORMAL)
            val tire = Matrix4f(swivel).mul(roll).mul(cart).mul(shape)
            transforms[i + 1] = Matrix4f(inverse).mul(tire)
            if (i >= 2) transforms[i + 3] = Matrix4f(inverse).mul(swivel).mul(cart)
        }
        states[item!!] = next
        return Frame(item, transforms, next.phase.clone(), next.caster.clone())
    }

    @JvmStatic
    fun follow(item: InventoryItem?, x: Float, y: Float, angle: Float, cart: Matrix4f?): Frame? =
        follow(item, x, y, angle, cart, System.nanoTime())

    @JvmStatic
    @Synchronized
    fun clear(slot: ModelSlotRenderData) {
        for (data in slot.modelData) frames.remove(data)
    }

    @JvmStatic
    @Synchronized
    fun prepare(
        slot: ModelSlotRenderData?,
        item: InventoryItem?,
        data: ModelInstanceRenderData?,
        cart: Matrix4f?,
    ) {
        frames.remove(data)
        val frame = follow(item, slot!!.x, slot.y, slot.animPlayerAngle, cart)
        if (frame != null) frames[data] = frame
    }

    @JvmStatic @Synchronized fun frame(data: ModelInstanceRenderData?): Frame? = frames[data]

    @JvmStatic
    fun transform(
        cart: Matrix4f?,
        frame: Frame?,
        part: Int,
        transpose: Boolean,
        out: Matrix4f?,
    ): Matrix4f =
        if (transpose)
            (out ?: throw NullPointerException())
                .set(cart)
                .transpose()
                .mul(frame!!.relative!![part])
                .transpose()
        else (out ?: throw NullPointerException()).set(cart).mul(frame!!.relative!![part])

    @JvmStatic
    fun pointHash(vertices: FloatArray?): String {
        try {
            val values = vertices ?: throw NullPointerException()
            val points = TreeSet<Point>()
            var i = 0
            while (i < values.size) {
                points.add(Point(values[i], values[i + 1], values[i + 2]))
                i += 3
            }
            val digest = MessageDigest.getInstance("SHA-256")
            val bytes = ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
            for (p in points) {
                bytes.clear()
                bytes.putInt(p.x).putInt(p.y).putInt(p.z)
                digest.update(bytes.array())
            }
            return HexFormat.of().formatHex(digest.digest())
        } catch (error: Exception) {
            throw IllegalStateException(error)
        }
    }

    private fun edge(a: Int, b: Int): Long =
        (Math.min(a, b).toLong() shl 32) or (Math.max(a, b).toLong() and 0xffffffffL)

    @JvmStatic
    fun topology(
        points: Array<out FloatArray?>?,
        polygons: Array<out IntArray?>?,
        triangles: List<IntArray?>?,
    ): Boolean {
        if (points == null || polygons == null || triangles == null) return false
        for (p in points) if (
            p == null || p.size != 3 || !java.lang.Float.isFinite(p[0] + p[1] + p[2])
        )
            return false
        for (p in polygons) {
            if (p == null || p.size < 3) return false
            for (v in p) if (v < 0 || v >= points.size) return false
        }
        val edges = Array(polygons.size) { HashMap<Long, Int>() }
        val counts = IntArray(polygons.size)
        for (triangle in triangles) {
            if (triangle == null || triangle.size != 3) return false
            for (v in triangle) if (v < 0 || v >= points.size) return false
            if (
                triangle[0] == triangle[1] ||
                    triangle[1] == triangle[2] ||
                    triangle[2] == triangle[0]
            )
                return false
            var face = -1
            for (i in polygons.indices) {
                var found = 0
                for (v in triangle) {
                    for (p in polygons[i]!!) if (v == p) {
                        found++
                        break
                    }
                }
                if (found == 3) {
                    if (face != -1) return false
                    face = i
                }
            }
            if (face < 0) return false
            val a = point(points[triangle[0]]!!)
            val b = point(points[triangle[1]]!!)
            val c = point(points[triangle[2]]!!)
            if (b.sub(a).cross(c.sub(a)).lengthSquared() < 1e-16f) return false
            counts[face]++
            for (i in 0 until 3) edges[face].merge(
                edge(triangle[i], triangle[(i + 1) % 3]),
                1,
                Integer::sum,
            )
        }
        for (i in polygons.indices) {
            val polygon = polygons[i]!!
            if (counts[i] != polygon.size - 2) return false
            val boundary = HashSet<Long>()
            for (j in polygon.indices) boundary.add(
                edge(polygon[j], polygon[(j + 1) % polygon.size]),
            )
            for ((key, value) in edges[i]) if (value != if (boundary.remove(key)) 1 else 2)
                return false
            if (!boundary.isEmpty()) return false
        }
        return true
    }

    @JvmStatic
    fun partition(vertices: FloatArray?, elements: IntArray?): Array<IntArray>? {
        if (
            vertices == null || vertices.size % 3 != 0 || elements == null || elements.size % 3 != 0
        )
            return null
        val hash = pointHash(vertices)
        var expected = -1
        for (i in CartShoppingWheelMesh.POSITION_HASHES.indices) if (
            CartShoppingWheelMesh.POSITION_HASHES[i].equals(hash)
        )
            expected = CartShoppingWheelMesh.TRIANGLES[i] * 3
        if (expected != elements.size) return null
        val parts = HashMap<Point, Part>()
        for (p in CartShoppingWheelMesh.PART_POINTS.indices) for (v in
            CartShoppingWheelMesh.PART_POINTS[p].indices) {
            val q = CartShoppingWheelMesh.PART_POINTS[p][v]
            if (parts.put(Point(q[0], q[1], q[2]), Part(p + 1, v)) != null) return null
        }
        val ids = arrayOfNulls<Part>(vertices.size / 3)
        for (v in ids.indices) {
            for (j in 0 until 3) if (!java.lang.Float.isFinite(vertices[v * 3 + j])) return null
            ids[v] =
                parts.getOrDefault(
                    Point(vertices[v * 3], vertices[v * 3 + 1], vertices[v * 3 + 2]),
                    Part(0, -1),
                )
        }
        val triangles = ArrayList<MutableList<IntArray>>()
        repeat(6) { triangles.add(ArrayList()) }
        val runs = ArrayList<IntArray>()
        var run: IntArray? = null
        var i = 0
        while (i < elements.size) {
            val t = arrayOfNulls<Part>(3)
            for (j in 0 until 3) {
                val v = elements[i + j]
                if (v < 0 || v >= ids.size) return null
                t[j] = ids[v]
            }
            val part = t[0]!!.part
            if (t[1]!!.part != part || t[2]!!.part != part) return null
            if (part > 0)
                triangles[part - 1].add(intArrayOf(t[0]!!.vertex, t[1]!!.vertex, t[2]!!.vertex))
            if (run == null || run[2] != part) {
                run = intArrayOf(i, 0, part)
                runs.add(run)
            }
            run[1] += 3
            i += 3
        }
        for (part in 0 until 6) if (
            !topology(
                CartShoppingWheelMesh.PART_POINTS[part],
                CartShoppingWheelMesh.PART_FACES[part],
                triangles[part],
            )
        )
            return null
        return runs.toTypedArray()
    }

    private fun field(buffer: VertexBufferObject, name: String): Any? {
        val f = VertexBufferObject::class.java.getDeclaredField(name)
        f.isAccessible = true
        return f.get(buffer)
    }

    private fun mesh(buffer: VertexBufferObject): Array<IntArray>? {
        val cached = meshes[buffer]
        if (cached != null) return cached.runs
        var runs: Array<IntArray>? = null
        var ready = false
        val binding = GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING)
        try {
            val h = field(buffer, "handle") as VertexBufferObject.Vbo?
            val format = field(buffer, "vertexFormat") as VertexBufferObject.VertexFormat
            val pos = format.indexOf(VertexBufferObject.VertexType.VertexArray)
            if (h == null || h.vboId <= 0 || h.eboId <= 0) return null
            ready = true
            if (format.getStride() != 32 || pos < 0 || format.getElement(pos).byteOffset != 0)
                return null
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, h.vboId)
            val size = GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER, GL15.GL_BUFFER_SIZE)
            if (size <= 0 || size % 32 != 0 || size > 2_000_000) return null
            val raw = BufferUtils.createByteBuffer(size)
            GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER, 0, raw)
            val vertices = FloatArray(size / 32 * 3)
            for (i in 0 until vertices.size / 3) for (j in 0 until 3) vertices[i * 3 + j] =
                raw.getFloat(i * 32 + j * 4)
            val elements = field(buffer, "elements") as IntArray?
            if (elements != null && elements.size == h.numElements)
                runs = partition(vertices, elements)
            if (runs != null)
                println(
                    "[PZToolkitJavaPatches] Shopping cart wheels verified: ${runs.size} original index ranges",
                )
        } catch (error: Exception) {
            if (!errorLogged) {
                errorLogged = true
                System.err.println("[PZToolkitJavaPatches] Shopping cart wheels disabled: $error")
            }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, binding)
            if (ready) meshes[buffer] = Mesh(runs)
        }
        return runs
    }

    @JvmStatic
    fun render(model: Model?, slot: ModelSlotRenderData?, data: ModelInstanceRenderData?): Boolean {
        if (
            slot!!.character !is IsoPlayer ||
                data!!.modelInstance == null ||
                data.modelInstance.modelScript == null ||
                !CartShopping.model(data.modelInstance.modelScript.getName()) ||
                data.modelInstance.parent == null ||
                !model!!.isStatic ||
                model.mesh == null ||
                model.mesh.vb == null
        )
            return false
        val frame = frame(data) ?: return false
        if (mesh(model.mesh.vb) == null) return false
        val shader = ShaderManager.instance.getOrCreateShader("basicEffect", true, false)
        if (shader == null || shader.getID() == 0) return false
        shader.Start()
        try {
            shader.startCharacter(slot, data)
            shader.setScale(slot.finalScale)
            return draw(model.mesh.vb, shader, data.xfrm, frame, true)
        } finally {
            shader.setScale(1f)
            shader.End()
        }
    }

    @JvmStatic
    fun draw(
        buffer: VertexBufferObject?,
        shader: Shader?,
        cart: Matrix4f?,
        frame: Frame?,
        transpose: Boolean,
    ): Boolean {
        if (buffer == null || shader == null || cart == null || !cart.isFinite || frame == null)
            return false
        val runs = mesh(buffer) ?: return false
        val array = GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING)
        val elements = GL11.glGetInteger(GL15.GL_ELEMENT_ARRAY_BUFFER_BINDING)
        val parts = Array(7) { transform(cart, frame, it, transpose, Matrix4f()) }
        try {
            val blend = buffer.BeginDraw(shader)
            try {
                for (run in runs) {
                    shader.setTransformMatrix(parts[run[2]], transpose)
                    GL11.glDrawElements(
                        GL11.GL_TRIANGLES,
                        run[1],
                        GL11.GL_UNSIGNED_INT,
                        run[0].toLong() * 4,
                    )
                }
            } finally {
                shader.setTransformMatrix(cart, transpose)
                buffer.FinishDraw(shader, blend)
            }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, array)
            GL15.glBindBuffer(GL15.GL_ELEMENT_ARRAY_BUFFER, elements)
        }
        return true
    }
}
