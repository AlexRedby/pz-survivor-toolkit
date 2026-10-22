package net.alexredby.pztoolkitjavapatches;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.Patch;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import zombie.core.Transaction;
import zombie.core.Transaction.TransactionState;
import zombie.inventory.ItemContainer;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.fields.ContainerID;
import zombie.network.fields.ContainerID.ContainerType;
import zombie.network.packets.ItemTransactionPacket;

/** Adds an incoming batch's checked prefix to native Request admission, without publishing it. */
public final class ItemBatchAdmission {
    private static final String TARGET = "zombie/core/TransactionManager";
    private static final String HELPER = "net/alexredby/pztoolkitjavapatches/ItemBatchAdmission";
    private static final String HASH = "4a0f649f5e55edd13eff7d6788934fbec49e0073901609e1c12731fc47d7481d";
    private static final String CHECK_DESCRIPTOR = "(ILzombie/inventory/InventoryItem;Lzombie/inventory/ItemContainer;"
        + "Lzombie/inventory/ItemContainer;Ljava/lang/String;Lzombie/network/packets/ItemTransactionPacket;"
        + "Lzombie/characters/IsoPlayer;)B";
    public static final boolean SUPPORTED = QueueManagers.ITEM_SUPPORTED
        && BytecodeSupport.supports("zombie/network/fields/ContainerID.class",
            "d7ef29f65c423135d70f829a1381b9e32ce06d68f87ae49de1980bfcf7c0244b")
        && BytecodeSupport.supports("zombie/inventory/ItemContainer.class",
            "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96");

    private static final ThreadLocal<RequestScope> requests = new ThreadLocal<>();
    private static final ThreadLocal<CheckScope> checks = new ThreadLocal<>();
    private static boolean installed;
    private static volatile boolean woven;

    private ItemBatchAdmission() { }

