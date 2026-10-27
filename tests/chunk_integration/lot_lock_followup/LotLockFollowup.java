import com.sun.management.ThreadMXBean;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import zombie.ZomboidFileSystem;
import zombie.iso.IsoLot;
import zombie.iso.MapFiles;

/** Native get/put and original fixture; telemetry never changes the parsed workload. */
public final class LotLockFollowup {
    private static final ThreadMXBean CPU = (ThreadMXBean)ManagementFactory.getThreadMXBean();
    private static final int[][] CHUNKS = {{0, 0}, {1, 2}, {31, 31}};
    private static volatile long sink;
    private record Dataset(MapFiles map, long[] checksums) {}
    private record Sample(long checksum, long wall, long cpu, long allocated,
                          long opens, long refills, long bytes, long eof) {}

    public static void main(String[] args) throws Exception {
        int iterations = Integer.getInteger("lot.iterations", 100000);
        int rounds = Integer.getInteger("lot.rounds", 5);
        int warmup = Integer.getInteger("lot.warmup", 8);
        String mode = args[0];
        require(iterations > 0 && iterations <= 1000000 && rounds > 0 && rounds <= 20
                && warmup >= 1 && warmup <= 30, "bounds");
        require(CPU.isThreadCpuTimeSupported() && CPU.isThreadAllocatedMemorySupported(), "CPU/allocation support");
        CPU.setThreadCpuTimeEnabled(true);
        CPU.setThreadAllocatedMemoryEnabled(true);
        Path cache = Path.of(System.getProperty("pz.test.cache"));
        require(cache.isAbsolute() && !Files.exists(Path.of("media")), "isolated cache/work required");
        Files.createDirectories(cache);
        ZomboidFileSystem.instance.setCacheDir(cache.toString());
        ZomboidFileSystem.instance.init();
        Path root = Files.createTempDirectory(cache, "lot-followup-");
        List<Dataset> sets = List.of(fixture(root, "legacy", false, -1, 1, 100),
            fixture(root, "version1", true, -1, 1, 200), fixture(root, "single-level", true, 0, 0, 300));
        try {
            // Equal cross-path priming exercises constructor/header and both get overloads.
            for (int i = 0; i < 20000; i++) {
                IsoLot lot = get(sets.get(i % 3), i % 3, (i & 1) == 0);
                sink = checksum(lot);
                IsoLot.put(lot);
            }
            clearPool();
            for (int i = 0; i < warmup; i++) phase(mode, "fixed-single", sets, iterations, 1, false, i);
            for (int i = 0; i < rounds; i++) phase(mode, "fixed-single", sets, iterations, 1, true, i);
            clearPool();
            // This reproduces the old single/two alternation and shared pool, including
            // scheduling-dependent file changes. It is not an equal-I/O throughput control.
            for (int i = 0; i < warmup; i++) {
                phase(mode, "mixed-single", sets, iterations, 1, false, i);
                phase(mode, "mixed-two", sets, iterations, 2, false, i);
            }
            for (int i = 0; i < rounds; i++) {
                phase(mode, "mixed-single", sets, iterations, 1, true, i);
                phase(mode, "mixed-two", sets, iterations, 2, true, i);
            }
            System.out.println("LOT_LOCK_FOLLOWUP_OK");
        } finally { clearPool(); }
    }

    private static Dataset fixture(Path root, String label, boolean modern, int min, int max, int salt) throws Exception {
        // Reuse the preserved synthetic fixture; no parser or fixture fork is maintained.
        Method create = LotLockCheck.class.getDeclaredMethod("dataset", Path.class, String.class,
            boolean.class, int.class, int.class, int.class);
        create.setAccessible(true);
        Object original = create.invoke(null, root, label, modern, min, max, salt);
        Method map = original.getClass().getDeclaredMethod("map");
        map.setAccessible(true);
        Dataset result = new Dataset((MapFiles)map.invoke(original), new long[3]);
        Method check = LotLockCheck.class.getDeclaredMethod("check", original.getClass(), int.class, IsoLot.class);
        check.setAccessible(true);
        for (int c = 0; c < 3; c++) {
            IsoLot lot = get(result, c, (c & 1) == 0);
            check.invoke(null, original, c, lot);
            result.checksums[c] = checksum(lot);
            IsoLot.put(lot);
        }
        System.out.printf(Locale.ROOT, "FIXTURE %s %d %d %d%n", label,
            result.checksums[0], result.checksums[1], result.checksums[2]);
        return result;
    }

