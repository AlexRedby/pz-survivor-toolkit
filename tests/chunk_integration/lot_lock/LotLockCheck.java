import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import zombie.ChunkMapFilenames;
import zombie.ZomboidFileSystem;
import zombie.iso.IsoChunk;
import zombie.iso.IsoCell;
import zombie.iso.IsoLot;
import zombie.iso.LotHeader;
import zombie.iso.MapFiles;

/**
 * Actual-source headless consumer: constructs owned synthetic lotpack files, then calls
 * the external game's get/load/put/Dispose implementation. No parser is substituted.
 * Run in an empty scratch directory with isolated user.home and absolute pz.test.cache.
 */
public final class LotLockCheck {
    private static final int THREADS = 4;
    private static final int ROUNDS = 24;
    private static final int CX = 2, CY = -3;
    private static final int[][] CHUNKS = {{0, 0}, {1, 2}, {31, 31}};
    private static final Field INPUT = field("in");
    private static final Field LAST_PATH = field("lastUsedPath");
    private static final Field VERSION = field("version");
    private static volatile long sink;

    private record Expected(int[] offsets, int[] data, int min, int max) {}
    private record Dataset(String label, MapFiles map, LotHeader header, Path path,
                           int version, Expected[] expected) {}

    public static void main(String[] args) throws Exception {
        require(args.length >= 1 && (args[0].equals("stock") || args[0].equals("candidate")),
            "first argument must be stock or candidate");
        String cache = System.getProperty("pz.test.cache");
        require(cache != null && Path.of(cache).isAbsolute(), "supply owned absolute pz.test.cache");
        Files.createDirectories(Path.of(cache));
        require(!Files.exists(Path.of("media")), "run in empty scratch directory");
        ZomboidFileSystem.instance.setCacheDir(cache);
        ZomboidFileSystem.instance.init();
        Path root = Files.createTempDirectory(Path.of(cache), "lot-fixture-");
        Dataset old = dataset(root, "legacy", false, -1, 1, 100);
        Dataset modern = dataset(root, "version1", true, -1, 1, 200);
        Dataset single = dataset(root, "single-level", true, 0, 0, 300);
        List<Dataset> sets = List.of(old, modern, single);
        try {
            sequential(sets);
            concurrent(sets);
            blockedIo(modern, args[0].equals("candidate"));
            if (List.of(args).contains("--measure")) measure(sets);
            System.out.println("LOT_LOCK_CHECK_OK");
        } finally {
            IsoLot.Dispose();
            IsoLot.pool.clear();
        }
    }

