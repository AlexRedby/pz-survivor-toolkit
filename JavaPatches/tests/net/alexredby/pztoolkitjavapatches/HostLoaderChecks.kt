package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.lang.instrument.ClassFileTransformer
import java.lang.instrument.Instrumentation
import java.lang.reflect.InvocationTargetException
import java.nio.file.Files
import java.nio.file.Path
import java.security.ProtectionDomain
import java.util.concurrent.TimeUnit
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Agent
import me.zed_0xff.zombie_buddy.Loader
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import zombie.ZomboidFileSystem
import zombie.network.CoopMaster

object HostLoaderChecks {
    private lateinit var captured: List<String>

    @JvmStatic
    fun capture(builder: ProcessBuilder): Process {
        captured = ArrayList(builder.command())
        throw IOException("host-launch-captured")
    }

    private fun builder(vararg extra: String): ProcessBuilder =
        ProcessBuilder(
                arrayListOf(
                    "java",
                    "-Xmx1024m",
                    *extra,
                    "zombie.network.GameServer",
                    "-coop",
                    "-servername",
                    "fixture with spaces",
                ),
            )
            .also {
                for (key in listOf("JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS")) it
                    .environment()
                    .remove(key)
            }

    private fun rejects(body: () -> Unit) {
        try {
            body()
        } catch (_: IOException) {
            return
        }
        throw AssertionError("unsafe Host loader options accepted")
    }

    private fun policies(jar: Path, config: Path) {
        val b = builder()
        val original = ArrayList(b.command())
        val env = HashMap(b.environment())
        val settings =
            mapOf(
                "policy" to "deny-new",
                "allow_unsigned_mods" to "false",
                "verbosity" to "2",
                "exit_after_game_init" to "",
                "patches_jar" to "do-not-propagate:client.only",
            )
        check(HostLoader.configure(b, jar, config, settings) === b)
        val added = b.command().single { it.startsWith("-javaagent:") }
        check(added.contains("config_dir=$config") && added.contains("policy=deny-new"))
        check(
            added.contains("allow_unsigned_mods=false") &&
                !added.contains("exit_after") &&
                !added.contains("patches_jar"),
        )
        check(b.command().filter { it != added } == original && b.environment() == env)
        HostLoader.configure(b, jar, config, settings)
        check(b.command().count { it.startsWith("-javaagent:") } == 1)
        for (loader in
            listOf(
                "-agentlib:zbNative",
                "-agentpath:C:\\Game With Spaces\\zbNative.dll",
                "-javaagent:$jar=policy=deny-new",
                "-agentpath:/game/libzbnative.so",
            )) {
            val explicit = builder(loader)
            val before = ArrayList(explicit.command())
            HostLoader.configure(explicit, jar, config, settings)
            check(explicit.command() == before)
        }
        for (key in listOf("JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS")) {
            val inherited = builder()
            inherited.environment()[key] =
                "-Dunrelated=kept -agentpath:\"C:\\Game With Spaces\\zbNative.dll\""
            val before = ArrayList(inherited.command())
            val beforeEnv = HashMap(inherited.environment())
            HostLoader.configure(inherited, jar, config, settings)
            check(before == inherited.command() && beforeEnv == inherited.environment())
        }
        val duplicate = builder("-agentlib:zbNative")
        duplicate.environment()["JDK_JAVA_OPTIONS"] = "-javaagent:\"$jar\""
        rejects { HostLoader.configure(duplicate, jar, config, settings) }
        rejects { HostLoader.options("-Dopen=\"unfinished") }
        rejects { HostLoader.agentOption(jar, config.resolve("comma,folder"), settings) }
        rejects { HostLoader.agentOption(jar.resolveSibling("bad=loader.jar"), config, settings) }
        val argumentFile = builder()
        argumentFile.environment()["JDK_JAVA_OPTIONS"] = "@hidden-agent-options"
        rejects { HostLoader.configure(argumentFile, jar, config, settings) }
        val foreign = ProcessBuilder("java", "other.Main", "zombie.network.GameServer")
        val before = ArrayList(foreign.command())
        HostLoader.configure(foreign, jar, config, settings)
        check(foreign.command() == before)
        val dedicated =
            ProcessBuilder("java", "zombie.network.GameServer", "-servername", "dedicated")
        val dedicatedBefore = ArrayList(dedicated.command())
        HostLoader.configure(dedicated, jar, config, settings)
        check(dedicated.command() == dedicatedBefore)
        val otherAgent = builder("-javaagent:/other/Profiler.jar")
        HostLoader.configure(otherAgent, jar, config, settings)
        check(otherAgent.command().contains("-javaagent:/other/Profiler.jar"))
    }

