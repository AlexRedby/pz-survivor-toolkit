package zombie.scripting.entity.components.fluids

import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.FluidContainerNames
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity
import zombie.entity.ComponentType
import zombie.scripting.ScriptParser

object FluidChecks {
    @JvmStatic
    fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun nativeBlock(name: String): ScriptParser.Block {
        val bucket = name == "Large Bucket"
        val file =
            if (bucket) "media/scripts/generated/items/normal.txt"
            else "media/scripts/generated/entities/appliances/workstations/entity_fuelpump.txt"
        val kind = if (bucket) "item" else "entity"
        val id = if (bucket) "BucketLargeWood" else "FuelPump"
        val module =
            ScriptParser.parse(ScriptParser.stripComments(Files.readString(Path.of(file))))
                .getBlock("module", "Base")
        val block = module.getBlock(kind, id).getBlock("component", "FluidContainer")
        require(
            block.getValue("ContainerName").getValue().trim { it <= ' ' } == name,
            "native token changed",
        )
        return block
    }

    @JvmStatic
    fun block(name: String): ScriptParser.Block =
        ScriptParser.parse(
                "component FluidContainer { ContainerName = $name" +
                    ", Capacity = 3.5, Fluids { fluid = Water:0.25, fluid = Petrol:0.75, } }",
            )
            .getBlock("component", "FluidContainer")

    @JvmStatic
    fun load(block: ScriptParser.Block): List<Any> {
        val script = ComponentType.FluidContainer.CreateComponentScript() as FluidContainerScript
        script.load(block)
        val contents =
            script.getInitialFluids()?.map { "${it.getFluidType()}:${it.getPercentage()}" }
                ?: emptyList()
        return listOf(
            script.getContainerName(),
            script.getCapacity(),
            contents,
            Accessor.tryGet(script, "initialAmountMin", Float.NaN),
            Accessor.tryGet(script, "initialAmountMax", Float.NaN),
            script.getRainCatcher(),
            script.getTransferRate(),
            script.getCanEmpty(),
            script.getInputLocked(),
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val logger = DebugLog.getInstance()
        val log = ByteArrayOutputStream()
        DebugType.General.setLogSeverity(LogSeverity.Error)
        logger.setStdOut(log)
        logger.setStdErr(log)
        try {
            val bucket = load(nativeBlock("Large Bucket"))
            val pump = load(nativeBlock("Fuel Pump"))
            require(
                bucket[0] == "LargeBucket" &&
                    bucket[1] == 20.0f &&
                    bucket[2] == emptyList<String>() &&
                    bucket[5] == .7f &&
                    bucket[6] == 5.0f,
                "native bucket fields",
            )
            require(
                pump[0] == "FuelPump" &&
                    pump[1] == 22000.0f &&
                    pump[2] == listOf("Petrol:1.0") &&
                    pump[3] == .05f &&
                    pump[4] == .15f,
                "native pump fields",
            )
            require(
                log.toString().lineSequence().count { "Sanitizing container name" in it } == 2,
                "native baseline must diagnose both malformed tokens: $log",
            )
            val unknown = load(block("Unknown Container"))
            require(
                "Sanitizing container name 'Unknown Container'" in log.toString(),
                "unknown native diagnostic missing",
            )
            PatchEngine.applyPatches(
                "net.alexredby.pztoolkitjavapatches",
                FluidChecks::class.java.classLoader,
            )
            require(FluidContainerNames.SUPPORTED, "unsupported fluid parser bytecode")
            require(
                !BytecodeSupport.supports(
                    "zombie/scripting/entity/components/fluids/FluidContainerScript.class",
                    "unknown",
                ),
                "unknown fingerprint accepted",
            )
            val untouched = nativeBlock("Large Bucket")
            FluidContainerNames.normalize(untouched, false)
            require(
                untouched.getValue("ContainerName").getValue().trim { it <= ' ' } == "Large Bucket",
                "unsupported parser was modified",
            )
            FluidContainerNames.normalize(null, true)
            val noName =
                ScriptParser.parse("component FluidContainer { Capacity = 2, }")
                    .getBlock("component", "FluidContainer")
            FluidContainerNames.normalize(noName, true)
            require(noName.getValue("ContainerName") == null, "missing property invented")
            val unicodeSpaced = block("\u00a0Large Bucket\u00a0")
            val unicodeToken = unicodeSpaced.getValue("ContainerName").string
            FluidContainerNames.normalize(unicodeSpaced, true)
            require(
                unicodeSpaced.getValue("ContainerName").string == unicodeToken,
                "Unicode whitespace broadened the native token normalization",
            )
            log.reset()
            require(
                load(nativeBlock("Large Bucket")) == bucket &&
                    load(nativeBlock("Fuel Pump")) == pump,
                "woven parser changed native names/capacity/contents/amounts/flags",
            )
            require(
                "Sanitizing container name" !in log.toString(),
                "woven native tokens still fail validation",
            )
            for (name in arrayOf("Unknown Container", "large bucket", "Fuel  Pump", "Fuel\tPump")) {
                val original = block(name)
                val token = original.getValue("ContainerName").string
                log.reset()
                val result = load(original)
                require(
                    original.getValue("ContainerName").string == token,
                    "unknown token modified",
                )
                require(
                    "Sanitizing container name '$name'" in log.toString(),
                    "unrelated validation suppressed",
                )
                if (name == "Unknown Container")
                    require(result == unknown, "unknown native result changed")
            }
            for (name in arrayOf("LargeBucket", "FuelPump")) {
                log.reset()
                require(
                    load(block(name))[0] == name && "Sanitizing" !in log.toString(),
                    "valid canonical token changed",
                )
            }
        } finally {
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
        }
        println(
            "FLUID_CHECKS_PASS (native errors=2, woven errors=0, shipped blocks, unchanged names/capacity/contents/amounts/flags, unknown diagnostics, unsupported guard)",
        )
    }
}
