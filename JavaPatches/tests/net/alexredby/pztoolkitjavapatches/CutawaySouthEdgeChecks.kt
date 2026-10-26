package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.HexFormat
import java.util.zip.ZipFile
import javax.tools.ToolProvider
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.Label
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes

/** Run the engine's extracted south-edge block, including its real branch and neighbour call. */
object CutawaySouthEdgeChecks {
    private const val TARGET = "zombie/iso/fboRenderChunk/FBORenderCutaways"
    private const val LEVEL = "$TARGET\$ChunkLevelData"
    private const val METHOD = "(ILjava/util/ArrayList;)V"
    private const val NATIVE_HASH =
        "9f44080e7858af88c858235939a7bfc2b3c792ee64b69c763568f1ecc6d6ce03"
    private const val OFFICIAL_HASH =
        "adf81d2ee0e30dc05a90bb61694b9049508169122d6e21ef40bc2b5fb2a9bb5a"

    private data class Instruction(
        val kind: String,
        val opcode: Int,
        val variable: Int = -1,
        val owner: String? = null,
        val name: String? = null,
        val descriptor: String? = null,
        val itf: Boolean = false,
    ) {
        fun emit(method: MethodVisitor, done: Label) {
            when (kind) {
                "var" -> method.visitVarInsn(opcode, variable)
                "insn" -> method.visitInsn(opcode)
                "int" -> method.visitIntInsn(opcode, variable)
                "field" -> method.visitFieldInsn(opcode, owner, name, descriptor)
                "call" -> method.visitMethodInsn(opcode, owner, name, descriptor, itf)
                "jump" -> {
                    check(opcode == Opcodes.IF_ICMPEQ)
                    method.visitJumpInsn(opcode, done)
                }
                else -> error("Unsupported extracted instruction: $kind")
            }
        }
    }

    private fun instructions(bytes: ByteArray): List<Instruction> {
        val result = ArrayList<Instruction>()
        ClassReader(bytes)
            .accept(
                object : ClassVisitor(Opcodes.ASM9) {
                    override fun visitMethod(
                        access: Int,
                        name: String?,
                        descriptor: String?,
                        signature: String?,
                        exceptions: Array<out String>?,
                    ): MethodVisitor? {
                        if (name != "doCutawayVisitSquares" || descriptor != METHOD) return null
                        return object : MethodVisitor(Opcodes.ASM9) {
                            override fun visitVarInsn(opcode: Int, variable: Int) {
                                result.add(Instruction("var", opcode, variable))
                            }

                            override fun visitInsn(opcode: Int) {
                                result.add(Instruction("insn", opcode))
                            }

                            override fun visitIntInsn(opcode: Int, operand: Int) {
                                result.add(Instruction("int", opcode, operand))
                            }

                            override fun visitFieldInsn(
                                opcode: Int,
                                owner: String?,
                                name: String?,
                                descriptor: String?,
                            ) {
                                result.add(
                                    Instruction(
                                        "field",
                                        opcode,
                                        owner = owner,
                                        name = name,
                                        descriptor = descriptor,
                                    ),
                                )
                            }

                            override fun visitMethodInsn(
                                opcode: Int,
                                owner: String?,
                                name: String?,
                                descriptor: String?,
                                itf: Boolean,
                            ) {
                                result.add(
                                    Instruction(
                                        "call",
                                        opcode,
                                        owner = owner,
                                        name = name,
                                        descriptor = descriptor,
                                        itf = itf,
                                    ),
                                )
                            }

                            override fun visitJumpInsn(opcode: Int, label: Label) {
                                result.add(Instruction("jump", opcode))
                            }

                            // Other instructions outside the extracted block remain tagged so
                            // indices
                            // cannot accidentally skip an unsupported instruction inside the
                            // boundary.
                            override fun visitTypeInsn(opcode: Int, type: String?) {
                                result.add(Instruction("type", opcode))
                            }

                            override fun visitLdcInsn(value: Any?) {
                                result.add(Instruction("ldc", Opcodes.LDC))
                            }

                            override fun visitIincInsn(variable: Int, increment: Int) {
                                result.add(Instruction("iinc", Opcodes.IINC))
                            }
                        }
                    }
                },
                ClassReader.SKIP_DEBUG,
            )
        return result
    }

