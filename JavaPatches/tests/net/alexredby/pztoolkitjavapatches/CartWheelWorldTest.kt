package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.InvocationTargetException
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.scripting.objects.ModelScript
import sun.misc.Unsafe
import zombie.core.skinnedmodel.model.ItemModelRenderer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.shader.Shader
import zombie.inventory.InventoryItem
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.iso.IsoGridSquare
import zombie.core.ImmutableColor

object CartWheelWorldTest {
    private lateinit var unsafe: Unsafe
    private fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))
    private fun check(value: Boolean, message: String) { if (!value) throw AssertionError(message) }
    private fun set(target: Any, name: String, value: Any?) {
        val field = target.javaClass.getDeclaredField(name); field.isAccessible = true; field.set(target, value)
    }
    private fun current(): Any? {
        val field = CartWheelWorld::class.java.getDeclaredField("drawing"); field.isAccessible = true
        return (field.get(null) as ThreadLocal<*>).get()
    }
    private fun phase(): Double {
        val draw = current()!!; val method = draw.javaClass.getDeclaredMethod("phase"); method.isAccessible = true
        return method.invoke(draw) as Double
    }
    private class Cart : InventoryItem(null, null, null, null as String?) {
        var world: IsoWorldInventoryObject? = null
        var kind = "SaucedWheelbarrow.WheelbarrowWood"
        override fun getFullType(): String = kind
        override fun getWorldItem(): IsoWorldInventoryObject? = world
    }
    private fun litSquare(): IsoGridSquare {
        val square = allocate(IsoGridSquare::class.java)
        val lighting = Array<IsoGridSquare.ILighting>(4) {
            IsoGridSquare.Lighting().apply { for (vertex in 0 until 8) lightverts(vertex, 0xffffffff.toInt()) }
        }
        set(square, "lighting", lighting)
        return square
    }
    private class World : IsoWorldInventoryObject(null as zombie.iso.IsoCell?) {
        var heldItem: InventoryItem? = null
        override fun getItem(): InventoryItem? = heldItem
    }
    private fun cart(): Cart {
        val cart = allocate(Cart::class.java); cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
        val world = allocate(World::class.java); world.heldItem = cart; cart.world = world
        return cart
    }
    private fun model(): Model = allocate(Model::class.java).apply {
        isStatic = true; set(this, "mesh", allocate(ModelMesh::class.java))
    }
    private fun renderer(model: Model): ItemModelRenderer = ItemModelRenderer().apply { set(this, "model", model) }
    private fun prepare(renderer: ItemModelRenderer, item: Cart, transform: Matrix4f, phase: Double) {
        CartWheelSpin.record(item, renderer.x, renderer.y, Math.PI.toFloat(), CartWheelWorld.worldTransform(renderer, transform, Matrix4f()), phase)
        CartWheelWorld.snapshot(renderer, item, transform); CartWheelWorld.ready(renderer)
    }
    private fun compositionAndPool() {
        val model = model(); val renderer = renderer(model); var item = cart()
        val transform = Matrix4f().translation(.1f, .2f, -.3f).rotateX(.4f).scale(.85f)
        CartWheelWorld.snapshot(renderer, item, transform)
        var previous = CartWheelWorld.begin(renderer, model, transform, false)
        check(current() == null, "unfinished init snapshot was drawable before native final rotation/scale"); CartWheelWorld.end(previous)
        // Native renderMain applies both scales and rotation after returning from init.
        transform.scale(90f); renderer.angle.set(17f, 43f, -9f); renderer.x = 10.25f; renderer.y = 20.75f
        val original = Matrix4f(transform)
        val expected = Matrix4f().rotationX(Math.toRadians(17.0).toFloat()).rotateY(Math.toRadians(43.0).toFloat())
            .rotateZ(Math.toRadians(-9.0).toFloat()).mul(transform)
        check(CartWheelWorld.worldTransform(renderer, transform, Matrix4f()).equals(expected, .00001f), "world rotation did not follow native Rx/Ry/Rz order")
        check(transform == original, "world composition mutated native root transform")
        CartWheelSpin.record(item, renderer.x, renderer.y, Math.PI.toFloat(), expected, .7)
        CartWheelWorld.ready(renderer)
        previous = CartWheelWorld.begin(renderer, model, transform, false)
        check(current() != null && Math.abs(phase() - .7) < .00001, "phase used pre-finalization rotation/scale"); CartWheelWorld.end(previous)
        check(CartWheelWorld.rendered(renderer) == null, "prepared phase became successful draw evidence")
        renderer.reset()
        previous = CartWheelWorld.begin(renderer, model, transform, false)
        check(current() == null, "pooled native reset retained an old world item phase"); CartWheelWorld.end(previous)
        prepare(renderer, item, transform, .4)
        item.kind = "SaucedCarts.ShoppingCart"
        CartWheelWorld.snapshot(renderer, item, transform); CartWheelWorld.ready(renderer)
        previous = CartWheelWorld.begin(renderer, model, transform, false)
        check(current() == null, "foreign item retained recycled renderer phase"); CartWheelWorld.end(previous)
        item.kind = "SaucedWheelbarrow.WheelbarrowWood"; item.world = null
        CartWheelWorld.snapshot(renderer, item, transform); CartWheelWorld.ready(renderer)
        previous = CartWheelWorld.begin(renderer, model, transform, false)
        check(current() == null, "inventory item entered the world wheel draw"); CartWheelWorld.end(previous)
        item = cart(); (item.world as World).heldItem = cart()
        CartWheelWorld.snapshot(renderer, item, transform); CartWheelWorld.ready(renderer)
        previous = CartWheelWorld.begin(renderer, model, transform, false)
        check(current() == null, "mismatched world object entered the wheel draw"); CartWheelWorld.end(previous)
    }
    private fun nestedAndException() {
        val outerModel = model(); val innerModel = model(); val outer = renderer(outerModel); val inner = renderer(innerModel)
        val transform = Matrix4f().scale(76.5f); prepare(outer, cart(), transform, .3); prepare(inner, cart(), transform, .9)
        val original = CartWheelWorld.begin(outer, outerModel, transform, false); val outerScope = current()
        check(outerScope != null, "missing exact root world scope")
        var saved = CartWheelWorld.begin(inner, innerModel, transform, false)
        check(current() != null && current() !== outerScope && Math.abs(phase() - .9) < .00001, "nested root did not use its own snapshot")
        CartWheelWorld.end(saved); check(current() === outerScope, "nested root lost previous scope")
        for (part in booleanArrayOf(false, true)) {
            saved = CartWheelWorld.begin(outer, if (part) outerModel else innerModel, transform, part)
            check(current() == null, "foreign/weapon-part pass inherited outer scope")
            check(!CartWheelWorld.render(outerModel.mesh, allocate(Shader::class.java)), "unmatched pass entered GL")
            CartWheelWorld.end(saved); check(current() === outerScope, "foreign/part exit lost previous scope")
        }
        check(!CartWheelWorld.render(innerModel.mesh, allocate(Shader::class.java)), "foreign mesh entered GL")
        check(!CartWheelWorld.render(outerModel.mesh, null), "missing shader entered GL")
        check(!CartWheelWorld.render(outerModel.mesh, allocate(Shader::class.java)), "missing VBO entered GL")
        check(CartWheelWorld.rendered(outer) == null, "failed split draw emitted successful receipt")
        // Real woven native method fails before Shader.Start/GL; its throwable exit must restore the outer scope.
        innerModel.effect = allocate(Shader::class.java)
        val nativeRender = ItemModelRenderer::class.java.getDeclaredMethod("renderModel", Model::class.java, Matrix4f::class.java,
            Boolean::class.javaPrimitiveType, Boolean::class.javaPrimitiveType, Boolean::class.javaPrimitiveType)
        nativeRender.isAccessible = true
        try { nativeRender.invoke(inner, innerModel, transform, false, false, false); throw AssertionError("native fixture did not throw") }
        catch (expected: InvocationTargetException) { check(expected.cause is NullPointerException, "wrong native fixture failure") }
        check(current() === outerScope, "ZombieBuddy onThrowable exit did not restore outer scope")
        CartWheelWorld.end(original); check(current() == null, "outer scope leaked after exit")
        try { nativeRender.invoke(inner, innerModel, transform, false, false, false); throw AssertionError("native fixture did not throw") }
        catch (expected: InvocationTargetException) { check(expected.cause is NullPointerException, "wrong native fixture failure") }
        check(current() == null, "exception leaked a world wheel scope to later draws")
        outerModel.mesh.Draw(allocate(Shader::class.java)) // Woven unrelated native draw, no VBO and no GL.
    }
    private fun metalWorld() {
        val nativeModel = model(); val renderer = renderer(nativeModel); val item = cart()
        item.kind = "SaucedWheelbarrow.WheelbarrowMetal"
        val transform = CartWheelbarrow.METAL.held(Matrix4f())
        prepare(renderer, item, transform, .6)
        val previous = CartWheelWorld.begin(renderer, nativeModel, transform, false)
        check(current() != null && Math.abs(phase() - .6) < .00001, "metal world phase was not retained")
        check(!CartWheelWorld.render(nativeModel.mesh, allocate(Shader::class.java)), "metal missing VBO entered GL")
        check(CartWheelWorld.rendered(renderer) == null, "metal failed draw produced successful receipt")
        CartWheelWorld.end(previous); CartWheelWorld.clear(renderer)
    }
    private fun close(actual: Float, expected: Float, message: String) {
        check(Math.abs(actual - expected) < .000003f, "$message: $actual vs $expected")
    }
    private fun supportGeometry(transform: Matrix4f) {
        // Independent native metal VBO foot vertices and measured tire rim/cylinder, before item yaw.
        val floor = .008f - .00175f * 2.44949f / 1.5f
        for (x in floatArrayOf(-8.86394978f, -38.22069931f)) {
            val foot = transform.transformPosition(Vector3f(x, -20.28660011f, 37.90950012f))
            close(foot.y, floor, "metal support foot does not share the floor")
        }
        // Sample actual rim through arbitrary shader phases, rather than one captured lowest vertex.
        for (phase in 0 until 37) {
            var lowest = Float.POSITIVE_INFINITY
            for (vertex in 0 until 720) {
                val a = vertex * Math.PI / 360 + phase * .137
                val point = transform.transformPosition(Vector3f(-23.54235f, -11.737464f + 12.154752f * Math.cos(a).toFloat(), .78115034f + 12.154752f * Math.sin(a).toFloat()))
                check(point.y >= floor - .000003f, "retained wheel phase penetrates support floor")
                lowest = Math.min(lowest, point.y)
            }
            check(lowest - floor < .00002f, "wheel envelope floats above both grounded feet")
        }
    }
    private fun supportCalibration() {
        val item = cart(); item.kind = "SaucedWheelbarrow.WheelbarrowMetal"
        val nativeModel = model(); val renderer = renderer(nativeModel)
        val field = ItemModelRenderer::class.java.getDeclaredField("transform"); field.isAccessible = true
        val nativeTransform = field.get(renderer) as Matrix4f
        val script = ModelScript()
        for (modelScale in floatArrayOf(.5f, 1f, 2f)) for (itemScale in floatArrayOf(.6f, 1f, 1.4f)) {
            item.worldScale = itemScale; script.scale = modelScale
            val original = Matrix4f().translation(.2800003f, .28608033f, -.4227159f).scale(.010794421f)
            val axle = Vector3f(-23.54235f, -11.737464f, .78115034f)
            val before = Matrix4f(original).scale(.85f * modelScale * itemScale).transformPosition(axle, Vector3f())
            nativeTransform.set(original)
            Main.WoodenWorldScale.exit(renderer, item, script)
            nativeTransform.scale(modelScale * itemScale) // Actual renderMain post-init order.
            supportGeometry(nativeTransform)
            val after = nativeTransform.transformPosition(axle, Vector3f())
            close(after.x, before.x, "support calibration moved native axle sideways")
            close(after.z, before.z, "support calibration moved native axle forwards")
            val projected = Matrix4f(original).scale(modelScale)
            check(CartWorldSupport.apply(item.getFullType(), projected, itemScale * .85f), "transition support calibration refused")
            projected.scale(itemScale * .85f)
            check(projected.equals(nativeTransform, .000003f), "transition/native world pipelines disagree")
            val repeated = Matrix4f(projected)
            check(CartWorldSupport.apply(item.getFullType(), repeated, 1f), "repeat support calibration refused")
            check(repeated.equals(projected, .000003f), "repeat support calibration rotated or translated twice")
            for (yaw in floatArrayOf(0f, 43f, 135f, 270f)) {
                renderer.angle.set(0f, yaw, 0f)
                supportGeometry(CartWheelWorld.worldTransform(renderer, nativeTransform, Matrix4f()))
            }
            renderer.reset() // Pooled init must start from the newly built native matrix.
        }
        val original = Matrix4f().translation(.28f, .286f, -.42f).scale(.01f)
        for (kind in arrayOf("SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.Unknown", "Base.Hammer")) {
            val transform = Matrix4f(original)
            check(!CartWorldSupport.apply(kind, transform, 1f) && transform == original, "foreign model support was changed")
        }
        item.world = null; script.scale = 1f; item.worldScale = 1f; nativeTransform.set(original)
        Main.WoodenWorldScale.exit(renderer, item, script)
        check(nativeTransform == Matrix4f(original).scale(.85f), "inventory icon received world support calibration")
        for (invalid in floatArrayOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            val transform = Matrix4f(original)
            check(!CartWorldSupport.apply(item.getFullType(), transform, invalid) && transform == original, "invalid support scale changed model")
        }
    }
    private fun wovenNativeSupportInit() {
        // Actual transformed engine method, whose advice executes in the native engine package.
        val init = ItemModelRenderer::class.java.getDeclaredMethod("init", InventoryItem::class.java, IsoGridSquare::class.java,
            IsoGridSquare::class.java, Float::class.javaPrimitiveType, Float::class.javaPrimitiveType, Float::class.javaPrimitiveType,
            Model::class.java, ModelScript::class.java, Float::class.javaPrimitiveType, ImmutableColor::class.java,
            Float::class.javaPrimitiveType, Boolean::class.javaPrimitiveType, Boolean::class.javaPrimitiveType)
        init.isAccessible = true
        val renderer = renderer(model()); val square = litSquare(); val item = cart()
        val script = ModelScript(); script.scale = .010794421f; item.worldScale = 1f
        val nativeModel = model() // Mesh.transform=null skips readiness and GPU calls in native init.
        val field = ItemModelRenderer::class.java.getDeclaredField("transform"); field.isAccessible = true
        for (kind in arrayOf("SaucedWheelbarrow.WheelbarrowMetal", "SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal")) {
            item.kind = kind
            renderer.reset()
            try {
                init.invoke(renderer, item, square, square, 10.25f, 20.75f, 2.00175f, nativeModel, script, 1f, ImmutableColor(1f, 1f, 1f, 1f), 0f, false, false)
            } catch (failure: InvocationTargetException) { throw AssertionError("actual woven native init failed for $kind", failure.cause) }
            val transform = field.get(renderer) as Matrix4f
            // renderMain applies script/item scales after the private init advice returned.
            transform.scale(script.scale * item.worldScale)
            if (kind.endsWith("Metal")) supportGeometry(transform)
            else check(transform.equals(Matrix4f().scale(.85f * script.scale), .000001f), "pooled wood init inherited the metal support calibration")
            close(renderer.x, 10.25f, "native init did not complete actor X assignment")
            close(renderer.z, 2.00175f, "native init did not complete level assignment")
        }
    }
    @JvmStatic fun main(args: Array<String>) {
        val field = Unsafe::class.java.getDeclaredField("theUnsafe"); field.isAccessible = true; unsafe = field.get(null) as Unsafe
        check(me.zed_0xff.zombie_buddy.Patch.OnExit::class.java.getMethod("onThrowable").returnType == Class::class.java, "ZombieBuddy Patch API lacks onThrowable")
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CartWheelWorldTest::class.java.classLoader)
        check(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED, "installed world wheel bytecode unsupported")
        compositionAndPool(); nestedAndException(); metalWorld(); supportCalibration(); wovenNativeSupportInit()
        println("CART_WHEEL_WORLD_PASS (native matrix order, pooled renderer, exact nested scope and woven exception cleanup; no GL)")
    }
}
