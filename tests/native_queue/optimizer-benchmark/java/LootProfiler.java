package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Bounded owner-thread ledger; nested fills overlap and retain inclusive call counts. */
public final class LootProfiler {
    public static final int CAPACITY=120000, MAX_DEPTH=256;
    public static final int CHANCE=0, FACTORY=1, FACTORY_NONNULL=2, BAG=3, ROLL=4,
            TRANSLATION_PLAIN=5, TRANSLATION_OTHER=6, COUNTERS=7;
    private static final String[] STAGE_NAMES={"logic","render","chunk","loot","lua","tiles","ui"};
    private static final String[] COUNTER_NAMES={"chance_calls","factory_calls","factory_nonnull",
            "bag_roll_calls","direct_roll_calls","plain_translation_calls","other_translation_calls"};
    private final int capacity;
    // All row arrays and the bounded active stack are allocated before hooks become active.
    private final long[] frames, starts, ends;
    private final int[] tokens, depths;
    private final String[] types;
    private final long[][] durations, counts;
    private final int[] stack=new int[MAX_DEPTH];
    private final long[] previous=new long[STAGE_NAMES.length], cumulative=new long[COUNTERS];
    private int used, committed, frameBase, depth;
    private long frameId, lastFrameId, lastNow, omitted;
    private boolean frameOpen, haveTime, haveSnapshot, finished;
    private String diagnostic;

    public LootProfiler() { this(CAPACITY); }
    public LootProfiler(int capacity) {
        if (capacity<1 || capacity>CAPACITY) throw new IllegalArgumentException("Loot capacity out of bounds");
        this.capacity=capacity;
        frames=new long[capacity]; starts=new long[capacity]; ends=new long[capacity];
        tokens=new int[capacity]; depths=new int[capacity]; types=new String[capacity];
        durations=new long[STAGE_NAMES.length][capacity]; counts=new long[COUNTERS][capacity];
    }

    public String diagnostic() { return diagnostic; }
    public int completeFills() { return committed; }
    public long omittedFills() { return omitted; }
    public boolean filling() { return capturing() && depth>0; }

    public void frameBegin(long id) {
        if (finished || diagnostic!=null) return;
        if (frameOpen) { fail("frame_already_open"); return; }
        if (id<=0 || id<=lastFrameId) { fail("invalid_frame_order"); return; }
        frameId=id; lastFrameId=id; frameBase=used; frameOpen=true; haveSnapshot=false;
        for (int i=0;i<previous.length;i++) previous[i]=0;
        for (int i=0;i<cumulative.length;i++) cumulative[i]=0;
    }

    public void begin(int token,String containerType,long now,long[] exclusive) {
        if (!capturing()) return;
        if (token<=0) { omitted++; fail("invalid_token"); return; }
        if (depth==MAX_DEPTH) { omitted++; fail("loot_stack_overflow"); return; }
        if (used==capacity) { omitted++; fail("loot_buffer_overflow"); return; }
        for (int i=0;i<depth;i++) {
            if (tokens[stack[i]]==token) { omitted++; fail("duplicate_active_token"); return; }
        }
        if (!snapshot(now,exclusive)) { omitted++; return; }
        int row=used++;
        frames[row]=frameId; starts[row]=now; tokens[row]=token; depths[row]=depth+1;
        types[row]=containerType==null ? "" : containerType;
        for (int stage=0;stage<durations.length;stage++) durations[stage][row]=exclusive[stage];
        for (int kind=0;kind<COUNTERS;kind++) counts[kind][row]=cumulative[kind];
        stack[depth++]=row;
    }

    /** No clock, boxing, strings or per-fill traversal on the frequently called counter path. */
    public void counter(int kind) {
        if (!capturing() || depth==0) return;
        if (kind<0 || kind>=COUNTERS) { fail("invalid_loot_counter"); return; }
        if (cumulative[kind]==Long.MAX_VALUE) { fail("loot_counter_overflow"); return; }
        cumulative[kind]++;
    }

