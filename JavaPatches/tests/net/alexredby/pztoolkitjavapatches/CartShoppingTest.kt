package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.Model
import zombie.inventory.InventoryItem
import zombie.scripting.objects.ModelScript

/**
 * Four native tire samples protect support and mesh scale independently of production contact
 * constants.
 */
object CartShoppingTest {
    // Actual VBO positions from ShoppingCartModel.bin (sha256
    // 2aff1983c0bf843edbf012a33cc2d0d77124d3865b2e9dc35785d31cb08d0aab).
    // These are the lowest vertex of each separate 64-point tire under the measured axle support
    // plane.
    private val TIRES =
        arrayOf(
            Vector3f(-108.67859649658203f, -8.72284984588623f, -1.097890853881836f),
            Vector3f(-108.67859649658203f, -8.722865104675293f, 1.1834654808044434f),
            Vector3f(110.04669952392578f, 8.371068000793457f, -.910473644733429f),
            Vector3f(110.04669952392578f, 8.371052742004395f, .9835692644119263f),
        )
    private val BAR = Vector3f(-150.07166f, 343.47412f, -.0000065f)

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(actual: Float, expected: Float, tolerance: Float, message: String) {
        check(
            actual.isFinite() && Math.abs(actual - expected) <= tolerance,
            "$message: $actual expected $expected",
        )
    }

    private fun at(m: Matrix4f, p: Vector3f): Vector3f = m.transformPosition(p, Vector3f())

    private fun tires(m: Matrix4f, where: String) {
        for (i in TIRES.indices) close(at(m, TIRES[i]).y, .008f, .000002f, "$where tire $i")
    }

    private fun barXZ(before: Matrix4f, after: Matrix4f, where: String) {
        val a = at(before, BAR)
        val b = at(after, BAR)
        close(b.x, a.x, .000002f, "$where bar X")
        close(b.z, a.z, .000002f, "$where bar Z")
    }

    // Native atlas ItemParams render receipt from atlas01/interaction, not
    // CartShopping.worldModel().
    private fun nativeModel(): Matrix4f =
        Matrix4f()
            .set(
                .002273866f,
                -.00014903705f,
                0f,
                0f,
                .000111277506f,
                .0016977666f,
                -7.437096e-11f,
                0f,
                3.159179e-10f,
                4.819975e-9f,
                .11050479f,
                0f,
                0f,
                0f,
                0f,
                1f,
            )

    // Native Bob idle hand attachment before the shopping correction.
    private fun nativeHeld(): Matrix4f =
        Matrix4f()
            .set(
                -5.080325e-10f,
                -.00022194229f,
                -.0021531826f,
                0f,
                7.381783e-10f,
                .0016076594f,
                -.00016571165f,
                0f,
                .104969054f,
                -6.051497e-8f,
                -1.0280073e-8f,
                0f,
                -.0016536561f,
                .0033783615f,
                -.44702002f,
                1f,
            )

    private fun support() {
        for (size in floatArrayOf(.6f, 1f, 1.7f)) for (later in
            floatArrayOf(.2f, 1f, 2.5f)) for (yaw in floatArrayOf(0f, .7f, 2.3f)) {
            // Native outer init applies laterScale to basis only, after the support hook.
            val raw =
                Matrix4f()
                    .translation(.14f, .21f, -.32f)
                    .rotateY(yaw)
                    .rotateX(.12f)
                    .mul(nativeModel())
                    .scale(size / later)
            val before = Matrix4f(raw).scale(later)
            val originalBasis = before.getScale(Vector3f())
            check(CartShopping.support(raw, later), "valid nonuniform native basis rejected")
            val effective = Matrix4f(raw).scale(later)
            tires(effective, "effective world")
            barXZ(before, effective, "support")
            val afterBasis = effective.getScale(Vector3f())
            close(afterBasis.x, originalBasis.x, 1e-8f, "support changed native X scale")
            close(afterBasis.y, originalBasis.y, 1e-8f, "support changed native Y scale")
            close(afterBasis.z, originalBasis.z, 1e-6f, "support changed native Z scale")
            val once = Matrix4f(raw)
            check(CartShopping.support(raw, later), "second support rejected")
            check(raw.equals(once, .000002f), "support is not idempotent")
        }
    }

