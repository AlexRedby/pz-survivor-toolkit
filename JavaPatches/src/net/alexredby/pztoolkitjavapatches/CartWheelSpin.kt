package net.alexredby.pztoolkitjavapatches

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.HexFormat
import java.util.WeakHashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import org.lwjgl.BufferUtils
import org.lwjgl.opengl.GL11
import org.lwjgl.opengl.GL15
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.VertexBufferObject
import zombie.core.skinnedmodel.shader.Shader
import zombie.core.skinnedmodel.shader.ShaderManager
import zombie.inventory.InventoryItem

/** Draw each calibrated wheel separately without changing its shared mesh. */
internal object CartWheelSpin {
    // shortcut: source vertex ordering is calibrated to this exact Workshop mesh; a changed mesh
    // falls back to native drawing.
    const val WHEEL_VERTICES = 1114
    const val VERTICES = 8116
    const val STRIDE = 32
    const val CENTER_X = -6.642862e-6f
    const val CENTER_Y = -.0041269097f
    const val CENTER_Z = -.0010569958f
    const val RADIUS = .001062454f
    const val WORLD_RADIUS = RADIUS * 76.5 * 1.5
    private val phases = WeakHashMap<ModelInstanceRenderData, Double>()

    @JvmRecord
    private data class Mesh(val profile: CartWheelbarrow?, val runs: Array<IntArray>?) {
        override fun equals(other: Any?): Boolean =
            this === other || other is Mesh && profile === other.profile && runs === other.runs

        override fun hashCode(): Int =
            31 * (profile?.hashCode() ?: 0) + System.identityHashCode(runs)

        override fun toString() = "Mesh[profile=$profile, runs=$runs]"
    }

    private val meshes = WeakHashMap<VertexBufferObject, Mesh>()

    @JvmRecord
    private data class Pose(
        val x: Double,
        val y: Double,
        val forwardX: Double,
        val forwardY: Double,
        val pitch: Double,
        val radius: Double,
    ) {
        override fun toString() =
            "Pose[x=$x, y=$y, forwardX=$forwardX, forwardY=$forwardY, pitch=$pitch, radius=$radius]"
    }

    @JvmRecord
    private data class Wheel(val profile: CartWheelbarrow?, val phase: Double, val pose: Pose?) {
        override fun toString() = "Wheel[profile=$profile, phase=$phase, pose=$pose]"
    }

    // Cosmetic continuity follows the exact item while it moves between world and hands.
    private val wheels = WeakHashMap<InventoryItem, Wheel>()
    private val wheelTransform = Matrix4f()
    private var errorLogged = false

    @JvmStatic
    fun advance(phase: Double, acceptedTravel: Double): Double =
        advance(CartWheelbarrow.WOOD, phase, acceptedTravel)

    @JvmStatic
    fun advance(profile: CartWheelbarrow?, phase: Double, acceptedTravel: Double): Double {
        if (profile == null || !acceptedTravel.isFinite() || Math.abs(acceptedTravel) > 1)
            return phase
        return Math.IEEEremainder(phase - acceptedTravel / profile.worldRadius(), Math.PI * 2)
    }

    @JvmStatic
    fun itemPhase(item: InventoryItem?): Double =
        synchronized(CartWheelSpin::class.java) {
            val wheel = wheels[item]
            if (wheel == null || wheel.profile !== CartWheelbarrow.forItem(item)) 0.0
            else wheel.phase
        }

