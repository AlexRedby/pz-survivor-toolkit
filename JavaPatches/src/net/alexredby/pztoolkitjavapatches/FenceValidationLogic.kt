package net.alexredby.pztoolkitjavapatches

import java.lang.instrument.ClassFileTransformer
import java.lang.instrument.Instrumentation
import java.security.MessageDigest
import java.security.ProtectionDomain
import java.util.ArrayList
import java.util.Arrays
import java.util.Collections
import java.util.HexFormat
import java.util.LinkedHashSet
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import net.bytebuddy.jar.asm.*
import zombie.Lua.Event
import zombie.Lua.LuaManager
import zombie.audio.parameters.ParameterFenceTypeLow.FenceType
import zombie.debug.DebugType
import zombie.iso.sprite.IsoSpriteManager

/** State is accessed through FenceValidation's synchronized Java entry points. */
object FenceValidationLogic {
    @JvmField
    val SUPPORTED = BytecodeSupport.supports("zombie/iso/BrokenFences.class",
        "4368bbe6d2ec26198062bced328c3fef349e6be8e0f7184cbb9086de4cccc015")
        && BytecodeSupport.supports("zombie/Lua/Event.class",
            "cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952")
        && BytecodeSupport.supports("zombie/Lua/LuaEventManager.class",
            "9706f17e9b5e095a0e24230dc944de5d552fa62c997214636c4deb4957cf354b")
        && BytecodeSupport.supports("zombie/iso/IsoWorld.class",
            "5b7406a70f33578a47ff417b0b6aa7a2b7a5bebfa00487a60935303f5747fb71")
        && BytecodeSupport.supports("zombie/iso/sprite/IsoSpriteManager.class",
            "2b2a7b9de0ebd5fb4e346a998a1618503422ddffb8098caa365e8b626054e14a")
        && BytecodeSupport.supports("zombie/entity/components/spriteconfig/SpriteConfigManager.class",
            "ef52c9f6406c594784183ac8598db2bf3d4a8db7933981956e1d79d7b40ba10e")
        && BytecodeSupport.supports("zombie/core/properties/PropertyContainer.class",
            "bc236f8e9e4e0da8a86b0d1fd19ad8d44a040fe4f67d1baac77401b3b148bd77")
        && BytecodeSupport.supports("zombie/audio/parameters/ParameterFenceTypeLow\$FenceType.class",
            "8b69bc70ce19066b64ec887a049320046c2659b4727dd51d4038e4e756bcfd09")

    private const val TARGET = "zombie/iso/BrokenFences"
    private const val HELPER = "net/alexredby/pztoolkitjavapatches/FenceValidation"
    private const val HASH = "4368bbe6d2ec26198062bced328c3fef349e6be8e0f7184cbb9086de4cccc015"
    private val pending = LinkedHashSet<String?>()
    private var installed = false
    private var ready = false

    @JvmStatic
    fun install(supported: Boolean): Boolean {
        if (!supported) return false
        if (installed) return true
        val instrumentation = Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
            ?: return false
        if (!instrumentation.isRetransformClassesSupported) return false
        val transformer = object : ClassFileTransformer {
            override fun transform(loader: ClassLoader?, name: String?, type: Class<*>?,
                                   domain: ProtectionDomain?, bytes: ByteArray?): ByteArray? =
                // Foreign loads include Kotlin itself; do not resolve Intrinsics during its definition.
                if (TARGET.equals(name)) weave(bytes) else null
        }
        instrumentation.addTransformer(transformer, true)
        try {
            for (type in instrumentation.allLoadedClasses)
                if (type.name == TARGET.replace('/', '.')) instrumentation.retransformClasses(type)
            installed = true
            return true
        } catch (error: Exception) {
            instrumentation.removeTransformer(transformer)
            System.err.println("[PZToolkitJavaPatches] Disabled fence validation: $error")
            return false
        }
    }

    @JvmStatic
    fun registered(name: String?) {
        if (ready) validate(name) else pending.add(name)
    }

    @JvmStatic
    fun tilesLoaded() {
        if (ready) return
        ready = true
        val corrected = FenceProperties.tilesLoaded(IsoSpriteManager.instance, FenceValidation.SUPPORTED && TilePropertyNames.SUPPORTED)
        val checked = pending.size
        var missing = 0
        for (name in pending) if (validate(name)) missing++
        pending.clear()
        println("[PZToolkitJavaPatches] Fence validation ready: checked=$checked, missing=$missing, corrected=$corrected")
    }

    @JvmStatic
    fun reset() {
        pending.clear()
        ready = false
    }

    private fun validate(name: String?): Boolean {
        val properties = IsoSpriteManager.instance.getSprite(name).getProperties()
        if (properties.get("ThumpSound") == null
            && FenceType.fromString(properties.get("FenceTypeLow"), null) == null) {
            DebugType.Sound.error("Missing ThumpSound for breakable object $name")
            return true
        }
        return false
    }

