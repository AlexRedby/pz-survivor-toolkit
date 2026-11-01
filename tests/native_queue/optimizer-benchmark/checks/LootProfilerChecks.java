package net.alexredby.drivingperf;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Deterministic ledger and export checks; no game initialization or native runtime. */
public final class LootProfilerChecks {
    private static int checks;
    private static final int STAGES=7, LOOT=3, LUA=4, COUNTER_START=15;
    private static final String HEADER="frame_id,fill_index,token,depth,container_type,nano_start,nano_end,wall_ns,logic_exclusive_ns,render_exclusive_ns,chunk_exclusive_ns,loot_exclusive_ns,lua_exclusive_ns,tiles_exclusive_ns,ui_exclusive_ns,chance_calls,factory_calls,factory_nonnull,bag_roll_calls,direct_roll_calls,plain_translation_calls,other_translation_calls";
    private static void check(boolean value,String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    private static void eq(long expected,long actual,String message) {
        check(expected==actual,message+": "+actual+" != "+expected);
    }
    private static long[] s(long loot,long lua) {
        long[] result=new long[STAGES]; result[LOOT]=loot; result[LUA]=lua;
        return result;
    }
    private static long n(List<String> row,int column) { return Long.parseLong(row.get(column)); }
    private static void diagnostic(LootProfiler c,String expected,long omitted) {
        check(expected.equals(c.diagnostic()),"diagnostic "+expected+": "+c.diagnostic());
        eq(omitted,c.omittedFills(),"omitted fills");
        c.frameBegin(999); c.begin(9,"ignored",999,s(0,0)); c.counter(LootProfiler.CHANCE);
        c.end(9,1000,s(1,0)); c.frameEnd(true);
        check(expected.equals(c.diagnostic()),"persistent diagnostic");
        eq(omitted,c.omittedFills(),"disabled hooks preserve omitted count");
    }
    private static Path output(LootProfiler c,Path root,String name) throws Exception {
        Path out=Files.createDirectory(root.resolve(name));
        c.finish(out); c.finish(out);
        return out;
    }
    /** Small RFC4180 reader for asserting exact strings, including embedded record separators. */
    private static List<List<String>> csv(Path path) throws Exception {
        String input=Files.readString(path);
        List<List<String>> rows=new ArrayList<>(); List<String> row=new ArrayList<>();
        StringBuilder cell=new StringBuilder(); boolean quoted=false;
        for (int i=0;i<input.length();i++) {
            char ch=input.charAt(i);
            if (ch=='"') {
                if (quoted && i+1<input.length() && input.charAt(i+1)=='"') { cell.append('"'); i++; }
                else quoted=!quoted;
            } else if (!quoted && (ch==',' || ch=='\n')) {
                row.add(cell.toString()); cell.setLength(0);
                if (ch=='\n') { rows.add(row); row=new ArrayList<>(); }
            } else cell.append(ch);
        }
        check(!quoted && row.isEmpty() && cell.length()==0,"CSV records terminate outside quotes");
        return rows;
    }
    private static void outputChecks(Path root) throws Exception {
        LootProfiler c=new LootProfiler(8);
        check(!c.filling(),"inactive fill scope");
        c.counter(-1); c.counter(LootProfiler.CHANCE); // Inactive counters are intentionally ignored.
        c.frameBegin(12); check(!c.filling(),"frame alone is not a fill");
        c.counter(LootProfiler.FACTORY); c.counter(999);
        c.begin(4,"crate",100,s(4,4)); check(c.filling(),"active fill scope"); c.counter(LootProfiler.CHANCE); c.counter(LootProfiler.FACTORY);
        c.counter(LootProfiler.FACTORY_NONNULL); c.counter(LootProfiler.TRANSLATION_PLAIN);
        Path out=Files.createDirectory(root.resolve("output"));
        check(!Files.exists(out.resolve("driving-loot.csv")),"no hook-time output");
        c.end(4,128,new long[]{1,2,8,4,8,5,8});
        check(!c.filling(),"completed fill scope closes");
        c.counter(LootProfiler.FACTORY); c.counter(LootProfiler.TRANSLATION_OTHER);
        c.begin(5,null,140,new long[]{1,2,20,4,8,5,8}); c.counter(LootProfiler.BAG);
        c.end(5,150,new long[]{1,2,26,4,12,5,8});
        eq(0,c.completeFills(),"frame remains pending"); c.frameEnd(true);
        eq(2,c.completeFills(),"whole valid frame committed"); check(c.diagnostic()==null,"valid frame");
        c.finish(out); c.finish(out);
        check(!c.filling(),"finished fill scope inactive");
        check(Files.readString(out.resolve("driving-loot.csv")).startsWith(HEADER+"\n"),"stable exact schema");
        List<List<String>> rows=csv(out.resolve("driving-loot.csv")); eq(3,rows.size(),"header and two rows");
        for (int i=1;i<rows.size();i++) {
            List<String> row=rows.get(i); eq(22,row.size(),"column count");
            eq(12,n(row,0),"frame identity"); eq(i,n(row,1),"entry order fill index");
            eq(n(row,6)-n(row,5),n(row,7),"wall interval");
            long total=0; for (int stage=8;stage<15;stage++) total+=n(row,stage);
            eq(n(row,7),total,"stage partition");
        }
        check(rows.get(1).get(4).equals("crate"),"type preserved");
        check(rows.get(2).get(4).isEmpty(),"null type becomes empty");
        long[] first={1,1,1,0,0,1,0}, second={0,0,0,1,0,0,0};
        for (int i=0;i<LootProfiler.COUNTERS;i++) {
            eq(first[i],n(rows.get(1),COUNTER_START+i),"first counter "+i);
            eq(second[i],n(rows.get(2),COUNTER_START+i),"second counter "+i);
        }
        String status=Files.readString(out.resolve("driving-loot-status.txt"));
        check(status.equals("version=1 complete_fills=2 omitted_fills=0 capacity=8 max_depth=256 diagnostic=none semantics=per_fill_inclusive_wall_exclusive_stage_partition nested_rows=overlap counters=inclusive_calls_not_items\n"),"exact status schema");
        c.frameBegin(13); c.begin(6,"ignored",151,s(0,0)); c.counter(-1); c.end(6,152,s(1,0));
        eq(2,c.completeFills(),"finish ignores hooks"); check(c.diagnostic()==null,"finished invalid counter ignored");
    }
    private static void nestedChecks(Path root) throws Exception {
        LootProfiler c=new LootProfiler(4); c.frameBegin(1);
        c.begin(1,"outer",100,s(0,0)); c.counter(LootProfiler.CHANCE); c.counter(LootProfiler.ROLL);
        c.begin(2,"inner",110,s(10,0)); c.counter(LootProfiler.CHANCE); c.counter(LootProfiler.CHANCE);
        c.counter(LootProfiler.FACTORY); c.counter(LootProfiler.FACTORY_NONNULL); c.counter(LootProfiler.BAG);
        c.counter(LootProfiler.TRANSLATION_PLAIN); c.counter(LootProfiler.TRANSLATION_OTHER);
        c.end(2,130,s(15,15)); c.counter(LootProfiler.CHANCE); c.end(1,150,s(35,15)); c.frameEnd(true);
        check(c.diagnostic()==null,"nested fills accepted");
        List<List<String>> rows=csv(output(c,root,"nested").resolve("driving-loot.csv"));
        List<String> outer=rows.get(1), inner=rows.get(2);
        eq(1,n(outer,3),"outer depth"); eq(2,n(inner,3),"inner depth");
        eq(50,n(outer,7),"outer wall includes child"); eq(20,n(inner,7),"child wall");
        eq(35,n(outer,11),"outer loot delta"); eq(15,n(outer,12),"outer Lua delta");
        eq(5,n(inner,11),"inner loot delta"); eq(15,n(inner,12),"inner Lua delta");
        long[] expectedOuter={4,1,1,1,1,1,1}, expectedInner={2,1,1,1,0,1,1};
        for (int i=0;i<LootProfiler.COUNTERS;i++) {
            eq(expectedOuter[i],n(outer,COUNTER_START+i),"inclusive outer counter "+i);
            eq(expectedInner[i],n(inner,COUNTER_START+i),"inner counter "+i);
        }
    }
    private static void stringChecks(Path root) throws Exception {
        String[] types={"",null,"ящик 🎒","crate,\"rare\"","line\r\nbreak"};
        LootProfiler c=new LootProfiler(types.length); c.frameBegin(1);
        for (int i=0;i<types.length;i++) {
            c.begin(i+1,types[i],100+i*2,s(i*2,0)); c.end(i+1,101+i*2,s(i*2+1,0));
        }
        c.frameEnd(true); Path out=output(c,root,"types");
        List<List<String>> rows=csv(out.resolve("driving-loot.csv")); eq(types.length+1,rows.size(),"escaped record count");
        for (int i=0;i<types.length;i++) check(rows.get(i+1).get(4).equals(types[i]==null ? "" : types[i]),"exact type "+i);
        String raw=Files.readString(out.resolve("driving-loot.csv"));
        check(raw.contains("\"crate,\"\"rare\"\"\""),"quote doubling");
        check(raw.contains("\"line\r\nbreak\""),"embedded newline is quoted");
    }
    private static void betweenFillGapChecks(Path root) throws Exception {
        LootProfiler c=new LootProfiler(4); c.frameBegin(1);
        c.begin(1,"first",100,s(0,0)); c.end(1,110,s(10,0));
        // No stage is active in this gap: Timer.other advances, the seven stage counters do not.
        c.begin(2,"after other",130,s(10,0)); c.end(2,140,s(20,0)); c.frameEnd(true);
        check(c.diagnostic()==null,"unattributed gap between top-level fills is accepted");
        List<List<String>> rows=csv(output(c,root,"between-fill-gap").resolve("driving-loot.csv"));
        eq(3,rows.size(),"both fills after other gap exported");
        eq(10,n(rows.get(1),7),"first fill wall excludes gap");
        eq(10,n(rows.get(2),7),"second fill wall excludes gap");
        eq(20,n(rows.get(2),5)-n(rows.get(1),6),"separate top-level gap retained");
    }
    private static void rollbackChecks(Path root) throws Exception {
        LootProfiler c=new LootProfiler(4); c.frameBegin(1);
        c.begin(1,"kept",100,s(0,0)); c.counter(LootProfiler.CHANCE); c.end(1,110,s(10,0)); c.frameEnd(true);
        c.frameBegin(2); c.begin(2,"rolled back",120,s(0,0)); c.counter(LootProfiler.CHANCE);
        c.end(2,130,s(10,0)); c.begin(3,"open",140,s(20,0)); c.frameEnd(false);
        eq(1,c.completeFills(),"rollback preserves prior commit"); eq(2,c.omittedFills(),"all pending fills omitted");
        c.end(3,145,s(25,0)); c.counter(-1); check(c.diagnostic()==null,"trailing cancelled hooks ignored");
        c.frameBegin(3); c.begin(4,"cancelled",150,s(0,0)); c.counter(LootProfiler.FACTORY); c.cancelFrame();
        c.end(4,160,s(10,0)); eq(3,c.omittedFills(),"explicit cancellation");
        c.frameBegin(4); c.begin(5,"kept too",170,s(0,0)); c.counter(LootProfiler.BAG);
        c.end(5,180,s(10,0)); c.frameEnd(true);
        c.frameBegin(5); c.begin(6,"unfinished",190,s(0,0)); c.counter(LootProfiler.CHANCE);
        List<List<String>> rows=csv(output(c,root,"rollback").resolve("driving-loot.csv"));
        eq(3,rows.size(),"whole valid frames only"); eq(4,c.omittedFills(),"finish cancels partial frame");
        eq(4,n(rows.get(2),0),"later committed frame"); eq(2,n(rows.get(2),1),"rolled back index reused");
        for (int i=0;i<LootProfiler.COUNTERS;i++) eq(i==LootProfiler.BAG ? 1 : 0,n(rows.get(2),COUNTER_START+i),"frame counter reset "+i);
    }
    private static void failureChecks(Path root) throws Exception {
        LootProfiler c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0));
        c.end(2,10,s(10,0)); diagnostic(c,"loot_token_mismatch",1);
        eq(1,csv(output(c,root,"failed").resolve("driving-loot.csv")).size(),"failed frame has no rows");
        c=new LootProfiler(1); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.end(1,1,s(1,0));
        c.begin(2,"",2,s(2,0)); diagnostic(c,"loot_buffer_overflow",2); eq(0,c.completeFills(),"overflow rolls back pending frame");
        c=new LootProfiler(1); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.end(1,1,s(1,0)); c.frameEnd(true);
        c.frameBegin(2); c.begin(2,"",2,s(0,0)); diagnostic(c,"loot_buffer_overflow",1); eq(1,c.completeFills(),"overflow preserves prior frame");
        c=new LootProfiler(300); c.frameBegin(1);
        for (int i=1;i<=LootProfiler.MAX_DEPTH+1;i++) c.begin(i,"",i,s(i,0));
        diagnostic(c,"loot_stack_overflow",257);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(0,"",0,s(0,0)); diagnostic(c,"invalid_token",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.begin(1,"",1,s(1,0)); diagnostic(c,"duplicate_active_token",2);
        c=new LootProfiler(4); c.frameBegin(1); c.end(1,0,s(0,0)); diagnostic(c,"loot_token_mismatch",0);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",10,s(0,0)); c.end(1,9,s(1,0)); diagnostic(c,"nonmonotonic_loot_time",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",10,s(5,0)); c.end(1,20,s(4,0)); diagnostic(c,"negative_stage_delta",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",10,s(-1,0)); diagnostic(c,"negative_stage_delta",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",10,s(0,0)); c.end(1,20,s(9,0)); diagnostic(c,"loot_partition_mismatch",1);
        // An impossible intermediate snapshot must fail before a later endpoint could hide it.
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.begin(2,"",10,s(9,0)); diagnostic(c,"loot_partition_mismatch",2);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,null); diagnostic(c,"invalid_stage_snapshot",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,new long[6]); diagnostic(c,"invalid_stage_snapshot",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.end(1,1,null); diagnostic(c,"invalid_stage_snapshot",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.frameEnd(true); diagnostic(c,"unclosed_loot",1);
        c=new LootProfiler(4); c.frameBegin(1); c.frameBegin(2); diagnostic(c,"frame_already_open",0);
        c=new LootProfiler(4); c.frameBegin(1); c.frameEnd(true); c.frameBegin(1); diagnostic(c,"invalid_frame_order",0);
        c=new LootProfiler(4); c.frameBegin(0); diagnostic(c,"invalid_frame_order",0);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",Long.MIN_VALUE,s(0,0)); c.end(1,Long.MAX_VALUE,s(1,0)); diagnostic(c,"loot_duration_overflow",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.end(1,10,s(Long.MAX_VALUE,Long.MAX_VALUE)); diagnostic(c,"loot_duration_overflow",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",-100,s(0,0)); c.end(1,-50,s(50,0)); c.frameEnd(true);
        c.frameBegin(2); c.begin(2,"",-40,s(0,0)); c.end(2,-30,s(10,0)); c.frameEnd(true);
        check(c.diagnostic()==null,"signed nanoTime and frame snapshot resets"); eq(2,c.completeFills(),"signed origins complete");
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.counter(-1); diagnostic(c,"invalid_loot_counter",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0)); c.counter(LootProfiler.COUNTERS); diagnostic(c,"invalid_loot_counter",1);
        c=new LootProfiler(4); c.frameBegin(1); c.begin(1,"",0,s(0,0));
        Field field=LootProfiler.class.getDeclaredField("cumulative"); field.setAccessible(true);
        ((long[])field.get(c))[LootProfiler.CHANCE]=Long.MAX_VALUE;
        c.counter(LootProfiler.CHANCE); diagnostic(c,"loot_counter_overflow",1);
        for (int capacity:new int[]{0,-1,LootProfiler.CAPACITY+1}) {
            boolean rejected=false; try { new LootProfiler(capacity); } catch (IllegalArgumentException expected) { rejected=true; }
            check(rejected,"capacity bound "+capacity);
        }
    }
    public static void main(String[] args) throws Exception {
        Path root=Files.createTempDirectory("pz-loot-profiler-checks-");
        try {
            outputChecks(root); nestedChecks(root); stringChecks(root); betweenFillGapChecks(root); rollbackChecks(root); failureChecks(root);
            System.out.println("LootProfilerChecks PASS ("+checks+" checks)");
        } finally {
            try (var paths=Files.walk(root)) {
                for (Path path:paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
    }
}
