package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import me.zed_0xff.zombie_buddy.Accessor
import org.joml.Matrix4f
import org.joml.Matrix4fc
import zombie.core.skinnedmodel.model.ItemModelRenderer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.shader.Shader
import zombie.inventory.InventoryItem

/**
 * Carry the exact item's wheel angle into native world rendering without replacing its material
 * setup.
 */
object CartWheelWorld {
    private class Snapshot(
        val item: InventoryItem,
        val model: Model,
        val transform: Matrix4f,
        val phase: Double,
        val shopping: CartShoppingWheels.Frame?,
    )

    private class Draw(
        val renderer: ItemModelRenderer,
        val item: InventoryItem,
        val mesh: ModelMesh,
        val transform: Matrix4f,
        private val phase: Double,
        val shopping: CartShoppingWheels.Frame?,
    ) {
        fun phase(): Double = phase
    }

    @JvmRecord
    data class Receipt(val item: InventoryItem?, val phase: Double, val cart: Matrix4fc?) {
        override fun toString(): String = "Receipt[item=$item, phase=$phase, cart=$cart]"
    }

    private val snapshots = WeakHashMap<ItemModelRenderer?, Snapshot>()
    private val receipts = WeakHashMap<ItemModelRenderer?, Receipt>()
    private val drawing = ThreadLocal<Draw>()

    private fun worldCart(item: InventoryItem?): Boolean =
        CartTransition.supported(item) &&
            item!!.getWorldItem() != null &&
            item.getWorldItem().getItem() === item

    @JvmStatic
    @Synchronized
    fun snapshot(renderer: ItemModelRenderer?, item: InventoryItem?, transform: Matrix4f?) {
        snapshots.remove(renderer)
        receipts.remove(renderer)
        if (!worldCart(item) || transform == null || !transform.isFinite) return
        val model = Accessor.tryGet(renderer, "model", null as Model?)
        if (model != null && model.isStatic)
            snapshots[renderer] = Snapshot(item!!, model, transform, Double.NaN, null)
    }

    @JvmStatic
    fun worldTransform(renderer: ItemModelRenderer, transform: Matrix4f, out: Matrix4f): Matrix4f =
        out.rotationXYZ(
                Math.toRadians(renderer.angle.x.toDouble()).toFloat(),
                Math.toRadians(renderer.angle.y.toDouble()).toFloat(),
                Math.toRadians(renderer.angle.z.toDouble()).toFloat(),
            )
            .mul(transform)

    /** renderMain assigns item rotation and model/world scale after init returns. */
    @JvmStatic
    @Synchronized
    fun ready(renderer: ItemModelRenderer?) {
        val snapshot = snapshots[renderer] ?: return
        if (!worldCart(snapshot.item)) {
            clear(renderer)
            return
        }
        val transform = worldTransform(renderer!!, snapshot.transform, Matrix4f())
        if (!transform.isFinite) {
            clear(renderer)
            return
        }
        // Virtual actor angle PI gives the native world camera's +X/-Z tile projection.
        val shopping =
            if (CartShopping.item(snapshot.item))
                CartShoppingWheels.follow(
                    snapshot.item,
                    renderer.x,
                    renderer.y,
                    Math.PI.toFloat(),
                    transform,
                )
            else null
        val phase =
            if (shopping != null) shopping.phases!![0]
            else
                CartWheelSpin.follow(
                    snapshot.item,
                    renderer.x,
                    renderer.y,
                    Math.PI.toFloat(),
                    transform,
                )
        if (java.lang.Double.isFinite(phase))
            snapshots[renderer] =
                Snapshot(snapshot.item, snapshot.model, snapshot.transform, phase, shopping)
        else clear(renderer)
    }

    @JvmStatic
    @Synchronized
    fun clear(renderer: ItemModelRenderer?) {
        snapshots.remove(renderer)
        receipts.remove(renderer)
    }

    /** Null until the current root pass actually completed the verified split draw. */
    @JvmStatic
    @Synchronized
    fun rendered(renderer: ItemModelRenderer?): Receipt? = receipts[renderer]

    @JvmStatic
    @Synchronized
    private fun recorded(draw: Draw) {
        receipts[draw.renderer] = Receipt(draw.item, draw.phase(), Matrix4f(draw.transform))
    }

    @JvmStatic
    @Synchronized
    private fun clearReceipt(renderer: ItemModelRenderer?) {
        receipts.remove(renderer)
    }

    @JvmStatic
    @Synchronized
    private fun snapshot(renderer: ItemModelRenderer?): Snapshot? = snapshots[renderer]

    /** Every nested call masks the outer scope, including foreign models and weapon parts. */
    @JvmStatic
    fun begin(
        renderer: ItemModelRenderer?,
        model: Model?,
        transform: Matrix4f?,
        weaponPart: Boolean,
    ): Any? {
        val previous = drawing.get()
        val snapshot = snapshot(renderer)
        if (!weaponPart) clearReceipt(renderer)
        if (
            !weaponPart &&
                snapshot != null &&
                snapshot.model === model &&
                java.lang.Double.isFinite(snapshot.phase) &&
                model.mesh != null &&
                transform != null &&
                transform.isFinite
        )
            drawing.set(
                Draw(
                    renderer!!,
                    snapshot.item,
                    model.mesh,
                    transform,
                    snapshot.phase,
                    snapshot.shopping,
                ),
            )
        else drawing.remove()
        return previous
    }

    @JvmStatic
    fun end(previous: Any?) {
        if (previous == null) drawing.remove() else drawing.set(previous as Draw)
    }

    @JvmStatic
    fun render(mesh: ModelMesh?, shader: Shader?): Boolean {
        val draw = drawing.get()
        if (draw == null || draw.mesh !== mesh || shader == null) return false
        val rendered =
            if (draw.shopping != null)
                CartShoppingWheels.draw(mesh.vb, shader, draw.transform, draw.shopping, false)
            else
                CartWheelSpin.draw(
                    CartWheelbarrow.forItem(draw.item),
                    mesh.vb,
                    shader,
                    draw.transform,
                    draw.phase(),
                    false,
                )
        if (!rendered) return false
        recorded(draw)
        return true
    }
}
