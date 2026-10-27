package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.core.Core;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemBodyLocation;

public final class ScriptItemPropertiesChecks {
    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Core.debug = false;
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ScriptItemPropertiesChecks.class.getClassLoader());
        var bridge = Exposer.getClassesWithGlobalLuaMethod().stream()
            .filter(type -> type.getName().equals("net.alexredby.pztoolkitjavapatches.ScriptItemProperties"))
            .findFirst().orElseThrow(() -> new AssertionError("ZombieBuddy did not discover the script bridge"));
        require(Path.of(bridge.getProtectionDomain().getCodeSource().getLocation().toURI())
            .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "bridge did not come from the built JAR");
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newTable();
        LuaManager.exposer = new LuaManager.Exposer(new KahluaConverterManager(), LuaManager.platform, LuaManager.env);
        Exposer.afterExposeAll();
        Object function = LuaManager.env.rawget("toolkitScriptCanBeEquipped");
        require(function != null, "ZombieBuddy did not register the Lua global");
        Object writableFunction = LuaManager.env.rawget("toolkitScriptCanBeWrite");
        require(writableFunction != null, "ZombieBuddy did not register the writable Lua global");
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;

        var script = new Item();
        require(ScriptItemProperties.SUPPORTED, "current native script Item hash is unsupported");
        require(Boolean.FALSE.equals(thread.call(function, new Object[]{null})), "nil script was not false");
        require(thread.call(writableFunction, new Object[]{null}) == null, "nil script writable property was not nil");
        for (boolean client : new boolean[]{false, true}) {
            GameClient.client = client;
            GameServer.server = !client;
            for (ItemBodyLocation slot : new ItemBodyLocation[]{null, ItemBodyLocation.BACK, ItemBodyLocation.SATCHEL, null}) {
                script.canBeEquipped = slot;
                require(Boolean.valueOf(slot != null).equals(thread.call(function, new Object[]{script})),
                    "Kahlua bridge did not read the live native slot on client/server");
                require(script.canBeEquipped == slot, "bridge changed the native script slot");
            }
            for (boolean writable : new boolean[]{false, true, false}) {
                script.canBeWrite = writable;
                require(Boolean.valueOf(writable).equals(thread.call(writableFunction, new Object[]{script})),
                    "Kahlua bridge did not read the live native writable property on client/server");
                require(script.canBeWrite == writable, "bridge changed the native writable property");
            }
        }
        script.canBeEquipped = ItemBodyLocation.BACK;
        require(!ScriptItemProperties.read(script, false), "unsupported bytecode exposed a wearable slot");
        require(script.canBeEquipped == ItemBodyLocation.BACK, "unsupported read changed the native slot");
        for (boolean writable : new boolean[]{false, true}) {
            script.canBeWrite = writable;
            require(ScriptItemProperties.readCanBeWrite(script, false) == null,
                "unsupported bytecode exposed a writable value");
            require(script.canBeWrite == writable, "unsupported read changed the native writable property");
        }
        GameClient.client = false;
        GameServer.server = false;
        System.out.println("SCRIPT_ITEM_PROPERTIES_CHECKS_PASS (live native script slot and writable property, no writes, non-debug client/server, nil/unsupported, ZombieBuddy scan and Kahlua)");
        System.exit(0);
    }
}