    private fun directSupport() {
        val offset = .00175f * 2.44949f / 1.5f
        val raw = nativeModel()
        val before = Matrix4f(raw).scale(.28f)
        check(
            CartWorldSupport.applyDirect("SaucedCarts.ShoppingCart", raw, .28f),
            "direct support refused",
        )
        val effective = Matrix4f(raw).scale(.28f)
        barXZ(before, effective, "direct world")
        effective.m31(effective.m31() + offset)
        tires(effective, "direct origin compensation")
        val once = Matrix4f(raw)
        check(
            CartWorldSupport.applyDirect("SaucedCarts.ShoppingCart", raw, .28f),
            "repeat direct refused",
        )
        check(raw.equals(once, .000002f), "direct support is not idempotent")
    }

    private fun align() {
        val model = nativeModel()
        check(CartShopping.support(model, 1f), "canonical support rejected")
        val modelBefore = Matrix4f(model)
        for (worldScale in floatArrayOf(.6f, 1f, 1.7f)) {
            val held = nativeHeld()
            val before = Matrix4f(held)
            val delta = Matrix4f().translation(2f, 3f, 4f).rotateY(.2f)
            check(CartShopping.align(held, model, worldScale, delta), "valid held basis rejected")
            tires(held, "held")
            barXZ(before, held, "align")
            check(delta.equals(Matrix4f()), "actor delta contains cart scale/pitch")
            val residual = Matrix4f(held).mul(Matrix4f(model).invert())
            for (axis in 0 until 3) close(
                residual.getColumn(axis, Vector3f()).length(),
                worldScale,
                .000002f,
                "held/world mesh size mismatch",
            )
            val once = Matrix4f(held)
            check(CartShopping.align(held, model, worldScale, delta), "second align rejected")
            check(held.equals(once, .000002f), "align is not idempotent")
            check(model.equals(modelBefore), "align mutated imported model")
        }
    }

    private fun steeringAxle() {
        // Independent native tire centers, not the production generated table or old .8 pivot.
        val rear = Vector3f(-109.615318f, 8.723767f, -.021271825f)
        for (scale in floatArrayOf(.6f, 1f, 1.7f)) {
            val pose = nativeHeld()
            val model = nativeModel()
            check(CartShopping.support(model, 1f), "steering world support rejected")
            check(CartShopping.align(pose, model, scale, Matrix4f()), "steering held pose rejected")
            val expected = -1.5f * at(pose, rear).z
            close(
                CartShopping.axle(scale).toFloat(),
                expected,
                1e-6f,
                "rear rolling axle at scale $scale",
            )
        }
        close(CartShopping.axle(1f).toFloat(), .35949203f, 1e-6f, "native held rear axle")
        for (scale in floatArrayOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) check(
            CartShopping.axle(scale) == 0.0,
            "invalid scale cannot create a steering pivot",
        )
    }

    private fun invalid() {
        for (scale in floatArrayOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            val m = nativeModel()
            val before = Matrix4f(m)
            check(!CartShopping.support(m, scale), "invalid laterScale accepted")
            check(m.equals(before), "invalid support changed output")
            val h = nativeHeld()
            val original = Matrix4f(h)
            val delta = Matrix4f().translation(3f, 2f, 1f)
            val d = Matrix4f(delta)
            check(!CartShopping.align(h, m, scale, delta), "invalid worldScale accepted")
            check(h.equals(original) && delta.equals(d), "invalid scale changed held/actor")
        }
        for (invalid in
            arrayOf(
                Matrix4f().scale(0f),
                Matrix4f().scale(-1f, 1f, 1f),
                Matrix4f().m00(Float.NaN),
                Matrix4f().rotateX(Math.PI.toFloat() / 2).mul(nativeModel()),
            )) {
            val original = Matrix4f(invalid)
            check(!CartShopping.support(invalid, 1f), "invalid/upside support accepted")
            check(
                invalid.get(FloatArray(16)).contentEquals(original.get(FloatArray(16))),
                "failed support mutated input",
            )
        }
        val failedHeld = Matrix4f().translation(3f, 2f, 1f)
        check(
            CartShopping.held(failedHeld, null, 1f) == null && failedHeld.equals(nativeHeld()),
            "held initialization must precede invalid model rejection",
        )
        val model = nativeModel()
        var h = Matrix4f().rotateZ(Math.PI.toFloat() / 2).mul(model).scale(.5f)
        val before = Matrix4f(h)
        val delta = Matrix4f().translation(3f, 2f, 1f)
        val deltaBefore = Matrix4f(delta)
        check(!CartShopping.align(h, model, 1f, delta), "sideways held pose accepted")
        check(h.equals(before) && delta.equals(deltaBefore), "failed alignment mutated held/actor")
        h = nativeHeld()
        before.set(h)
        check(!CartShopping.align(h, model, 1f, null), "null actor delta accepted")
        check(h.equals(before), "null delta changed held")
        check(
            !CartShopping.support(null, 1f) &&
                !CartShopping.align(null, model, 1f, delta) &&
                !CartShopping.align(h, null, 1f, delta),
            "null input accepted",
        )
        for (badModel in arrayOf(Matrix4f().scale(0f), Matrix4f().m00(Float.NaN))) {
            before.set(h)
            check(!CartShopping.align(h, badModel, 1f, delta), "invalid model accepted")
            check(h.equals(before) && delta.equals(deltaBefore), "invalid model changed outputs")
        }
    }