    public static synchronized boolean install(boolean supported) {
        if (!supported || !SUPPORTED) return false;
        if (installed) return woven;
        Instrumentation instrumentation = Accessor.tryGet(Loader.class, "g_instrumentation", (Instrumentation)null);
        if (instrumentation == null || !instrumentation.isRetransformClassesSupported()) return false;
        ClassFileTransformer transformer = new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader, String name, Class<?> type,
                                               ProtectionDomain domain, byte[] bytes) {
                if (!TARGET.equals(name)) return null;
                byte[] replacement = weave(bytes);
                woven = replacement != null;
                if (!woven) System.err.println("[PZToolkitJavaPatches] Disabled item batch admission: native consistency method changed");
                return replacement;
            }
        };
        instrumentation.addTransformer(transformer, true);
        try {
            Class<?> loaded = null;
            for (Class<?> type : instrumentation.getAllLoadedClasses()) {
                if (type.getName().equals(TARGET.replace('/', '.'))) { loaded = type; break; }
            }
            if (loaded != null) instrumentation.retransformClasses(loaded);
            else Class.forName(TARGET.replace('/', '.'), false, ItemBatchAdmission.class.getClassLoader());
            if (!woven) {
                instrumentation.removeTransformer(transformer);
                return false;
            }
            installed = true;
            return true;
        } catch (Exception | LinkageError error) {
            woven = false;
            instrumentation.removeTransformer(transformer);
            System.err.println("[PZToolkitJavaPatches] Disabled item batch admission: " + error);
            return false;
        }
    }

    public static final class RequestScope {
        final RequestScope previous;
        final ItemTransactionPacket packet;
        final List<?> entries;
        final Shadow prefix;
        int index;
        boolean checking;
        RequestScope(RequestScope previous, ItemTransactionPacket packet, List<?> entries) {
            this.previous = previous;
            this.packet = packet;
            this.entries = entries;
            this.prefix = new Shadow(packet);
        }
    }

    private static final class Shadow extends Transaction {
        Shadow(ItemTransactionPacket packet) {
            state = TransactionState.Request;
            var owner = Accessor.tryGet(packet, "playerId", (zombie.network.fields.character.PlayerID)null);
            if (owner != null && owner.getPlayer() != null) playerId.set(owner.getPlayer());
        }
        void append(Object entry) { entries.add((TransactionEntry)entry); }
        boolean isEmpty() { return entries.isEmpty(); }
        static Integer id(Object entry) { return ((TransactionEntry)entry).itemId; }
        static ContainerID source(Object entry) { return ((TransactionEntry)entry).sourceId; }
        static ContainerID destination(Object entry) { return ((TransactionEntry)entry).destinationId; }
        public String getDescription() { return "Toolkit incoming item batch prefix"; }
    }

    public static RequestScope beginRequest(ItemTransactionPacket packet) {
        if (!woven || !GameServer.server || GameClient.client
            || Accessor.tryGet(packet, "state", (TransactionState)null) != TransactionState.Request) return null;
        String extra = Accessor.tryGet(packet, "extra", (String)null);
        if (extra != null && !extra.isEmpty()) return null;
        List<?> entries = Accessor.tryGet(packet, "entries", (List<?>)null);
        if (entries == null || entries.size() < 2) return null;
        ItemContainer source = null, destination = null;
        for (Object entry : entries) {
            if (entry == null || Shadow.id(entry) == null || Shadow.id(entry) == -1
                || special(Shadow.source(entry).containerType) || special(Shadow.destination(entry).containerType)) return null;
            ItemContainer sc = Shadow.source(entry).getContainer(), dc = Shadow.destination(entry).getContainer();
            if (sc == null || dc == null || "floor".equals(sc.getType()) || "floor".equals(dc.getType())) return null;
            if (source == null) { source = sc; destination = dc; }
            else if (source != sc || destination != dc) return null;
        }
        RequestScope scope = new RequestScope(requests.get(), packet, entries);
        requests.set(scope);
        return scope;
    }

    private static boolean special(ContainerType type) {
        return type == ContainerType.Undefined || type == ContainerType.IsoObject || type == ContainerType.Floor;
    }

    public static void endRequest(RequestScope scope) {
        if (scope == null) return;
        if (scope.previous == null) requests.remove();
        else requests.set(scope.previous);
    }

    public static final class CheckScope {
        final CheckScope previous;
        final RequestScope request;
        final Object entry;
        CheckScope(CheckScope previous, RequestScope request, Object entry) {
            this.previous = previous;
            this.request = request;
            this.entry = entry;
        }
    }

    public static CheckScope beginCheck(ItemTransactionPacket packet, int itemId,
                                        ItemContainer source, ItemContainer destination) {
        RequestScope request = requests.get();
        CheckScope previous = checks.get();
        if (request == null && previous == null) return null;
        Object entry = null;
        if (request != null && request.packet == packet && !request.checking && request.index < request.entries.size()) {
            Object candidate = request.entries.get(request.index);
            if (Shadow.id(candidate) == itemId && Shadow.source(candidate).getContainer() == source
                && Shadow.destination(candidate).getContainer() == destination) entry = candidate;
        }
        // Mask an outer check during unrelated/reentrant native consistency calls.
        CheckScope scope = new CheckScope(previous, entry == null ? null : request, entry);
        if (scope.request != null) scope.request.checking = true;
        checks.set(scope);
        return scope;
    }

    public static void endCheck(CheckScope scope, byte result, Throwable failure) {
        if (scope == null) return;
        try {
            if (scope.request != null) {
                if (failure == null && result == 0) {
                    scope.request.prefix.append(scope.entry);
                    scope.request.index++;
                }
                scope.request.checking = false;
            }
        } finally {
            if (scope.previous == null) checks.remove();
            else checks.set(scope.previous);
        }
    }

    /** Called only at the native isConsistent reservation-iteration site. No queue mutation. */
    public static Iterator<Transaction> reservations(ConcurrentLinkedQueue<Transaction> real) {
        Iterator<Transaction> nativeIterator = real.iterator();
        CheckScope check = checks.get();
        if (check == null || check.request == null || check.request.prefix.isEmpty()) return nativeIterator;
        Shadow prefix = check.request.prefix;
        return new Iterator<>() {
            boolean pending = true;
            public boolean hasNext() { return nativeIterator.hasNext() || pending; }
            public Transaction next() {
                if (nativeIterator.hasNext()) return nativeIterator.next();
                if (!pending) throw new NoSuchElementException();
                pending = false;
                return prefix;
            }
        };
    }

    // Compare only this method: the independent cancellation-ownership advice changes a different
    // TransactionManager method. Fresh constant pools also tolerate HotSpot's retransformation order.
    private static byte[] canonicalCheck(byte[] bytes) {
        ClassWriter writer = new ClassWriter(0);
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, TARGET, null, "java/lang/Object", null);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                                                       String signature, String[] exceptions) {
                return "isConsistent".equals(name) && CHECK_DESCRIPTOR.equals(descriptor)
                    ? writer.visitMethod(access, name, descriptor, signature, exceptions) : null;
            }
        }, ClassReader.SKIP_DEBUG);
        writer.visitEnd();
        return writer.toByteArray();
    }

    /** Testable transformation seam. Unsupported or already changed native bytecode stays untouched. */
    public static byte[] weave(byte[] bytes) {
        try {
            byte[] original;
            try (var input = ItemBatchAdmission.class.getClassLoader().getResourceAsStream(TARGET + ".class")) {
                if (input == null) return null;
                original = input.readAllBytes();
            }
            if (!HASH.equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(original)))
                || !Arrays.equals(canonicalCheck(original), canonicalCheck(bytes))) return null;
            ClassReader reader = new ClassReader(bytes);
            ClassWriter writer = new ClassWriter(reader, 0);
            int[] replacements = {0};
            reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
                @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                                                           String signature, String[] exceptions) {
                    MethodVisitor output = super.visitMethod(access, name, descriptor, signature, exceptions);
                    if (!"isConsistent".equals(name) || !CHECK_DESCRIPTOR.equals(descriptor)) return output;
                    return new MethodVisitor(Opcodes.ASM9, output) {
                        @Override public void visitMethodInsn(int opcode, String owner, String method,
                                                              String descriptor, boolean itf) {
                            if (opcode == Opcodes.INVOKEVIRTUAL && "java/util/concurrent/ConcurrentLinkedQueue".equals(owner)
                                && "iterator".equals(method) && "()Ljava/util/Iterator;".equals(descriptor)) {
                                super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "reservations",
                                    "(Ljava/util/concurrent/ConcurrentLinkedQueue;)Ljava/util/Iterator;", false);
                                replacements[0]++;
                            } else super.visitMethodInsn(opcode, owner, method, descriptor, itf);
                        }
                    };
                }
            }, 0);
            return replacements[0] == 1 ? writer.toByteArray() : null;
        } catch (Exception error) {
            System.err.println("[PZToolkitJavaPatches] Disabled item batch bytecode: " + error);
            return null;
        }
    }

    @Patch(className="zombie.network.packets.ItemTransactionPacket", methodName="processServer", warmUp=true, strictMatch=true)
    public static class RequestAdmission {
        @Patch.OnEnter
        public static void enter(@Patch.This ItemTransactionPacket packet,
                                 @Patch.Argument(1) zombie.core.raknet.UdpConnection connection,
                                 @Patch.Local("toolkitItemBatchRequest") RequestScope scope) {
            scope = beginRequest(packet);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitItemBatchRequest") RequestScope scope) {
            endRequest(scope);
        }
    }

    @Patch(className="zombie.core.TransactionManager", methodName="isConsistent", warmUp=true, strictMatch=true)
    public static class EntryAdmission {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) int itemId, @Patch.Argument(2) ItemContainer source,
                                 @Patch.Argument(3) ItemContainer destination, @Patch.Argument(5) ItemTransactionPacket packet,
                                 @Patch.Local("toolkitItemBatchCheck") CheckScope scope) {
            scope = beginCheck(packet, itemId, source, destination);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitItemBatchCheck") CheckScope scope,
                                @Patch.Return byte result, @Patch.Thrown Throwable failure) {
            endCheck(scope, result, failure);
        }
    }
}
