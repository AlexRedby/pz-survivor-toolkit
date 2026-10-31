package toolkit.lootresolved.bootstrap;

import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.uncommons.maths.random.CellularAutomatonRNG;
import zombie.core.random.*;

/** Real native algorithms and concurrent worker; headless fixture validation, not gameplay. */
public final class RngScopeChecks {
    private static final int PATTERNS = 20_000, WIDTH = 10;
    private static final List<String> CHOICES = List.of("A","B","C");
    private static Field field(String name) throws Exception { Field f = RandAbstract.class.getDeclaredField(name); f.setAccessible(true); return f; }
    private static RandStandard random(byte tail) throws Exception {
        var ctor = RandStandard.class.getDeclaredConstructor(); ctor.setAccessible(true);
        RandStandard value = ctor.newInstance(); field("rand").set(value,new CellularAutomatonRNG(new byte[]{7,19,31,tail}));
        return value;
    }
    private static byte[] state() throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ObjectOutputStream stream = new ObjectOutputStream(bytes)) { stream.writeObject(field("rand").get(RandStandard.INSTANCE)); }
        return bytes.toByteArray();
    }
    private static long[] oracle(RandStandard random, int count) {
        long[] out = new long[count * WIDTH];
        for (int n=0; n<count; n++) {
            int at=n*WIDTH;
            out[at]=random.Next(1_000_000); out[at+1]=random.Next(100_000L);
            out[at+2]=random.Next(-100,100); out[at+3]=random.Next(-10_000L,10_000L);
            out[at+4]=Float.floatToRawIntBits(random.Next(-1.25f,2.75f)); out[at+5]=random.NextBool(3) ? 1 : 0;
            out[at+6]=random.Next(2,16); out[at+7]=random.Next(CHOICES.size());
            float multiplier=zombie.GameTime.getInstance().getThirtyFPSMultiplier();
            out[at+8]=random.Next(0f,30f*multiplier) < multiplier ? 1 : 0;
            out[at+9]=random.AdjustForFramerate(9);
        }
        return out;
    }
    private static void wrappers(long[] expected, int begin, int end) {
        for (int n=begin; n<end; n++) {
            int at=n*WIDTH;
            long[] actual = {Rand.Next(1_000_000),Rand.Next(100_000L),Rand.Next(-100,100),Rand.Next(-10_000L,10_000L),
                Float.floatToRawIntBits(Rand.Next(-1.25f,2.75f)),Rand.NextBool(3) ? 1 : 0,Rand.NextInclusive(2,15),
                CHOICES.indexOf(Rand.Next(CHOICES)),Rand.PerThirtiethOfASecond(30) ? 1 : 0,Rand.AdjustForFramerate(9)};
            for (int i=0;i<WIDTH;i++) if (actual[i] != expected[at+i]) throw new AssertionError("native sequence mismatch pattern="+n+" slot="+i);
        }
    }
    private static void await(CountDownLatch latch) {
        try { if (!latch.await(30,TimeUnit.SECONDS)) throw new AssertionError("concurrent check deadline"); }
        catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new AssertionError(error); }
    }
    private interface Work { void run() throws Exception; }
    private static void refuses(Work work) throws Exception {
        try { work.run(); throw new AssertionError("unsupported RNG access admitted"); }
        catch (IllegalStateException expected) { }
    }
    private static void concurrent() throws Exception {
        RandStandard ownerOracle=random((byte)43), globalOracle=random((byte)91);
        long[] ownerExpected=oracle(ownerOracle,PATTERNS), foreignExpected=oracle(globalOracle,PATTERNS);
        int ownerNext=ownerOracle.Next(1_000_000), globalId=field("id").getInt(globalOracle), globalNext=globalOracle.Next(1_000_000);
        Object original=field("rand").get(RandStandard.INSTANCE);
        int originalId=field("id").getInt(RandStandard.INSTANCE);
        // Headless-only setup of the otherwise uninitialized native singleton. The implementation
        // under test performs no shared writes; this disposable check restores its initial setup.
        CellularAutomatonRNG shared=new CellularAutomatonRNG(new byte[]{7,19,31,91});
        field("rand").set(RandStandard.INSTANCE,shared); field("id").setInt(RandStandard.INSTANCE,0);
        byte[] before=state();
        AtomicReference<Throwable> failure=new AtomicReference<>();
        CountDownLatch start=new CountDownLatch(1), first=new CountDownLatch(1), continueWorker=new CountDownLatch(1), done=new CountDownLatch(1);
        Thread worker=new Thread(() -> {
            try {
                await(start);
                refuses(Bootstrap::beginRng); refuses(() -> Bootstrap.seedRng(99)); refuses(Bootstrap::endRng);
                wrappers(foreignExpected,0,1); first.countDown(); await(continueWorker);
                wrappers(foreignExpected,1,PATTERNS);
            } catch (Throwable problem) { failure.set(problem); first.countDown(); }
            finally { done.countDown(); }
        },"loot-rng-foreign");
        worker.setDaemon(true); worker.start();
        boolean ended=false;
        try {
            Bootstrap.beginRng();
            wrappers(ownerExpected,0,1_000);
            if (field("rand").get(RandStandard.INSTANCE) != shared || field("id").getInt(RandStandard.INSTANCE) != 0
                    || !Arrays.equals(before,state())) throw new AssertionError("owner changed original singleton state");
            start.countDown(); await(first); continueWorker.countDown();
            wrappers(ownerExpected,1_000,PATTERNS); await(done);
            if (failure.get()!=null) throw new AssertionError("foreign native worker failed",failure.get());
            if (Rand.Next(1_000_000) != ownerNext) throw new AssertionError("private owner continuation");
            if (field("rand").get(RandStandard.INSTANCE) != shared || field("id").getInt(RandStandard.INSTANCE) != globalId)
                throw new AssertionError("owner rewound/advanced shared identity or native id");
            Bootstrap.endRng(); ended=true;
            if (!Bootstrap.rngComplete() || Rand.Next(1_000_000) != globalNext) throw new AssertionError("outside-bank global continuation");
            Bootstrap.writeRngReceipt();
            String receipt=java.nio.file.Files.readString(Bootstrap.cache().resolve("loot-resolved-runtime-rng-"+ProcessHandle.current().pid()+".txt"));
            if (!receipt.contains("foreign_first_thread=loot-rng-foreign") || receipt.contains("foreign_wrapper_selections=0\n"))
                throw new AssertionError("missing legitimate foreign RNG observations");
        } finally {
            start.countDown(); continueWorker.countDown(); await(done);
            if (!ended) try { Bootstrap.endRng(); } catch (IllegalStateException ignored) { }
            field("rand").set(RandStandard.INSTANCE,original); field("id").setInt(RandStandard.INSTANCE,originalId);
        }
        System.out.println("LOOT_RESOLVED_RNG_CONCURRENT_CHECK_PASS owner_patterns="+PATTERNS+" foreign_patterns="+PATTERNS);
    }
    private static void poisoned(Work work, String reason) throws Exception {
        byte[] before=state(); int id=field("id").getInt(RandStandard.INSTANCE);
        Bootstrap.beginRng();
        // Deliberately swallow the original guard exception, like a native protected Lua callback.
        refuses(work);
        if (!Arrays.equals(before,state()) || field("id").getInt(RandStandard.INSTANCE) != id)
            throw new AssertionError("rejected owner bypass mutated original RNG");
        try { Bootstrap.endRng(); throw new AssertionError("swallowed guard did not poison final bank"); }
        catch (IllegalStateException expected) { if (!expected.getMessage().contains(reason)) throw expected; }
        if (Bootstrap.rngComplete()) throw new AssertionError("poisoned scope complete");
        // Following wrapper must use the original global, with no live owner remaining.
        if (RngScope.dispatch() != RandStandard.INSTANCE) throw new AssertionError("exception exit retained private routing");
    }
    public static void run() throws Exception {
        zombie.GameTime.instance=new zombie.GameTime();
        RandStandard shared=RandStandard.INSTANCE;
        field("rand").set(shared,new CellularAutomatonRNG(new byte[]{7,19,31,91}));
        concurrent();
        poisoned(() -> RandStandard.INSTANCE.Next(1_000_000),"owner-native-RNG-bypass");
        Method protectedNext=RandAbstract.class.getDeclaredMethod("Next",int.class,java.util.Random.class); protectedNext.setAccessible(true);
        poisoned(() -> {
            try { protectedNext.invoke(shared,1000,field("rand").get(shared)); }
            catch (InvocationTargetException problem) { if (problem.getCause() instanceof IllegalStateException expected) throw expected; throw problem; }
        },"owner-native-RNG-bypass");
        poisoned(shared::init,"owner-native-RNG-bypass");
        poisoned(() -> RandLua.INSTANCE.Next(1000),"owner-native-RNG-bypass");
        poisoned(() -> Rand.NextBool(0.5f),"unseeded-owner-NextBool-float");
        poisoned(() -> {
            RandStandard escaped=RngScope.dispatch();
            AtomicReference<Throwable> rejected=new AtomicReference<>();
            Thread foreign=new Thread(() -> { try { escaped.Next(1000); } catch (Throwable error) { rejected.set(error); } },"loot-rng-escaped-private");
            foreign.start(); foreign.join(10_000);
            if (foreign.isAlive() || !(rejected.get() instanceof IllegalStateException)) throw new AssertionError("escaped private receiver admitted");
            // The worker exception was observed, but this task intentionally swallows it.
            throw (IllegalStateException)rejected.get();
        },"foreign-private-RNG-receiver");
        Bootstrap.beginRng();
        try { Bootstrap.seedRng(3); Rand.Next(1000); throw new IOException("synthetic-fixture-body-failure"); }
        catch (IOException expected) { }
        finally { Bootstrap.endRng(); }
        if (!Bootstrap.rngComplete() || RngScope.dispatch()!=shared) throw new AssertionError("body exception cleanup retained private routing");
        System.out.println("LOOT_RESOLVED_RNG_BYPASS_CHECK_PASS public-protected-init-Lua-TLR-escape-finally");
    }
}