    // HotSpot reorders methods and Code attributes; compare the whole class after ASM serialization.
    private fun canonical(bytes: ByteArray?): ByteArray {
        val reader = ClassReader(bytes)
        val writer = ClassWriter(reader, 0)
        val methods = ArrayList<String>()
        reader.accept(object : ClassVisitor(Opcodes.ASM9, writer) {
            override fun visitMethod(access: Int, name: String, descriptor: String,
                                     signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                methods.add(name + descriptor)
                return null
            }
            override fun visitEnd() {}
        }, 0)
        Collections.sort(methods)
        for (key in methods) {
            reader.accept(object : ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(access: Int, name: String, descriptor: String,
                                         signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                    if (key != name + descriptor) return null
                    return object : MethodVisitor(Opcodes.ASM9,
                        writer.visitMethod(access, name, descriptor, signature, exceptions)) {}
                }
            }, 0)
        }
        writer.visitEnd()
        return writer.toByteArray()
    }

    @JvmStatic
    fun weave(bytes: ByteArray?): ByteArray? {
        try {
            val original = FenceValidation::class.java.classLoader.getResourceAsStream("$TARGET.class").use { input ->
                if (input == null) return null
                input.readAllBytes()
            }
            if (HASH != HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(original))
                || !Arrays.equals(canonical(original), canonical(bytes))) return null
            val reader = ClassReader(bytes)
            val writer = ClassWriter(reader, 0)
            val replacements = IntArray(2)
            reader.accept(object : ClassVisitor(Opcodes.ASM9, writer) {
                override fun visitMethod(access: Int, name: String, descriptor: String,
                                         signature: String?, exceptions: Array<out String>?): MethodVisitor {
                    val output = super.visitMethod(access, name, descriptor, signature, exceptions)
                    if (name == "Reset" && descriptor == "()V") {
                        return object : MethodVisitor(Opcodes.ASM9, output) {
                            override fun visitInsn(opcode: Int) {
                                if (opcode == Opcodes.RETURN) {
                                    super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "reset", "()V", false)
                                    replacements[1]++
                                }
                                super.visitInsn(opcode)
                            }
                        }
                    }
                    if (name != "addBrokenTiles" || descriptor != "(Lse/krka/kahlua/j2se/KahluaTableImpl;)V") return output
                    return object : MethodVisitor(Opcodes.ASM9, output) {
                        private var skip = 0
                        private fun skipInstruction(): Boolean {
                            if (skip == 0) return false
                            skip--
                            return true
                        }
                        override fun visitFieldInsn(opcode: Int, owner: String, field: String, type: String) {
                            if (skipInstruction()) return
                            if (opcode == Opcodes.GETSTATIC && owner == "zombie/iso/sprite/IsoSpriteManager" && field == "instance") {
                                super.visitVarInsn(Opcodes.ALOAD, 3)
                                super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "registered", "(Ljava/lang/String;)V", false)
                                skip = 10
                                replacements[0]++
                            } else super.visitFieldInsn(opcode, owner, field, type)
                        }
                        override fun visitVarInsn(opcode: Int, variable: Int) {
                            if (!skipInstruction()) super.visitVarInsn(opcode, variable)
                        }
                        override fun visitMethodInsn(opcode: Int, owner: String, method: String, type: String, itf: Boolean) {
                            if (!skipInstruction()) super.visitMethodInsn(opcode, owner, method, type, itf)
                        }
                        override fun visitLdcInsn(value: Any?) {
                            if (!skipInstruction()) super.visitLdcInsn(value)
                        }
                        override fun visitJumpInsn(opcode: Int, label: Label) {
                            if (!skipInstruction()) super.visitJumpInsn(opcode, label)
                        }
                        override fun visitInvokeDynamicInsn(method: String, type: String, handle: Handle, vararg args: Any) {
                            if (!skipInstruction()) super.visitInvokeDynamicInsn(method, type, handle, *args)
                        }
                    }
                }
            }, 0)
            return if (replacements[0] == 1 && replacements[1] == 1) writer.toByteArray() else null
        } catch (error: Exception) {
            System.err.println("[PZToolkitJavaPatches] Disabled fence bytecode: $error")
            return null
        }
    }

    @JvmStatic
    fun dispatched(event: String?, manager: Any?) {
        // Empty events bypass Event.trigger; queued callbacks complete through its separate advice.
        if (FenceValidation.SUPPORTED && event == "OnLoadedTileDefinitions"
            && manager === IsoSpriteManager.instance && LuaManager.env != null && LuaManager.thread != null
            && LuaManager.thread.debugOwnerThread === Thread.currentThread())
            FenceValidation.tilesLoaded()
    }

    @JvmStatic
    fun triggered(event: Event?, args: Array<out Any?>?) {
        if (FenceValidation.SUPPORTED && (event ?: throw NullPointerException()).name == "OnLoadedTileDefinitions"
            && args != null && args.size == 1 && args[0] === IsoSpriteManager.instance)
            FenceValidation.tilesLoaded()
    }
}
