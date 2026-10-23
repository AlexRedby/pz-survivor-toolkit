package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread

object QueueMembershipChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueMembership.lua",
                ),
            )
            .use { reader ->
                environment.rawset(
                    "TestQueueMembership",
                    thread.call(
                        LuaCompiler.loadis(reader, "ActionQueueMembership.lua", environment),
                        emptyArray<Any?>(),
                    ),
                )
            }
        Files.newBufferedReader(root.resolve("tests/test_action_queue_membership.lua")).use { reader
            ->
            thread.call(
                LuaCompiler.loadis(reader, "test_action_queue_membership.lua", environment),
                emptyArray<Any?>(),
            )
        }
        System.out.println(
            "QUEUE_MEMBERSHIP_CHECKS_PASS (same Lua helper and vectors in native Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
