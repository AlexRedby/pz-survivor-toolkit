package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

public final class InventoryMembershipChecks {
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var environment = platform.newEnvironment();
        var thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        try (var reader = Files.newBufferedReader(root.resolve(
                "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/InventoryMembership.lua"))) {
            environment.rawset("TestInventoryMembership", thread.call(
                    LuaCompiler.loadis(reader, "InventoryMembership.lua", environment), new Object[]{}));
        }
        try (var reader = Files.newBufferedReader(root.resolve("tests/test_inventory_membership.lua"))) {
            thread.call(LuaCompiler.loadis(reader, "test_inventory_membership.lua", environment), new Object[]{});
        }
        System.out.println("INVENTORY_MEMBERSHIP_CHECKS_PASS (same Lua helper and vectors in native Kahlua)");
        System.exit(0);
    }
}
