package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.lang.instrument.ClassFileTransformer
import java.lang.instrument.Instrumentation
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.security.ProtectionDomain
import java.util.HexFormat
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

    internal data class OptimizerOverlay(val directory: Path, val clientClasspath: String)

    private fun classpathPaths(classpath: String): List<Path> {
        if (classpath.isBlank() || classpath.any { it == '\n' || it == '\r' || it == '\u0000' })
            throw IOException("Invalid Host optimizer classpath")
        return classpath.split(java.io.File.pathSeparatorChar).map { entry ->
            if (entry.isEmpty() || '*' in entry)
                throw IOException("Ambiguous Host optimizer classpath entry")
            Path.of(entry).toRealPath()
        }
    }

    // Authenticate the explicit launcher-owned directory without initializing any optimizer class.
    // Admission reuses the exact 770-property and 888-resource policy, not a directory name match.
    internal fun optimizerOverlay(): OptimizerOverlay? {
        val declared = System.getProperty("pz.optimizerTrial.overlay") ?: return null
        val directory = Path.of(declared)
        if (
            !directory.isAbsolute ||
                directory.normalize() != directory ||
                !Files.isDirectory(directory) ||
                directory.toRealPath() != directory
        )
            throw IOException("Host optimizer overlay must name a distinct canonical directory")
        val classpath = System.getProperty("java.class.path")
        if (classpathPaths(classpath).count { it == directory } != 1)
            throw IOException(
                "Host optimizer overlay must occur exactly once in the client classpath",
            )
        val loader = HostLoader::class.java.classLoader
        val source = loader.getResources("pzopt/Config.class").toList().singleOrNull()
        if (
            source == null ||
                source.protocol != "file" ||
                Path.of(source.toURI()).toRealPath() !=
                    directory.resolve("pzopt/Config.class").toRealPath()
        )
            throw IOException(
                "Host optimizer overlay differs from the effective client resource source",
            )
        val resource = "zombie/iso/IsoWorld.class"
        val pair = OptimizerCompatibility.alternatives.getValue(resource)
        val checksum =
            loader.getResourceAsStream(resource)?.use {
                HexFormat.of()
                    .formatHex(MessageDigest.getInstance("SHA-256").digest(it.readAllBytes()))
            }
        if (!OptimizerCompatibility.supports(resource, pair.nativeSha256, checksum))
            throw IOException(
                "Host optimizer overlay lacks the exact reviewed client profile/resources",
            )
        return OptimizerOverlay(directory, classpath)
    }

    private fun isolateOptimizer(
        command: List<String>,
        main: Int,
        overlay: OptimizerOverlay?,
    ): List<String> {
        if (overlay == null) return command
        val prefix = "-Djava.class.path="
        val indexes = (1 until main).filter { command[it].startsWith(prefix) }
        if (
            indexes.size != 1 ||
                (1 until main).any {
                    command[it] in
                        listOf("-cp", "-classpath", "--class-path", "-jar", "-Djava.class.path") ||
                        command[it].startsWith("--class-path=") ||
                        command[it].startsWith('@')
                }
        )
            throw IOException("Ambiguous native Host optimizer classpath arguments")
        val index = indexes.single()
        val original = command[index].substring(prefix.length)
        if (original != overlay.clientClasspath)
            throw IOException(
                "Native Host classpath differs from the authenticated client classpath",
            )
        val paths = classpathPaths(original)
        if (paths.count { it == overlay.directory } != 1)
            throw IOException(
                "Host optimizer overlay must occur exactly once in the child classpath",
            )
        val entries = original.split(java.io.File.pathSeparatorChar)
        val clean = entries.filterIndexed { i, _ -> paths[i] != overlay.directory }
        if (clean.isEmpty())
            throw IOException("Host optimizer isolation would remove the entire classpath")
        return ArrayList(command).also {
            it[index] = prefix + clean.joinToString(java.io.File.pathSeparator)
        }
    }

    @JvmStatic
    @Throws(IOException::class)
    fun prepare(builder: ProcessBuilder): ProcessBuilder {
        val jar = loaderJar()
        return configure(
            builder,
            jar,
            Agent.configDir(),
            HashMap(Agent.arguments),
            optimizerOverlay(),
        )
    }

    internal fun configure(
        builder: ProcessBuilder,
        jar: Path,
        config: Path,
        arguments: Map<String, String>,
        overlay: OptimizerOverlay? = null,
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
            if (
                overlay != null &&
                    inherited.any {
                        it in
                            listOf(
                                "-cp",
                                "-classpath",
                                "--class-path",
                                "-jar",
                                "-Djava.class.path",
                            ) ||
                            it.startsWith("--class-path=") ||
                            it.startsWith("-Djava.class.path=")
                    }
            )
                throw IOException("Inherited JVM options can override the isolated Host classpath")
            existing.addAll(inherited.filter { isLoader(it, jar) })
        }
        if (existing.size > 1)
            throw IOException(
                "Multiple ZombieBuddy loaders configured for Host; remove duplicate JVM options",
            )
        val updated = ArrayList(isolateOptimizer(command, main, overlay))
        if (existing.isEmpty()) updated.add(main, agentOption(jar, config, arguments))
        builder.command(updated)
        if (overlay != null)
            System.out.println(
                "[PZToolkitJavaPatches] Optimizer overlay excluded from native Host server classpath",
            )
        if (existing.isEmpty())
            System.out.println(
                "[PZToolkitJavaPatches] Host loader supplied to native server launch (saved approvals retained)",
            )
        return builder
    }
}