    private static void sequential(List<Dataset> sets) throws Exception {
        for (Dataset set : sets) {
            clearPool();
            IsoLot previous = null;
            RandomAccessFile previousInput = null;
            for (int i = 0; i < CHUNKS.length; i++) {
                IsoLot lot = get(set, i, (i & 1) == 0, null);
                check(set, i, lot);
                require(previous == null || lot == previous, "pooled identity reuse");
                require(previousInput == null || INPUT.get(lot) == previousInput, "same path input reuse");
                report(set.label + "/chunk" + i, set, i, lot);
                previous = lot;
                previousInput = (RandomAccessFile)INPUT.get(lot);
                IsoLot.put(lot);
                require(lot.info == null && lot.data.isEmpty(), "put clears payload/header");
            }
            System.out.println("VECTOR " + set.label + "/pool-reuse true input-reuse=true put-clears=true");
        }
        clearPool();
        IsoLot first = get(sets.get(0), 1, true, null);
        RandomAccessFile original = (RandomAccessFile)INPUT.get(first);
        IsoLot.put(first);
        IsoLot changed = get(sets.get(1), 2, false, null);
        check(sets.get(1), 2, changed);
        require(first == changed && original != INPUT.get(changed), "map/path switch on pooled instance");
        require(!original.getFD().valid(), "old file closed on path change");
        report("map-path-change", sets.get(1), 2, changed);
        IsoLot.put(changed);
        System.out.println("VECTOR map-path-change/reuse true old-input-closed=true");

        Dataset set = sets.get(0);
        String headerKey = ChunkMapFilenames.instance.getHeader(CX, CY);
        IsoLot.InfoHeaders.put(headerKey, set.header);
        IsoChunk chunk = new IsoChunk((IsoCell)null);
        IsoLot lot = get(set, 0, true, chunk);
        require(chunk.lotheader == set.header, "matching global header assigned to chunk");
        IsoLot.put(lot);
        chunk.lotheader = null;
        IsoLot.InfoHeaders.put(headerKey, new LotHeader(CX, CY));
        lot = get(set, 0, false, chunk);
        require(lot.info == set.header && chunk.lotheader == null, "foreign global header not assigned");
        IsoLot.put(lot);
        System.out.println("VECTOR chunk-header same-identity=true foreign-identity-skipped=true");
        IsoLot.Dispose();
        require(INPUT.get(lot) == null, "Dispose closes pooled input");
        // Dispose retains the pool. Synthetic MapFiles are not globally registered here;
        // this checks stream close/reopen, not full world metadata teardown/reload.
        IsoLot reopened = get(set, 0, true, null);
        require(reopened == lot && INPUT.get(reopened) != null, "pooled reopen after Dispose");
        check(set, 0, reopened);
        IsoLot.put(reopened);
        System.out.println("VECTOR dispose pooled-input-closed=true retained-instance-reopens=true");
    }

    private static void concurrent(List<Dataset> sets) throws Exception {
        clearPool();
        Set<IsoLot> held = Collections.newSetFromMap(new IdentityHashMap<>());
        CyclicBarrier barrier = new CyclicBarrier(THREADS);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        List<Thread> workers = new ArrayList<>();
        for (int id = 0; id < THREADS; id++) {
            final int worker = id;
            Thread thread = new Thread(() -> {
                try {
                    for (int round = 0; round < ROUNDS; round++) {
                        Dataset set = sets.get((round + worker) % sets.size());
                        int chunk = (round + worker) % CHUNKS.length;
                        IsoLot lot = get(set, chunk, ((round + worker) & 1) == 0, null);
                        synchronized (held) { require(held.add(lot), "simultaneously held identity duplicated"); }
                        check(set, chunk, lot);
                        barrier.await(10, TimeUnit.SECONDS);
                        // All four callers retain their object while each checks its parsed output.
                        synchronized (held) { require(held.size() == THREADS, "missing held identity"); }
                        check(set, chunk, lot);
                        barrier.await(10, TimeUnit.SECONDS);
                        synchronized (held) { held.remove(lot); }
                        IsoLot.put(lot);
                        barrier.await(10, TimeUnit.SECONDS);
                    }
                } catch (Throwable error) { failure.compareAndSet(null, error); barrier.reset(); }
            }, "lot-file-worker-" + id);
            thread.setDaemon(true);
            workers.add(thread);
            thread.start();
        }
        for (Thread worker : workers) {
            worker.join(30_000);
            require(!worker.isAlive(), "concurrent workload timed out");
        }
        if (failure.get() != null) throw new AssertionError("concurrent native loads", failure.get());
        require(held.isEmpty(), "held identities leaked");
        System.out.printf(Locale.ROOT, "VECTOR concurrent-file-loads workers=%d rounds=%d unique-held=true outputs=true%n",
            THREADS, ROUNDS);
    }

