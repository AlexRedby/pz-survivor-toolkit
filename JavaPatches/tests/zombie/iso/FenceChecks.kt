package zombie.iso

import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.EOFException
import java.lang.instrument.Instrumentation
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import java.util.HashMap
import java.util.LinkedHashMap
import java.util.TreeMap
import java.util.TreeSet
import java.util.regex.Pattern
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import me.zed_0xff.zombie_buddy.PatchEngine
import net.bytebuddy.jar.asm.*
import net.alexredby.pztoolkitjavapatches.FenceValidation
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.integration.LuaCaller
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread
import zombie.core.TilePropertyAliasMap
import zombie.Lua.Event
import zombie.Lua.LuaEventManager
import zombie.Lua.LuaManager
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity
import zombie.iso.sprite.IsoSpriteManager

object FenceChecks {
    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun table(): KahluaTableImpl = KahluaTableImpl(LinkedHashMap<Any, Any>())

    private fun line(input: DataInputStream): String {
        val bytes = ByteArrayOutputStream()
        while (true) {
            val c = input.read()
            if (c == 10) break
            if (c < 0) throw EOFException()
            bytes.write(c)
        }
        return bytes.toString(StandardCharsets.UTF_8).trim()
    }

    private fun number(input: DataInputStream): Int = Integer.reverseBytes(input.readInt())

    private fun tileProperties(): Map<String, Map<String, String>> {
        val result = HashMap<String, MutableMap<String, String>>()
        for (file in listOf("newtiledefinitions.tiles", "tiledefinitions_noiseworks.patch.tiles")) {
            DataInputStream(BufferedInputStream(Files.newInputStream(Path.of("media", file)))).use { input ->
                require(String(input.readNBytes(4), StandardCharsets.US_ASCII) == "tdef", "tile magic")
                require(number(input) == 1, "tile version")
                val sets = number(input)
                repeat(sets) {
                    val set = line(input)
                    line(input)
                    number(input)
                    number(input)
                    number(input)
                    val tiles = number(input)
                    repeat(tiles) { tile ->
                        val properties = result.computeIfAbsent("${set}_$tile") { HashMap() }
                        val count = number(input)
                        repeat(count) {
                            val name = line(input)
                            val value = line(input)
                            if (name == "ThumpSound" || name == "FenceTypeLow") properties[name] = value
                        }
                    }
                }
                require(input.read() == -1, "unparsed tile data")
            }
        }
        return result
    }

    private fun nativeTables(): Array<KahluaTableImpl> {
        val result = arrayOf(table(), table())
        val source = Files.readString(Path.of("media/lua/server/Items/BrokenFences.lua"))
        val row = Pattern.compile("""^(tiles|debris)\["([^"]+)"\] = \{(.*)\}.*$""", Pattern.MULTILINE)
        val field = Pattern.compile("""(self|left|right|north|south|west|east) = \{([^}]+)\}""")
        val value = Pattern.compile("\"([^\"]+)\"")
        val rows = row.matcher(source)
        while (rows.find()) {
            val entry = table()
            val fields = field.matcher(rows.group(3))
            while (fields.find()) {
                val values = table()
                val names = value.matcher(fields.group(2))
                var i = 0
                while (names.find()) values.rawset(++i, names.group(1))
                entry.rawset(fields.group(1), values)
            }
            result[if (rows.group(1) == "tiles") 0 else 1].rawset(rows.group(2), entry)
        }
        require(result[0].size() == 42 && result[1].size() > 0, "native fence table coverage changed")
        return result
    }

    private fun snapshot(fences: BrokenFences): List<Map<*, *>> {
        val result = ArrayList<Map<*, *>>()
        for (name in listOf("unbrokenMap", "brokenLeftMap", "brokenRightMap", "allMap")) {
            val field = BrokenFences::class.java.getDeclaredField(name).apply { isAccessible = true }
            result.add(HashMap(field.get(fences) as Map<*, *>))
        }
        return result
    }

    private fun contents(maps: List<Map<*, *>>): Map<String, List<*>> {
        val result = TreeMap<String, List<*>>()
        for (i in maps.indices) for ((key, entry) in maps[i]) {
            val values = ArrayList<Any?>()
            for (name in listOf("self", "left", "right", "debrisN", "debrisS", "debrisW", "debrisE")) {
                val field = entry!!.javaClass.getDeclaredField(name).apply { isAccessible = true }
                val value = field.get(entry)
                values.add(if (value == null) null else ArrayList(value as List<*>))
            }
            result["$i:$key"] = values
        }
        return result
    }

    private fun register(fences: BrokenFences, name: String) {
        val row = table()
        val entries = table()
        entries.rawset(name, row)
        fences.addBrokenTiles(entries)
    }