    private fun fixture(root: Path) {
        val sources =
            linkedMapOf(
                "zombie.iso.IsoChunk" to "public int wx, wy;",
                "zombie.iso.IsoChunkMap" to "",
                TARGET.replace('/', '.') to
                    """
                public boolean north, south;
                public int invalidations,lastPlayer,lastX,lastY,lastZ;
                public zombie.iso.IsoChunk chunk = new zombie.iso.IsoChunk();
                public ChunkLevelData level = new ChunkLevelData();
                public static class ChunkLevelData { public boolean hasCutawayWestWallsOnSouthEdge; }
                public void exercise(int player, int z) {}
                private boolean hasAnyCutawayWalls(int p,zombie.iso.IsoChunk c,int z,byte bit,int x1,int y1,int x2,int y2) {
                    if (c != chunk || bit != 2 || x1 != 0 || y1 != 7 || x2 != 7 || y2 != 7)
                        throw new AssertionError("Actual south-edge probe changed");
                    return south;
                }
                private void invalidateChunk(int player,zombie.iso.IsoChunkMap map,int x,int y,int z) {
                    invalidations++;lastPlayer=player;lastX=x;lastY=y;lastZ=z;
                }
            """,
            )
        val files = sources.map { (name, body) ->
            root.resolve(name.replace('.', '/') + ".java").also {
                Files.createDirectories(it.parent)
                Files.writeString(
                    it,
                    "package ${name.substringBeforeLast('.')}; public class ${name.substringAfterLast('.')} { $body }",
                )
            }
        }
        check(
            ToolProvider.getSystemJavaCompiler()
                .run(
                    null,
                    null,
                    null,
                    "-d",
                    root.toString(),
                    *files.map { it.toString() }.toTypedArray(),
                ) == 0,
        )
    }

    private fun extracted(root: Path, bytes: ByteArray): ByteArray {
        val all = instructions(bytes)
        val calls =
            all.indices.filter { all[it].kind == "call" && all[it].name == "hasAnyCutawayWalls" }
        check(calls.size == 4)
        val probe = calls.last()
        val end =
            (probe + 1 until all.size).first {
                all[it].kind == "call" && all[it].name == "invalidateChunk"
            }
        val code = all.subList(probe - 9, end + 1)
        check(code.first() == Instruction("var", Opcodes.ALOAD, 0))
        check(code.count { it.kind == "jump" } == 1)
        check(
            code.count {
                it.kind == "field" &&
                    it.opcode == Opcodes.PUTFIELD &&
                    it.name == "hasCutawayWestWallsOnSouthEdge"
            } == 1,
        )
        val chunkLocal = code[2].variable
        val zLocal = code[3].variable
        val comparison = code.indexOfFirst {
            it.kind == "field" &&
                it.opcode == Opcodes.GETFIELD &&
                it.name == "hasCutawayWestWallsOnSouthEdge"
        }
        val levelLocal = code[comparison - 1].variable
        val southLocal = code[comparison - 2].variable
        val northLocal = southLocal - 1
        val mapLocal = code[end - (probe - 9) - 8].variable
        check(
            chunkLocal in listOf(9, 11) &&
                levelLocal == chunkLocal + 1 &&
                zLocal == 4 &&
                mapLocal == 5,
        )
        val template = Files.readAllBytes(root.resolve("$TARGET.class"))
        val reader = ClassReader(template)
        val writer = ClassWriter(reader, ClassWriter.COMPUTE_MAXS or ClassWriter.COMPUTE_FRAMES)
        reader.accept(
            object : ClassVisitor(Opcodes.ASM9, writer) {
                override fun visitMethod(
                    access: Int,
                    name: String?,
                    descriptor: String?,
                    signature: String?,
                    exceptions: Array<out String>?,
                ): MethodVisitor? {
                    if (name != "exercise")
                        return super.visitMethod(access, name, descriptor, signature, exceptions)
                    val method = super.visitMethod(access, name, descriptor, signature, exceptions)
                    method.visitCode()
                    method.visitVarInsn(Opcodes.ALOAD, 0)
                    method.visitFieldInsn(
                        Opcodes.GETFIELD,
                        TARGET,
                        "chunk",
                        "Lzombie/iso/IsoChunk;",
                    )
                    method.visitVarInsn(Opcodes.ASTORE, chunkLocal)
                    method.visitVarInsn(Opcodes.ILOAD, 2)
                    method.visitVarInsn(Opcodes.ISTORE, zLocal)
                    method.visitInsn(Opcodes.ACONST_NULL)
                    method.visitVarInsn(Opcodes.ASTORE, mapLocal)
                    method.visitVarInsn(Opcodes.ALOAD, 0)
                    method.visitFieldInsn(Opcodes.GETFIELD, TARGET, "level", "L$LEVEL;")
                    method.visitVarInsn(Opcodes.ASTORE, levelLocal)
                    method.visitVarInsn(Opcodes.ALOAD, 0)
                    method.visitFieldInsn(Opcodes.GETFIELD, TARGET, "north", "Z")
                    method.visitVarInsn(Opcodes.ISTORE, northLocal)
                    val done = Label()
                    for (instruction in code) instruction.emit(method, done)
                    method.visitLabel(done)
                    method.visitInsn(Opcodes.RETURN)
                    method.visitMaxs(0, 0)
                    method.visitEnd()
                    return null
                }
            },
            0,
        )
        return writer.toByteArray()
    }

