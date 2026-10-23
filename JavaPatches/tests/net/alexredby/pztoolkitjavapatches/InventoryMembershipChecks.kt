package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread

object InventoryMembershipChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/InventoryMembership.lua",
                ),
            )
            .use { reader ->
                environment.rawset(
                    "TestInventoryMembership",
                    thread.call(
                        LuaCompiler.loadis(reader, "InventoryMembership.lua", environment),
                        emptyArray<Any?>(),
                    ),
                )
            }
        val first = zombie.inventory.ItemContainer()
        val second = zombie.inventory.ItemContainer()
        val nativeContainers = java.util.ArrayList<zombie.inventory.ItemContainer>()
        nativeContainers.add(first)
        if (!nativeContainers.contains(first) || nativeContainers.contains(second)) {
            throw AssertionError("Native container membership must use identity")
        }
        environment.rawset("TestReachableContainerA", first)
        environment.rawset("TestReachableContainerB", second)
        Files.newBufferedReader(root.resolve("tests/test_inventory_membership.lua")).use { reader ->
            thread.call(
                LuaCompiler.loadis(reader, "test_inventory_membership.lua", environment),
                emptyArray<Any?>(),
            )
        }
        System.out.println(
            "INVENTORY_MEMBERSHIP_CHECKS_PASS (same Lua helper and vectors in native Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
