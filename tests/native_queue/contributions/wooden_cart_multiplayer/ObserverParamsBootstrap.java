package net.alexredby.cartlab;

/** Install the diagnostic escape ledger at normal mod load, before fixture actors and parameter objects are published. */
public final class ObserverParamsBootstrap {
    public static void install() {
        if(!"true".equals(System.getenv("PZ_CART_OBSERVER_ASSOCIATION")))return;
        try {
            var loader=Class.forName("me.zed_0xff.zombie_buddy.Loader",false,ObserverParamsBootstrap.class.getClassLoader());
            var field=loader.getDeclaredField("g_instrumentation");field.setAccessible(true);
            var instrumentation=(java.lang.instrument.Instrumentation)field.get(null);
            if(instrumentation==null)throw new IllegalStateException("Native loader instrumentation unavailable");
            Main.observerParamsInstall(instrumentation);
            if(!Main.observerParamsHealthy())throw new IllegalStateException("Native parameter monitor installation failed");
        }catch(Throwable error) {
            System.err.println("[CART_OBSERVER] ERROR params installation "+error);
            throw new IllegalStateException("Diagnostic native parameter monitoring was not installed",error);
        }
    }
}