    public void end(int token,long now,long[] exclusive) {
        // Exits after cancellation, failure or finish are deliberately harmless.
        if (!capturing()) return;
        if (depth==0 || token<=0 || tokens[stack[depth-1]]!=token) { fail("loot_token_mismatch"); return; }
        if (!snapshot(now,exclusive)) return;
        int row=stack[depth-1];
        long wall, total=0;
        try {
            wall=Math.subtractExact(now,starts[row]);
            if (wall<0) { fail("negative_loot_duration"); return; }
            for (int stage=0;stage<durations.length;stage++) {
                long value=Math.subtractExact(exclusive[stage],durations[stage][row]);
                if (value<0) { fail("negative_stage_duration"); return; }
                total=Math.addExact(total,value);
            }
        } catch (ArithmeticException overflow) { fail("loot_duration_overflow"); return; }
        if (total!=wall) { fail("loot_partition_mismatch"); return; }
        for (int stage=0;stage<durations.length;stage++) durations[stage][row]=exclusive[stage]-durations[stage][row];
        for (int kind=0;kind<COUNTERS;kind++) counts[kind][row]=cumulative[kind]-counts[kind][row];
        ends[row]=now; depth--;
    }

    public void frameEnd(boolean valid) {
        if (!capturing()) return;
        if (!valid) { rollback(); return; }
        if (depth!=0) { fail("unclosed_loot"); return; }
        committed=used; frameOpen=false;
    }

    public void cancelFrame() { if (frameOpen) rollback(); }

    private boolean capturing() { return frameOpen && !finished && diagnostic==null; }

    private boolean snapshot(long now,long[] exclusive) {
        if (haveTime && now<lastNow) { fail("nonmonotonic_loot_time"); return false; }
        if (exclusive==null || exclusive.length!=STAGE_NAMES.length) { fail("invalid_stage_snapshot"); return false; }
        long total=0;
        try {
            for (int stage=0;stage<previous.length;stage++) {
                if (exclusive[stage]<0 || exclusive[stage]<previous[stage]) {
                    fail("negative_stage_delta"); return false;
                }
                if (haveSnapshot && depth>0) total=Math.addExact(total,exclusive[stage]-previous[stage]);
            }
            // Outside a fill, elapsed time may belong to the timer's separate other bucket.
            if (haveSnapshot && depth>0 && total!=Math.subtractExact(now,lastNow)) {
                fail("loot_partition_mismatch"); return false;
            }
        } catch (ArithmeticException overflow) { fail("loot_duration_overflow"); return false; }
        for (int stage=0;stage<previous.length;stage++) previous[stage]=exclusive[stage];
        lastNow=now; haveTime=true; haveSnapshot=true;
        return true;
    }

    private void rollback() {
        omitted+=used-frameBase;
        for (int row=frameBase;row<used;row++) types[row]=null;
        used=frameBase; depth=0; frameOpen=false;
    }

    private void fail(String message) {
        if (diagnostic==null) diagnostic=message;
        if (frameOpen) rollback();
    }

    /** Escape only during export; hook entry retains the existing immutable String reference. */
    private static void csvString(BufferedWriter out,String value) throws IOException {
        boolean quoted=value.indexOf(',')>=0 || value.indexOf('"')>=0 || value.indexOf('\n')>=0 || value.indexOf('\r')>=0;
        if (!quoted) { out.write(value); return; }
        out.write('"');
        for (int i=0;i<value.length();i++) {
            char ch=value.charAt(i);
            if (ch=='"') out.write('"');
            out.write(ch);
        }
        out.write('"');
    }

    public void finish(Path cache) throws IOException {
        if (finished) return;
        cancelFrame(); finished=true;
        try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-loot.csv"))) {
            out.write("frame_id,fill_index,token,depth,container_type,nano_start,nano_end,wall_ns");
            for (String name:STAGE_NAMES) out.write(","+name+"_exclusive_ns");
            for (String name:COUNTER_NAMES) out.write(","+name);
            out.newLine();
            for (int row=0;row<committed;row++) {
                out.write(Long.toString(frames[row]));
                out.write(","+(row+1)+","+tokens[row]+","+depths[row]+",");
                csvString(out,types[row]);
                out.write(","+starts[row]+","+ends[row]+","+(ends[row]-starts[row]));
                for (long[] stage:durations) out.write(","+stage[row]);
                for (long[] counter:counts) out.write(","+counter[row]);
                out.newLine();
            }
        }
        Files.writeString(cache.resolve("driving-loot-status.txt"),
                "version=1 complete_fills="+committed+" omitted_fills="+omitted+" capacity="+capacity
                +" max_depth="+MAX_DEPTH+" diagnostic="+(diagnostic==null ? "none" : diagnostic)
                +" semantics=per_fill_inclusive_wall_exclusive_stage_partition nested_rows=overlap"
                +" counters=inclusive_calls_not_items\n");
    }
}