    private fun pose(
        profile: CartWheelbarrow?,
        x: Float,
        y: Float,
        angle: Float,
        cart: Matrix4f?,
    ): Pose? {
        if (
            profile == null ||
                !x.isFinite() ||
                !y.isFinite() ||
                !angle.isFinite() ||
                cart == null ||
                !cart.isFinite()
        )
            return null
        val center = cart.transformPosition(profile.center(Vector3f()))
        val axle = cart.getColumn(0, Vector3f())
        if (axle.lengthSquared() < 1e-12f) return null
        axle.normalize()
        val up = Vector3f(0f, 1f, 0f).fma(-axle.y, axle)
        if (up.lengthSquared() < 1e-8f) return null
        up.normalize()
        val radial = cart.getColumn(1, Vector3f())
        val pitch =
            Math.atan2(radial.dot(Vector3f(axle).cross(up)).toDouble(), radial.dot(up).toDouble())
        val c = Math.cos(angle.toDouble())
        val s = Math.sin(angle.toDouble())
        val sideX = -(c * axle.x + s * axle.z)
        val sideY = -s * axle.x + c * axle.z
        val length = Math.hypot(sideX, sideY)
        if (length < 1e-6) return null
        return Pose(
            x - 1.5 * (c * center.x + s * center.z),
            y - 1.5 * s * center.x + 1.5 * c * center.z,
            -sideY / length,
            sideX / length,
            pitch,
            radial.length() * profile.radius() * 1.5,
        )
    }

    @JvmStatic
    fun follow(item: InventoryItem?, x: Float, y: Float, angle: Float, cart: Matrix4f?): Double =
        synchronized(CartWheelSpin::class.java) {
            val profile = CartWheelbarrow.forItem(item) ?: return@synchronized Double.NaN
            val pose = pose(profile, x, y, angle, cart) ?: return@synchronized Double.NaN
            var previous = wheels[item]
            if (previous != null && previous.profile !== profile) previous = null
            var phase = if (previous == null) 0.0 else previous.phase
            if (previous != null) {
                val before = previous.pose ?: throw NullPointerException()
                val fx = before.forwardX + pose.forwardX
                val fy = before.forwardY + pose.forwardY
                val length = Math.hypot(fx, fy)
                val dx = pose.x - before.x
                val dy = pose.y - before.y
                if (
                    length > 1e-6 &&
                        Math.hypot(dx, dy) <= 1 &&
                        pose.radius > 1e-6 &&
                        before.radius > 1e-6
                )
                    phase -= (dx * fx + dy * fy) / length / ((pose.radius + before.radius) * .5)
                // Rotation is relative to the cart; lifting its handles must leave a stationary
                // tire still.
                phase =
                    Math.IEEEremainder(
                        phase - Math.IEEEremainder(pose.pitch - before.pitch, Math.PI * 2),
                        Math.PI * 2,
                    )
            }
            wheels[item] = Wheel(profile, phase, pose)
            phase
        }

    @JvmStatic
    fun record(
        item: InventoryItem?,
        x: Float,
        y: Float,
        angle: Float,
        cart: Matrix4f?,
        phase: Double,
    ) =
        synchronized(CartWheelSpin::class.java) {
            val profile = CartWheelbarrow.forItem(item)
            val pose = pose(profile, x, y, angle, cart)
            if (profile != null && pose != null && phase.isFinite())
                wheels[item] = Wheel(profile, phase, pose)
        }

    /** Snapshot the simulation angle; NaN clears recycled render data before eligibility checks. */
    @JvmStatic
    fun prepare(slot: ModelSlotRenderData?, phase: Double) =
        synchronized(CartWheelSpin::class.java) {
            for (data in (slot ?: throw NullPointerException()).modelData) {
                phases.remove(data)
                if (
                    phase.isFinite() &&
                        data.modelInstance != null &&
                        data.modelInstance.modelScript != null &&
                        CartWheelbarrow.forModel(data.modelInstance.modelScript.getName()) != null
                )
                    phases[data] = phase
            }
        }

    @JvmStatic
    private fun phase(data: ModelInstanceRenderData?): Double? =
        synchronized(CartWheelSpin::class.java) { phases[data] }

    @JvmStatic
    fun transform(cart: Matrix4f?, phase: Double, out: Matrix4f?): Matrix4f =
        transform(CartWheelbarrow.WOOD, cart, phase, out)

