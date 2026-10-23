package net.alexredby.pztoolkitjavapatches

import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelCamera
import zombie.core.skinnedmodel.ModelCameraRenderData
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.model.ModelSlotRenderData

object CartObserverRenderTest {
    private class Camera : ModelCamera() { override fun Begin() {}; override fun End() {} }
    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        override fun setTargetAndCurrentDirection(x: Float, y: Float) { throw AssertionError("cosmetic snapshot changed native actor direction") }
    }
    private lateinit var unsafe: Unsafe
    private fun check(value: Boolean, message: String) { if (!value) throw AssertionError(message) }
    private fun close(expected: Float, actual: Float, message: String) { check(Math.abs(expected - actual) < 1e-6f, "$message: $expected != $actual") }
    private fun field(owner: Any, name: String, value: Any?) { val field = owner.javaClass.getDeclaredField(name); field.isAccessible = true; field.set(owner, value) }
    private fun slot(player: Player): ModelSlotRenderData = ModelSlotRenderData().apply {
        character = player; `object` = player; x = 10.75f; y = 20.5f; z = 0f; animPlayerAngle = -.5f
    }
    private fun pose(source: ModelManager.ModelSlot, player: Player, x: Float, y: Float, angle: Float): CartObserverRender.DrawPose =
        CartObserverRender.DrawPose(source, player, 10.75f, 20.5f, 0f, x, y, 0f, angle)
    private fun snapshots() {
        val player = unsafe.allocateInstance(Player::class.java) as Player; player.setX(10.75f); player.setY(20.5f)
        val source = unsafe.allocateInstance(ModelManager.ModelSlot::class.java) as ModelManager.ModelSlot; source.character = player
        val snapshot = ModelCameraRenderData(); val camera = Camera(); var slot = slot(player)
        CartObserverRender.queue(snapshot, camera, pose(source, player, 10.4f, 20.3f, 2.1f))
        // Actor advances between snapshots; retain the camera's accepted pose.
        slot.x += .01f; CartObserverRender.bind(slot, source)
        close(10.4f, slot.x, "producer position was not set before native depth init"); close(20.3f, slot.y, "producer y was not set")
        field(slot, "camCharacterX", 10f); field(slot, "camCharacterY", 20f)
        field(slot, "fixJigglyModelsSquareX", .125f); field(slot, "fixJigglyModelsSquareY", -.25f); slot.squareDepth = Float.NaN
        try { slot.init(source); throw AssertionError("incomplete test model unexpectedly initialized") } catch (expectedIncompleteModel: NullPointerException) {}
        val expected = zombie.iso.IsoDepthHelper.getSquareDepthData(10, 20, 10.525f, 20.05f, 0f).depthStart
        close(expected, slot.squareDepth, "native depth prefix used the uncorrected actor position")
        slot.animPlayerAngle = -.5f
        val failure = java.util.concurrent.atomic.AtomicReference<Throwable>(); val workerSlot = slot
        val worker = Thread { try { CartObserverRender.prepare(workerSlot) } catch (error: Throwable) { failure.set(error) } }
        worker.start(); worker.join()
        check(failure.get() == null, "worker could not read captured slot pose: ${failure.get()}")
        snapshot.render()
        close(camera.x, slot.x, "actual consumed camera x differs from slot"); close(camera.y, slot.y, "actual consumed camera y differs from slot")
        close(camera.z, slot.z, "actual consumed camera z differs from slot"); close(camera.useAngle, slot.animPlayerAngle, "actual camera heading differs from worker slot")
        check(camera.useWorldIso && !camera.inVehicle, "snapshot lost native cart camera mode")
        close(10.75f, player.getX(), "render changed native actor x"); close(20.5f, player.getY(), "render changed native actor y")
        CartObserverRender.forget(player); CartObserverRender.clearAll(); slot.animPlayerAngle = 0f; CartObserverRender.prepare(slot)
        close(2.1f, slot.animPlayerAngle, "reset split an already queued camera/slot pair")
        CartObserverRender.release(slot); slot.animPlayerAngle = 0f; CartObserverRender.prepare(slot)
        close(0f, slot.animPlayerAngle, "released pooled slot retained old pose")
        slot = slot(player)
        CartObserverRender.queue(snapshot, camera, pose(source, player, 10.2f, 20.2f, 1.7f)); CartObserverRender.bind(slot, source)
        // Unpaired reuse drops old association even without previous postRender.
        slot.x = 10.75f; slot.y = 20.5f; slot.animPlayerAngle = 0f
        CartObserverRender.bind(slot, source); CartObserverRender.prepare(slot)
        close(10.75f, slot.x, "unpaired reused slot moved"); close(0f, slot.animPlayerAngle, "unpaired reused slot retained yaw")
        CartObserverRender.queue(snapshot, camera, pose(source, player, 10.2f, 20.2f, 1.7f))
        val other = unsafe.allocateInstance(ModelManager.ModelSlot::class.java) as ModelManager.ModelSlot
        CartObserverRender.bind(slot, other); CartObserverRender.bind(slot, source); CartObserverRender.prepare(slot)
        close(0f, slot.animPlayerAngle, "wrong model source did not consume stale producer token")
        CartObserverRender.queue(snapshot, camera, pose(source, player, 10.2f, 20.2f, 1.7f)); CartObserverRender.capture(snapshot, camera, null)
        CartObserverRender.bind(slot, source); CartObserverRender.prepare(slot)
        close(0f, slot.animPlayerAngle, "ineligible camera draw retained a stale producer token")
    }
    private fun value(owner: Any, name: String): Any? { val field = owner.javaClass.getDeclaredField(name); field.isAccessible = true; return field.get(owner) }
    private fun seed(state: CartObserverPose.State) {
        check(state.update({ _, _, _, _ -> false }, 10.0, 20.0, 0.0, CartFootprint.WALK_FRONT, 1.0 / 60) != null, "visual reset fixture must seed a pose")
    }
    @Suppress("UNCHECKED_CAST") private fun lifecycle() {
        val visualType = Class.forName(CartObserverRender::class.java.name + "\$Visual")
        val constructor = visualType.getDeclaredConstructor(); constructor.isAccessible = true; val visual = constructor.newInstance()
        val bind = visualType.getDeclaredMethod("bind", zombie.inventory.InventoryItem::class.java, Int::class.javaPrimitiveType, Any::class.java); bind.isAccessible = true
        val state = value(visual, "pose") as CartObserverPose.State
        val first = unsafe.allocateInstance(zombie.inventory.types.InventoryContainer::class.java) as zombie.inventory.types.InventoryContainer
        val replacement = unsafe.allocateInstance(zombie.inventory.types.InventoryContainer::class.java) as zombie.inventory.types.InventoryContainer
        first.setID(71); replacement.setID(71)
        val connection = Any(); val reconnected = Any()
        bind.invoke(visual, first, 0, connection); seed(state); val accepted = value(state, "accepted")
        bind.invoke(visual, first, 0, connection)
        check(value(state, "accepted") === accepted, "stable item/floor/connection discarded current visual continuity")
        bind.invoke(visual, replacement, 0, connection)
        check(value(state, "accepted") == null && value(state, "rawPrevious") == null, "replaced cart with reused native ID retained the previous cart's pose")
        seed(state); replacement.setID(72); bind.invoke(visual, replacement, 0, connection)
        check(value(state, "accepted") == null, "same item object with changed native ID retained old pose")
        seed(state); bind.invoke(visual, replacement, 1, connection)
        check(value(state, "accepted") == null, "floor change retained a visual anchor on the old level")
        seed(state); bind.invoke(visual, replacement, 1, reconnected)
        check(value(state, "accepted") == null, "replacement client connection retained an old remote pose")
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val visualsField = CartObserverRender::class.java.getDeclaredField("visuals"); visualsField.isAccessible = true
        val visuals = visualsField.get(null) as MutableMap<IsoPlayer, Any>
        seed(state); visuals[player] = visual; CartMotionSync.reset(player)
        check(!visuals.containsKey(player) && value(state, "accepted") == null, "motion reset retained the actor's observer state")
        seed(state); visuals[player] = visual; CartMotionSync.clearAll()
        check(visuals.isEmpty() && value(state, "accepted") == null, "connection cleanup retained observer visual state")
    }
    /** Native producer/worker ordering contracts, checked on the real jar. */
    private fun instructions(type: Class<*>, method: String, descriptor: String?): List<String> {
        val result = ArrayList<String>()
        type.getResourceAsStream("/" + type.name.replace('.', '/') + ".class").use { stream ->
            ClassReader(stream).accept(object : ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(access: Int, name: String?, desc: String?, signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                    if (name != method || descriptor != null && descriptor != desc) return null
                    return object : MethodVisitor(Opcodes.ASM9) {
                        override fun visitMethodInsn(opcode: Int, owner: String?, name: String?, desc: String?, itf: Boolean) { result.add("$owner.$name") }
                        override fun visitFieldInsn(opcode: Int, owner: String?, name: String?, desc: String?) { if (opcode == Opcodes.PUTFIELD) result.add("set:$name") }
                    }
                }
            }, ClassReader.SKIP_DEBUG or ClassReader.SKIP_FRAMES)
        }
        return result
    }
    private fun before(code: List<String>, first: String, second: String) {
        check(code.indexOf(first) >= 0 && code.indexOf(second) > code.indexOf(first), "native ordering changed: $first before $second")
    }
    private fun ordering() {
        val sprite = instructions(zombie.iso.sprite.IsoSprite::class.java, "renderActiveModel", null)
        before(sprite, "zombie/core/skinnedmodel/ModelCameraRenderData.init", "zombie/core/SpriteRenderer.drawModel")
        val draw = instructions(zombie.core.textures.TextureDraw::class.java, "drawModel", null)
        before(draw, "zombie/core/skinnedmodel/model/ModelSlotRenderData.initModel", "java/util/concurrent/ExecutorService.submit")
        before(draw, "zombie/core/skinnedmodel/model/ModelSlotRenderData.initModel", "zombie/core/skinnedmodel/model/ModelSlotRenderData.init")
        val init = instructions(ModelSlotRenderData::class.java, "init", null)
        before(init, "set:squareDepth", "zombie/core/skinnedmodel/model/ModelSlotRenderData.initRenderData")
        before(init, "set:animPlayerAngle", "zombie/core/skinnedmodel/model/ModelSlotRenderData.initRenderData")
        val hook = instructions(Main.CartFloor::class.java, "enter", null)
        check(hook.contains("net/alexredby/pztoolkitjavapatches/CartObserverRender.prepare"), "pre-grounding pose hook missing")
    }
    @JvmStatic fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe"); field.isAccessible = true; unsafe = field.get(null) as Unsafe
        check(Main.CART_OBSERVER_SUPPORTED, "observer render bytecode is unsupported")
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CartObserverRenderTest::class.java.classLoader)
        snapshots(); lifecycle(); ordering()
        println("CART_OBSERVER_RENDER_PASS (real camera consumption, async slot pairing, pooling, item/connection lifecycle and native depth/order)")
        System.exit(0)
    }
}
