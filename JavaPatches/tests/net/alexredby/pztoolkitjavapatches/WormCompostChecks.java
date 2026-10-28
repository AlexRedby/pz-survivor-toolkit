package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.jar.asm.Type;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.inventory.types.Food;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemTag;

public final class WormCompostChecks {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static Food food(Item script) {
        var food = new Food("Base", "Worm", "Worm", script);
        food.setScriptItem(script);
        food.setOffAge(4);
        food.setOffAgeMax(8);
        food.setAge(8);
        return food;
    }

    private static void nativeExposure() throws Exception {
        var listed = new HashSet<String>();
        boolean[] recursive = {false};
        try (var stream = LuaManager.Exposer.class.getResourceAsStream("LuaManager$Exposer.class")) {
            require(stream != null, "native exposure class bytes unavailable");
            new ClassReader(stream).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                    if (!name.equals("exposeAll")) return null;
                    return new MethodVisitor(Opcodes.ASM9) {
                        private String lastClass;
                        @Override public void visitLdcInsn(Object value) {
                            lastClass = value instanceof Type ? ((Type)value).getInternalName() : null;
                        }
                        @Override public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean isInterface) {
                            if (name.equals("setExposed") && lastClass != null) listed.add(lastClass);
                            if (name.equals("exposeLikeJavaRecursively")) recursive[0] = true;
                            lastClass = null;
                        }
                    };
                }
            }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        }
        require(listed.contains("java/util/HashSet") && listed.contains("zombie/scripting/objects/Item") && recursive[0],
            "production exposeAll does not expose the native Item/HashSet methods used by the Lua fix");
    }


    public static void main(String[] args) throws Exception {
        nativeExposure();
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newEnvironment();
        LuaManager.exposer = new LuaManager.Exposer(new KahluaConverterManager(), LuaManager.platform, LuaManager.env);
        var exposed = new Class<?>[]{Item.class, HashSet.class};
        for (var type : exposed) LuaManager.exposer.setExposed(type);
        for (var type : exposed) LuaManager.exposer.exposeLikeJavaRecursively(type, LuaManager.env);
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        var script = new Item();
        script.getTags().add(ItemTag.CANT_COMPOST);
        script.getTags().add(ItemTag.NO_COOKING_XP);
        var other = new Item();
        other.getTags().add(ItemTag.CANT_COMPOST);
        var existing = food(script);
        require(existing.hasTag(ItemTag.CANT_COMPOST), "native control did not retain the worm restriction");
        LuaManager.env.rawset("TestWormDefinition", script);
        LuaManager.env.rawset("TestCantCompost", ItemTag.CANT_COMPOST);
        thread.call(LuaCompiler.loadstring("Events={OnGameBoot={Add=function(fn) TestWormBoot=fn end}}; "
            + "ItemTag={CANT_COMPOST=TestCantCompost}; "
            + "ScriptManager={instance={FindItem=function(_,name) assert(name=='Base.Worm'); return TestWormDefinition end}}",
            "worm-test-setup", LuaManager.env), new Object[]{});
        var path = Path.of(System.getProperty("pz.test.project"))
            .resolve("PZSurvivorToolkit/42/media/lua/shared/000ToolkitWormCompost.lua");
        try (var reader = Files.newBufferedReader(path)) {
            thread.call(LuaCompiler.loadis(reader, "000ToolkitWormCompost.lua", LuaManager.env), new Object[]{});
        }
        for (int mode = 0; mode < 3; mode++) {
            GameClient.client = mode == 1;
            GameServer.server = mode == 2;
            script.getTags().add(ItemTag.CANT_COMPOST);
            thread.call(LuaManager.env.rawget("TestWormBoot"), new Object[]{});
            require(!script.hasTag(ItemTag.CANT_COMPOST), "Kahlua did not remove the native ItemTag from the real Set");
            require(!existing.hasTag(ItemTag.CANT_COMPOST), "existing Food retained a copied tag restriction");
            require(!food(script).hasTag(ItemTag.CANT_COMPOST), "new Food retained the tag restriction");
            require(script.hasTag(ItemTag.NO_COOKING_XP), "other native worm tag was removed");
            require(!script.hasTag(ItemTag.IS_COMPOSTABLE), "fresh worms were made directly compostable");
            require(other.hasTag(ItemTag.CANT_COMPOST), "another item lost its restriction");
            require(existing.isRotten(), "rotten worm control no longer reaches native rot eligibility");
            existing.setAge(0);
            require(existing.isFresh() && !existing.isRotten(), "fresh-worm breeding predicates changed");
            existing.setAge(8);
        }
        GameClient.client = GameServer.server = false;
        System.out.println("WORM_COMPOST_CHECKS_PASS (owned startup Lua in Kahlua mutates real ScriptItem Set; existing/new native Food reads, SP/client/server and unrelated restrictions)");
        System.exit(0);
    }
}
