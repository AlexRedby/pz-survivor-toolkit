package toolkit.lootresolved.bootstrap;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import org.uncommons.maths.random.CellularAutomatonRNG;
import zombie.core.random.RandAbstract;
import zombie.core.random.RandStandard;

/** Test-only owner routing. Never replaces, seeds, restores or serializes the shared singleton. */
public final class RngScope {
    public static final String KIND = "owner-thread-private-native-randstandard-v1";
    private static final AtomicReference<Scope> ACTIVE = new AtomicReference<>();
    private static volatile Scope completed;
    private static final StackWalker WALKER = StackWalker.getInstance();
    private static final Constructor<RandStandard> CONSTRUCTOR = constructor();
    private static final Field RANDOM = field("rand"), ID = field("id");
    private record Foreign(String thread, long threadId, String caller, String entry) { }
    private static final class Scope {
        final Thread owner = Thread.currentThread();
        final RandStandard random;
        final AtomicLong foreignWrappers = new AtomicLong(), foreignReceivers = new AtomicLong();
        final AtomicLong foreignPrivateRejections = new AtomicLong();
        final AtomicReference<Foreign> firstForeign = new AtomicReference<>();
        long ownerWrappers, ownerReceivers, bypasses, unseededFloatBool;
        final AtomicReference<String> poison = new AtomicReference<>();
        Scope(RandStandard random) { this.random = random; }
    }
    private static Constructor<RandStandard> constructor() {
        try { var result = RandStandard.class.getDeclaredConstructor(); result.setAccessible(true); return result; }
        catch (ReflectiveOperationException problem) { throw new ExceptionInInitializerError(problem); }
    }
    private static Field field(String name) {
        try { Field result = RandAbstract.class.getDeclaredField(name); result.setAccessible(true); return result; }
        catch (ReflectiveOperationException problem) { throw new ExceptionInInitializerError(problem); }
    }
    private static String caller() {
        return WALKER.walk(frames -> frames.filter(frame -> {
            String name = frame.getClassName();
            return !name.startsWith("toolkit.lootresolved.bootstrap.") && !name.startsWith("zombie.core.random.");
        }).findFirst().map(Object::toString).orElse("unknown"));
    }
    private static void foreign(Scope scope, String entry, boolean wrapper) {
        // Diagnostic snapshots only, with no waiting for foreign calls or RNG serialization.
        // An entry that captured the previous scope just before close can finish recording later.
        if (scope.firstForeign.get() == null) {
            Thread thread = Thread.currentThread();
            scope.firstForeign.compareAndSet(null,new Foreign(thread.getName(),thread.threadId(),caller(),entry));
        }
        (wrapper ? scope.foreignWrappers : scope.foreignReceivers).incrementAndGet();
    }
    /** Exact replacement for the nine native GETSTATIC receiver selections. */
    public static RandStandard dispatch() {
        Scope scope = ACTIVE.get();
        if (scope != null) {
            if (Thread.currentThread() == scope.owner) { scope.ownerWrappers++; return scope.random; }
            foreign(scope,"Rand.INSTANCE",true);
        }
        return RandStandard.INSTANCE;
    }
    /** Native public/protected entries retain their actual receiver and implementation. */
    public static void receiver(Object receiver, String entry, int kind) {
        Scope scope = ACTIVE.get();
        if (scope == null) return;
        if (Thread.currentThread() != scope.owner) {
            foreign(scope,entry,false);
            if (receiver == scope.random) {
                scope.foreignPrivateRejections.incrementAndGet();
                reject(scope,"foreign-private-RNG-receiver:" + caller());
            }
            return;
        }
        scope.ownerReceivers++;
        if (kind == 1) {
            scope.unseededFloatBool++;
            reject(scope,"unseeded-owner-NextBool-float:" + caller());
        }
        if (receiver != scope.random || kind == 2) {
            scope.bypasses++;
            reject(scope,"owner-native-RNG-bypass:" + entry + ":" + receiver.getClass().getName() + ":" + caller());
        }
    }
    private static void reject(Scope scope, String reason) {
        scope.poison.compareAndSet(null,reason);
        throw new IllegalStateException(reason);
    }
    public static void begin() throws Exception {
        if (ACTIVE.get() != null) throw new IllegalStateException("RNG scope already owned");
        RandStandard random = CONSTRUCTOR.newInstance();
        seed(random,0); // Fully construct/seed before publishing the owner scope.
        Scope scope = new Scope(random);
        if (!ACTIVE.compareAndSet(null,scope)) throw new IllegalStateException("RNG scope already owned");
        completed = null;
    }
    private static Scope owned() {
        Scope scope = ACTIVE.get();
        if (scope == null || Thread.currentThread() != scope.owner) throw new IllegalStateException("RNG scope owner required");
        return scope;
    }
    private static void seed(RandStandard random, int number) throws Exception {
        RANDOM.set(random,new CellularAutomatonRNG(new byte[]{7,19,31,(byte)(43 + number)}));
        ID.setInt(random,0);
    }
    public static void seed(int number) throws Exception { seed(owned().random,number); }
    public static void end() {
        Scope scope = owned();
        // Release owner routing even if a native protected callback swallowed the original error.
        if (!ACTIVE.compareAndSet(scope,null)) throw new IllegalStateException("RNG scope changed");
        completed = scope;
        if (scope.poison.get() != null) throw new IllegalStateException(scope.poison.get());
    }
    public static boolean complete() {
        Scope scope = completed;
        return ACTIVE.get() == null && scope != null && scope.poison.get() == null;
    }
    public static void writeReceipt(Path cache) throws Exception {
        Scope scope = completed;
        if (scope == null) throw new IllegalStateException("RNG scope did not close");
        long foreignWrappers = scope.foreignWrappers.get(), foreignReceivers = scope.foreignReceivers.get();
        Foreign first = scope.firstForeign.get(); // A positive captured count publishes the first observation.
        String text = "rng_scope=" + KIND + "\nrng_scope_complete=" + complete() + "\nowner_wrapper_selections=" + scope.ownerWrappers
            + "\nowner_receiver_entries=" + scope.ownerReceivers + "\nowner_bypass_rejections=" + scope.bypasses
            + "\nowner_unseeded_float_bool_rejections=" + scope.unseededFloatBool + "\nreason=" + String.valueOf(scope.poison.get())
            + "\nforeign_private_receiver_rejections=" + scope.foreignPrivateRejections.get()
            + "\nforeign_wrapper_selections=" + foreignWrappers + "\nforeign_receiver_entries=" + foreignReceivers
            + "\nforeign_counts_scope=nonblocking-entry-snapshot\nforeign_first_thread=" + (first == null ? "none" : first.thread())
            + "\nforeign_first_thread_id=" + (first == null ? 0 : first.threadId()) + "\nforeign_first_caller=" + (first == null ? "none" : first.caller())
            + "\nforeign_first_entry=" + (first == null ? "none" : first.entry()) + "\nshared_singleton_writes=0\n";
        Files.writeString(cache.resolve("loot-resolved-runtime-rng-" + ProcessHandle.current().pid() + ".txt"),text);
    }
}
