package zombie.core;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Accessor;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.TilePropertyNames;
import zombie.core.properties.IsoPropertyType;
import zombie.core.properties.PropertyContainer;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

public final class PropertyChecks {
    static final String[] STRINGS = {"ladderW", "ladderN", "ladderE", "ladderS", "WindowShape"};
    static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    static Map<String, List<String>> generate() {
        HashMap<String, ArrayList<String>> inputs = new LinkedHashMap<>();
        for (String name : STRINGS)
            inputs.put(new String(name), new ArrayList<>(name.equals("WindowShape") ? List.of("1", "19") : List.of("")));
        var aliases = TilePropertyAliasMap.instance;
        aliases.Generate(inputs);
        Map<String, List<String>> snapshot = new LinkedHashMap<>();
        for (var entry : inputs.entrySet()) {
            String name = entry.getKey();
            int id = aliases.getIDFromPropertyName(name);
            require(id == snapshot.size(), "property order/ID changed: " + name);
            require(aliases.properties.get(id).propertyName.equals(name), "property renamed");
            snapshot.put(name, List.copyOf(aliases.properties.get(id).possibleValues));
            for (int valueID = 0; valueID < entry.getValue().size(); valueID++) {
                String value = entry.getValue().get(valueID);
                require(aliases.getIDFromPropertyValue(id, value) == valueID, "value ID changed");
                require(aliases.getPropertyValueString(id, valueID).equals(value), "value changed");
                PropertyContainer container = new PropertyContainer();
                container.set(name, value);
                require(container.has(name) && value.equals(container.get(name)), "string round-trip changed");
            }
        }
        return snapshot;
    }

    static void ordinaryLookups() {
        for (IsoPropertyType type : IsoPropertyType.values()) {
            String fresh = new String(type.getName());
            require(IsoPropertyType.lookupOrDefaultStr(fresh) == type.getName(), "canonical typed string changed");
        }
        for (String name : STRINGS) {
            String fresh = new String(name);
            require(IsoPropertyType.lookupOrDefaultStr(fresh) == fresh, "native string identity changed");
        }
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        var log = new ByteArrayOutputStream();
        var logger = DebugLog.getInstance();
        DebugType.WorldGen.setLogSeverity(LogSeverity.Error);
        logger.setStdOut(log);
        logger.setStdErr(log);
        try {
            var baseline = generate();
            String originalLog = log.toString();
            require(originalLog.lines().filter(line -> line.contains("IsoPropertyType$IsoPropertyTypeNotFoundException:")).count() == 5,
                "native baseline did not log exactly five property exceptions: " + originalLog);
            for (String name : STRINGS)
                require(originalLog.contains("Property Name not found: " + name), "native startup failure not reproduced: " + name + ": " + originalLog);

            me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", PropertyChecks.class.getClassLoader());
            require(TilePropertyNames.SUPPORTED, "unsupported property bytecode");
            require(!BytecodeSupport.supports("zombie/core/properties/IsoPropertyType.class", "unknown"), "unknown fingerprint accepted");
            require(!TilePropertyNames.accepts("ladderW", false), "unsupported engine accepted");
            log.reset();
            require(generate().equals(baseline), "alias storage differs from native baseline");
            ordinaryLookups();
            require(!log.toString().contains("Exception thrown"), "woven native strings still log exceptions");
            require(!log.toString().contains("IsoPropertyTypeNotFoundException")
                && !log.toString().contains("Property Name not found"), "woven property rejection remains");
            try {
                IsoPropertyType.lookup("ladderW");
                throw new AssertionError("strict lookup accepted unknown enum");
            } catch (IsoPropertyType.IsoPropertyTypeNotFoundException expected) { }

            for (String name : new String[]{"toolkit_unknown_property", "windowshape", "", null}) {
                log.reset();
                require(IsoPropertyType.lookupOrDefaultStr(name) == name, "unknown fallback changed");
                require(log.toString().contains("Property Name not found: " + name), "unrelated diagnostic suppressed");
            }
            Map<String, IsoPropertyType> types = Accessor.tryGet(IsoPropertyType.class, "BY_NAME", (Map<String, IsoPropertyType>)null);
            var alias = IsoPropertyType.values()[0];
            types.put("ladderW", alias);
            try {
                require(IsoPropertyType.lookupOrDefaultStr("ladderW") == alias.getName(), "mod typed alias bypassed");
            } finally {
                types.remove("ladderW");
            }
        } finally {
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
        }
        System.out.println("PROPERTY_CHECKS_PASS (native exceptions=5, woven exceptions=0, unchanged IDs/values/storage, canonical types, strict lookup, unrelated diagnostics, typed aliases, unsupported guard)");
    }
}