    private fun nativeBoundary(instrumentation: Instrumentation) {
        val original =
            CoopMaster::class
                .java
                .classLoader
                .getResourceAsStream("zombie/network/CoopMaster.class")!!
                .use { it.readAllBytes() }
        val woven = HostLoader.weave(original)!!
        check(!woven.contentEquals(original) && HostLoader.weave(woven) == null)
        var injections = 0
        ClassReader(woven)
            .accept(
                object : ClassVisitor(Opcodes.ASM9) {
                    override fun visitMethod(
                        access: Int,
                        name: String?,
                        descriptor: String?,
                        signature: String?,
                        exceptions: Array<out String>?,
                    ): MethodVisitor =
                        object : MethodVisitor(Opcodes.ASM9) {
                            override fun visitMethodInsn(
                                opcode: Int,
                                owner: String?,
                                method: String?,
                                desc: String?,
                                itf: Boolean,
                            ) {
                                if (
                                    owner == "net/alexredby/pztoolkitjavapatches/HostLoader" &&
                                        method == "prepare"
                                ) {
                                    check(
                                        name == "launchServer" &&
                                            descriptor ==
                                                "(Ljava/lang/String;Ljava/lang/String;IZ)V",
                                    )
                                    injections++
                                }
                            }
                        }
                },
                0,
            )
        check(injections == 1)
        // Test-only interception AFTER the production prepare hook. Exercise both real native
        // public entrypoints, but do not start a game server, touch a world or create its threads.
        val capture =
            object : ClassFileTransformer {
                override fun transform(
                    loader: ClassLoader?,
                    name: String?,
                    type: Class<*>?,
                    domain: ProtectionDomain?,
                    bytes: ByteArray?,
                ): ByteArray? {
                    if (name != "zombie/network/CoopMaster") return null
                    val reader = ClassReader(bytes)
                    val writer = ClassWriter(reader, 0)
                    reader.accept(
                        object : ClassVisitor(Opcodes.ASM9, writer) {
                            override fun visitMethod(
                                access: Int,
                                name: String?,
                                descriptor: String?,
                                signature: String?,
                                exceptions: Array<out String>?,
                            ): MethodVisitor? {
                                val output =
                                    super.visitMethod(
                                        access,
                                        name,
                                        descriptor,
                                        signature,
                                        exceptions,
                                    )
                                if (
                                    name != "launchServer" ||
                                        descriptor != "(Ljava/lang/String;Ljava/lang/String;IZ)V"
                                )
                                    return output
                                return object : MethodVisitor(Opcodes.ASM9, output) {
                                    override fun visitMethodInsn(
                                        opcode: Int,
                                        owner: String?,
                                        method: String?,
                                        desc: String?,
                                        itf: Boolean,
                                    ) {
                                        if (
                                            owner == "java/lang/ProcessBuilder" && method == "start"
                                        )
                                            super.visitMethodInsn(
                                                Opcodes.INVOKESTATIC,
                                                "net/alexredby/pztoolkitjavapatches/HostLoaderChecks",
                                                "capture",
                                                "(Ljava/lang/ProcessBuilder;)Ljava/lang/Process;",
                                                false,
                                            )
                                        else super.visitMethodInsn(opcode, owner, method, desc, itf)
                                    }
                                }
                            }
                        },
                        0,
                    )
                    return writer.toByteArray()
                }
            }
        instrumentation.addTransformer(capture, true)
        try {
            instrumentation.retransformClasses(CoopMaster::class.java)
            for (entry in listOf("launchServer", "softreset")) {
                try {
                    CoopMaster::class
                        .java
                        .getMethod(
                            entry,
                            String::class.java,
                            String::class.java,
                            Int::class.javaPrimitiveType,
                        )
                        .invoke(CoopMaster.instance, "fixture", "fixture", 256)
                    error("Native Host launch escaped capture")
                } catch (error: InvocationTargetException) {
                    check(
                        error.cause is IOException &&
                            error.cause?.message == "host-launch-captured",
                    ) {
                        error.cause.toString()
                    }
                }
                check(captured.count { it.startsWith("-javaagent:") } == 1)
                check(("-Dsoftreset" in captured) == (entry == "softreset"))
                check("zombie.network.GameServer" in captured && "-coop" in captured)
            }
        } finally {
            instrumentation.removeTransformer(capture)
            instrumentation.retransformClasses(CoopMaster::class.java)
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.firstOrNull() == "child") {
            check(
                Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null) !=
                    null,
            )
            check(Agent.configDir().toAbsolutePath().normalize() == Path.of(args[1]))
            check(Agent.arguments["policy"] == "deny-new")
            println("HOST_CHILD_AGENT_ACTIVE")
            return
        }
        val cache = Path.of(System.getProperty("pz.test.cache"))
        ZomboidFileSystem.instance.setCacheDir(cache.toString())
        val jar =
            Path.of(Agent::class.java.protectionDomain.codeSource.location.toURI())
                .toAbsolutePath()
                .normalize()
        val config = cache.resolve("approval directory with spaces")
        Files.createDirectories(config)
        policies(jar, config)
        check(HostLoader.install() && HostLoader.install())
        val instrumentation =
            Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)!!
        nativeBoundary(instrumentation)
        // Launch a real bundled-JVM child with only the automatically supplied agent. No inherited
        // loader or approval bypass; it must initialize the original ZombieBuddy premain itself.
        val child = builder()
        child.command(
            arrayListOf(
                Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-cp",
                System.getProperty("java.class.path"),
                "zombie.network.GameServer",
                "-coop",
            ),
        )
        HostLoader.configure(child, jar, config, mapOf("policy" to "deny-new"))
        val command = ArrayList(child.command())
        val main = command.indexOf("zombie.network.GameServer")
        command[main] = HostLoaderChecks::class.java.name
        command[main + 1] = "child"
        command.add(config.toString())
        val output = cache.resolve("host-child.log")
        child.command(command).redirectErrorStream(true).redirectOutput(output.toFile())
        val process = child.start()
        try {
            check(process.waitFor(30, TimeUnit.SECONDS)) { "Child loader timed out" }
            val text = Files.readString(output)
            check(process.exitValue() == 0 && "HOST_CHILD_AGENT_ACTIVE" in text) { text }
        } finally {
            if (process.isAlive) process.destroyForcibly().waitFor()
        }
        println(
            "HOST_LOADER_CHECKS_PASS (native Host/softreset boundary, idempotency, inherited/explicit loaders, approval policy, unrelated processes and real agent child)",
        )
    }
}
