package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaThread;
import sun.misc.Unsafe;
import zombie.Lua.LuaManager;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.network.GameClient;
import zombie.network.GameServer;

public final class MedicineCooldownChecks {
    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }

    private static Field field(Class<?> type, String name) throws Exception {
        Field result = type.getDeclaredField(name); result.setAccessible(true); return result;
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        var unsafe = (Unsafe)field(Unsafe.class, "theUnsafe").get(null);
        var player = (IsoPlayer)unsafe.allocateInstance(IsoPlayer.class);
        var timer = field(IsoGameCharacter.class, "effectiveEdibleBuffTimer");
        timer.setFloat(player, 57.25f);
        GameClient.client = false;

        // Discover and activate the built bridge before any direct call or constant reference.
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MedicineCooldownChecks.class.getClassLoader());
        var bridge = Exposer.getClassesWithGlobalLuaMethod().stream()
            .filter(type -> type.getName().equals("net.alexredby.pztoolkitjavapatches.MedicineCooldown"))
            .findFirst().orElseThrow(() -> new AssertionError("ZombieBuddy did not discover the annotated bridge"));
        require(Path.of(bridge.getProtectionDomain().getCodeSource().getLocation().toURI())
            .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "bridge did not come from the built JAR");
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newTable();
        var converters = new KahluaConverterManager();
        LuaManager.exposer = new LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env);
        Exposer.afterExposeAll();
        Object function = LuaManager.env.rawget("toolkitMedicineCooldown");
        require(function != null, "ZombieBuddy did not register the Lua global");
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        require(Double.valueOf(57.25).equals(thread.call(function, new Object[]{player})),
            "real Kahlua bridge did not return the exact native value");
        GameClient.client = true;
        require(thread.call(function, new Object[]{player}) == null, "Kahlua did not preserve unavailable as nil");
        GameClient.client = false;
        require(timer.getFloat(player) == 57.25f, "Lua bridge changed native cooldown");

        require(MedicineCooldown.SUPPORTED, "current native character hash is unsupported");
        for (float value : new float[]{0, .03125f, 123.456f, 280, Float.MAX_VALUE, -1,
                Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY}) {
            timer.setFloat(player, value);
            Double result = MedicineCooldown.cooldown(player);
            require(Float.isFinite(value) && value >= 0 ? Double.valueOf(value).equals(result) : result == null,
                "native cooldown was estimated, rounded or accepted invalid data: " + value);
            require(Float.floatToRawIntBits(timer.getFloat(player)) == Float.floatToRawIntBits(value),
                "getter changed native cooldown");
        }
        timer.setFloat(player, 57.25f);
        require(MedicineCooldown.read(player, false) == null, "unsupported bytecode exposed a value");
        require(MedicineCooldown.cooldown(null) == null, "null character exposed a value");
        GameServer.server = true;
        require(Double.valueOf(57.25).equals(MedicineCooldown.cooldown(player)),
            "authoritative Host server did not expose its exact cooldown");
        GameClient.client = true;
        require(MedicineCooldown.cooldown(player) == null, "MP client exposed a non-authoritative cooldown");
        require(timer.getFloat(player) == 57.25f, "unavailable reads changed native cooldown");
        GameClient.client = false;
        GameServer.server = false;
        System.out.println("MEDICINE_COOLDOWN_CHECKS_PASS (native field, no writes, invalid/unsupported/client/nil, ZombieBuddy scan and Kahlua)");
        System.exit(0);
    }
}