    private class Engine(val root: Path, bytes: ByteArray) :
        ClassLoader(CutawaySouthEdgeChecks::class.java.classLoader) {
        init {
            defineClass(TARGET.replace('/', '.'), bytes, 0, bytes.size)
        }

        override fun loadClass(name: String, resolve: Boolean): Class<*> =
            synchronized(getClassLoadingLock(name)) {
                val found =
                    findLoadedClass(name)
                        ?: root.resolve(name.replace('.', '/') + ".class").let {
                            if (Files.isRegularFile(it))
                                Files.readAllBytes(it).let { b -> defineClass(name, b, 0, b.size) }
                            else super.loadClass(name, false)
                        }
                if (resolve) resolveClass(found)
                found
            }

        val type
            get() = loadClass(TARGET.replace('/', '.'))

        fun value() = type.getConstructor().newInstance()

        fun set(value: Any, name: String, input: Any) {
            type.getField(name).set(value, input)
        }

        fun calls(value: Any) = type.getField("invalidations").getInt(value)

        fun cached(value: Any): Boolean {
            val level = type.getField("level").get(value)
            return level.javaClass.getField("hasCutawayWestWallsOnSouthEdge").getBoolean(level)
        }

        fun cache(value: Any, input: Boolean) {
            val level = type.getField("level").get(value)
            level.javaClass.getField("hasCutawayWestWallsOnSouthEdge").setBoolean(level, input)
        }

        fun visit(value: Any, player: Int, z: Int) {
            type
                .getMethod("exercise", Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
                .invoke(value, player, z)
        }
    }

    private fun checkInput(root: Path, label: String, original: ByteArray, woven: ByteArray) {
        val before = instructions(original)
        val after = instructions(woven)
        check(before.size == after.size)
        val changes = before.indices.filter { before[it] != after[it] }
        check(changes.size == 1)
        val changed = changes.single()
        check(
            before[changed].kind == "var" &&
                before[changed].opcode == Opcodes.ILOAD &&
                after[changed].variable == before[changed].variable + 1,
        )
        val native = Engine(root, extracted(root, original))
        val fixed = Engine(root, extracted(root, woven))
        var cases = 0
        var redundant = 0
        for (north in listOf(false, true)) for (south in listOf(false, true)) for (cached in
            listOf(false, true)) for (player in 0..3) {
            val a = native.value()
            val b = fixed.value()
            for ((engine, value) in listOf(native to a, fixed to b)) {
                engine.set(value, "north", north)
                engine.set(value, "south", south)
                engine.cache(value, cached)
                val chunk = engine.type.getField("chunk").get(value)
                chunk.javaClass.getField("wx").setInt(chunk, 17)
                chunk.javaClass.getField("wy").setInt(chunk, 23)
            }
            // A first legitimate transition must retain the exact single neighbour invalidation.
            native.visit(a, player, 3)
            fixed.visit(b, player, 3)
            check(
                native.calls(a) == fixed.calls(b) &&
                    fixed.calls(b) == if (cached != south) 1 else 0,
            )
            check(fixed.cached(b) == south)
            repeat(4) {
                native.visit(a, player, 3)
                fixed.visit(b, player, 3)
            }
            check(fixed.calls(b) == if (cached != south) 1 else 0)
            if (north != south && cached != south) {
                check(native.calls(a) == 5)
                redundant += 4
            }
            // Changing the real south condition in either direction must still invalidate once.
            for (next in listOf(!south, south, !south)) {
                val count = fixed.calls(b)
                fixed.set(b, "south", next)
                fixed.visit(b, player, 3)
                check(fixed.cached(b) == next && fixed.calls(b) == count + 1)
                fixed.visit(b, player, 3)
                check(fixed.calls(b) == count + 1)
            }
            for ((name, expected) in
                listOf("lastPlayer" to player, "lastX" to 17, "lastY" to 24, "lastZ" to 3)) check(
                fixed.type.getField(name).getInt(b) == expected,
            )
            cases++
        }
        println(
            "SOUTH_EDGE_SEQUENCE_PASS $label cases=$cases redundant-neighbour-invalidations=$redundant",
        )
    }

    private fun changedBoundary(bytes: ByteArray, method: String): ByteArray {
        val writer = ClassWriter(0)
        ClassReader(bytes)
            .accept(
                object : ClassVisitor(Opcodes.ASM9, writer) {
                    override fun visitMethod(
                        access: Int,
                        name: String?,
                        descriptor: String?,
                        signature: String?,
                        exceptions: Array<out String>?,
                    ): MethodVisitor? {
                        val output =
                            super.visitMethod(access, name, descriptor, signature, exceptions)
                        if (name != method) return output
                        return object : MethodVisitor(Opcodes.ASM9, output) {
                            override fun visitCode() {
                                super.visitCode()
                                super.visitInsn(Opcodes.NOP)
                            }
                        }
                    }
                },
                0,
            )
        return writer.toByteArray()
    }

    @JvmStatic
    fun main(args: Array<String>) {
        check(CutawaySouthEdge.SUPPORTED)
        val original =
            javaClass.classLoader.getResourceAsStream("$TARGET.class")!!.use { it.readAllBytes() }
        check(
            HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(original)) ==
                NATIVE_HASH,
        )
        val woven = CutawaySouthEdge.weave(original) ?: error("native south assignment not woven")
        check(CutawaySouthEdge.weave(woven) == null && CutawaySouthEdge.weave(null) == null)
        for (method in
            listOf("doCutawayVisitSquares", "hasAnyCutawayWalls", "invalidateChunk")) check(
            CutawaySouthEdge.weave(changedBoundary(original, method)) == null,
        ) {
            "Changed cutaway boundary accepted: $method"
        }
        val root =
            Files.createTempDirectory(Path.of(System.getProperty("pz.test.cache")), "south-edge-")
        try {
            fixture(root)
            checkInput(root, "native", original, woven)
            val official =
                System.getProperty("pz.test.optimizer.archive")
                    ?: System.getenv("PZ_TEST_OPTIMIZER_ARCHIVE")
            if (official != null) {
                val archive = Path.of(official)
                check(
                    HexFormat.of()
                        .formatHex(
                            MessageDigest.getInstance("SHA-256")
                                .digest(Files.readAllBytes(archive)),
                        ) == "2bcd0e01a3ac66856fae137ff1dbda66c8397375da781e7a6ed67fe2b9d6590d",
                )
                val bytes =
                    ZipFile(archive.toFile()).use {
                        it.getInputStream(it.getEntry("$TARGET.class")).readAllBytes()
                    }
                check(
                    HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)) ==
                        OFFICIAL_HASH,
                )
                // Pure rewrite test only. Runtime official admission is separately tested against
                // all exact configuration/resource pins, never bypassed by this test reflection.
                val transform =
                    CutawaySouthEdge::class
                        .java
                        .getDeclaredMethod("transformReviewed", ByteArray::class.java)
                        .apply { isAccessible = true }
                val patched = transform.invoke(CutawaySouthEdge, bytes) as ByteArray
                checkInput(root, "official", bytes, patched)
            } else
                println(
                    "SOUTH_EDGE_OFFICIAL_SEQUENCE_SKIP (explicit reviewed archive not supplied)",
                )
        } finally {
            Files.walk(root).use { files ->
                files.sorted(Comparator.reverseOrder()).forEach { Files.delete(it) }
            }
        }
        println(
            "CUTAWAY_SOUTH_EDGE_CHECKS_PASS (actual native/optional official south sequence; flags, four players, transitions, exact neighbour coordinates)",
        )
    }
}
