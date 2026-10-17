package net.alexredby.javapatchfixture;

import java.lang.instrument.Instrumentation;
import java.nio.file.Path;

/** Run from an isolated test directory beside the built mod JAR, without the other regression classes. */
public final class CartBootstrapCheck {
    private static boolean loaded(Instrumentation instrumentation,String name) {
        for(var type:instrumentation.getAllLoadedClasses()) if(type.getName().equals(name)) return true;
        return false;
    }

    public static void main(String[] args) throws Exception {
        var field=Class.forName("me.zed_0xff.zombie_buddy.Loader").getDeclaredField("g_instrumentation");
        field.setAccessible(true);
        var instrumentation=(Instrumentation)field.get(null);
        String target="zombie.core.skinnedmodel.ModelManager";
        var loader=CartBootstrapCheck.class.getClassLoader();
        for(String name:new String[]{"zombie.characters.IsoGameCharacter","zombie.characters.IsoPlayer",
                "zombie.core.skinnedmodel.model.ModelSlotRenderData","zombie.core.skinnedmodel.model.ItemModelRenderer",
                "zombie.core.skinnedmodel.model.Model","zombie.core.skinnedmodel.model.ModelMesh","zombie.iso.IsoGridSquare"})
            Class.forName(name,false,loader);
        if(loaded(instrumentation,target)) throw new AssertionError("bootstrap fixture preloaded the target before mod main");
        var main=Class.forName("net.alexredby.pztoolkitjavapatches.Main");
        if(!Path.of(main.getProtectionDomain().getCodeSource().getLocation().toURI()).toString().endsWith(".jar"))
            throw new AssertionError("bootstrap must use the built mod JAR");
        main.getMethod("main",String[].class).invoke(null,(Object)new String[0]);
        if(!loaded(instrumentation,target)) throw new AssertionError("mod main did not define the cold model target before patch registration");
        Class.forName("me.zed_0xff.zombie_buddy.PatchEngine").getMethod("applyPatches",String.class,ClassLoader.class)
            .invoke(null,"net.alexredby.pztoolkitjavapatches",loader);
        System.out.println("CART_BOOTSTRAP_PASS (cold built-JAR target defined by mod main before patch registration)");
    }
}
