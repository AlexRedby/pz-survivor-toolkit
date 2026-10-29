package net.alexredby.drivingperf;

import java.io.StringReader;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;

/** Real Kahlua helper semantics and spans nested under actual woven callback boundaries. */
public final class LuaCallbackDetailsChecks {
    private static final String SETUP="""
        require=function(name)
            assert(name=='QueueTestSelection')
            return {options={callback_profile=true,callback_detail_profile=true,callback_chain_profile=chainProfile}}
        end
        Events={OnGameStart={Add=function(fn) installCallback=fn end}}
        print=function(message) lastPrint=message end
        local function fresh() return function(...) return ... end end
        PZSurvivorToolkit={VehicleLightDashboard={bind=fresh()}}
        YourDash={InstallCompactTooltipTree=fresh()}
        ISVehicleDashboard={
            _YourDashSportEnsureControls=fresh(),_YourDashSportPositionControls=fresh(),
            _YourDashFinalizeWearOrder=fresh(),checkEngineFull=fresh()}
        """;
    private static final String SEMANTICS="""
        local function packed(...) return {n=select('#',...),...} end
        local result=packed(PZDrivingCallbackCall(function(...)
            assert(select('#',...)==4)
            local a,b,c,d=...; assert(a=='a' and b==nil and c=='c' and d==nil)
            return 10,nil,30,nil
        end,'a',nil,'c',nil))
        assert(result.n==4 and result[1]==10 and result[2]==nil and result[3]==30 and result[4]==nil)
        assert(packed(PZDrivingCallbackCall(function() end)).n==0)
        assert(packed(PZDrivingCallbackCall(function() return nil end)).n==1)
        local sentinel={original=true}
        local ok,value=pcall(PZDrivingCallbackCall,function() error(sentinel,0) end)
        assert(not ok and value==sentinel)
        local outer=function() return PZDrivingCallbackCall(function() return 'nested',nil end) end
        result=packed(PZDrivingCallbackCall(outer));assert(result.n==2 and result[1]=='nested' and result[2]==nil)
        result=packed(PZSurvivorToolkit.VehicleLightDashboard.bind('bind',nil))
        assert(result.n==2 and result[1]=='bind' and result[2]==nil)
        result=packed(YourDash.InstallCompactTooltipTree('tree',nil));assert(result.n==2 and result[1]=='tree')
        result=packed(ISVehicleDashboard:_YourDashSportEnsureControls(nil,'ensure',nil))
        assert(result.n==4 and result[1]==ISVehicleDashboard and result[2]==nil and result[3]=='ensure')
        ISVehicleDashboard:_YourDashSportPositionControls()
        ISVehicleDashboard:_YourDashFinalizeWearOrder()
        ISVehicleDashboard:checkEngineFull()
        return 'semantics-pass'
        """;