    private static void blockedIo(Dataset set, boolean candidate) throws Exception {
        clearPool();
        CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        BlockingInput input = new BlockingInput(set.path, entered, release);
        IsoLot seeded = new IsoLot();
        INPUT.set(seeded, input);
        LAST_PATH.set(seeded, set.path.toAbsolutePath().toString());
        VERSION.setInt(seeded, set.version);
        IsoLot.put(seeded);
        AtomicReference<IsoLot> first = new AtomicReference<>(), second = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();
        CountDownLatch secondDone = new CountDownLatch(1);
        Thread one = thread("lot-blocked-reader", failure, () -> first.set(get(set, 0, true, null)));
        require(entered.await(10, TimeUnit.SECONDS), "first native parser did not enter injected read");
        Thread two = thread("lot-independent-reader", failure, () -> {
            try { second.set(get(set, 1, false, null)); } finally { secondDone.countDown(); }
        });
        try {
            if (candidate) {
                require(secondDone.await(10, TimeUnit.SECONDS), "independent candidate load did not complete");
                require(first.get() == null && one.isAlive(), "first read must remain blocked");
                require(second.get() != null && second.get() != seeded, "distinct identity while first held");
                check(set, 1, second.get());
            } else {
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
                boolean observed = false;
                while (System.nanoTime() < deadline && failure.get() == null) {
                    ThreadInfo info = ManagementFactory.getThreadMXBean().getThreadInfo(two.threadId());
                    if (info != null && info.getThreadState() == Thread.State.BLOCKED
                            && info.getLockInfo() != null
                            && info.getLockInfo().getIdentityHashCode() == System.identityHashCode(IsoLot.class)
                            && info.getLockOwnerId() == one.threadId()) { observed = true; break; }
                    Thread.sleep(1);
                }
                require(observed && secondDone.getCount() == 1, "stock second caller must block on IsoLot.class");
            }
        } finally {
            release.countDown();
            one.join(10_000);
            two.join(10_000);
            input.close();
        }
        require(!one.isAlive() && !two.isAlive(), "blocked-I/O threads did not finish");
        if (failure.get() != null) throw new AssertionError("blocked-I/O native calls", failure.get());
        require(first.get() == seeded && first.get() != second.get(), "blocked fixture identities");
        check(set, 0, first.get());
        check(set, 1, second.get());
        IsoLot.put(first.get());
        IsoLot.put(second.get());
        // This is a deterministic scheduling assertion, not an I/O latency measurement.
        System.out.println("SCHEDULING synthetic-block " + (candidate ? "independent-load-completed" : "class-monitor-blocked"));
        System.out.println("VECTOR blocked-io parsed-outputs=true unique-held=true");
    }

    @FunctionalInterface private interface CheckedRunnable { void run() throws Exception; }

    private static Thread thread(String name, AtomicReference<Throwable> failure, CheckedRunnable action) {
        Thread thread = new Thread(() -> {
            try { action.run(); } catch (Throwable error) { failure.compareAndSet(null, error); }
        }, name);
        thread.setDaemon(true);
        thread.start();
        return thread;
    }

