package zombie.scripting.entity.components.fluids;

import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.Main;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;
import zombie.entity.ComponentType;
import zombie.scripting.ScriptParser;

public final class FluidChecks {
    static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    static ScriptParser.Block nativeBlock(String name) throws Exception {
        String file = name.equals("Large Bucket") ? "media/scripts/generated/items/normal.txt"
            : "media/scripts/generated/entities/appliances/workstations/entity_fuelpump.txt";
        String kind = name.equals("Large Bucket") ? "item" : "entity";
        String id = name.equals("Large Bucket") ? "BucketLargeWood" : "FuelPump";
        var module = ScriptParser.parse(ScriptParser.stripComments(Files.readString(Path.of(file)))).getBlock("module", "Base");
        var block = module.getBlock(kind, id).getBlock("component", "FluidContainer");
        require(block.getValue("ContainerName").getValue().trim().equals(name), "native token changed");
        return block;
    }

    static ScriptParser.Block block(String name) {
        return ScriptParser.parse("component FluidContainer { ContainerName = " + name
            + ", Capacity = 3.5, Fluids { fluid = Water:0.25, fluid = Petrol:0.75, } }")
            .getBlock("component", "FluidContainer");
    }

    static List<Object> load(ScriptParser.Block block) throws Exception {
        var script = (FluidContainerScript)ComponentType.FluidContainer.CreateComponentScript();
        script.load(block);
        var contents = new ArrayList<String>();
        if (script.getInitialFluids() != null)
            for (var fluid : script.getInitialFluids()) contents.add(fluid.getFluidType() + ":" + fluid.getPercentage());
        return List.of(script.getContainerName(), script.getCapacity(), contents,
            Accessor.tryGet(script, "initialAmountMin", Float.NaN), Accessor.tryGet(script, "initialAmountMax", Float.NaN),
            script.getRainCatcher(), script.getTransferRate(), script.getCanEmpty(), script.getInputLocked());
    }

    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        var logger = DebugLog.getInstance();
        var log = new ByteArrayOutputStream();
        DebugType.General.setLogSeverity(LogSeverity.Error);
        logger.setStdOut(log);
        logger.setStdErr(log);
        try {
            var bucket = load(nativeBlock("Large Bucket"));
            var pump = load(nativeBlock("Fuel Pump"));
            require(bucket.get(0).equals("LargeBucket") && bucket.get(1).equals(20.0f)
                && bucket.get(2).equals(List.of()) && bucket.get(5).equals(0.7f) && bucket.get(6).equals(5.0f), "native bucket fields");
            require(pump.get(0).equals("FuelPump") && pump.get(1).equals(22000.0f)
                && pump.get(2).equals(List.of("Petrol:1.0")) && pump.get(3).equals(0.05f)
                && pump.get(4).equals(0.15f), "native pump fields");
            require(log.toString().lines().filter(line -> line.contains("Sanitizing container name")).count() == 2,
                "native baseline must diagnose both malformed tokens: " + log);
            var unknown = load(block("Unknown Container"));
            require(log.toString().contains("Sanitizing container name 'Unknown Container'"), "unknown native diagnostic missing");

            PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FluidChecks.class.getClassLoader());
            require(Main.FLUID_SUPPORTED, "unsupported fluid parser bytecode");
            require(!Main.supports("zombie/scripting/entity/components/fluids/FluidContainerScript.class", "unknown"), "unknown fingerprint accepted");
            var untouched = nativeBlock("Large Bucket");
            Main.NativeFluidName.normalize(untouched, false);
            require(untouched.getValue("ContainerName").getValue().trim().equals("Large Bucket"), "unsupported parser was modified");
            Main.NativeFluidName.normalize(null, true);
            var noName = ScriptParser.parse("component FluidContainer { Capacity = 2, }").getBlock("component", "FluidContainer");
            Main.NativeFluidName.normalize(noName, true);
            require(noName.getValue("ContainerName") == null, "missing property invented");
            log.reset();
            require(load(nativeBlock("Large Bucket")).equals(bucket) && load(nativeBlock("Fuel Pump")).equals(pump),
                "woven parser changed native names/capacity/contents/amounts/flags");
            require(!log.toString().contains("Sanitizing container name"), "woven native tokens still fail validation");
            for (String name : new String[]{"Unknown Container", "large bucket", "Fuel  Pump", "Fuel\tPump"}) {
                var original = block(name);
                String token = original.getValue("ContainerName").string;
                log.reset();
                var result = load(original);
                require(original.getValue("ContainerName").string.equals(token), "unknown token modified");
                require(log.toString().contains("Sanitizing container name '" + name + "'"), "unrelated validation suppressed");
                if (name.equals("Unknown Container")) require(result.equals(unknown), "unknown native result changed");
            }
            for (String name : new String[]{"LargeBucket", "FuelPump"}) {
                log.reset();
                require(load(block(name)).get(0).equals(name) && !log.toString().contains("Sanitizing"), "valid canonical token changed");
            }
        } finally {
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
        }
        System.out.println("FLUID_CHECKS_PASS (native errors=2, woven errors=0, shipped blocks, unchanged names/capacity/contents/amounts/flags, unknown diagnostics, unsupported guard)");
    }
}
