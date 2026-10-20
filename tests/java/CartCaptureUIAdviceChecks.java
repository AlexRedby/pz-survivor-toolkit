package net.alexredby.cartlabchecks;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.InvocationTargetException;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.modifier.Ownership;
import net.bytebuddy.description.modifier.Visibility;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.implementation.FixedValue;
import net.alexredby.cartlab.Main;
import static net.bytebuddy.matcher.ElementMatchers.named;

/** Runs the actual fixture advice from a foreign class; no game, player or renderer is created. */
public final class CartCaptureUIAdviceChecks {
    private static Instrumentation instrumentation;
    public static void premain(String options,Instrumentation agent) {instrumentation=agent;}

    public static void main(String[] args) throws Exception {
        if(!"false".equals(System.getenv("PZ_CART_TEST_PAD")))
            throw new AssertionError("Offline advice check requires the out-of-test-world branch");
        var core=zombie.core.Core.getInstance();
        if(Main.captureUIKeyBound(67))throw new AssertionError("Fresh native Core unexpectedly binds F9");
        if(core.getKeyBinding(67)!=zombie.core.Core.KEYBINDING_EMPTY)
            throw new AssertionError("Unbound key did not return the native empty sentinel");
        core.addKeyBinding("CartCaptureOffline",67,0,false,false,false);
        if(!Main.captureUIKeyBound(67))throw new AssertionError("Native binding was not detected by the fixture bridge");
        // Use ZombieBuddy's real @Patch -> @Advice conversion rather than reproducing the advice body.
        var transformer=Class.forName("me.zed_0xff.zombie_buddy.PatchTransformer");
        var transform=transformer.getDeclaredMethod("transformPatchClass",Class.class,Instrumentation.class,int.class,boolean.class);
        transform.setAccessible(true);
        if(instrumentation==null)throw new AssertionError("Offline check agent was not loaded");
        var advice=(Class<?>)transform.invoke(null,Main.CaptureUIRender.class,instrumentation,0,false);
        if(!advice.getDeclaredMethod("enter").isAnnotationPresent(Advice.OnMethodEnter.class))
            throw new AssertionError("Installed ZombieBuddy did not convert the actual capture advice");
        var target=new ByteBuddy().subclass(Object.class).name("foreign.capture.CartUIRenderTarget")
            .defineMethod("render",int.class,Visibility.PUBLIC,Ownership.STATIC).intercept(FixedValue.value(42))
            .visit(Advice.to(advice).on(named("render")))
            .make().load(CartCaptureUIAdviceChecks.class.getClassLoader(),ClassLoadingStrategy.Default.WRAPPER).getLoaded();
        // Setting stale state makes the actual world-change reset observable when the advice executes.
        var hidden=Main.class.getDeclaredField("captureUIHidden");hidden.setAccessible(true);hidden.setBoolean(null,true);
        try {
            if(!Integer.valueOf(42).equals(target.getMethod("render").invoke(null)))
                throw new AssertionError("Out-of-world advice skipped the foreign render method");
        } catch(InvocationTargetException failure) {
            throw new AssertionError("Actual inlined capture advice cannot execute across its class boundary",failure.getCause());
        }
        if(hidden.getBoolean(null))throw new AssertionError("Actual inlined advice did not clear stale capture state");
        System.out.println("CART_CAPTURE_UI_ADVICE_PASS (actual ZombieBuddy conversion, foreign-class execution, stale-state reset; no game launch)");
    }
}
