package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.inventory.InventoryItem
import zombie.scripting.objects.ModelScript

object CartWheelSpinTest {
    private fun close(actual: Number, expected: Number, message: String) {
        if (Math.abs(actual.toDouble() - expected.toDouble()) > 1e-6)
            throw AssertionError("$message: $actual != $expected")
    }

    private fun metalGeometry(unsafe: Unsafe) {
        val profile = CartWheelbarrow.METAL
        if (
            CartWheelbarrow.forModel("WheelbarrowMetal") !== profile ||
                CartWheelbarrow.forType("SaucedWheelbarrow.WheelbarrowMetal") !== profile ||
                CartWheelbarrow.forModel("ShoppingCartModel") != null ||
                CartWheelbarrow.forItem(null) != null
        )
            throw AssertionError("wheelbarrow profile routing changed")
        val indices = intArrayOf(0, 1, 2134, 2135, 2136, 2994, 2995, 2996, 3687)
        if (
            !java.util.Arrays.deepEquals(
                CartWheelSpin.ranges(profile, indices),
                arrayOf(intArrayOf(0, 3, 0), intArrayOf(3, 3, 1), intArrayOf(6, 3, 0)),
            )
        )
            throw AssertionError("metal wheel middle range was not partitioned")
        for (invalid in
            arrayOf(
                intArrayOf(2134, 2135, 2136),
                intArrayOf(2994, 2995, 2996),
                intArrayOf(0, 1, 3688),
                intArrayOf(2135, 2136, 2994),
                intArrayOf(0, 1, 2),
            )) if (CartWheelSpin.ranges(profile, invalid) != null)
            throw AssertionError("unsafe metal geometry accepted")
        close(
            CartWheelSpin.advance(profile, .3, profile.worldRadius() * Math.PI / 2),
            .3 - Math.PI / 2,
            "metal rolling radius",
        )
        val held = profile.held(Matrix4f())
        val center = profile.center(Vector3f())
        val fixed = held.transformPosition(Vector3f(center))
        val point = Vector3f(center).add(0f, -profile.radius(), 0f)
        for (angle in floatArrayOf(0f, .4f, Math.PI.toFloat() / 2, Math.PI.toFloat(), -.4f)) {
            val spun =
                CartWheelSpin.transform(
                        profile,
                        Matrix4f(held).transpose(),
                        angle.toDouble(),
                        Matrix4f(),
                    )
                    .transpose()
            if (spun.transformPosition(Vector3f(center)).distance(fixed) > 1e-6f)
                throw AssertionError("metal axle moved during wheel rotation")
            close(
                spun.transformPosition(Vector3f(point)).distance(fixed),
                profile.worldRadius() / 1.5,
                "metal tire radius changed",
            )
        }
        close(-fixed.z * 1.5, profile.axle(), "metal steering axle differs from rendered tire")
        close(-fixed.x * 1.5, profile.lateral(), "metal lateral axle differs from rendered tire")
        val item = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        item.setModule("SaucedWheelbarrow")
        item.setType("WheelbarrowMetal")
        close(CartWheelSpin.follow(item, 0f, 0f, 0f, held), 0, "first metal pose")
        val travel = (profile.worldRadius() * .7).toFloat()
        close(CartWheelSpin.follow(item, 0f, -travel, 0f, held), -.7, "metal actual axle travel")
        val tilted =
            Matrix4f(held).translate(center).rotateX(.4f).translate(-center.x, -center.y, -center.z)
        close(
            CartWheelSpin.follow(item, 0f, -travel, 0f, tilted),
            -1.1,
            "metal stationary tire counter-rotation",
        )
        // Returned geometry must not expose the shared profile's calibration to callers.
        held.identity()
        center.zero()
        if (profile.held(Matrix4f()).equals(held) || profile.center(Vector3f()).equals(center))
            throw AssertionError("mutable geometry escaped its profile")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val elements = intArrayOf(0, 1, 1113, 1114, 1115, 8115, 4, 5, 6, 7, 8, 9)
        val original = elements.clone()
        val runs = CartWheelSpin.ranges(elements)
        if (
            !java.util.Arrays.deepEquals(
                runs,
                arrayOf(intArrayOf(0, 3, 1), intArrayOf(3, 3, 0), intArrayOf(6, 6, 1)),
            ) || !elements.contentEquals(original)
        )
            throw AssertionError("original indexed geometry was changed or partitioned incorrectly")
        for (invalid in
            arrayOf(
                intArrayOf(),
                intArrayOf(0, 1),
                intArrayOf(0, 1, 1114),
                intArrayOf(-1, 0, 1),
                intArrayOf(0, 1, 8116),
                intArrayOf(0, 1, 2),
                intArrayOf(1114, 1115, 1116),
            )) if (CartWheelSpin.ranges(invalid) != null)
            throw AssertionError("unsafe geometry accepted: ${invalid.contentToString()}")
        val phase = .3
        close(CartWheelSpin.advance(phase, 0.0), phase, "blocked cart spun")
        close(
            CartWheelSpin.advance(phase, CartWheelSpin.WORLD_RADIUS * Math.PI / 2),
            phase - Math.PI / 2,
            "accepted forward travel",
        )
        close(
            CartWheelSpin.advance(phase, -CartWheelSpin.WORLD_RADIUS * Math.PI / 2),
            phase + Math.PI / 2,
            "accepted reverse travel",
        )
        for (invalid in doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY, 2.0, -2.0)) close(
            CartWheelSpin.advance(phase, invalid),
            phase,
            "teleport/nonfinite travel spun wheel",
        )
        close(
            CartWheelSpin.advance(0.0, CartWheelSpin.WORLD_RADIUS * Math.PI * 2),
            0,
            "one circumference",
        )
        val center =
            Vector3f(CartWheelSpin.CENTER_X, CartWheelSpin.CENTER_Y, CartWheelSpin.CENTER_Z)
        val point = Vector3f(center).add(0f, -CartWheelSpin.RADIUS, 0f)
        val cart = Matrix4f().translation(.2f, .3f, -.7f).rotateXYZ(.18f, .4f, -.15f).scale(76.5f)
        val stored = Matrix4f(cart).transpose()
        val before = Matrix4f(stored)
        for (angle in floatArrayOf(0f, .4f, Math.PI.toFloat() / 2, Math.PI.toFloat(), -.4f)) {
            val spun = CartWheelSpin.transform(stored, angle.toDouble(), Matrix4f()).transpose()
            if (!stored.equals(before)) throw AssertionError("shared parent transform changed")
            val fixed = cart.transformPosition(Vector3f(center))
            if (spun.transformPosition(Vector3f(center)).distance(fixed) > 1e-6f)
                throw AssertionError("wheel axle moved while spinning")
            close(
                spun.transformPosition(Vector3f(point)).distance(fixed),
                CartWheelSpin.RADIUS * 76.5,
                "wheel radius changed",
            )
            if (
                angle != 0f &&
                    spun
                        .transformPosition(Vector3f(point))
                        .distance(cart.transformPosition(Vector3f(point))) < .001f
            )
                throw AssertionError("wheel did not visibly rotate")
        }
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe")
        unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val item = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        item.setModule("SaucedWheelbarrow")
        item.setType("WheelbarrowWood")
        val identity = Matrix4f().scale(76.5f)
        close(CartWheelSpin.follow(item, 0f, 0f, 0f, identity), 0, "first world pose")
        val distance = CartWheelSpin.WORLD_RADIUS * .7
        close(
            CartWheelSpin.follow(item, 0f, (-distance).toFloat(), 0f, identity),
            -.7,
            "actual axle travel",
        )
        val tilted =
            Matrix4f(identity)
                .translate(CartWheelSpin.CENTER_X, CartWheelSpin.CENTER_Y, CartWheelSpin.CENTER_Z)
                .rotateX(.4f)
                .translate(
                    -CartWheelSpin.CENTER_X,
                    -CartWheelSpin.CENTER_Y,
                    -CartWheelSpin.CENTER_Z,
                )
        close(
            CartWheelSpin.follow(item, 0f, (-distance).toFloat(), 0f, tilted),
            -1.1,
            "stationary tire compensates cart pitch",
        )
        val banked = Matrix4f(tilted).rotateLocalZ(.12f)
        val centerBefore = tilted.transformPosition(Vector3f(center))
        banked.translateLocal(centerBefore.sub(banked.transformPosition(Vector3f(center))))
        close(
            CartWheelSpin.follow(item, 0f, (-distance).toFloat(), 0f, banked),
            -1.1,
            "bank did not introduce a false pitch change",
        )
        close(CartWheelSpin.itemPhase(item), -1.1, "same item retains rendered phase")
        close(
            CartWheelSpin.follow(item, 0f, (-distance).toFloat(), 0f, tilted),
            -1.1,
            "held/world handoff continuity",
        )
        close(CartWheelSpin.follow(item, 0f, 0f, 0f, tilted), -.4, "reverse travel")
        close(CartWheelSpin.follow(item, 50f, 50f, 0f, tilted), -.4, "teleport does not spin wheel")
        if (!CartWheelSpin.follow(item, Float.NaN, 0f, 0f, identity).isNaN())
            throw AssertionError("invalid pose accepted")
        close(CartWheelSpin.itemPhase(item), -.4, "invalid pose poisoned phase")
        val other = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        other.setModule("SaucedWheelbarrow")
        other.setType("WheelbarrowWood")
        close(
            CartWheelSpin.follow(other, 0f, 0f, 0f, identity),
            0,
            "phase leaked to a different cart",
        )
        other.setType("WheelbarrowMetal")
        close(
            CartWheelSpin.follow(other, 0f, 0f, 0f, CartWheelbarrow.METAL.held(Matrix4f())),
            0,
            "type change reused wooden wheel pose",
        )
        val slot = ModelSlotRenderData()
        val data = ModelInstanceRenderData()
        data.modelInstance = ModelInstance()
        data.modelInstance.modelScript = ModelScript()
        data.modelInstance.modelScript.name = "WheelbarrowWood"
        slot.modelData.add(data)
        val read =
            CartWheelSpin::class
                .java
                .getDeclaredMethod("phase", ModelInstanceRenderData::class.java)
        read.isAccessible = true
        CartWheelSpin.prepare(slot, .7)
        close(read.invoke(null, data) as Double, .7, "simulation angle was not snapshotted")
        CartWheelSpin.prepare(slot, Double.NaN)
        if (read.invoke(null, data) != null)
            throw AssertionError("recycled render data kept a stale wheel angle")
        data.modelInstance.modelScript.name = "WheelbarrowMetal"
        CartWheelSpin.prepare(slot, .9)
        close(read.invoke(null, data) as Double, .9, "metal wheel phase was not snapshotted")
        data.modelInstance.modelScript.name = "ShoppingCartModel"
        CartWheelSpin.prepare(slot, .2)
        if (read.invoke(null, data) != null)
            throw AssertionError("shopping cart entered wheelbarrow split drawing")
        metalGeometry(unsafe)
        println("CART_WHEEL_SPIN_PASS")
    }
}
