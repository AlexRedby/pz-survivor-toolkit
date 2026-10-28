package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.IdentityHashMap;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.integration.LuaCaller;

/** Opt-in owner-thread callback census. It never invokes Lua or writes during capture. */
public final class LuaCallbacks {
    static final int MAX_FRAMES=6000, MAX_ROWS=1200000, MAX_IDENTITIES=2048, MAX_DEPTH=64;
    private static Thread owner;
    private static Capture capture;
    private static volatile boolean enabled;
    private static boolean started;
    private LuaCallbacks() {}

    static void start(Thread thread) throws Exception {
        if (!Boolean.getBoolean("pz.drivingPerf.callbackProfile")) return;
        if (started || thread!=Thread.currentThread()) throw new IllegalStateException("One owned callback capture per JVM");
        owner=thread; capture=new Capture(Boolean.getBoolean("pz.drivingPerf.callbackDetailProfile"));
        try { LuaCallbackHooks.install(); started=true; enabled=true; }
        catch (Exception | Error failure) { LuaCallbackHooks.remove(); throw failure; }
    }
    static void abort() { enabled=false; LuaCallbackHooks.remove(); }
    static void frameBegin(long id,long now) {
        if (enabled && Thread.currentThread()==owner) capture.begin(id,now);
    }
    static void frameEnd(long now, boolean stageComplete) {
        if (enabled && Thread.currentThread()==owner) capture.end(now,stageComplete);
    }
    public static int enter(Object caller,Object function) {
        if (!enabled || Thread.currentThread()!=owner || !capture.active) return 0;
        if (LuaCallbackHooks.diagnostic!=null) { capture.fail("hook-changed"); return 0; }
        if (caller==null || caller.getClass()!=LuaCaller.class) { capture.fail("unsupported-caller-class"); return 0; }
        try { return capture.enter(function,System.nanoTime()); }
        catch (Throwable failure) { capture.fail("callback-telemetry-entry-failure"); return 0; }
    }
    /** Explicit diagnostic Lua spans share the bounded callback identity/interval stack. */
    public static int enterSpan(Object function) {
        if (!enabled || Thread.currentThread()!=owner || !capture.detailSpans || !capture.active || capture.error!=null) return 0;
        if (LuaCallbackHooks.diagnostic!=null) { capture.fail("hook-changed"); return 0; }
        if (!(function instanceof LuaClosure)) { capture.fail("unsupported-detail-span-function"); return 0; }
        try { return capture.enter(function,System.nanoTime()); }
        catch (Throwable failure) { capture.fail("detail-span-entry-failure"); return 0; }
    }
    public static void exit(int token) {
        if (token==0 || !enabled || Thread.currentThread()!=owner || !capture.active) return;
        try { capture.exit(token,System.nanoTime()); }
        catch (Throwable failure) { capture.fail("callback-telemetry-exit-failure"); }
    }
    static void finish(Path cache) throws Exception {
        if (!started) return;
        enabled=false;
        if (capture.active) { capture.omitted++; capture.cancel(); }
        if (LuaCallbackHooks.diagnostic!=null) capture.fail("hook-changed");
        LuaCallbackHooks.remove();
        capture.write(cache);
        if (capture.error!=null) throw new IllegalStateException("Invalid callback profile: "+capture.error);
    }