    private static final class BlockingInput extends RandomAccessFile {
        private final CountDownLatch entered, release;
        private boolean blocked;
        BlockingInput(Path path, CountDownLatch entered, CountDownLatch release) throws IOException {
            super(path.toFile(), "r");
            this.entered = entered;
            this.release = release;
        }
        @Override public int read() throws IOException {
            if (!blocked) {
                blocked = true;
                entered.countDown();
                try {
                    if (!release.await(20, TimeUnit.SECONDS)) throw new IOException("fixture read release timeout");
                } catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new IOException(error); }
            }
            return super.read();
        }
    }

    private static Dataset dataset(Path root, String label, boolean modern, int min, int max, int salt) throws Exception {
        Path path = root.resolve(label + ".lotpack");
        Expected[] expectations = new Expected[CHUNKS.length];
        try (RandomAccessFile file = new RandomAccessFile(path.toFile(), "rw")) {
            if (modern) { file.write(LotHeader.LOTPACK_MAGIC); little(file, 1); }
            little(file, 1024);
            int table = modern ? 12 : 4;
            file.setLength(table + 1024 * 8L);
            for (int c = 0; c < CHUNKS.length; c++) {
                ByteArrayOutputStream payload = new ByteArrayOutputStream();
                int count = (max - min + 1) * 64;
                int[] offsets = new int[count];
                Arrays.fill(offsets, -1);
                List<Integer> values = new ArrayList<>();
                int nonemptyMin = 0, nonemptyMax = 0;
                for (int pos = 0; pos < count;) {
                    boolean populated = pos == 0 || pos == 7 || pos == 65 || pos == count - 1;
                    if (populated) {
                        int level = min + pos / 64;
                        int x = (pos % 64) / 8, y = pos % 8;
                        offsets[x + y * 8 + (level - min) * 64] = values.size();
                        int tiles = 1 + (pos % 3);
                        little(payload, tiles + 1);
                        little(payload, -12345); // Room metadata read/discarded by the actual native parser.
                        values.add(tiles);
                        for (int tile = 0; tile < tiles; tile++) {
                            int value = salt + c * 1000 + pos * 10 + tile;
                            little(payload, value);
                            values.add(value);
                        }
                        nonemptyMin = Math.min(nonemptyMin, level);
                        nonemptyMax = Math.max(nonemptyMax, level);
                        pos++;
                    } else if (pos == 1 || pos == 2) {
                        little(payload, pos - 1); // Exercise both explicit empty counts, 0 and 1.
                        pos++;
                    } else {
                        int end = pos + 1;
                        while (end < count && end != 7 && end != 65 && end != count - 1) end++;
                        little(payload, -1);
                        little(payload, end - pos); // Includes an empty run across level boundaries.
                        pos = end;
                    }
                }
                long offset = file.length();
                file.seek(offset);
                file.write(payload.toByteArray());
                int chunkIndex = CHUNKS[c][0] * 32 + CHUNKS[c][1];
                file.seek(table + chunkIndex * 8L);
                little(file, Math.toIntExact(offset));
                little(file, payload.size());
                expectations[c] = new Expected(offsets, values.stream().mapToInt(Integer::intValue).toArray(),
                    nonemptyMin, nonemptyMax + 1);
            }
        }
        MapFiles map = new MapFiles(label, root.toString(), root.toString(), 0);
        LotHeader header = new LotHeader(CX, CY);
        header.minLevel = min;
        header.maxLevel = max;
        header.mapFiles = map;
        map.infoHeaders.put(ChunkMapFilenames.instance.getHeader(CX, CY), header);
        map.infoFileNames.put("world_" + CX + "_" + CY + ".lotpack", path.toAbsolutePath().toString());
        return new Dataset(label, map, header, path, modern ? 1 : 0, expectations);
    }

    private static IsoLot get(Dataset set, int index, boolean primitive, IsoChunk chunk) {
        int wx = CX * 32 + CHUNKS[index][0], wy = CY * 32 + CHUNKS[index][1];
        if (primitive) return IsoLot.get(set.map, CX, CY, wx, wy, chunk);
        return IsoLot.get(set.map, Integer.valueOf(CX), Integer.valueOf(CY), Integer.valueOf(wx), Integer.valueOf(wy), chunk);
    }

    private static void check(Dataset set, int index, IsoLot lot) {
        Expected expected = set.expected[index];
        require(lot.info == set.header, "native header identity " + set.label);
        require(lot.wx == CX * 32 + CHUNKS[index][0] && lot.wy == CY * 32 + CHUNKS[index][1], "wx/wy");
        require(lot.minLevel == expected.min && lot.maxLevel == expected.max, "min/max level");
        require(Arrays.equals(Arrays.copyOf(lot.offsetInData, expected.offsets.length), expected.offsets), "offsets " + set.label);
        require(Arrays.equals(lot.data.toArray(), expected.data), "data " + set.label);
    }

    private static void report(String label, Dataset set, int index, IsoLot lot) {
        System.out.printf(Locale.ROOT, "VECTOR %s wx=%d wy=%d min=%d max=%d header=true offsets=%s data=%s%n",
            label, lot.wx, lot.wy, lot.minLevel, lot.maxLevel,
            Arrays.toString(Arrays.copyOf(lot.offsetInData, set.expected[index].offsets.length)),
            Arrays.toString(lot.data.toArray()));
    }

    private static void measure(List<Dataset> sets) throws Exception {
        int iterations = Integer.getInteger("lot.iterations", 2000);
        require(iterations > 0 && iterations <= 1_000_000, "lot.iterations must be 1..1000000");
        clearPool();
        // Exercise header read(byte[], off, len) deterministically. Shared-pool scheduling
        // otherwise makes reopen frequency nondeterministic and can defer its compilation.
        for (int i = 0; i < 20000; i++) {
            IsoLot lot = get(sets.get(i % sets.size()), i % CHUNKS.length, (i & 1) == 0, null);
            sink = lot.data.size();
            IsoLot.put(lot);
        }
        // Warm filesystem/cache workload; no synthetic delays or claims about cold disk latency.
        for (int i = 0; i < 5; i++) {
            timedLoop(sets, Math.min(iterations, 10000), 1, false, i);
            timedLoop(sets, Math.min(iterations, 10000), 2, false, i);
        }
        for (int round = 0; round < 3; round++) {
            timedLoop(sets, iterations, 1, true, round);
            timedLoop(sets, iterations, 2, true, round);
        }
    }

    private static long loop(Dataset set, int iterations) {
        long sum = 0;
        for (int i = 0; i < iterations; i++) {
            IsoLot lot = get(set, i % CHUNKS.length, (i & 1) == 0, null);
            sum += lot.wx + lot.wy + lot.minLevel + lot.maxLevel + lot.offsetInData[0] + lot.offsetInData[56];
            for (int d = 0; d < lot.data.size(); d++) sum += lot.data.getQuick(d);
            IsoLot.put(lot);
        }
        return sum;
    }

    private static void timedLoop(List<Dataset> sets, int iterations, int threads, boolean report, int round) throws Exception {
        String label = threads == 1 ? "warm-file-single" : "warm-file-two";
        CountDownLatch ready = new CountDownLatch(threads), start = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        long[] sums = new long[threads];
        List<Thread> workers = new ArrayList<>();
        for (int id = 0; id < threads; id++) {
            final int worker = id;
            workers.add(thread("lot-measure-" + id, failure, () -> {
                ready.countDown();
                require(start.await(10, TimeUnit.SECONDS), "measurement start timeout");
                sums[worker] = loop(sets.get(worker), iterations);
            }));
        }
        require(ready.await(10, TimeUnit.SECONDS), "measurement ready timeout");
        long beganMs = ManagementFactory.getRuntimeMXBean().getUptime();
        long began = System.nanoTime();
        start.countDown();
        for (Thread worker : workers) { worker.join(30_000); require(!worker.isAlive(), "measurement worker timeout"); }
        long elapsed = System.nanoTime() - began;
        long endedMs = ManagementFactory.getRuntimeMXBean().getUptime();
        if (failure.get() != null) throw new AssertionError("measurement native calls", failure.get());
        long sum = Arrays.stream(sums).sum();
        sink = sum;
        if (report) {
            System.out.printf(Locale.ROOT, "WINDOW %s %d %d %d%n", label, round, beganMs, endedMs);
            System.out.printf(Locale.ROOT, "MEASURE %s %d %d %d%n", label, round, iterations * threads, elapsed);
            System.out.printf(Locale.ROOT, "CONSUMED %s %d %d%n", label, round, sum);
        }
    }

    private static void clearPool() { IsoLot.Dispose(); IsoLot.pool.clear(); }
    private static Field field(String name) {
        try { Field value = IsoLot.class.getDeclaredField(name); value.setAccessible(true); return value; }
        catch (ReflectiveOperationException error) { throw new ExceptionInInitializerError(error); }
    }
    private static void little(RandomAccessFile out, int value) throws IOException {
        for (int i = 0; i < 4; i++) out.write(value >>> (i * 8));
    }
    private static void little(ByteArrayOutputStream out, int value) {
        for (int i = 0; i < 4; i++) out.write(value >>> (i * 8));
    }
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
