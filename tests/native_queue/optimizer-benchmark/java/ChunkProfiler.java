package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Bounded owner-thread ledger. The caller supplies settled timer snapshots at each boundary. */
public final class ChunkProfiler {
    public static final int CAPACITY=120000, MAX_DEPTH=256;
    private static final String[] NAMES={"logic","render","chunk","loot","lua","tiles","ui"};
    private final int capacity;
    // 104 bytes per row in primitive arrays, plus less than 16 KiB of stack/state.
    private final long[] frames, starts, ends;
    private final int[] tokens, depths, xs, ys, before, after;
    private final long[][] durations;
    private final int[] stack=new int[MAX_DEPTH];
    private final long[] previous=new long[StageProfiler.STAGES];
    private int used, committed, frameBase, depth;
    private long frameId, lastFrameId, lastNow, omitted;
    private boolean frameOpen, haveTime, finished;
    private String diagnostic;

    public ChunkProfiler() { this(CAPACITY); }
    public ChunkProfiler(int capacity) {
        if (capacity<1 || capacity>CAPACITY) throw new IllegalArgumentException("Chunk capacity out of bounds");
        this.capacity=capacity;
        frames=new long[capacity]; starts=new long[capacity]; ends=new long[capacity];
        tokens=new int[capacity]; depths=new int[capacity]; xs=new int[capacity]; ys=new int[capacity];
        before=new int[capacity]; after=new int[capacity];
        durations=new long[StageProfiler.STAGES][capacity];
    }

    public String diagnostic() { return diagnostic; }
    public int completeChunks() { return committed; }
    public long omittedChunks() { return omitted; }

    public void frameBegin(long id) {
        if (finished || diagnostic!=null) return;
        if (frameOpen) { fail("frame_already_open"); return; }
        if (id<=0 || id<=lastFrameId) { fail("invalid_frame_order"); return; }
        frameId=id; lastFrameId=id; frameBase=used; frameOpen=true;
        for (int i=0;i<previous.length;i++) previous[i]=0;
    }

    public void begin(int token,int wx,int wy,int queueDepth,long now,long[] exclusive) {
        if (!capturing()) return;
        if (token<=0) { omitted++; fail("invalid_token"); return; }
        if (depth==MAX_DEPTH) { omitted++; fail("chunk_stack_overflow"); return; }
        if (used==capacity) { omitted++; fail("chunk_buffer_overflow"); return; }
        for (int i=0;i<depth;i++) {
            if (tokens[stack[i]]==token) { omitted++; fail("duplicate_active_token"); return; }
        }
        if (!snapshot(now,exclusive)) { omitted++; return; }
        int row=used++;
        frames[row]=frameId; starts[row]=now; tokens[row]=token; depths[row]=depth+1;
        xs[row]=wx; ys[row]=wy; before[row]=queueDepth;
        for (int stage=0;stage<durations.length;stage++) durations[stage][row]=exclusive[stage];
        stack[depth++]=row;
    }

    public void end(int token,int queueDepth,long now,long[] exclusive) {
        // Exits after cancellation/finish are deliberately harmless.
        if (!capturing()) return;
        if (depth==0 || token<=0 || tokens[stack[depth-1]]!=token) { fail("chunk_token_mismatch"); return; }
        if (!snapshot(now,exclusive)) return;
        int row=stack[depth-1];
        long wall, total=0;
        try {
            wall=Math.subtractExact(now,starts[row]);
            if (wall<0) { fail("negative_chunk_duration"); return; }
            for (int stage=0;stage<durations.length;stage++) {
                long value=Math.subtractExact(exclusive[stage],durations[stage][row]);
                if (value<0) { fail("negative_stage_duration"); return; }
                total=Math.addExact(total,value);
            }
        } catch (ArithmeticException overflow) { fail("chunk_duration_overflow"); return; }
        if (total!=wall) { fail("chunk_partition_mismatch"); return; }
        for (int stage=0;stage<durations.length;stage++) durations[stage][row]=exclusive[stage]-durations[stage][row];
        ends[row]=now; after[row]=queueDepth; depth--;
    }

    public void frameEnd(boolean valid) {
        if (!capturing()) return;
        if (!valid) { rollback(); return; }
        if (depth!=0) { fail("unclosed_chunk"); return; }
        committed=used; frameOpen=false;
    }

    public void cancelFrame() { if (frameOpen) rollback(); }

    private boolean capturing() { return frameOpen && !finished && diagnostic==null; }

    private boolean snapshot(long now,long[] exclusive) {
        if (haveTime && now<lastNow) { fail("nonmonotonic_chunk_time"); return false; }
        if (exclusive==null || exclusive.length!=StageProfiler.STAGES) { fail("invalid_stage_snapshot"); return false; }
        for (int stage=0;stage<previous.length;stage++) {
            if (exclusive[stage]<0 || exclusive[stage]<previous[stage]) {
                fail("negative_stage_delta"); return false;
            }
        }
        for (int stage=0;stage<previous.length;stage++) previous[stage]=exclusive[stage];
        lastNow=now; haveTime=true;
        return true;
    }

    private void rollback() {
        omitted+=used-frameBase; used=frameBase; depth=0; frameOpen=false;
    }

    private void fail(String message) {
        if (diagnostic==null) diagnostic=message;
        if (frameOpen) rollback();
    }

    public void finish(Path cache) throws IOException {
        if (finished) return;
        cancelFrame(); finished=true;
        try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-chunks.csv"))) {
            out.write("frame_id,chunk_index,token,depth,wx,wy,queue_depth_before,queue_depth_after,nano_start,nano_end,wall_ns");
            for (String name:NAMES) out.write(","+name+"_exclusive_ns");
            out.newLine();
            for (int row=0;row<committed;row++) {
                out.write(Long.toString(frames[row]));
                out.write(","+(row+1)+","+tokens[row]+","+depths[row]+","+xs[row]+","+ys[row]
                        +","+before[row]+","+after[row]+","+starts[row]+","+ends[row]+","+(ends[row]-starts[row]));
                for (long[] stage:durations) out.write(","+stage[row]);
                out.newLine();
            }
        }
        Files.writeString(cache.resolve("driving-chunks-status.txt"),
                "version=1 complete_chunks="+committed+" omitted_chunks="+omitted+" capacity="+capacity
                +" max_depth="+MAX_DEPTH+" diagnostic="+(diagnostic==null ? "none" : diagnostic)
                +" semantics=per_chunk_inclusive_wall_exclusive_stage_partition nested_rows=overlap"
                +" queue_depth=O1_observed_after_dequeue_not_wait\n");
    }
}
