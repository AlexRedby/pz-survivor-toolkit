package toolkit.warehousewalking;

import java.nio.file.*;
import java.lang.management.ManagementFactory;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.*;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.network.GameServer;

/** Disposable observer, explicitly bound to one owned client cache and thread. */
public final class Main {
    static Profile profile;
    static Thread owner;
    private static int phase;
    private static long start;
    private static com.sun.management.ThreadMXBean allocationBean;
    private static long allocationStart=-1;
    public static void main(String[] args) {}
    private static void gate() throws Exception {
        String path=System.getProperty("pz.warehouseWalking.cache","");
        if(path.isBlank() || GameServer.server || !"MainThread".equals(Thread.currentThread().getName()))
            throw new IllegalStateException("Owned client MainThread required");
        Path actual=Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath();
        Path marker=actual.resolve("Lua/smoke-user.txt");
        if(!actual.equals(Path.of(path).toRealPath()) || !Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS)
            || Files.size(marker)>1024 || !Files.readString(marker).trim().matches("client[12]"))
            throw new IllegalStateException("Owned warehouse cache marker required");
    }
    @LuaMethod(name="warehouseWalkingProfileReset",global=true)
    public static void reset() throws Exception {
        gate();if(profile!=null&&profile.active)throw new IllegalStateException("Observer already active");
        owner=Thread.currentThread();profile=new Profile();
        prepareAllocation();
    }
    static void prepareAllocation() {
        var bean=ManagementFactory.getThreadMXBean();
        allocationBean=bean instanceof com.sun.management.ThreadMXBean allocated
            && allocated.isThreadAllocatedMemorySupported()&&allocated.isThreadAllocatedMemoryEnabled()?allocated:null;
    }
    @LuaMethod(name="warehouseWalkingProfileBind",global=true)
    public static void bind(String name,Object function) {
        if(Thread.currentThread()!=owner || profile==null || !(function instanceof LuaClosure closure))
            throw new IllegalStateException("Expected owned native Lua closure: "+name);
        profile.bind(name,closure);
    }
    @LuaMethod(name="warehouseWalkingProfileBegin",global=true)
    public static void begin(int index) {
        if(Thread.currentThread()!=owner || profile==null || index<1||index>16)throw new IllegalStateException("Invalid phase");
        phase=index;allocationStart=allocationBytes();profile.begin();start=System.nanoTime();
    }
    static long allocationBytes(){return allocationBean==null?-1:allocationBean.getThreadAllocatedBytes(Thread.currentThread().threadId());}
    private static KahluaTable table(){return LuaManager.platform.newTable();}
    @LuaMethod(name="warehouseWalkingProfileFinish",global=true)
    public static KahluaTable finish() {
        if(Thread.currentThread()!=owner||profile==null)throw new IllegalStateException("Owned observer required");
        long end=System.nanoTime(),allocationEnd=allocationBytes();profile.finish();
        KahluaTable result=table(),metrics=table(),hooks=table();
        result.rawset("phase",(double)phase);result.rawset("index",(double)phase);result.rawset("clock","nanoTime");
        result.rawset("elapsed_ms",(end-start)/1e6);
        result.rawset("scope","registered-native-lua-calls");
        result.rawset("tail_calls","separate-frame-spans");result.rawset("exclusive_scope","registered-children");
        result.rawset("registration","public-roots-direct-upvalues-and-nested-prototypes");result.rawset("receiver_scope","shared-prototypes");result.rawset("observer_overhead_included",true);
        KahluaTable allocation=table();boolean allocated=allocationStart>=0&&allocationEnd>=allocationStart;
        allocation.rawset("available",allocated);allocation.rawset("scope","owner-thread-whole-interval");allocation.rawset("includes_observer",true);
        if(allocated)allocation.rawset("bytes",(double)(allocationEnd-allocationStart));result.rawset("allocation",allocation);
        hooks.rawset("init",(double)profile.initHooks);hooks.rawset("shrink",(double)profile.shrinkHooks);result.rawset("hooks",hooks);
        for(int i=0;i<profile.count;i++) {
            KahluaTable row=table();row.rawset("name",profile.names[i]);row.rawset("source",profile.sources[i]);row.rawset("first_line",(double)profile.lines[i]);
            KahluaTable aliases=table();int aliasIndex=0;
            for(String alias:profile.aliases.get(i))aliases.rawset((double)++aliasIndex,alias);
            row.rawset("aliases",aliases);
            row.rawset("calls",(double)profile.calls[i]);row.rawset("inclusive_ms",profile.inclusive[i]/1e6);
            row.rawset("exclusive_ms",profile.exclusive[i]/1e6);row.rawset("max_ms",profile.max[i]/1e6);
            metrics.rawset((double)i+1,row);
        }
        result.rawset("metrics",metrics);return result;
    }
    public static void initialized(LuaCallFrame frame){Profile p=profile;if(p!=null&&p.active&&Thread.currentThread()==owner)p.init(frame,System.nanoTime());}
    public static void shrinking(Coroutine coroutine,int top){Profile p=profile;if(p!=null&&p.active&&Thread.currentThread()==owner)p.shrink(coroutine,top,System.nanoTime());}
    @Patch(className="se.krka.kahlua.vm.LuaCallFrame",methodName="init",strictMatch=true)
    public static class Init {
        @Patch.OnEnter public static void enter(@Patch.This LuaCallFrame frame){Main.initialized(frame);}
    }
    @Patch(className="se.krka.kahlua.vm.Coroutine",methodName="setCallFrameStackTop",strictMatch=true)
    public static class Shrink {
        @Patch.OnEnter public static void enter(@Patch.This Coroutine coroutine,@Patch.Argument(0) int top){Main.shrinking(coroutine,top);}
    }
}