    private static IsoLot get(Dataset set, int chunk, boolean primitive) {
        int wx = 64 + CHUNKS[chunk][0], wy = -96 + CHUNKS[chunk][1];
        return primitive ? IsoLot.get(set.map, 2, -3, wx, wy, null)
            : IsoLot.get(set.map, Integer.valueOf(2), Integer.valueOf(-3), Integer.valueOf(wx), Integer.valueOf(wy), null);
    }
    private static long checksum(IsoLot lot) {
        long sum = lot.wx + lot.wy + lot.minLevel + lot.maxLevel + lot.offsetInData[0] + lot.offsetInData[56];
        for (int d = 0; d < lot.data.size(); d++) sum += lot.data.getQuick(d);
        return sum;
    }
    private static long expected(Dataset set, int iterations) {
        long sum = 0;
        for (int i = 0; i < iterations; i++) sum += set.checksums[i % 3];
        return sum;
    }
    private static Sample loop(Dataset set, int iterations) {
        LotIoCounters.Counts counts = LotIoCounters.counts();
        long opens = counts.opens, refills = counts.refills, bytes = counts.bytes, eof = counts.eof;
        long cpu = CPU.getCurrentThreadCpuTime(), allocated = CPU.getCurrentThreadAllocatedBytes();
        long begin = System.nanoTime(), sum = 0;
        for (int i = 0; i < iterations; i++) {
            IsoLot lot = get(set, i % 3, (i & 1) == 0);
            sum += checksum(lot);
            IsoLot.put(lot);
        }
        long wall = System.nanoTime() - begin;
        return new Sample(sum, wall, CPU.getCurrentThreadCpuTime() - cpu,
            CPU.getCurrentThreadAllocatedBytes() - allocated, counts.opens - opens,
            counts.refills - refills, counts.bytes - bytes, counts.eof - eof);
    }
    private static void phase(String mode, String label, List<Dataset> sets, int iterations,
                              int threads, boolean report, int round) throws Exception {
        CountDownLatch ready = new CountDownLatch(threads), start = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        Sample[] samples = new Sample[threads];
        List<Thread> workers = new ArrayList<>();
        for (int id = 0; id < threads; id++) {
            final int worker = id;
            final long expectedChecksum = expected(sets.get(worker), iterations);
            Thread thread = new Thread(() -> {
                try {
                    LotIoCounters.counts();
                    ready.countDown();
                    require(start.await(10, TimeUnit.SECONDS), "start timeout");
                    samples[worker] = loop(sets.get(worker), iterations);
                    require(samples[worker].checksum == expectedChecksum, "checksum mismatch");
                } catch (Throwable error) { failure.compareAndSet(null, error); }
            }, "lot-followup-" + worker);
            thread.setDaemon(true);
            workers.add(thread);
            thread.start();
        }
        require(ready.await(10, TimeUnit.SECONDS), "ready timeout");
        long beganMs = ManagementFactory.getRuntimeMXBean().getUptime(), begin = System.nanoTime();
        start.countDown();
        for (Thread worker : workers) {
            worker.join(30000);
            require(!worker.isAlive(), "worker timeout");
        }
        long wall = System.nanoTime() - begin, endedMs = ManagementFactory.getRuntimeMXBean().getUptime();
        if (failure.get() != null) throw new AssertionError("native loop failed", failure.get());
        long sum = 0, cpu = 0, allocated = 0, opens = 0, refills = 0, bytes = 0, eof = 0;
        for (Sample sample : samples) {
            sum += sample.checksum; cpu += sample.cpu; allocated += sample.allocated;
            opens += sample.opens; refills += sample.refills; bytes += sample.bytes; eof += sample.eof;
        }
        sink = sum;
        if (report) {
            System.out.printf(Locale.ROOT, "WINDOW %s %d %d %d%n", label, round, beganMs, endedMs);
            System.out.printf(Locale.ROOT, "ROW %s %s %d %d %d %d %d %d %d %d %d %d%n",
                mode, label, round, iterations * threads, wall, cpu, allocated, opens, refills, bytes, eof, sum);
            for (int worker = 0; worker < samples.length; worker++) {
                Sample s = samples[worker];
                System.out.printf(Locale.ROOT, "WORKER %s %d %d %d %d %d %d %d %d %d %d%n",
                    label, round, worker, s.wall, s.cpu, s.allocated, s.opens, s.refills, s.bytes, s.eof, s.checksum);
            }
            if (label.equals("fixed-single")) require(opens == 0 && refills > 0 && bytes > 0,
                "fixed path must be primed and perform counted real reads");
        }
    }
    private static void clearPool() { IsoLot.Dispose(); IsoLot.pool.clear(); }
    private static void require(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