    @JvmStatic
    fun transform(
        profile: CartWheelbarrow?,
        cart: Matrix4f?,
        phase: Double,
        out: Matrix4f?,
    ): Matrix4f {
        val result = (out ?: throw NullPointerException()).set(cart).transpose()
        val geometry = profile ?: throw NullPointerException()
        return result
            .translate(geometry.centerX(), geometry.centerY(), geometry.centerZ())
            .rotateX(phase.toFloat())
            .translate(-geometry.centerX(), -geometry.centerY(), -geometry.centerZ())
            .transpose()
    }

    /** Each run is [first index, index count, wheel flag]; every triangle belongs to one part. */
    @JvmStatic
    fun ranges(elements: IntArray?): Array<IntArray>? = ranges(CartWheelbarrow.WOOD, elements)

    @JvmStatic
    fun ranges(profile: CartWheelbarrow?, elements: IntArray?): Array<IntArray>? {
        if (profile == null || elements == null || elements.isEmpty() || elements.size % 3 != 0)
            return null
        val result = ArrayList<IntArray>()
        var run: IntArray? = null
        var wheel = false
        var body = false
        for (i in elements.indices step 3) {
            val part = if (profile.wheelVertex(elements[i])) 1 else 0
            for (j in 0 until 3) if (
                elements[i + j] < 0 ||
                    elements[i + j] >= profile.vertices() ||
                    (if (profile.wheelVertex(elements[i + j])) 1 else 0) != part
            )
                return null
            if (part == 1) wheel = true else body = true
            if (run == null || run[2] != part) {
                run = intArrayOf(i, 0, part)
                result.add(run)
            }
            run[1] += 3
        }
        return if (wheel && body) result.toTypedArray() else null
    }

    @Throws(ReflectiveOperationException::class)
    private fun field(buffer: VertexBufferObject?, name: String): Any? {
        val field = VertexBufferObject::class.java.getDeclaredField(name)
        field.isAccessible = true
        return field.get(buffer)
    }