    private fun eventDispatch(fences: BrokenFences, log: ByteArrayOutputStream, sound: String) {
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FenceChecks::class.java.classLoader)
        require(FenceValidation.SUPPORTED, "unsupported event hook")
        val env = table()
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = env
        LuaManager.thread = KahluaThread(LuaManager.platform, env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller = LuaCaller(KahluaConverterManager())
        val calls = intArrayOf(0)
        env.rawset("finish", JavaFunction { frame, count ->
            if (count > 0 && frame.get(0) === IsoSpriteManager.instance) {
                calls[0]++
                IsoSpriteManager.instance.getSprite("toolkit-event-fence").properties.set("ThumpSound", sound)
            }
            0
        })
        val loaded = Event("OnLoadedTileDefinitions", 0)
        loaded.callbacks.add(LuaCompiler.loadstring("finish(...)", "FenceChecks", env))
        val unrelated = Event("ToolkitUnrelated", 1)
        LuaEventManager.setEvents(ArrayList(listOf(loaded, unrelated)),
            HashMap(mapOf(loaded.name to loaded, unrelated.name to unrelated)))
        fences.Reset()
        log.reset()
        register(fences, "toolkit-event-fence")
        LuaEventManager.triggerEvent("ToolkitUnrelated", IsoSpriteManager.instance)
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", Any())
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions")
        require(log.size() == 0 && calls[0] == 0, "wrong event/manager/arity drained validation: $log")
        LuaManager.env = null
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance)
        require(log.size() == 0 && calls[0] == 0, "null environment dispatched callback")
        LuaManager.env = env
        val worker = Thread { LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance) }
        worker.start()
        worker.join()
        require(calls[0] == 0 && log.size() == 0, "queued event validated before callbacks: $log")
        LuaEventManager.RunQueuedEvents()
        require(calls[0] == 1 && log.size() == 0, "callback properties were not applied before validation: $log")
        register(fences, "toolkit-event-late-invalid")
        require(log.toString().contains("toolkit-event-late-invalid"), "actual queued event did not mark ready")
        fences.Reset()
        log.reset()
        register(fences, "toolkit-event-direct-invalid")
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance)
        require(calls[0] == 2 && log.toString().contains("toolkit-event-direct-invalid"), "actual direct event did not validate after callbacks")
        loaded.callbacks.clear()
        fences.Reset()
        log.reset()
        register(fences, "carpentry_02_48")
        register(fences, "carpentry_02_49")
        LuaEventManager.triggerEvent("ToolkitUnrelated", IsoSpriteManager.instance)
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", Any())
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions")
        LuaManager.env = null
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance)
        LuaManager.env = env
        val owner = LuaManager.thread
        LuaManager.thread = null
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance)
        LuaManager.thread = owner
        val emptyWorker = Thread { LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance) }
        emptyWorker.start()
        emptyWorker.join()
        require(log.size() == 0, "empty-consumer fallback drained on wrong event/manager/environment/thread: $log")
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance)
        val emptyLog = log.toString()
        require(emptyLog.lines().count { it.contains("Missing ThumpSound for breakable object") } == 2
            && emptyLog.contains("carpentry_02_48") && emptyLog.contains("carpentry_02_49"),
            "native empty-consumer event did not drain both pending fences: $emptyLog")
        register(fences, "toolkit-empty-event-late-invalid")
        require(log.toString().contains("toolkit-empty-event-late-invalid"), "empty-consumer event did not mark ready")
        val completed = log.toString()
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance)
        require(log.toString() == completed, "repeat empty-consumer completion validated twice")
    }

    private fun cold() {
        val instrumentation = Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
        require(instrumentation != null, "instrumentation unavailable")
        for (type in (instrumentation ?: throw AssertionError("instrumentation unavailable")).allLoadedClasses)
            require(type.name != "zombie.iso.BrokenFences", "cold check started after fences loaded")
        require(FenceValidation.install(true), "cold install failed")
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val logger = DebugLog.getInstance()
        val log = ByteArrayOutputStream()
        logger.setStdOut(log)
        logger.setStdErr(log)
        DebugType.Sound.setLogSeverity(LogSeverity.Error)
        try {
            val fences = BrokenFences()
            register(fences, "toolkit-cold-fence")
            require(log.size() == 0, "cold load retained native premature validation")
            FenceValidation.tilesLoaded()
            require(log.toString().contains("toolkit-cold-fence"), "cold deferred validation lost")
        } finally {
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
        }
        println("FENCE_COLD_CHECKS_PASS (unloaded class transformer, deferred registration, real validation)")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.isNotEmpty() && args[0] == "cold") {
            cold()
            return
        }
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val data = tileProperties()
        val tables = nativeTables()
        val aliases = LinkedHashMap<String, ArrayList<String>>()
        for (key in listOf("ThumpSound", "FenceTypeLow")) {
            val values = TreeSet<String>()
            for (properties in data.values) if (properties.containsKey(key)) values.add(properties[key] ?: throw NullPointerException())
            if (key == "FenceTypeLow") values.add("toolkit-invalid-low")
            aliases[key] = ArrayList(values)
        }
        TilePropertyAliasMap.instance.Generate(aliases)
        val logger = DebugLog.getInstance()
        val log = ByteArrayOutputStream()
        logger.setStdOut(log)
        logger.setStdErr(log)
        DebugType.Sound.setLogSeverity(LogSeverity.Error)
        try {
            val nativeFences = BrokenFences()
            nativeFences.addBrokenTiles(tables[0])
            nativeFences.addDebrisTiles(tables[1])
            val baseline = contents(snapshot(nativeFences))
            val early = log.toString().lines().count { it.contains("Missing ThumpSound for breakable object") }
            require(early == 42, "native early validation count $early")
            require(!FenceValidation.install(false), "unsupported guard accepted")
            val original = FenceChecks::class.java.classLoader.getResourceAsStream("zombie/iso/BrokenFences.class").use { it!!.readAllBytes() }
            val weave = FenceValidation::class.java.getDeclaredMethod("weave", ByteArray::class.java).apply { isAccessible = true }
            val unknown = original.clone()
            unknown[unknown.size - 1] = (unknown.last().toInt() xor 1).toByte()
            require(weave.invoke(null, unknown) == null, "unknown transformed bytes accepted")
            val changedReader = ClassReader(original)
            val changedWriter = ClassWriter(changedReader, 0)
            changedReader.accept(object : ClassVisitor(Opcodes.ASM9, changedWriter) {
                override fun visitMethod(access: Int, name: String, descriptor: String, signature: String?, exceptions: Array<out String>?): MethodVisitor {
                    return object : MethodVisitor(Opcodes.ASM9, super.visitMethod(access, name, descriptor, signature, exceptions)) {
                        override fun visitLdcInsn(value: Any) {
                            super.visitLdcInsn(if (value == "VERSION") "MODIFIED_VERSION" else value)
                        }
                    }
                }
            }, 0)
            require(weave.invoke(null, changedWriter.toByteArray()) == null, "modified native registration accepted")
            require(FenceValidation.install(true) && FenceValidation.install(true), "transformer install/retransform failed")
            val fences = BrokenFences()
            fences.Reset()
            log.reset()
            fences.addBrokenTiles(tables[0])
            fences.addDebrisTiles(tables[1])
            require(log.size() == 0, "premature validation remains: $log")
            val before = snapshot(fences)
            require(contents(before) == baseline, "registration/debris changed")
            for (name in tables[0].delegate.keys.map { it.toString() }) {
                val sprite = IsoSpriteManager.instance.getSprite(name)
                for ((key, value) in data.getOrDefault(name, emptyMap())) sprite.properties.set(key, value)
            }
            FenceValidation.tilesLoaded()
            val real = log.toString()
            require(real.lines().count { it.contains("Missing ThumpSound for breakable object") } == 2
                && real.contains("carpentry_02_48") && real.contains("carpentry_02_49"), "unexpected real diagnostics: $real")
            val after = snapshot(fences)
            require(contents(after) == baseline, "validation changed maps/debris")
            for (i in before.indices) for (key in before[i].keys)
                require(before[i][key] === after[i][key], "native Tile identity changed")
            log.reset()
            register(fences, "toolkit-missing-fence")
            val invalid = IsoSpriteManager.instance.getSprite("toolkit-invalid-fence")
            invalid.properties.set("FenceTypeLow", "toolkit-invalid-low")
            register(fences, "toolkit-invalid-fence")
            require(log.toString().contains("toolkit-missing-fence") && log.toString().contains("toolkit-invalid-fence"), "late invalid fences suppressed")
            log.reset()
            register(fences, "fencing_01_1")
            require(log.size() == 0, "late valid fence rejected")
            fences.Reset()
            log.reset()
            register(fences, "toolkit-reset-fence")
            require(log.size() == 0, "Reset left validator ready")
            FenceValidation.tilesLoaded()
            require(log.toString().contains("toolkit-reset-fence"), "reload lost pending validation")
            log.reset()
            FenceValidation.tilesLoaded()
            require(log.size() == 0, "ready event validated pending twice")
            val sound = data.values.mapNotNull { it["ThumpSound"] }.first()
            eventDispatch(fences, log, sound)
        } finally {
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
        }
        println("FENCE_CHECKS_PASS (native tables/maps/debris/Tile identities preserved, 42 premature errors deferred to 2 genuine errors from native tiles, missing/invalid/late/reset/reload unsupported bytes and actual callback/queued/direct/empty-consumer event dispatch)")
    }
}
