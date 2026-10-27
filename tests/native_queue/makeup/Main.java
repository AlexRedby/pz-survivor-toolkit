package net.alexredby.makeupcapturefixture;

import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.security.MessageDigest;
import java.util.HexFormat;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel;
import zombie.ui.UI3DModel;
import zombie.network.GameClient;

/** Test-only observation. No constructors, rendering, actor writes or debug-mode reflection. */
public final class Main {
    private static final boolean NATIVE_SUPPORTED =
        supports("zombie/ui/UI3DModel.class", "c71f4d2ce3c7de6c1e36b39810e9314e94284cbc6f675f822230eb2a1297e936")
        && supports("zombie/core/skinnedmodel/advancedanimation/AnimatedModel.class", "7bf82e3342c8aa7f9df5153646754339c19918f67480122b47f11a639db977d4");
    private static final Field MODEL = modelField();

    private static boolean supports(String resource, String expected) {
        try (InputStream stream = Main.class.getClassLoader().getResourceAsStream(resource)) {
            return stream != null && expected.equals(HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes())));
        } catch (Exception unavailable) {
            return false;
        }
    }

    private static Field modelField() {
        if (!NATIVE_SUPPORTED) return null;
        try {
            Field field = UI3DModel.class.getDeclaredField("animatedModel");
            return field.getType() == AnimatedModel.class && Modifier.isFinal(field.getModifiers())
                && field.trySetAccessible() ? field : null;
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return null;
        }
    }

    @LuaMethod(name="makeupAvatarCaptureSupported", global=true)
    public static boolean supported() {
        return NATIVE_SUPPORTED && MODEL != null;
    }

    /** Mirrors the native clothing packet's connection gate without changing it. */
    @LuaMethod(name="makeupClientReady", global=true)
    public static boolean clientReady() {
        return !GameClient.client || GameClient.connection != null && GameClient.connection.isReady();
    }

    @LuaMethod(name="makeupAvatarRendered", global=true)
    public static boolean rendered(UI3DModel ui) {
        if (!supported() || ui == null || ui.getClass() != UI3DModel.class) return false;
        try {
            Object value = MODEL.get(ui);
            if (value == null || value.getClass() != AnimatedModel.class) return false;
            AnimatedModel model = (AnimatedModel)value;
            // isReadyToRender alone omits texture-creator readiness. isRendered is the
            // native completed render-state flag, not UI3DModel.Drawer.rendered.
            return model.isReadyToRender() && model.isRendered();
        } catch (IllegalAccessException | RuntimeException unavailable) {
            return false;
        }
    }

    public static void main(String[] args) throws Exception {
        if (!supported() || rendered(null)) throw new AssertionError("native capture guard/field failed");
        LuaMethod annotation = Main.class.getMethod("rendered", UI3DModel.class).getAnnotation(LuaMethod.class);
        if (annotation == null || !annotation.global() || !annotation.name().equals("makeupAvatarRendered"))
            throw new AssertionError("test-only capture Lua method missing");
        // Inspect registration only: do not initialize or query GameClient outside a game.
        LuaMethod ready = Main.class.getMethod("clientReady").getAnnotation(LuaMethod.class);
        if (ready == null || !ready.global() || !ready.name().equals("makeupClientReady"))
            throw new AssertionError("test-only connection-readiness Lua method missing");
        System.out.println("MAKEUP_AVATAR_CAPTURE_CHECKS_PASS (native class hashes/field and nil; no GL)");
    }

    private Main() {}
}
