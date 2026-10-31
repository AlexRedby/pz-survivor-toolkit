package net.alexredby.pztoolkitjavapatches

/** Match only a bare module name or the native label of an already-validated provider. */
internal object CompilerInputName {
    @JvmStatic
    fun matches(name: String?, bareName: String, resolved: String?): Boolean =
        name != null &&
            (name == bareName ||
                // RunLuaInternal strips only '/', not the platform separator. Keep the raw path.
                (resolved != null && name == resolved.substringAfterLast('/')))
}
