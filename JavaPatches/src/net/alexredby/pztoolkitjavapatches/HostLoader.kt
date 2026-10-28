package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.lang.instrument.ClassFileTransformer
import java.lang.instrument.Instrumentation
import java.nio.file.Files
import java.nio.file.Path
import java.security.ProtectionDomain
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Agent
import me.zed_0xff.zombie_buddy.Loader
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes

/**
 * Supply the loader only at the native Host/soft-reset child launch, never ProcessBuilder globally.
 */
object HostLoader {
    private const val TARGET = "zombie/network/CoopMaster"
    private const val METHOD = "(Ljava/lang/String;Ljava/lang/String;IZ)V"
    private const val HELPER = "net/alexredby/pztoolkitjavapatches/HostLoader"
    private const val HASH = "02f6659b2e96c2e4309a9fa0752f6a91da97898d85c4ed60f662e63055a4854d"
    @JvmField val SUPPORTED = BytecodeSupport.supports("$TARGET.class", HASH)
    private var installed = false
    @Volatile private var woven = false

    @JvmStatic
    @Synchronized
    fun install(): Boolean {
        if (installed) return woven
        if (!SUPPORTED) return false
        val instrumentation =
            Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
                ?: return false
        if (!instrumentation.isRetransformClassesSupported) return false
        val transformer =
            object : ClassFileTransformer {
                override fun transform(
                    loader: ClassLoader?,
                    name: String?,
                    type: Class<*>?,
                    domain: ProtectionDomain?,
                    bytes: ByteArray?,
                ): ByteArray? {
                    if (name != TARGET) return null
                    val result = weave(bytes)
                    woven = result != null
                    if (!woven)
                        System.err.println(
                            "[PZToolkitJavaPatches] Host loader disabled: native launch changed",
                        )
                    return result
                }
            }
        instrumentation.addTransformer(transformer, true)
        try {
            val loaded =
                instrumentation.allLoadedClasses.firstOrNull { it.name == TARGET.replace('/', '.') }
            if (loaded != null) instrumentation.retransformClasses(loaded)
            else Class.forName(TARGET.replace('/', '.'), false, HostLoader::class.java.classLoader)
            if (woven) {
                installed = true
                return true
            }
        } catch (error: Exception) {
            System.err.println("[PZToolkitJavaPatches] Host loader disabled: $error")
        } catch (error: LinkageError) {
            System.err.println("[PZToolkitJavaPatches] Host loader disabled: $error")
        }
        instrumentation.removeTransformer(transformer)
        woven = false
        return false
    }

