import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.*;

/** Research-only native-method cloning; never included by either shipped mod. */
public final class ResolvedCandidate {
    static final String OWNER = "zombie/inventory/ItemPickerJava";
    static final String ITEM = "Lzombie/scripting/objects/Item;";
    static final String PICK = "Lzombie/inventory/ItemPickerJava$ItemPickerItem;";
    static final String CHARACTER = "Lzombie/characters/IsoGameCharacter;";
    static final String CONTAINER = "Lzombie/inventory/ItemContainer;";
    static final String INFO = "Lzombie/inventory/ItemPickInfo;";
    static final String DIST = "Lzombie/inventory/ItemPickerJava$ItemPickerContainer;";
    static final String ROOM = "Lzombie/inventory/ItemPickerJava$ItemPickerRoom;";
    static final String CHANCE = "(" + PICK + CHARACTER + CONTAINER + "FZ)F";
    static final String RESOLVED = CHANCE.replace(")F", ITEM + ")F");
    static final String DO_ROLL = "(" + INFO + DIST + CONTAINER + "F" + CHARACTER + "Z" + ROOM + "Z)V";
    static final String BAG_ROLL = "(" + INFO + "Lzombie/inventory/types/InventoryContainer;" + CHARACTER + DIST + "Z)V";
    static final String HASH = "5c8cf626e46a52cdbd9d73e9de10766dece3388ee3e4f4d8d071df5e44d68522";
    static final Map<String, Integer> CLONES = Map.of(
        "getActualSpawnChance" + CHANCE, 5,
        "getLootModifier(Ljava/lang/String;Z)F", 2,
        "getLootModifier(Ljava/lang/String;)F", 1,
        "getBaseChance(" + PICK + CHARACTER + "Z)F", 3);

