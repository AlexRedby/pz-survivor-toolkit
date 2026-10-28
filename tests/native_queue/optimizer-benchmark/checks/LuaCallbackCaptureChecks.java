package net.alexredby.drivingperf;

import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;

/** Runs real LuaCaller/Kahlua callbacks in joined stage frames, without starting the game. */
public final class LuaCallbackCaptureChecks {
    static void check(boolean value,String label) { if(!value) throw new AssertionError(label); }
    public static void main(String[] args) throws Exception {
        Path cache=Path.of(args[0]); Files.createDirectories(cache);
        var platform=new J2SEPlatform(); var env=platform.newTable(); env.rawset("n",0.0);
        var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
        var caller=new LuaCaller(new KahluaConverterManager());
        var child=LuaCompiler.loadis(new StringReader("n=n+1; return n"),"child.lua",env);
        env.rawset("reenter",(JavaFunction)(frame,count)->{caller.pcallvoid(thread,child,(Object)null);return 0;});
        var parent=LuaCompiler.loadis(new StringReader("reenter(); n=n+1"),"parent.lua",env);
        System.setProperty("pz.drivingPerf.stageProfile","true");
        System.setProperty("pz.drivingPerf.callbackProfile","true");
        System.setProperty("pz.drivingPerf.cachedir",cache.toString());
        StageProfiler.start(cache,Thread.currentThread());
        check(LuaCallbackHooks.verified && LuaCallbackHooks.installed,"actual hooks verified");
        StageProfiler.frameBegin(1,0,0);
        caller.pcallvoid(thread,parent,(Object)null);
        var values=caller.pcall(thread,child,new Object[0]);
        check(Boolean.TRUE.equals(values[0]) && Double.valueOf(3).equals(values[1]),"native return and side effects preserved");
        Thread foreign=new Thread(()->{
            var foreignThread=new KahluaThread(platform,env);foreignThread.debugOwnerThread=Thread.currentThread();
            caller.pcallvoid(foreignThread,child,(Object)null);
        });foreign.start();foreign.join();
        StageProfiler.frameEnd();
        StageProfiler.frameBegin(2,1,35);caller.protectedCallVoid(thread,child,new Object[0]);StageProfiler.frameEnd();
        check(!Files.exists(cache.resolve("driving-callbacks.csv")),"no capture file I/O");
        StageProfiler.frameBegin(2,1,0);
        JavaFunction finisher=(frame,count)->{try{StageProfiler.finish();}catch(Exception e){throw new RuntimeException(e);}return 0;};
        caller.pcallvoid(thread,finisher,(Object)null);
        check(LuaCallbackHooks.diagnostic==null && !LuaCallbackHooks.installed,"normal removal preserves verified status");
        var status=Files.readString(cache.resolve("driving-callback-status.txt"));
        check(status.contains("complete_frames=2") && status.contains("omitted_incomplete_frames=1") && status.contains("diagnostic=none"),"joined complete/partial artifact contract");
        check(Double.valueOf(5).equals(env.rawget("n")),"foreign/native callbacks retain effects");
        System.out.println("LUA_CALLBACK_CAPTURE_CHECKS_PASS");
    }
}