    // Compare the actual launch body to the pinned original, tolerating debug/constant-pool
    // layout differences but not a third party's edits to this launch boundary.
    private fun launchBody(bytes: ByteArray): ByteArray {
        val writer = ClassWriter(0)
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, TARGET, null, "java/lang/Object", null)
        ClassReader(bytes)
            .accept(
                object : ClassVisitor(Opcodes.ASM9) {
                    override fun visitMethod(
                        access: Int,
                        name: String?,
                        descriptor: String?,
                        signature: String?,
                        exceptions: Array<out String>?,
                    ): MethodVisitor? =
                        if (name == "launchServer" && descriptor == METHOD)
                            writer.visitMethod(access, name, descriptor, signature, exceptions)
                        else null
                },
                ClassReader.SKIP_DEBUG,
            )
        writer.visitEnd()
        return writer.toByteArray()
    }

    internal fun weave(bytes: ByteArray?): ByteArray? {
        if (!SUPPORTED || bytes == null) return null
        val original =
            HostLoader::class.java.classLoader.getResourceAsStream("$TARGET.class")?.use {
                it.readAllBytes()
            } ?: return null
        if (!launchBody(original).contentEquals(launchBody(bytes))) return null
        val reader = ClassReader(bytes)
        val writer = ClassWriter(reader, 0)
        var calls = 0
        reader.accept(
            object : ClassVisitor(Opcodes.ASM9, writer) {
                override fun visitMethod(
                    access: Int,
                    name: String?,
                    descriptor: String?,
                    signature: String?,
                    exceptions: Array<out String>?,
                ): MethodVisitor? {
                    val output = super.visitMethod(access, name, descriptor, signature, exceptions)
                    if (name != "launchServer" || descriptor != METHOD) return output
                    return object : MethodVisitor(Opcodes.ASM9, output) {
                        override fun visitMethodInsn(
                            opcode: Int,
                            owner: String?,
                            name: String?,
                            descriptor: String?,
                            itf: Boolean,
                        ) {
                            if (
                                opcode == Opcodes.INVOKEVIRTUAL &&
                                    owner == "java/lang/ProcessBuilder" &&
                                    name == "start" &&
                                    descriptor == "()Ljava/lang/Process;"
                            ) {
                                calls++
                                super.visitMethodInsn(
                                    Opcodes.INVOKESTATIC,
                                    HELPER,
                                    "prepare",
                                    "(Ljava/lang/ProcessBuilder;)Ljava/lang/ProcessBuilder;",
                                    false,
                                )
                            }
                            super.visitMethodInsn(opcode, owner, name, descriptor, itf)
                        }
                    }
                }
            },
            0,
        )
        return if (calls == 1) writer.toByteArray() else null
    }

    private fun loaderJar(): Path =
        Path.of(Agent::class.java.protectionDomain.codeSource.location.toURI())
            .toAbsolutePath()
            .normalize()
            .also {
                if (!Files.isRegularFile(it))
                    throw IOException("ZombieBuddy loader JAR is unavailable: $it")
            }

    // JVM environment options accept quoted paths; quotes are syntax, not part of the path.
    internal fun options(text: String): List<String> {
        val result = ArrayList<String>()
        val token = StringBuilder()
        var quote: Char? = null
        for (c in text) {
            if (quote != null) {
                if (c == quote) quote = null else token.append(c)
            } else if (c == '"' || c == '\'') quote = c
            else if (c.isWhitespace()) {
                if (token.isNotEmpty()) {
                    result.add(token.toString())
                    token.setLength(0)
                }
            } else token.append(c)
        }
        if (quote != null) throw IOException("Unclosed quote in Host JVM environment options")
        if (token.isNotEmpty()) result.add(token.toString())
        return result
    }

    internal fun isLoader(option: String, jar: Path): Boolean {
        val prefix = option.substringBefore(':')
        if (prefix !in listOf("-javaagent", "-agentpath", "-agentlib")) return false
        val path = option.substringAfter(':').substringBefore('=')
        val name = path.replace('\\', '/').substringAfterLast('/').lowercase()
        return if (prefix == "-javaagent")
            name == "zombiebuddy.jar" ||
                runCatching { Path.of(path).toAbsolutePath().normalize() == jar }
                    .getOrDefault(false)
        else name in listOf("zbnative", "zbnative.dll", "libzbnative.so", "libzbnative.dylib")
    }

    internal fun agentOption(jar: Path, config: Path, arguments: Map<String, String>): String {
        if (jar.toString().any { it == '=' || it == '\n' || it == '\r' })
            throw IOException("ZombieBuddy JAR path cannot be represented as a JVM agent option")
        val values = linkedMapOf("config_dir" to config.toAbsolutePath().normalize().toString())
        for (key in
            listOf(
                "policy",
                "allow_unsigned_mods",
                "verbosity",
                "experimental",
                "frontend",
                "batch_approval_timeout",
            )) arguments[key]?.let { values[key] = it }
        // Agent arguments use comma separation without an escaping syntax. Never silently
        // truncate a custom approval directory or reinterpret a value as another loader option.
        if (values.values.any { ',' in it || '\n' in it || '\r' in it })
            throw IOException("Host loader options contain an unsupported comma or newline")
        return "-javaagent:$jar=" + values.entries.joinToString(",") { "${it.key}=${it.value}" }
    }

    @JvmStatic
    @Throws(IOException::class)
    fun prepare(builder: ProcessBuilder): ProcessBuilder {
        val jar = loaderJar()
        return configure(builder, jar, Agent.configDir(), HashMap(Agent.arguments))
    }

    internal fun configure(
        builder: ProcessBuilder,
        jar: Path,
        config: Path,
        arguments: Map<String, String>,
    ): ProcessBuilder {
        val command = builder.command()
        val main = command.indexOf("zombie.network.GameServer")
        // Only the reviewed native -coop command is eligible, including -Dsoftreset.
        if (
            main < 1 ||
                command.count { it == "zombie.network.GameServer" } != 1 ||
                command.getOrNull(main + 1) != "-coop"
        )
            return builder
        val existing = command.subList(1, main).filter { isLoader(it, jar) }.toMutableList()
        for (key in listOf("JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS")) {
            val inherited = options(builder.environment()[key] ?: "")
            if (inherited.any { it.startsWith('@') })
                throw IOException(
                    "Cannot verify Host loader in JVM environment argument files; use explicit JVM options",
                )
            existing.addAll(inherited.filter { isLoader(it, jar) })
        }
        if (existing.size > 1)
            throw IOException(
                "Multiple ZombieBuddy loaders configured for Host; remove duplicate JVM options",
            )
        if (existing.isNotEmpty()) return builder
        val updated = ArrayList(command)
        updated.add(main, agentOption(jar, config, arguments))
        builder.command(updated)
        System.out.println(
            "[PZToolkitJavaPatches] Host loader supplied to native server launch (saved approvals retained)",
        )
        return builder
    }
}