    static String sha(byte[] data) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
    }
    static String cloneName(String name, String desc) {
        return "pztest$" + name + (name.equals("getLootModifier") && desc.equals("(Ljava/lang/String;)F") ? "String" : "");
    }
    static byte[] transform(byte[] bytes, boolean candidate) throws Exception {
        if (!sha(bytes).equals(HASH)) throw new IllegalArgumentException("Unexpected ItemPickerJava bytes");
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
        Map<String, Integer> locals = new HashMap<>();
        reader.accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitMaxs(int stack, int count) { locals.put(n + d, count); }
                };
            }
        }, 0);
        int[] captures = {0}, calls = {0}, clones = {0}, replacements = {0};
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                MethodVisitor mv = super.visitMethod(a, n, d, s, e);
                if (!candidate || !(n.equals("doRollItemInternal") && d.equals(DO_ROLL)
                        || n.equals("rollContainerItemInternal") && d.equals(BAG_ROLL))) return mv;
                int saved = locals.get(n + d);
                return new MethodVisitor(Opcodes.ASM9, mv) {
                    @Override public void visitMethodInsn(int op, String o, String name, String desc, boolean itf) {
                        if (o.equals(OWNER) && name.equals("getActualSpawnChance") && desc.equals(CHANCE)) {
                            super.visitVarInsn(Opcodes.ALOAD, saved);
                            super.visitMethodInsn(op, o, "pztest$resolvedOrNative", RESOLVED, itf);
                            calls[0]++;
                        } else {
                            super.visitMethodInsn(op, o, name, desc, itf);
                            if (o.equals("zombie/scripting/ScriptManager") && name.equals("FindItem")
                                    && desc.equals("(Ljava/lang/String;)" + ITEM)) {
                                super.visitInsn(Opcodes.DUP);
                                super.visitVarInsn(Opcodes.ASTORE, saved);
                                captures[0]++;
                            }
                        }
                    }
                };
            }
        }, ClassReader.EXPAND_FRAMES);
        if (candidate) {
            reader.accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                    Integer slot = CLONES.get(n + d);
                    if (slot == null) return null;
                    clones[0]++;
                    MethodVisitor mv = writer.visitMethod(Opcodes.ACC_PRIVATE | Opcodes.ACC_STATIC | Opcodes.ACC_SYNTHETIC,
                        cloneName(n, d), d.replace(")F", ITEM + ")F"), null, e);
                    return new MethodVisitor(Opcodes.ASM9, mv) {
                        int lookups;
                        int remap(int index) { return index >= slot ? index + 1 : index; }
                        @Override public void visitVarInsn(int op, int index) { super.visitVarInsn(op, remap(index)); }
                        @Override public void visitIincInsn(int index, int amount) { super.visitIincInsn(remap(index), amount); }
                        @Override public void visitFrame(int t, int nl, Object[] l, int ns, Object[] st) { }
                        @Override public void visitLocalVariable(String name, String desc, String sig, Label start, Label end, int index) {
                            super.visitLocalVariable(name, desc, sig, start, end, remap(index));
                        }
                        @Override public void visitMethodInsn(int op, String o, String name, String desc, boolean itf) {
                            if (o.equals("zombie/scripting/ScriptManager") && name.equals("FindItem")
                                    && desc.equals("(Ljava/lang/String;)" + ITEM) && lookups++ == 0) {
                                // Receiver and name were loaded by the native method; preserve their evaluation.
                                super.visitInsn(Opcodes.POP);
                                super.visitInsn(Opcodes.POP);
                                super.visitVarInsn(Opcodes.ALOAD, slot);
                                replacements[0]++;
                            } else if (o.equals(OWNER) && CLONES.containsKey(name + desc)) {
                                super.visitVarInsn(Opcodes.ALOAD, slot);
                                super.visitMethodInsn(op, o, cloneName(name, desc), desc.replace(")F", ITEM + ")F"), itf);
                            } else super.visitMethodInsn(op, o, name, desc, itf);
                        }
                    };
                }
            }, ClassReader.EXPAND_FRAMES);
            if (captures[0] != 2 || calls[0] != 2 || clones[0] != 4 || replacements[0] != 3)
                throw new IllegalStateException("Unexpected splice counts " + Arrays.toString(new int[]{captures[0],calls[0],clones[0],replacements[0]}));
            MethodVisitor mv = writer.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC | Opcodes.ACC_SYNTHETIC,
                "pztest$resolvedOrNative", RESOLVED, null, null);
            mv.visitCode();
            Label stock = new Label();
            mv.visitVarInsn(Opcodes.ALOAD, 5);
            mv.visitJumpInsn(Opcodes.IFNULL, stock);
            loadChance(mv);
            mv.visitVarInsn(Opcodes.ALOAD, 5);
            mv.visitMethodInsn(Opcodes.INVOKESTATIC, OWNER, "pztest$getActualSpawnChance", RESOLVED, false);
            mv.visitInsn(Opcodes.FRETURN);
            mv.visitLabel(stock);
            loadChance(mv);
            mv.visitMethodInsn(Opcodes.INVOKESTATIC, OWNER, "getActualSpawnChance", CHANCE, false);
            mv.visitInsn(Opcodes.FRETURN);
            mv.visitMaxs(0, 0); mv.visitEnd();
        }
        // Both direct-call targets coexist in the candidate class. Shared generator
        // keeps the initial lookup/Rand prefix byte-identical; only chance target differs.
        iterationBridge(writer, "pztest$iterationNative", false);
        iterationBridge(writer, "pztest$iterationResolved", candidate);
        iterationBridge(writer, "pztest$iteration", candidate); // legacy semantic fixtures
        writer.visitEnd();
        return writer.toByteArray();
    }
    static void iterationBridge(ClassWriter writer, String name, boolean resolved) {
        MethodVisitor mv = writer.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
            name, CHANCE, null, null);
        mv.visitCode();
        mv.visitFieldInsn(Opcodes.GETSTATIC, "zombie/scripting/ScriptManager", "instance", "Lzombie/scripting/ScriptManager;");
        mv.visitVarInsn(Opcodes.ALOAD, 0);
        mv.visitFieldInsn(Opcodes.GETFIELD, OWNER + "$ItemPickerItem", "itemName", "Ljava/lang/String;");
        mv.visitMethodInsn(Opcodes.INVOKEVIRTUAL, "zombie/scripting/ScriptManager", "FindItem", "(Ljava/lang/String;)" + ITEM, false);
        mv.visitVarInsn(Opcodes.ASTORE, 5);
        mv.visitIntInsn(Opcodes.SIPUSH, 10000);
        mv.visitMethodInsn(Opcodes.INVOKESTATIC, "zombie/core/random/Rand", "Next", "(I)I", false);
        mv.visitInsn(Opcodes.POP);
        loadChance(mv);
        if (resolved) mv.visitVarInsn(Opcodes.ALOAD, 5);
        mv.visitMethodInsn(Opcodes.INVOKESTATIC, OWNER,
            resolved ? "pztest$resolvedOrNative" : "getActualSpawnChance", resolved ? RESOLVED : CHANCE, false);
        mv.visitInsn(Opcodes.FRETURN);
        mv.visitMaxs(0, 0); mv.visitEnd();
    }

    static void loadChance(MethodVisitor mv) {
        for (int i = 0; i < 3; i++) mv.visitVarInsn(Opcodes.ALOAD, i);
        mv.visitVarInsn(Opcodes.FLOAD, 3); mv.visitVarInsn(Opcodes.ILOAD, 4);
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 3) throw new IllegalArgumentException("native JAR, new overlay, stock|candidate required");
        if (!Set.of("stock", "candidate").contains(args[2])) throw new IllegalArgumentException("stock|candidate required");
        Path out = Path.of(args[1]);
        if (Files.exists(out)) throw new IllegalArgumentException("Output must be new");
        byte[] bytes;
        try (ZipFile jar = new ZipFile(args[0])) {
            bytes = jar.getInputStream(jar.getEntry(OWNER + ".class")).readAllBytes();
        }
        byte[] result = transform(bytes, args[2].equals("candidate"));
        try { transform(result, true); throw new AssertionError("Accepted changed bytes"); }
        catch (IllegalArgumentException expected) { }
        Path target = out.resolve(OWNER + ".class");
        Files.createDirectories(target.getParent()); Files.write(target, result);
        System.out.println("RESOLVED_SPLICE_READY " + args[2] + " " + sha(result));
    }
}