    private fun mesh(profile: CartWheelbarrow?, buffer: VertexBufferObject): Array<IntArray>? {
        val cached = meshes[buffer]
        if (cached != null) return if (cached.profile === profile) cached.runs else null
        var runs: Array<IntArray>? = null
        var ready = false
        val binding = GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING)
        try {
            val handle = field(buffer, "handle") as VertexBufferObject.Vbo?
            val format = field(buffer, "vertexFormat") as VertexBufferObject.VertexFormat?
            val position =
                (format ?: throw NullPointerException()).indexOf(
                    VertexBufferObject.VertexType.VertexArray,
                )
            if (handle == null || handle.vboId <= 0 || handle.eboId <= 0) return null
            ready = true
            if (
                format.getStride() != STRIDE ||
                    position < 0 ||
                    format.getElement(position).byteOffset != 0
            )
                return null
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, handle.vboId)
            val bytes = GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER, GL15.GL_BUFFER_SIZE)
            val geometry = profile ?: throw NullPointerException()
            if (bytes != geometry.vertices() * STRIDE) return null
            val raw: ByteBuffer = BufferUtils.createByteBuffer(bytes)
            GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER, 0L, raw)
            val vertices = ByteArray(bytes)
            raw.get(vertices)
            if (
                !geometry
                    .meshHash()
                    .equals(
                        HexFormat.of()
                            .formatHex(MessageDigest.getInstance("SHA-256").digest(vertices)),
                    )
            )
                return null
            val elements = field(buffer, "elements") as IntArray?
            if (elements != null && elements.size == handle.numElements)
                runs = ranges(geometry, elements)
            if (runs != null)
                println(
                    "[PZToolkitJavaPatches] Wheelbarrow wheel mesh verified: ${geometry.model()} ${runs.size} original index ranges",
                )
        } catch (error: Exception) {
            ready = true
            if (!errorLogged) {
                errorLogged = true
                System.err.println("[PZToolkitJavaPatches] Wheelbarrow wheel disabled: $error")
            }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, binding)
            if (ready) meshes[buffer] = Mesh(profile, runs)
            if (ready && runs == null && !errorLogged) {
                errorLogged = true
                System.err.println(
                    "[PZToolkitJavaPatches] Wheelbarrow wheel disabled: source mesh does not match calibrated geometry",
                )
            }
        }
        return runs
    }

    /** OnEnter for Model.DrawSolid; true skips the original draw after rendering both parts. */
    @JvmStatic
    fun render(model: Model?, slot: ModelSlotRenderData?, data: ModelInstanceRenderData?): Boolean {
        if (CartShoppingWheels.render(model, slot, data)) return true
        val state = slot ?: throw NullPointerException()
        if (
            state.character !is IsoPlayer ||
                (data ?: throw NullPointerException()).modelInstance == null ||
                data.modelInstance.modelScript == null ||
                CartWheelbarrow.forModel(data.modelInstance.modelScript.getName()) == null ||
                data.modelInstance.parent == null ||
                !(model ?: throw NullPointerException()).isStatic ||
                model.mesh == null ||
                model.mesh.vb == null
        )
            return false
        val phase = phase(data) ?: return false
        val profile = CartWheelbarrow.forModel(data.modelInstance.modelScript.getName())
        val runs = mesh(profile, model.mesh.vb) ?: return false
        val shader = ShaderManager.instance.getOrCreateShader("basicEffect", true, false)
        if (shader == null || shader.getID() == 0) return false
        shader.Start()
        try {
            shader.startCharacter(state, data)
            shader.setScale(state.finalScale)
            return draw(profile, model.mesh.vb, shader, data.xfrm, phase, true)
        } finally {
            shader.setScale(1f)
            shader.End()
        }
    }

    /** Draw within the caller's native shader/material scope. */
    @JvmStatic
    fun draw(
        buffer: VertexBufferObject?,
        shader: Shader?,
        cart: Matrix4f?,
        phase: Double,
        transpose: Boolean,
    ): Boolean = draw(CartWheelbarrow.WOOD, buffer, shader, cart, phase, transpose)

    @JvmStatic
    fun draw(
        profile: CartWheelbarrow?,
        buffer: VertexBufferObject?,
        shader: Shader?,
        cart: Matrix4f?,
        phase: Double,
        transpose: Boolean,
    ): Boolean {
        if (
            profile == null ||
                buffer == null ||
                shader == null ||
                cart == null ||
                !cart.isFinite() ||
                !phase.isFinite()
        )
            return false
        val runs = mesh(profile, buffer) ?: return false
        val oldArray = GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING)
        val oldElements = GL11.glGetInteger(GL15.GL_ELEMENT_ARRAY_BUFFER_BINDING)
        if (transpose) transform(profile, cart, phase, wheelTransform)
        else
            wheelTransform
                .set(cart)
                .translate(profile.centerX(), profile.centerY(), profile.centerZ())
                .rotateX(phase.toFloat())
                .translate(-profile.centerX(), -profile.centerY(), -profile.centerZ())
        try {
            val blend = buffer.BeginDraw(shader)
            try {
                for (run in runs) {
                    shader.setTransformMatrix(if (run[2] == 1) wheelTransform else cart, transpose)
                    GL11.glDrawElements(
                        GL11.GL_TRIANGLES,
                        run[1],
                        GL11.GL_UNSIGNED_INT,
                        run[0].toLong() * Int.SIZE_BYTES,
                    )
                }
            } finally {
                shader.setTransformMatrix(cart, transpose)
                buffer.FinishDraw(shader, blend)
            }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, oldArray)
            GL15.glBindBuffer(GL15.GL_ELEMENT_ARRAY_BUFFER, oldElements)
        }
        return true
    }
}
