package net.alexredby.drivingperf;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;

/** Deterministic ledger checks; does not launch or initialize the game. */
public final class ChunkProfilerChecks {
    private static int checks;
    private static void check(boolean value,String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    private static void eq(long expected,long actual,String message) {
        check(expected==actual,message+": "+actual+" != "+expected);
    }
    private static long[] s(long chunk,long lua) {
        long[] result=new long[StageProfiler.STAGES]; result[StageProfiler.CHUNK]=chunk; result[StageProfiler.LUA]=lua;
        return result;
    }
    private static void diagnostic(ChunkProfiler c,String expected,long omitted) {
        check(expected.equals(c.diagnostic()),"diagnostic "+expected+": "+c.diagnostic());
        eq(omitted,c.omittedChunks(),"omitted chunks");
        c.frameBegin(999); c.begin(9,0,0,0,999,s(0,0)); c.end(9,0,1000,s(1,0)); c.frameEnd(true);
        check(expected.equals(c.diagnostic()),"diagnostic remains persistent");
    }
    private static List<String> output(ChunkProfiler c,Path root,String name) throws Exception {
        Path out=Files.createDirectory(root.resolve(name));
        c.finish(out);
        c.finish(out);
        return Files.readAllLines(out.resolve("driving-chunks.csv"));
    }
    private static long n(String[] row,int column) { return Long.parseLong(row[column]); }
    private static void outputChecks(Path root) throws Exception {
        ChunkProfiler c=new ChunkProfiler(8); c.frameBegin(12);
        Path out=Files.createDirectory(root.resolve("output"));
        c.begin(4,-11,23,-1,100,s(5,3));
        check(!Files.exists(out.resolve("driving-chunks.csv")),"no runtime file output");
        c.end(4,-2,128,new long[]{1,2,8,4,8,5,8}); // Deltas 1,2,3,4,5,5,8 = 28.
        c.begin(5,31,-19,4,140,new long[]{1,2,20,4,8,5,8});
        c.end(5,1,150,new long[]{1,2,26,4,12,5,8});
        eq(0,c.completeChunks(),"pending frame is not committed");
        c.frameEnd(true); eq(2,c.completeChunks(),"two chunks committed together");
        check(c.diagnostic()==null,"valid multi-chunk frame");
        c.finish(out);
        List<String> lines=Files.readAllLines(out.resolve("driving-chunks.csv"));
        eq(3,lines.size(),"header and two rows");
        check(lines.getFirst().equals("frame_id,chunk_index,token,depth,wx,wy,queue_depth_before,queue_depth_after,nano_start,nano_end,wall_ns,logic_exclusive_ns,render_exclusive_ns,chunk_exclusive_ns,loot_exclusive_ns,lua_exclusive_ns,tiles_exclusive_ns,ui_exclusive_ns"),"stable schema");
        for (int i=1;i<lines.size();i++) {
            String[] row=lines.get(i).split(",",-1); eq(18,row.length,"column count");
            eq(12,n(row,0),"frame identity"); eq(i,n(row,1),"entry-order chunk index");
            eq(n(row,9)-n(row,8),n(row,10),"wall interval");
            long total=0; for (int stage=11;stage<18;stage++) total+=n(row,stage);
            eq(n(row,10),total,"all seven stage deltas partition wall");
        }
        String[] first=lines.get(1).split(",");
        eq(-11,n(first,4),"signed chunk x"); eq(-1,n(first,6),"transient signed entry queue observation");
        eq(-2,n(first,7),"transient signed exit queue observation");
        String status=Files.readString(out.resolve("driving-chunks-status.txt"));
        check(status.contains("complete_chunks=2 omitted_chunks=0 capacity=8 max_depth=256 diagnostic=none"),"status counts");
        check(status.contains("semantics=per_chunk_inclusive_wall_exclusive_stage_partition nested_rows=overlap queue_depth=O1_observed_after_dequeue_not_wait"),"honest wall and queue semantics");
        c.begin(6,0,0,0,151,s(0,0)); c.end(6,0,152,s(1,0)); c.frameBegin(13);
        eq(2,c.completeChunks(),"finish ignores trailing hooks");
    }
    private static void nestedChecks(Path root) throws Exception {
        ChunkProfiler c=new ChunkProfiler(4); c.frameBegin(1);
        c.begin(1,1,2,3,100,s(0,0)); c.begin(2,4,5,2,110,s(10,0));
        c.end(2,1,130,s(15,15)); c.end(1,0,150,s(35,15)); c.frameEnd(true);
        check(c.diagnostic()==null,"nested chunks accepted");
        List<String> rows=output(c,root,"nested");
        String[] outer=rows.get(1).split(","), inner=rows.get(2).split(",");
        eq(1,n(outer,3),"outer depth"); eq(2,n(inner,3),"inner depth");
        eq(50,n(outer,10),"outer wall includes child"); eq(20,n(inner,10),"nested wall");
        eq(35,n(outer,13),"outer chunk-exclusive delta"); eq(15,n(outer,15),"outer Lua-exclusive delta");
        eq(5,n(inner,13),"inner chunk-exclusive delta"); eq(15,n(inner,15),"inner Lua-exclusive delta");
    }
    private static void rollbackChecks(Path root) throws Exception {
        ChunkProfiler c=new ChunkProfiler(4); c.frameBegin(1);
        c.begin(1,0,0,0,100,s(0,0)); c.end(1,0,110,s(10,0)); c.frameEnd(true);
        c.frameBegin(2); c.begin(2,0,0,0,120,s(0,0)); c.end(2,0,130,s(10,0));
        c.begin(3,0,0,0,140,s(20,0)); c.frameEnd(false);
        eq(1,c.completeChunks(),"invalid frame preserves prior commit"); eq(2,c.omittedChunks(),"both pending rows rolled back");
        c.end(3,0,145,s(25,0)); check(c.diagnostic()==null,"invalid-frame trailing exit ignored");
        c.frameBegin(3); c.begin(4,0,0,0,150,s(0,0)); c.cancelFrame(); c.end(4,0,160,s(10,0));
        eq(3,c.omittedChunks(),"cancelled row omitted");
        c.frameBegin(4); c.begin(5,0,0,0,170,s(0,0)); c.end(5,0,180,s(10,0)); c.frameEnd(true);
        c.frameBegin(5); c.begin(6,0,0,0,190,s(0,0));
        List<String> rows=output(c,root,"rollback");
        eq(3,rows.size(),"only whole valid frames exported"); eq(4,c.omittedChunks(),"finish cancels trailing frame");
        eq(4,n(rows.get(2).split(","),0),"frame identity after rollback");
        eq(2,n(rows.get(2).split(","),1),"rolled-back indices reused");
    }
    private static void failureChecks(Path root) throws Exception {
        ChunkProfiler c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,0,s(0,0));
        c.end(2,0,10,s(10,0)); diagnostic(c,"chunk_token_mismatch",1);
        eq(1,output(c,root,"failed").size(),"failed frame has no rows");
        c=new ChunkProfiler(1); c.frameBegin(1); c.begin(1,0,0,0,0,s(0,0)); c.end(1,0,1,s(1,0));
        c.begin(2,0,0,0,2,s(2,0)); diagnostic(c,"chunk_buffer_overflow",2); eq(0,c.completeChunks(),"overflow rolls back whole frame");
        c=new ChunkProfiler(1); c.frameBegin(1); c.begin(1,0,0,0,0,s(0,0)); c.end(1,0,1,s(1,0)); c.frameEnd(true);
        c.frameBegin(2); c.begin(2,0,0,0,2,s(0,0)); diagnostic(c,"chunk_buffer_overflow",1); eq(1,c.completeChunks(),"overflow retains earlier frame");
        c=new ChunkProfiler(300); c.frameBegin(1);
        for (int i=1;i<=ChunkProfiler.MAX_DEPTH+1;i++) c.begin(i,0,0,0,i,s(i,0));
        diagnostic(c,"chunk_stack_overflow",257);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(0,0,0,0,0,s(0,0)); diagnostic(c,"invalid_token",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,0,s(0,0)); c.begin(1,0,0,0,1,s(1,0)); diagnostic(c,"duplicate_active_token",2);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,10,s(0,0)); c.end(1,0,9,s(1,0)); diagnostic(c,"nonmonotonic_chunk_time",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,10,s(5,0)); c.end(1,0,20,s(4,0)); diagnostic(c,"negative_stage_delta",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,10,s(-1,0)); diagnostic(c,"negative_stage_delta",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,10,s(0,0)); c.end(1,0,20,s(9,0)); diagnostic(c,"chunk_partition_mismatch",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,0,null); diagnostic(c,"invalid_stage_snapshot",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,0,new long[6]); diagnostic(c,"invalid_stage_snapshot",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,0,s(0,0)); c.frameEnd(true); diagnostic(c,"unclosed_chunk",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.frameBegin(2); diagnostic(c,"frame_already_open",0);
        c=new ChunkProfiler(4); c.frameBegin(1); c.frameEnd(true); c.frameBegin(1); diagnostic(c,"invalid_frame_order",0);
        c=new ChunkProfiler(4); c.frameBegin(0); diagnostic(c,"invalid_frame_order",0);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,Long.MIN_VALUE,s(0,0)); c.end(1,0,Long.MAX_VALUE,s(1,0)); diagnostic(c,"chunk_duration_overflow",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,0,s(0,0)); c.end(1,0,10,s(Long.MAX_VALUE,Long.MAX_VALUE)); diagnostic(c,"chunk_duration_overflow",1);
        c=new ChunkProfiler(4); c.frameBegin(1); c.begin(1,0,0,0,-100,s(0,0)); c.end(1,0,-50,s(50,0)); c.frameEnd(true);
        check(c.diagnostic()==null,"signed nanoTime origins accepted"); eq(1,c.completeChunks(),"signed origin completes");
        for (int capacity:new int[]{0,-1,ChunkProfiler.CAPACITY+1}) {
            boolean rejected=false; try { new ChunkProfiler(capacity); } catch (IllegalArgumentException expected) { rejected=true; }
            check(rejected,"capacity bound "+capacity);
        }
    }
    public static void main(String[] args) throws Exception {
        Path root=Files.createTempDirectory("pz-chunk-profiler-checks-");
        try {
            outputChecks(root); nestedChecks(root); rollbackChecks(root); failureChecks(root);
            System.out.println("ChunkProfilerChecks PASS ("+checks+" checks)");
        } finally {
            try (var paths=Files.walk(root)) {
                for (Path path:paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
    }
}
