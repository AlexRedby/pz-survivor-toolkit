package net.alexredby.equipworkprobe;

import java.util.Arrays;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.stdlib.BaseLib;
import se.krka.kahlua.vm.KahluaThread;

/** Native Kahlua clock and primitive bookkeeping only; no world, game or GUI startup. */
public final class EquipWorkProbeChecks {
    private static void check(boolean value,String message) {
        if (!value) throw new AssertionError(message);
    }
    private static double number(KahluaTableImpl table,String field) { return (Double)table.rawget(field); }
    public static void main(String[] args) throws Exception {
        var platform=new J2SEPlatform(); var environment=platform.newTable(); BaseLib.register(environment);
        Object originalType=environment.rawget("type"); EquipWorkProbe.install(environment);
        Object clock=environment.rawget("equipWorkNowMs"); EquipWorkProbe.install(environment);
        check(clock==environment.rawget("equipWorkNowMs") && originalType==environment.rawget("type"),"installer changed singleton/unrelated global");
        var thread=new KahluaThread(System.out,platform,environment); thread.debugOwnerThread=Thread.currentThread();
        var script=LuaCompiler.loadstring("""
            if type(equipWorkNowMs)~='function' or type(equipWorkMark)~='function' or type(equipWorkSnapshot)~='function' then return false end
            if equipWorkMark(42)~=false or equipWorkMark('bad','arity')~=false then return false end
            local previous=equipWorkNowMs()
            for i=1,64 do
                local value=equipWorkNowMs()
                if value-value~=0 or value<0 or value<previous then return false end
                previous=value
            end
            return equipWorkMark('clock-test'),equipWorkSnapshot().active
            ""","equip-work-native-clock",environment);
        Object[] values=thread.pcall(script,new Object[0]);
        check(values.length==3 && Boolean.TRUE.equals(values[0]) && Boolean.TRUE.equals(values[1]) && Boolean.TRUE.equals(values[2]),
            "native Lua controls failed: "+Arrays.toString(values));
        var read=LuaCompiler.loadstring("return equipWorkNowMs()","equip-work-clock-read",environment);
        long firstStart=System.nanoTime(); double first=(Double)thread.call(read,new Object[0]); long firstEnd=System.nanoTime();
        long lastStart=System.nanoTime(); double last=(Double)thread.call(read,new Object[0]); long lastEnd=System.nanoTime();
        double rounding=0.000001;
        check(last-first >= (lastStart-firstEnd)/1_000_000.0-rounding && last-first <= (lastEnd-firstStart)/1_000_000.0+rounding,
            "Lua clock units differ from native monotonic milliseconds");

        long parent=EquipWorkProbe.begin(EquipWorkProbe.CAPTURE);
        long child=EquipWorkProbe.begin(EquipWorkProbe.FINGERPRINT);
        EquipWorkProbe.end(EquipWorkProbe.FINGERPRINT,child); EquipWorkProbe.end(EquipWorkProbe.CAPTURE,parent);
        EquipWorkProbe.source("ExampleMod","media/lua/client/Example.lua");
        EquipWorkProbe.source("ExampleMod","media/lua/client/Example.lua");
        EquipWorkProbe.source(null,"media/lua/shared/Native.lua");
        EquipWorkProbe.source(null,"private/non-source-path");
        Thread foreign=new Thread(()->{
            check(EquipWorkProbe.begin(EquipWorkProbe.EVENT)==0,"foreign thread acquired scope");
            EquipWorkProbe.source(null,"media/lua/foreign.lua");
            check(!EquipWorkProbe.mark(thread,"foreign"),"foreign Java thread replaced phase");
        });
        // Return any foreign-thread assertion to this main test rather than accepting a logged error.
        final Throwable[] foreignFailure={null}; foreign.setUncaughtExceptionHandler((t,error)->foreignFailure[0]=error);
        foreign.start(); foreign.join(); check(foreignFailure[0]==null,"foreign thread guard failed");
        var snapshot=(KahluaTableImpl)EquipWorkProbe.snapshot(thread);
        check(snapshot.getMetatable()==null && snapshot.getRewriteTable()==null,"snapshot must be plain");
        check(snapshot.delegate.values().stream().allMatch(v->v instanceof String || v instanceof Boolean || v instanceof Double),"nonscalar snapshot retained an observed object");
        check(number(snapshot,"captureMatchCalls")==1 && number(snapshot,"captureMatchCompleted")==1
            && number(snapshot,"fingerprintTreeCalls")==1 && number(snapshot,"eventTriggerCalls")==0,"scope counters differ");
        check(number(snapshot,"captureMatchInclusiveNs")==number(snapshot,"captureMatchSelfNs")+number(snapshot,"fingerprintTreeInclusiveNs"),"nested self time did not exclude child");
        check(number(snapshot,"sourcePathCount")==2 && number(snapshot,"source1Count")==2
            && "media/lua/client/Example.lua".equals(snapshot.rawget("source1Path")),"source paths/counts escaped phase or filter");
        for (String name:new String[]{"modSource","gameSource","captureMatch","fingerprintTree","registryMatches","dispatchEnter","dispatchExit","eventTrigger"})
            check(Boolean.TRUE.equals(snapshot.rawget(name+"SignatureAvailable")),"exact native signature unavailable: "+name);
        check(Boolean.FALSE.equals(snapshot.rawget("overheadCorrected")) && Boolean.FALSE.equals(snapshot.rawget("perCallScopeAllocation")),"overhead metadata differs");
        check(EquipWorkProbe.mark(thread,null),"phase clear rejected");
        check(EquipWorkProbe.begin(EquipWorkProbe.EVENT)==0,"cleared phase counted work");
        var stopped=(KahluaTableImpl)EquipWorkProbe.snapshot(thread);
        check(Boolean.FALSE.equals(stopped.rawget("active")) && number(stopped,"elapsedMs")>=0,"stopped snapshot unavailable");
        check(EquipWorkProbe.mark(thread,"fresh"),"fresh phase rejected");
        check(number((KahluaTableImpl)EquipWorkProbe.snapshot(thread),"captureMatchCalls")==0,"counters survived reset");
        long stale=EquipWorkProbe.begin(EquipWorkProbe.EVENT);
        check(EquipWorkProbe.mark(thread,"after-boundary"),"nested phase boundary rejected");
        EquipWorkProbe.end(EquipWorkProbe.EVENT,stale);
        check("".equals(EquipWorkProbe.snapshot(thread).rawget("diagnostic")),"old exit damaged new phase");
        check(EquipWorkProbe.mark(thread,null),"final clear rejected");

        for (Class<?> advice:new Class<?>[]{EquipWorkProbe.ModSource.class,EquipWorkProbe.GameSource.class,
                EquipWorkProbe.Capture.class,EquipWorkProbe.Fingerprint.class,EquipWorkProbe.Registry.class,
                EquipWorkProbe.DispatchEnter.class,EquipWorkProbe.DispatchExit.class,EquipWorkProbe.EventTrigger.class}) {
            Patch patch=advice.getAnnotation(Patch.class); check(patch.strictMatch(),"instrumentation loosened strict native matching");
            for (var method:advice.getDeclaredMethods()) if (method.getName().equals("exit"))
                check(Arrays.equals(method.getParameterTypes(),new Class<?>[]{long.class}),"per-call exit scope is not primitive");
        }
        System.out.println("EQUIP_WORK_PROBE_PASS nativeKahluaClock=verified units=ms threadGuard=verified nestedSelf=verified sourceScope=verified signatures=verified gameStarted=false");
    }
}