    private static void check(boolean value,String message) { if(!value)throw new AssertionError(message); }
    private static LuaClosure closure(String text,KahluaTable env) throws Exception {
        return LuaCompiler.loadis(new StringReader(text),"callback-detail-check.lua",env);
    }
    private static Object[] call(LuaCaller caller,KahluaThread thread,LuaClosure closure) {
        Object[] result=caller.pcall(thread,closure,new Object[0]);
        check(Boolean.TRUE.equals(result[0]),"Lua check failed: "+java.util.Arrays.toString(result)); return result;
    }
    private static Field captureField() throws Exception {
        Field field=LuaCallbacks.class.getDeclaredField("capture");field.setAccessible(true);return field;
    }
    private static KahluaTable environment(J2SEPlatform platform) {
        KahluaTable env=platform.newEnvironment();
        env.rawset("drivingPerfCallbackEnter",(JavaFunction)(frame,count)->frame.push((double)Main.callbackEnter(frame.get(0))));
        env.rawset("drivingPerfCallbackExit",(JavaFunction)(frame,count)->{
            Main.callbackExit(((Double)frame.get(0)).intValue());return 0;
        });
        return env;
    }
    private static KahluaThread thread(J2SEPlatform platform,KahluaTable env) {
        KahluaThread thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();return thread;
    }
    public static void main(String[] args) throws Exception {
        check(args.length==2,"Expected helper source and new output cache");
        String helper=Files.readString(Path.of(args[0]));Path cache=Path.of(args[1]);Files.createDirectory(cache);
        System.setProperty("pz.drivingPerf.callbackProfile","true");
        System.setProperty("pz.drivingPerf.callbackDetailProfile","true");
        J2SEPlatform platform=new J2SEPlatform();KahluaTable env=environment(platform);
        KahluaThread thread=thread(platform,env);LuaCaller caller=new LuaCaller(new KahluaConverterManager());
        LuaCallbacks.start(Thread.currentThread());
        try {
            Field field=captureField();LuaCallbacks.Capture capture=(LuaCallbacks.Capture)field.get(null);
            check(capture.detailSpans,"property did not enable spans");
            call(caller,thread,closure(SETUP,env));call(caller,thread,closure(helper,env));
            call(caller,thread,closure("installCallback(); installCallback(); assert(lastPrint=='[DRIVING_PERF] CALLBACK_DETAILS_INSTALLED functions=6')",env));
            KahluaTable chainEnv=environment(platform);KahluaThread chainThread=thread(platform,chainEnv);
            call(caller,chainThread,closure(SETUP+"""
                chainProfile=true
                local function pass(...) return ... end
                PZSurvivorToolkit.VehicleDoorDashboard={update=pass}
                YourDash.GetVehicleProfile=pass;YourDash.GetScaleKey=pass
                for _,name in ipairs({'_applyLidMode','_updateStainLayer','_updateCrackLayer',
                    '_YourDashUpdateVoltage','_YourDashUpdateSideButtons','_updateACControls',
                    '_yourDashUpdateRoutedRadio','_YourDashSportRefreshCaches'}) do
                    ISVehicleDashboard[name]=pass
                end
                """,chainEnv));
            call(caller,chainThread,closure(helper,chainEnv));
            call(caller,chainThread,closure("installCallback(); assert(lastPrint=='[DRIVING_PERF] CALLBACK_DETAILS_INSTALLED functions=17'); assert(YourDash.GetScaleKey(12)==12)",chainEnv));
            LuaClosure root=closure(SEMANTICS,env);
            call(caller,thread,root);
            check(capture.identities==0 && capture.depth==0,"outside-frame wrapper captured work");
            LuaCallbacks.frameBegin(1,System.nanoTime());
            java.util.concurrent.atomic.AtomicReference<Throwable> foreignFailure=new java.util.concurrent.atomic.AtomicReference<>();
            Thread foreign=new Thread(()->{try {check(Main.callbackEnter(root)==0,"foreign thread span accepted");}
                catch(Throwable failure){foreignFailure.set(failure);}});
            foreign.start();foreign.join();check(foreignFailure.get()==null,"foreign thread receiver gate failed");
            call(caller,thread,root);
            check(capture.depth==0 && capture.error==null,"error/nested helper left token open");
            int rootId=capture.ids.get(root);long rootInclusive=capture.inclusive[rootId];
            check(capture.calls[rootId]==1 && capture.identities>=8,"missing original closure identities");
            check(rootInclusive>capture.exclusive[rootId],"inner spans were not nested under actual callback");
            LuaCallbacks.frameEnd(System.nanoTime(),true);
            check(capture.frames==1 && capture.totals[0]==rootInclusive,"callback/span exclusive tree does not partition root");
            check(Main.callbackEnter(root)==0,"inactive frame accepted span");

            LuaCallbacks.Capture disabled=new LuaCallbacks.Capture(false);disabled.begin(1,System.nanoTime());field.set(null,disabled);
            check(Main.callbackEnter(root)==0 && disabled.identities==0,"detail-disabled receiver captured span");
            LuaCallbacks.Capture invalid=new LuaCallbacks.Capture(true);invalid.begin(1,System.nanoTime());field.set(null,invalid);
            check(Main.callbackEnter(new Object())==0 && "unsupported-detail-span-function".equals(invalid.error),"non-Lua detail span not rejected");
            check(Main.callbackEnter(root)==0,"errored capture accepted detail span");field.set(null,capture);

            KahluaTable missing=environment(platform);KahluaThread missingThread=thread(platform,missing);
            call(caller,missingThread,closure(SETUP,missing));call(caller,missingThread,closure(helper,missing));
            call(caller,missingThread,closure("""
                ISVehicleDashboard.checkEngineFull=nil
                local original=PZSurvivorToolkit.VehicleLightDashboard.bind
                local ok,problem=pcall(installCallback)
                assert(not ok and string.find(tostring(problem),'Missing diagnostic callback target:',1,true))
                assert(PZSurvivorToolkit.VehicleLightDashboard.bind==original)
                assert(string.find(lastPrint,'[DRIVING_PERF] FAIL callback-detail-install:',1,true)==1)
                """,missing));
            LuaCallbacks.finish(cache);
            String status=Files.readString(cache.resolve("driving-callback-status.txt"));
            check(status.startsWith("version=2 ") && status.contains("detail_spans=enabled")
                && status.contains("max_rows=1200000") && status.contains("diagnostic=none"),"detail status contract wrong");
        } finally {LuaCallbacks.abort();}
        System.out.println("LUA_CALLBACK_DETAILS_CHECKS_PASS actual_kahlua=true exact_nil_returns=true original_error_object=true inner_spans=true");
    }
}