    /** Deterministic bounded state, also exercised without the game or wall clock. */
    static final class Capture {
        final boolean detailSpans;
        Capture() { this(false); }
        Capture(boolean details) { detailSpans=details; }
        final IdentityHashMap<Object,Integer> ids=new IdentityHashMap<>();
        final String[][] sources=new String[MAX_IDENTITIES][];
        final long[] inclusive=new long[MAX_IDENTITIES], exclusive=new long[MAX_IDENTITIES], max=new long[MAX_IDENTITIES], unionStart=new long[MAX_IDENTITIES];
        final int[] calls=new int[MAX_IDENTITIES], activeDepth=new int[MAX_IDENTITIES];
        final int[] stack=new int[MAX_DEPTH], tokens=new int[MAX_DEPTH];
        final long[] entered=new long[MAX_DEPTH];
        final long[] frameIds=new long[MAX_FRAMES], starts=new long[MAX_FRAMES], ends=new long[MAX_FRAMES], totals=new long[MAX_FRAMES];
        final int[] frameCalls=new int[MAX_FRAMES], frameRows=new int[MAX_FRAMES];
        final int[] rowFrames=new int[MAX_ROWS], rowIds=new int[MAX_ROWS], rowCalls=new int[MAX_ROWS];
        final long[] rowInclusive=new long[MAX_ROWS], rowExclusive=new long[MAX_ROWS], rowMax=new long[MAX_ROWS];
        int depth,serial,frames,rows,identities,omitted;
        long id,start,last;
        boolean active;
        String error;
        void fail(String reason) { if(error==null) error=reason; cancel(); }
        void cancel() { active=false; depth=0; Arrays.fill(activeDepth,0); }
        void begin(long frameId,long now) {
            if(error!=null || frames==MAX_FRAMES) return;
            if(active || frameId<=0 || (frames>0 && (frameId<=frameIds[frames-1] || now<ends[frames-1]))) { fail("invalid-frame-begin"); return; }
            Arrays.fill(inclusive,0); Arrays.fill(exclusive,0); Arrays.fill(max,0); Arrays.fill(calls,0); Arrays.fill(activeDepth,0);
            id=frameId; start=last=now; depth=0; active=true;
        }
        boolean advance(long now) {
            if(now<last) { fail("nonmonotonic-clock"); return false; }
            if(depth>0) exclusive[stack[depth-1]]+=now-last;
            last=now; return true;
        }
        int identity(Object function) {
            Integer known=ids.get(function);
            if(known!=null) return known;
            if(identities==MAX_IDENTITIES) { fail("identity-capacity"); return -1; }
            String kind=function==null ? "null" : function instanceof LuaClosure ? "lua" : function instanceof JavaFunction ? "java" : "other";
            String filename="",file="",name=function==null ? "" : function.getClass().getName(); int line=-1;
            if(function instanceof LuaClosure closure) {
                var prototype=closure.prototype;
                if(prototype==null) { fail("missing-prototype"); return -1; }
                filename=prototype.filename; file=prototype.file; name=prototype.name;
                if(prototype.lines!=null && prototype.lines.length>0) line=prototype.lines[0];
            }
            String[] meta={kind,filename==null ? "" : filename,file==null ? "" : file,name==null ? "" : name,Integer.toString(line)};
            for(String value:meta) if(value.length()>4096 || value.indexOf('\0')>=0) { fail("source-metadata-bound"); return -1; }
            if(line < -1) { fail("source-line-bound"); return -1; }
            int result=identities++; sources[result]=meta; ids.put(function,result); return result;
        }
        int enter(Object function,long now) {
            if(!active) return 0;
            if(depth==MAX_DEPTH || serial==Integer.MAX_VALUE) { fail("callback-stack-capacity"); return 0; }
            int callback=identity(function);
            if(callback<0 || !advance(now)) return 0;
            if(calls[callback]==Integer.MAX_VALUE) { fail("callback-call-capacity"); return 0; }
            calls[callback]++;
            if(activeDepth[callback]++==0) unionStart[callback]=now;
            stack[depth]=callback; entered[depth]=now; tokens[depth]=++serial;
            return tokens[depth++];
        }
        void exit(int token,long now) {
            if(token==0 || !active) return;
            if(depth==0 || tokens[depth-1]!=token) { fail("callback-token-order"); return; }
            if(!advance(now)) return;
            int callback=stack[--depth];
            max[callback]=Math.max(max[callback],now-entered[depth]);
            if(--activeDepth[callback]==0) inclusive[callback]+=now-unionStart[callback];
        }
        void end(long now,boolean stageComplete) {
            if(!active) return;
            if(!stageComplete) { omitted++; cancel(); return; }
            if(depth!=0 || now<=start) { fail("callback-frame-unbalanced"); return; }
            if(!advance(now)) return;
            int count=0,totalCalls=0; long total=0;
            for(int i=0;i<identities;i++) if(calls[i]>0) {
                count++; total+=exclusive[i];
                if(totalCalls>Integer.MAX_VALUE-calls[i]) { fail("frame-call-capacity"); return; }
                totalCalls+=calls[i];
            }
            if(rows+count>MAX_ROWS) { fail("row-capacity"); return; }
            frameIds[frames]=id; starts[frames]=start; ends[frames]=now; totals[frames]=total;
            frameCalls[frames]=totalCalls; frameRows[frames]=count;
            for(int i=0;i<identities;i++) if(calls[i]>0) {
                rowFrames[rows]=frames; rowIds[rows]=i; rowCalls[rows]=calls[i];
                rowInclusive[rows]=inclusive[i]; rowExclusive[rows]=exclusive[i]; rowMax[rows++]=max[i];
            }
            frames++; active=false;
        }
        static String quoted(String value) { return "\""+value.replace("\"","\"\"")+"\""; }
        void write(Path cache) throws Exception {
            try(BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-callback-sources.csv"))) {
                out.write("callback_id,kind,filename,file,name,line_first_instruction\n");
                for(int i=0;i<identities;i++) {
                    out.write(Integer.toString(i));
                    for(String value:sources[i]) out.write(","+quoted(value));
                    out.write("\n");
                }
            }
            try(BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-callback-frames.csv"))) {
                out.write("frame_id,nano_start,nano_end,callbacks,rows,exclusive_ns\n");
                for(int i=0;i<frames;i++) out.write(frameIds[i]+","+starts[i]+","+ends[i]+","+frameCalls[i]+","+frameRows[i]+","+totals[i]+"\n");
            }
            try(BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-callbacks.csv"))) {
                out.write("frame_id,callback_id,calls,inclusive_ns,exclusive_ns,max_call_ns\n");
                for(int i=0;i<rows;i++) out.write(frameIds[rowFrames[i]]+","+rowIds[i]+","+rowCalls[i]+","+rowInclusive[i]+","+rowExclusive[i]+","+rowMax[i]+"\n");
            }
            String status="version=2 complete_frames="+frames+" rows="+rows+" identities="+identities+" omitted_incomplete_frames="+omitted
                +" max_frames="+MAX_FRAMES+" max_rows="+MAX_ROWS+" max_identities="+MAX_IDENTITIES+" max_depth="+MAX_DEPTH
                +" stopped="+(frames==MAX_FRAMES ? "frame-limit" : "finish")+" diagnostic="+(error==null ? "none" : error)
                +" detail_spans="+(detailSpans ? "enabled" : "disabled")
                +" coverage=LuaCaller-native-terminal-overloads inclusive=identity-union-nonadditive exclusive=callback-stack-only\n";
            Files.writeString(cache.resolve("driving-callback-status.txt"),status);
        }
    }
}
