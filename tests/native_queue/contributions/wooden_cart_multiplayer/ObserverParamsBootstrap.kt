package net.alexredby.cartlab

/** Installs the diagnostic ledger before fixture actors and parameters are published. */
object ObserverParamsBootstrap {
    @JvmStatic
    fun install() {
        if (System.getenv("PZ_CART_OBSERVER_ASSOCIATION") != "true") return
        try {
            val loader =
                Class.forName(
                    "me.zed_0xff.zombie_buddy.Loader",
                    false,
                    ObserverParamsBootstrap::class.java.classLoader,
                )
            val field = loader.getDeclaredField("g_instrumentation").apply { isAccessible = true }
            val instrumentation =
                field.get(null) as? java.lang.instrument.Instrumentation
                    ?: error("Native loader instrumentation unavailable")
            ObserverParams.observerParamsInstall(instrumentation)
            check(ObserverParams.observerParamsHealthy()) {
                "Native parameter monitor installation failed"
            }
        } catch (error: Throwable) {
            System.err.println("[CART_OBSERVER] ERROR params installation $error")
            throw IllegalStateException(
                "Diagnostic native parameter monitoring was not installed",
                error,
            )
        }
    }
}
