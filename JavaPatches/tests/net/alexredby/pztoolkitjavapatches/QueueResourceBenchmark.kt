package net.alexredby.pztoolkitjavapatches

import com.sun.management.ThreadMXBean
import java.lang.management.ManagementFactory
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.IdentityHashMap
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype

/** Opt-in CPU-only host. It starts no game, UI, server or native action executor. */
object QueueResourceBenchmark {
    private const val MARKER = "QUEUE_RESOURCE_BENCHMARK_BANK_PASS"
    private const val MAX_JSON_NODES = 100_000
    private const val MAX_JSON_DEPTH = 32
    private val clockOrigin = System.nanoTime()
    private var emitted = 0

    private fun quote(value: String): String = buildString {
        append('"')
        for (char in value) {
            when (char) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (char.code < 32 || char.isSurrogate()) {
                    append("\\u").append(char.code.toString(16).padStart(4, '0'))
                } else append(char)
            }
        }
        append('"')
    }

    private class Json {
        private var nodes = 0
        private val ancestors = IdentityHashMap<Any, Boolean>()

        fun encode(value: Any?, depth: Int = 0): String {
            require(++nodes <= MAX_JSON_NODES && depth <= MAX_JSON_DEPTH) { "Benchmark result exceeds JSON work limit" }
            return when (value) {
                null -> "null"
                is String -> quote(value)
                is Boolean -> value.toString()
                is Number -> {
                    require(value.toDouble().isFinite()) { "Benchmark JSON cannot encode non-finite numbers" }
                    value.toString()
                }
                is KahluaTable -> {
                    require(ancestors.put(value, true) == null) { "Cyclic benchmark result" }
                    try {
                        val values = mutableListOf<Pair<Any, Any?>>()
                        val iterator = value.iterator()
                        while (iterator.advance()) {
                            require(values.size < MAX_JSON_NODES) { "Benchmark result table is too large" }
                            values.add(iterator.key to iterator.value)
                        }
                        val indexed = values.mapNotNull { (key, entry) ->
                            val n = (key as? Number)?.toDouble()
                            if (n != null && n.isFinite() && n >= 1 && n <= Int.MAX_VALUE && n == n.toInt().toDouble()) n.toInt() to entry else null
                        }
                        if (indexed.size == values.size && indexed.map { it.first }.sorted() == (1..values.size).toList()) {
                            indexed.sortedBy { it.first }.joinToString(",", "[", "]") { encode(it.second, depth + 1) }
                        } else {
                            require(values.all { it.first is String }) { "Benchmark object keys must be strings or a dense numeric array" }
                            values.sortedBy { it.first as String }.joinToString(",", "{", "}") {
                                quote(it.first as String) + ":" + encode(it.second, depth + 1)
                            }
                        }
                    } finally {
                        ancestors.remove(value)
                    }
                }
                is Map<*, *> -> {
                    require(ancestors.put(value, true) == null) { "Cyclic benchmark metadata" }
                    try {
                        require(value.keys.all { it is String }) { "Metadata keys must be strings" }
                        value.entries.sortedBy { it.key as String }.joinToString(",", "{", "}") {
                            quote(it.key as String) + ":" + encode(it.value, depth + 1)
                        }
                    } finally {
                        ancestors.remove(value)
                    }
                }
                is List<*> -> value.joinToString(",", "[", "]") { encode(it, depth + 1) }
                else -> throw IllegalArgumentException("Unsupported benchmark JSON value: ${value.javaClass.name}")
            }
        }
    }

    private fun emit(value: Map<String, Any?>) {
        println(Json().encode(value))
        System.out.flush()
    }

    private fun filename(prototype: Prototype, path: String) {
        prototype.filename = path
        for (child in prototype.prototypes) filename(child, path)
    }

    private fun compile(text: String, path: String, environment: KahluaTable): LuaClosure {
        val closure = LuaCompiler.loadstring(text, path, environment)
        filename(closure.prototype, path)
        return closure
    }

    private fun gc(phase: String) = emit(mapOf(
        "event" to "gc", "phase" to phase,
        "collectors" to ManagementFactory.getGarbageCollectorMXBeans().map {
            mapOf("name" to it.name, "collections" to it.collectionCount, "milliseconds" to it.collectionTime)
        },
        "heapUsedBytes" to ManagementFactory.getMemoryMXBean().heapMemoryUsage.used,
    ))

    @JvmStatic
    fun main(args: Array<String>) {
        try {
            require(args.isEmpty()) { "Use JVM properties supplied by tools/benchmark_queue_resources.py" }
            val root = Path.of(System.getProperty("pz.test.project")).toRealPath()
            val game = Path.of(System.getProperty("pz.test.game")).toRealPath()
            val samples = System.getProperty("pz.benchmark.samples", "30").toInt()
            val warmup = System.getProperty("pz.benchmark.warmup", "5").toInt()
            val sections = System.getProperty("pz.benchmark.sections", "component,edit,model,weights").split(',')
            val maxSteps = System.getProperty("pz.benchmark.maxSteps", "1000").toInt()
            require(sections.isNotEmpty() && sections.distinct().size == sections.size &&
                sections.all { it in setOf("component", "edit", "model", "weights") }) { "Invalid benchmark sections" }
            require(maxSteps in setOf(50, 200, 1000)) { "Invalid benchmark max steps" }
            require(samples in 1..100_000 && warmup in 0..100_000) { "Invalid benchmark sample/warmup count" }
            val bean = ManagementFactory.getThreadMXBean() as? ThreadMXBean
            var allocationReason: String? = null
            val allocation = try {
                if (bean == null || !bean.isThreadAllocatedMemorySupported) {
                    allocationReason = "current-thread allocated bytes unsupported"; null
                } else {
                    if (!bean.isThreadAllocatedMemoryEnabled) bean.isThreadAllocatedMemoryEnabled = true
                    if (bean.getThreadAllocatedBytes(Thread.currentThread().threadId()) < 0) {
                        allocationReason = "current-thread allocated bytes unavailable"; null
                    } else bean
                }
            } catch (error: Exception) {
                allocationReason = error.javaClass.simpleName + ": " + error.message; null
            }
            emit(mapOf("event" to "environment", "scope" to "native-kahlua-cpu-only", "gui" to false,
                "javaVersion" to System.getProperty("java.version"), "vmName" to System.getProperty("java.vm.name"),
                "osName" to System.getProperty("os.name"), "osArch" to System.getProperty("os.arch"),
                "processors" to Runtime.getRuntime().availableProcessors(), "samples" to samples, "warmup" to warmup,
                "sections" to sections, "maxSteps" to maxSteps,
                "clock" to "System.nanoTime relative nanoseconds", "allocatedBytesAvailable" to (allocation != null),
                "allocatedBytesUnavailableReason" to allocationReason))
            val readHashes = mutableMapOf<Path, String>()
            fun readText(input: Path): String {
                val path = input.toRealPath()
                val bytes = Files.readAllBytes(path)
                val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                val previous = readHashes.putIfAbsent(path, digest)
                require(previous == null || previous == digest) { "Benchmark input changed during execution: $path" }
                if (previous == null) {
                    val scope = if (path.startsWith(root)) "project" else if (path.startsWith(game)) "game" else "external"
                    val name = when (scope) { "project" -> root.relativize(path); "game" -> game.relativize(path); else -> path }
                    emit(mapOf("event" to "source", "scope" to scope, "path" to name.toString().replace('\\', '/'), "sha256" to digest))
                }
                return String(bytes, StandardCharsets.UTF_8)
            }
            val platform = J2SEPlatform()
            val environment = platform.newEnvironment()
            val thread = KahluaThread(platform, environment)
            thread.debugOwnerThread = Thread.currentThread()
            environment.rawset("ProjectRoot", root.toString())
            environment.rawset("NativeActionRoot", game.resolve("media/lua").toString())
            environment.rawset("NativeKahluaTableLookup", true)
            environment.rawset("BenchmarkSamples", samples.toDouble())
            environment.rawset("BenchmarkWarmup", warmup.toDouble())
            environment.rawset("BenchmarkSections", sections.joinToString(","))
            environment.rawset("BenchmarkMaxSteps", maxSteps.toDouble())
            environment.rawset("BenchmarkAllocatedBytesAvailable", allocation != null)
            environment.rawset("BenchmarkNanoTime", JavaFunction { frame, _ ->
                frame.push((System.nanoTime() - clockOrigin).toDouble()); 1
            })
            environment.rawset("BenchmarkAllocatedBytes", JavaFunction { frame, _ ->
                val bytes = allocation?.getThreadAllocatedBytes(Thread.currentThread().threadId())
                frame.push(bytes?.takeIf { it >= 0 }?.toDouble()); 1
            })
            environment.rawset("BenchmarkEmit", JavaFunction { frame, count ->
                require(count == 2 && frame.get(0) is String) { "BenchmarkEmit(label, value) requires a string label and one value" }
                emit(mapOf("event" to "sample", "label" to frame.get(0), "value" to frame.get(1)))
                emitted++; 0
            })
            val read = JavaFunction { frame, _ -> frame.push(readText(Path.of(frame.get(0) as String))); 1 }
            environment.rawset("NativeReadText", read)
            environment.rawset("NativeReadRawText", read)
            environment.rawset("NativeFileExists", JavaFunction { frame, _ -> frame.push(Files.isRegularFile(Path.of(frame.get(0) as String))); 1 })
            environment.rawset("NativeFilenameOfClosure", JavaFunction { frame, _ ->
                val callback = frame.get(0); frame.push(if (callback is LuaClosure) callback.prototype.filename else null); 1
            })
            environment.rawset("loadstring", JavaFunction { frame, count ->
                frame.push(compile(frame.get(0) as String, if (count > 1) frame.get(1) as String else "=(loadstring)", environment)); 1
            })
            environment.rawset("loadfile", JavaFunction { frame, _ ->
                val path = Path.of(frame.get(0) as String); frame.push(compile(readText(path), path.toString(), environment)); 1
            })
            thread.call(compile("function dofile(path) return assert(loadfile(path))() end", "=(benchmark bootstrap)", environment), emptyArray<Any?>())
            gc("before")
            val path = root.resolve("tests/benchmarks/queue_resources.lua")
            thread.call(compile(readText(path), path.toString(), environment), emptyArray<Any?>())
            require(environment.rawget("QueueResourceBenchmarkPassed") == true) { "Lua bank did not set QueueResourceBenchmarkPassed=true" }
            require(emitted > 0) { "Lua bank produced no BenchmarkEmit output" }
            gc("after")
            emit(mapOf("event" to "bank", "status" to "passed", "marker" to MARKER, "emitted" to emitted, "samples" to samples, "warmup" to warmup, "sections" to sections, "maxSteps" to maxSteps))
        } catch (error: Throwable) {
            emit(mapOf("event" to "bank", "status" to "failed", "reason" to (error.message ?: error.javaClass.name)))
            error.printStackTrace(System.err)
            kotlin.system.exitProcess(1)
        }
        kotlin.system.exitProcess(0)
    }
}
