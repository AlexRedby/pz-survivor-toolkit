package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import zombie.core.opengl.RenderThread;
import zombie.core.opengl.ShaderProgram;
import zombie.core.skinnedmodel.model.ModelOutlines;

/** Prepare only the native outline composite programs before the first world frame. */
public final class OutlineShaderPreparation {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/gameStates/IngameState.class",
            "07e35d9e04faa98aad8a7059e5bf82590e4d679f30941ca2469afe1555e3c10c")
            && BytecodeSupport.supports("zombie/core/skinnedmodel/model/ModelOutlines.class",
            "d73dc43bee39330a325ce816f49b69e822238d3da1e2051936b9c1d650441788")
            && BytecodeSupport.supports("zombie/core/opengl/RenderThread.class",
            "69c794b6b8d4d4108d73ff618e7a8787b4395b99dcd737c254d83526835b1fca")
            && BytecodeSupport.supports("zombie/core/opengl/ShaderProgram.class",
            "062a78360dab7245283099312d88d09c216da5ae5c0b4deb5edd3f4a08afb621")
            && BytecodeSupport.supports("zombie/core/opengl/ShaderUnit.class",
            "fbc3aa3aea91b2bf17f25181de411d240e5e202b0a5c7a65183b7afd0fe54255");
    // ModelOutlines owns these programs for the process lifetime; its resize path only replaces FBOs.
    // All reads/writes below run on the same render context as its lazy initialization.
    private static boolean attempted;

    private OutlineShaderPreparation() { }

    /** Called on normal completion of IngameState.enter, before its first world render. */
    public static void prepareAfterLoad() {
        if (!SUPPORTED) return;
        try {
            RenderThread.invokeOnRenderContext(OutlineShaderPreparation::prepareOnRenderContext);
        } catch (Exception | LinkageError error) {
            System.err.println("[PZToolkitJavaPatches] Outline shader preparation skipped: " + error);
        }
    }

    private static void prepareOnRenderContext() {
        if (attempted) return;
        attempted = true; // Includes reentry and a failed attempt; normal lazy initialization stays available.
        ShaderProgram[] programs = new ShaderProgram[3];
        boolean published = false;
        try {
            ModelOutlines outlines = ModelOutlines.instance;
            Field horizontal = shaderField("thickenHShader");
            Field vertical = shaderField("thickenVShader");
            Field blit = shaderField("blitShader");
            // An earlier renderer or another mod may already own the native cache.
            if (horizontal.get(outlines) != null || vertical.get(outlines) != null || blit.get(outlines) != null) return;
            String[] names = {"aim_outline_h", "aim_outline_v", "aim_outline_blit"};
            for (int i = 0; i < names.length; i++) {
                programs[i] = ShaderProgram.createShaderProgram(names[i], false, false, true);
                if (programs[i] == null || !programs[i].isCompiled()) {
                    throw new IllegalStateException("Outline program did not compile: " + names[i]);
                }
            }
            // Native endFrame uses horizontal as the all-three-ready sentinel.
            vertical.set(outlines, programs[1]);
            blit.set(outlines, programs[2]);
            horizontal.set(outlines, programs[0]);
            published = true;
            System.out.println("[PZToolkitJavaPatches] Outline composite shaders prepared on render context: 3");
        } catch (Exception | LinkageError error) {
            System.err.println("[PZToolkitJavaPatches] Outline shader preparation skipped: " + error);
        } finally {
            if (!published) {
                for (ShaderProgram program : programs) {
                    if (program == null) continue;
                    try { program.destroy(); }
                    catch (Exception | LinkageError error) {
                        System.err.println("[PZToolkitJavaPatches] Outline shader cleanup failed: " + error);
                    }
                }
            }
        }
    }

    private static Field shaderField(String name) throws ReflectiveOperationException {
        Field field = ModelOutlines.class.getDeclaredField(name);
        if (field.getType() != ShaderProgram.class) throw new NoSuchFieldException(name);
        field.setAccessible(true);
        return field;
    }
}
