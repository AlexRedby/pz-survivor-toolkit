package zombie.core

import java.io.ByteArrayOutputStream
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.TilePropertyNames
import zombie.core.properties.IsoPropertyType
import zombie.core.properties.PropertyContainer
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity

object PropertyChecks {
    @JvmField val STRINGS = arrayOf("ladderW", "ladderN", "ladderE", "ladderS", "WindowShape")

    @JvmStatic
    fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun generate(): Map<String, List<String>> {
        val inputs = LinkedHashMap<String, ArrayList<String>>()
        for (name in STRINGS) {
            inputs[String(name.toCharArray())] =
                if (name == "WindowShape") arrayListOf("1", "19") else arrayListOf("")
        }
        val aliases = TilePropertyAliasMap.instance
        aliases.Generate(inputs)
        val snapshot = LinkedHashMap<String, List<String>>()
        for ((name, values) in inputs) {
            val id = aliases.getIDFromPropertyName(name)
            require(id == snapshot.size, "property order/ID changed: $name")
            require(aliases.properties[id].propertyName == name, "property renamed")
            snapshot[name] = aliases.properties[id].possibleValues.toList()
            for ((valueID, value) in values.withIndex()) {
                require(aliases.getIDFromPropertyValue(id, value) == valueID, "value ID changed")
                require(aliases.getPropertyValueString(id, valueID) == value, "value changed")
                val container = PropertyContainer()
                container.set(name, value)
                require(
                    container.has(name) && value == container.get(name),
                    "string round-trip changed",
                )
            }
        }
        return snapshot
    }

    @JvmStatic
    fun ordinaryLookups() {
        for (type in IsoPropertyType.values()) {
            val fresh = String(type.getName().toCharArray())
            require(
                IsoPropertyType.lookupOrDefaultStr(fresh) === type.getName(),
                "canonical typed string changed",
            )
        }
        for (name in STRINGS) {
            val fresh = String(name.toCharArray())
            require(
                IsoPropertyType.lookupOrDefaultStr(fresh) === fresh,
                "native string identity changed",
            )
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val log = ByteArrayOutputStream()
        val logger = DebugLog.getInstance()
        DebugType.WorldGen.setLogSeverity(LogSeverity.Error)
        logger.setStdOut(log)
        logger.setStdErr(log)
        try {
            val baseline = generate()
            val originalLog = log.toString()
            require(
                originalLog.lineSequence().count {
                    "IsoPropertyType\$IsoPropertyTypeNotFoundException:" in it
                } == 5,
                "native baseline did not log exactly five property exceptions: $originalLog",
            )
            for (name in STRINGS) {
                require(
                    "Property Name not found: $name" in originalLog,
                    "native startup failure not reproduced: $name: $originalLog",
                )
            }
            PatchEngine.applyPatches(
                "net.alexredby.pztoolkitjavapatches",
                PropertyChecks::class.java.classLoader,
            )
            require(TilePropertyNames.SUPPORTED, "unsupported property bytecode")
            require(
                !BytecodeSupport.supports(
                    "zombie/core/properties/IsoPropertyType.class",
                    "unknown",
                ),
                "unknown fingerprint accepted",
            )
            require(!TilePropertyNames.accepts("ladderW", false), "unsupported engine accepted")
            log.reset()
            require(generate() == baseline, "alias storage differs from native baseline")
            ordinaryLookups()
            require(
                "Exception thrown" !in log.toString(),
                "woven native strings still log exceptions",
            )
            require(
                "IsoPropertyTypeNotFoundException" !in log.toString() &&
                    "Property Name not found" !in log.toString(),
                "woven property rejection remains",
            )
            try {
                IsoPropertyType.lookup("ladderW")
                throw AssertionError("strict lookup accepted unknown enum")
            } catch (_: IsoPropertyType.IsoPropertyTypeNotFoundException) {}
            for (name in arrayOf("toolkit_unknown_property", "windowshape", "", null)) {
                log.reset()
                require(
                    IsoPropertyType.lookupOrDefaultStr(name) === name,
                    "unknown fallback changed",
                )
                require(
                    "Property Name not found: $name" in log.toString(),
                    "unrelated diagnostic suppressed",
                )
            }
            val types =
                Accessor.tryGet<MutableMap<String, IsoPropertyType>>(
                    IsoPropertyType::class.java,
                    "BY_NAME",
                    null,
                ) ?: throw AssertionError("native property type map unavailable")
            val alias = IsoPropertyType.values()[0]
            types["ladderW"] = alias
            try {
                require(
                    IsoPropertyType.lookupOrDefaultStr("ladderW") === alias.getName(),
                    "mod typed alias bypassed",
                )
            } finally {
                types.remove("ladderW")
            }
        } finally {
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
        }
        println(
            "PROPERTY_CHECKS_PASS (native exceptions=5, woven exceptions=0, unchanged IDs/values/storage, canonical types, strict lookup, unrelated diagnostics, typed aliases, unsupported guard)",
        )
    }
}
