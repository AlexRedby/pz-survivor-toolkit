package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field

/** Test setup/observations across the signed game's package boundary; no replacement game classes. */
internal object NativeFixtureAccess {
    fun field(type: Class<*>, name: String): Field {
        var owner: Class<*>? = type
        while (owner != null) {
            try {
                return owner.getDeclaredField(name).apply { isAccessible = true }
            } catch (_: NoSuchFieldException) {
                owner = owner.superclass
            }
        }
        throw NoSuchFieldException(type.name + "." + name)
    }

    fun set(target: Any, name: String, value: Any?) = field(target.javaClass, name).set(target, value)

    @Suppress("UNCHECKED_CAST")
    fun <T> get(target: Any, name: String): T = field(target.javaClass, name).get(target) as T

    fun actionManager(operation: String, action: Any) {
        zombie.core.ActionManager::class.java
            .getDeclaredMethod(operation, Class.forName("zombie.core.Action"))
            .apply { isAccessible = true }.invoke(null, action)
    }
}