    class Params(@JvmField val transform: Matrix4f)

    private class Cart : InventoryItem(null, null, null, null as String?) {
        override fun getFullType(): String = "SaucedCarts.ShoppingCart"
    }

    private fun atlasLaterScale() {
        check(Main.CART_TRANSITION_SUPPORTED, "installed shopping atlas bytecode unsupported")
        val field = sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        val unsafe = field.get(null) as sun.misc.Unsafe
        val item = unsafe.allocateInstance(Cart::class.java) as Cart
        item.worldScale = .7f
        val script = ModelScript()
        script.scale = .4f
        val params = Params(nativeModel())
        val before = Matrix4f(params.transform).scale(script.scale * item.worldScale)
        Main.ShoppingWorldAtlas.exit(params, item, null, script, 1f, null, 0f, false)
        val effective = Matrix4f(params.transform).scale(script.scale * item.worldScale)
        tires(effective, "native atlas laterScale")
        barXZ(before, effective, "atlas")
    }

    private fun field(obj: Any, name: String, value: Any?) {
        val f = obj.javaClass.getDeclaredField(name)
        f.isAccessible = true
        f.set(obj, value)
    }

    private fun wovenAtlas() {
        val f = sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe")
        f.isAccessible = true
        val unsafe = f.get(null) as sun.misc.Unsafe
        val type = Class.forName("zombie.core.skinnedmodel.model.WorldItemAtlas\$ItemParams")
        val init =
            type.getDeclaredMethod(
                "init",
                InventoryItem::class.java,
                Model::class.java,
                ModelScript::class.java,
                Float::class.javaPrimitiveType,
                zombie.core.ImmutableColor::class.java,
                Float::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
            )
        init.isAccessible = true
        val mesh =
            unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelMesh::class.java)
                as zombie.core.skinnedmodel.model.ModelMesh
        val meshState = unsafe.allocateInstance(Class.forName("zombie.asset.Asset\$PRIVATE"))
        field(meshState, "currentState", zombie.asset.Asset.State.READY)
        val privateState = zombie.asset.Asset::class.java.getDeclaredField("priv")
        privateState.isAccessible = true
        privateState.set(mesh, meshState)
        mesh.transform = Matrix4f(nativeModel()).transpose()
        val model = unsafe.allocateInstance(Model::class.java) as Model
        field(model, "mesh", mesh)
        val script = ModelScript()
        script.scale = .4f
        val item = unsafe.allocateInstance(Cart::class.java) as Cart
        item.worldScale = .7f
        val params = unsafe.allocateInstance(type)
        val transform = Matrix4f()
        field(params, "transform", transform)
        field(params, "angle", Vector3f())
        init.invoke(params, item, model, script, 1f, zombie.core.ImmutableColor.white, 0f, false)
        val baseline = Matrix4f(transform).scale(script.scale * item.worldScale)
        check(
            Math.abs(at(baseline, TIRES[3]).y - .008f) > .001f,
            "native atlas fixture was already supported",
        )
        // Execute the real private native method after production advice is inlined into its own
        // package.
        // A plain call of Main.ShoppingWorldAtlas.exit cannot expose IllegalAccessError from that
        // context.
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartShoppingTest::class.java.classLoader,
        )
        init.invoke(params, item, model, script, 1f, zombie.core.ImmutableColor.white, 0f, false)
        val effective = Matrix4f(transform).scale(script.scale * item.worldScale)
        tires(effective, "woven native atlas")
        barXZ(baseline, effective, "woven atlas")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        support()
        directSupport()
        align()
        steeringAxle()
        invalid()
        atlasLaterScale()
        wovenAtlas()
        println(
            "CART_SHOPPING_PASS (four native tire contacts, imported scales, effective laterScale, bar X/Z, idempotence, transactional failures, woven native atlas hook)",
        )
    }
}
