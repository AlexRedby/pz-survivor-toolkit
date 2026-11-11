package net.alexredby.pztoolkitjavapatches;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.Reader;
import java.io.StringReader;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicReference;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.gameStates.ChooseGameInfo;

/** Uses the installed, explicitly selected upstream mod without editing its files. */
public final class VehicleSalvageSandboxChecks {
    private static final String TARGET = VehicleSalvageSandbox.TARGET;
    private static final String NAME = "VRO_SalvageSandbox.lua";
    private static final String KEY = TARGET.toLowerCase(Locale.ROOT);
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static Field field(Class<?> type, String name) throws Exception {
        Field field = type.getDeclaredField(name); field.setAccessible(true); return field;
    }
    private static Object scope() throws Exception {
        return ((ThreadLocal<?>) field(VehicleSalvageSandbox.class, "LOADING").get(null)).get();
    }
    private static String text(Reader reader) throws IOException {
        StringBuilder result = new StringBuilder(); char[] buffer = new char[8192];
        for (int count; (count = reader.read(buffer)) >= 0;) result.append(buffer, 0, count);
        return result.toString();
    }
    private static Object lua(String source) throws IOException {
        return LuaManager.thread.call(LuaCompiler.loadstring(source, "vehicle-salvage-check", LuaManager.env), new Object[0]);
    }
    private static byte[] compiled(String source) throws IOException {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        LuaCompiler.loadis(new StringReader(source), NAME, LuaManager.env).prototype.dump(result);
        return result.toByteArray();
    }
    private static void helpers(String original, String fixed) throws IOException {
        lua("VRO=nil; SandboxVars=nil\n" + fixed + "\n"
            + "assert(VRO.IsFullVehicleSalvagingEnabled()==true); assert(VRO.GetSalvageTime('VRO_SalvageTime_Doors',600)==600)\n"
            + "SandboxVars={VSO_EnableFullVehicleSalvaging=false,VRO_EnableFullVehicleSalvaging=true,VRO={EnableFullVehicleSalvaging=true}}\n"
            + "assert(VRO.IsFullVehicleSalvagingEnabled()==false)\n"
            + "SandboxVars.VSO_EnableFullVehicleSalvaging=true;SandboxVars.VRO_EnableFullVehicleSalvaging=false;assert(VRO.IsFullVehicleSalvagingEnabled()==true)\n"
            + "SandboxVars.VSO_EnableFullVehicleSalvaging='true';assert(VRO.IsFullVehicleSalvagingEnabled()==false)\n"
            + "SandboxVars={VSO_SalvageTime_Doors=120.9,VRO_SalvageTime_Doors=777,VRO={SalvageTime_Doors=888}}\n"
            + "assert(VRO.GetSalvageTime('VRO_SalvageTime_Doors',600)==120)\n"
            + "assert(SandboxVars.VRO_SalvageTime_Doors==777 and SandboxVars.VRO.SalvageTime_Doors==888)\n"
            + "for _,invalid in ipairs({false,'broken',0,-1,0.9,{}}) do SandboxVars.VSO_SalvageTime_Doors=invalid;assert(VRO.GetSalvageTime('VRO_SalvageTime_Doors',600)==600) end\n"
            + "SandboxVars.VSO_SalvageTime_Doors='1.9';assert(VRO.GetSalvageTime('VRO_SalvageTime_Doors',600)==1)\n"
            + "assert(VRO.GetSalvageTime(nil,'12.7')==12.7);assert(VRO.GetSalvageTime(nil,'broken')==100)\n"
            + "SandboxVars={VSO_Custom=120,Custom=234,VRO_Custom=345};assert(VRO.GetSalvageTime('Custom',600)==234);assert(VRO.GetSalvageTime('VRO_Custom',600)==345)\n"
            + "SandboxVars={VSO_SalvageTime_Doors=120};assert(VRO.GetSalvageTime('VRO_SalvageTime_Doors',600)==120);assert(SandboxVars.VRO_SalvageTime_Doors==nil and SandboxVars.VRO==nil)\n");
        // Every legacy/default case must preserve native upstream results exactly.
        for (String vars : new String[]{"nil", "{}", "{VRO_EnableFullVehicleSalvaging=false}",
                "{VRO={EnableFullVehicleSalvaging=false}}", "{VRO_EnableFullVehicleSalvaging=true,VRO={EnableFullVehicleSalvaging=false}}",
                "{VRO_SalvageTime_Doors='13.8'}", "{VRO={SalvageTime_Doors='14.9'}}",
                "{VRO_SalvageTime_Doors=false,VRO={SalvageTime_Doors=99}}", "{VRO_SalvageTime_Doors=0}", "{VRO_SalvageTime_Doors='bad'}"}) {
            String tail = "\nreturn tostring(VRO.IsFullVehicleSalvagingEnabled())..'|'..tostring(VRO.GetSalvageTime('VRO_SalvageTime_Doors',600))";
            Object before = lua("VRO=nil;SandboxVars=" + vars + "\n" + original + tail);
            Object after = lua("VRO=nil;SandboxVars=" + vars + "\n" + fixed + tail);
            require(before.equals(after), "legacy/default semantics changed: " + vars);
        }
    }
    private static void events(String helper, String handler, boolean server) throws IOException {
        // Exercise every current upstream option with distinct values, detecting key mixups too.
        StringBuilder assignments = new StringBuilder(), assertions = new StringBuilder();
        var options = java.util.regex.Pattern.compile("recipe\\s*=\\s*\"([^\"]+)\"\\s*,\\s*var\\s*=\\s*\"VRO_(SalvageTime_[^\"]+)\"").matcher(handler);
        int value = 120;
        while (options.find()) {
            assignments.append("SandboxVars.VSO_").append(options.group(2)).append('=').append(value).append(';');
            assertions.append("assert(times['").append(options.group(1)).append("']==").append(value++).append(");");
        }
        require(value > 120, "upstream handler has no recognized salvage option declarations");
        // Real upstream registration and callbacks; only game services are narrow Lua doubles.
        lua("VRO=nil;SandboxVars={};local server=" + server + "\n" + helper + "\n" + """
            local callbacks={}
            local function event(name) return {Add=function(callback) callbacks[name]=callback end} end
            Events={OnInitWorld=event('init'),OnGameBoot=event('boot'),OnGameStart=event('client'),OnServerStarted=event('server')}
            isServer=function() return server end
            require=function(name) if name=='VRO/Core' then return VRO end return {} end
            local times={}
            ScriptManager={instance={getCraftRecipe=function(self,name)
                return {Load=function(self,actual,source)
                    assert(actual==name)
                    local time=source:match('time = (%d+)')
                    if time then times[name]=tonumber(time) end
                end}
            end}}
            """ + handler + "\n" + """
            assert(type(callbacks.client)=='function')
            assert((callbacks.server~=nil)==server)
            -- Values are deliberately assigned after registration: callbacks must read helpers dynamically.
            SandboxVars={VSO_SalvageTime_Doors=120.9,VRO_SalvageTime_Doors=999}
            callbacks.client();assert(times['Salvage Vehicle Doors']==120)
            assert(times['Salvage Vehicle Tires']==600)
            SandboxVars.VSO_SalvageTime_Doors='bad';callbacks.client();assert(times['Salvage Vehicle Doors']==600)
            SandboxVars.VSO_SalvageTime_Doors=nil;callbacks.client();assert(times['Salvage Vehicle Doors']==999)
            if server then
                SandboxVars.VSO_SalvageTime_Doors=121;callbacks.server();assert(times['Salvage Vehicle Doors']==121)
                SandboxVars.VSO_SalvageTime_Doors=false;callbacks.server();assert(times['Salvage Vehicle Doors']==600)
            end
            """ + "\nSandboxVars={}\n" + assignments + "callbacks.client();" + assertions
            + (server ? "SandboxVars={}\n" + assignments + "callbacks.server();" + assertions : ""));
    }
    private static final Reader BOMB = new Reader() {
        @Override public int read(char[] b, int o, int n) { throw new AssertionError("foreign input consumed"); }
        @Override public void close() { throw new AssertionError("borrowed Reader closed"); }
    };
    private static void unchangedScope(String request) throws Exception {
        var previous = VehicleSalvageSandbox.begin(request, true);
        try { require(VehicleSalvageSandbox.compilerInput(BOMB, NAME, true) == BOMB, "foreign ownership accepted: " + request); }
        finally { VehicleSalvageSandbox.end(previous); }
    }
    private static void readerChecks() throws Exception {
        String large = "x".repeat(128 * 1024 + 17);
        final int[] capturedChars={0};
        Reader oversized = new StringReader(large) {
            @Override public int read(char[] buffer, int offset, int length) throws IOException {
                int count=super.read(buffer,offset,length); if(count>0) capturedChars[0]+=count; return count;
            }
            @Override public void close() { throw new AssertionError("borrowed oversized Reader closed"); }
        };
        var previous = VehicleSalvageSandbox.begin(TARGET, true);
        try {
            Reader replay=VehicleSalvageSandbox.compilerInput(oversized, NAME, true);
            require(capturedChars[0]==128*1024+1,"capture exceeded its read-ahead bound");
            require(text(replay).equals(large), "bounded replay lost prefix/tail");
            replay.close();
        } finally { VehicleSalvageSandbox.end(previous); }
        IOException failure = new IOException("fixture IO");
        Reader broken = new Reader() {
            private boolean read;
            @Override public int read(char[] b, int o, int n) throws IOException {
                if (read) throw failure; read=true; b[o]='x'; return 1;
            }
            @Override public void close() { throw new AssertionError("borrowed failure reader closed"); }
        };
        previous = VehicleSalvageSandbox.begin(TARGET, true);
        try {
            Reader replay = VehicleSalvageSandbox.compilerInput(broken, NAME, true);
            require(replay.read(new char[0],0,0)==0 && replay.read()=='x', "failure replay order changed");
            try { replay.read(); throw new AssertionError("IO failure swallowed"); }
            catch (IOException observed) { require(observed==failure, "IO failure identity changed"); }
            replay.close();
        } finally { VehicleSalvageSandbox.end(previous); }
        final int[] closes={0};
        Reader owned = new StringReader("return 1") { @Override public void close() { closes[0]++; super.close(); } };
        previous = VehicleSalvageSandbox.begin(TARGET, true);
        try { VehicleSalvageSandbox.compilerInput(owned, NAME, true).close(); require(closes[0]==0,"capture closed original"); }
        finally { VehicleSalvageSandbox.end(previous); owned.close(); }
        require(closes[0]==1,"native owner's close count changed");
    }
    public static void main(String[] args) throws Exception {
        String external = System.getenv("PZ_VSO_SOURCE");
        require(external!=null && !external.isBlank(), "set PZ_VSO_SOURCE to the upstream VSO mod root containing 42/media");
        Path externalVersion = Path.of(external).resolve("42");
        Path externalSource = externalVersion.resolve(TARGET);
        byte[] sourceBytes = Files.readAllBytes(externalSource);
        String original = Files.readString(externalSource), fixed = VehicleSalvageSandbox.transformSource(original);
        require(fixed!=original,"selected upstream source differs from reviewed digest");
        require(VehicleSalvageSandbox.transformSource(null)==null,"null source changed");
        require(VehicleSalvageSandbox.transformSource(fixed)==fixed,"already corrected source changed");
        String changed=original+"\n";
        require(VehicleSalvageSandbox.transformSource(changed)==changed,"unknown input digest accepted");
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        ZomboidFileSystem files=ZomboidFileSystem.instance;
        files.setCacheDir(System.getProperty("pz.test.cache"));files.init();
        Path root=Path.of(System.getProperty("pz.test.cache"),"mods/VSO"),version=root.resolve("42"),pane=version.resolve(TARGET);
        Files.createDirectories(pane.getParent());Files.createDirectories(root.resolve("common"));
        Files.writeString(root.resolve("common/mod.info"),"id="+VehicleSalvageSandbox.MOD_ID+"\n");
        Files.writeString(version.resolve("mod.info"),"id="+VehicleSalvageSandbox.MOD_ID+"\nmodversion=fixture\n");
        Files.writeString(pane,original);files.setModIdToDir(VehicleSalvageSandbox.MOD_ID,root.toString());
        require(Path.of(ChooseGameInfo.getModDetails(VehicleSalvageSandbox.MOD_ID).getVersionDir()).equals(version),"native versionDir selection changed");
        files.getModIDs().add(VehicleSalvageSandbox.MOD_ID);files.activeFileMap.put(KEY,pane.toString());
        require(VehicleSalvageSandbox.SUPPORTED,"unsupported installed engine bytes");
        LuaManager.platform=new J2SEPlatform();LuaManager.env=LuaManager.platform.newEnvironment();
        LuaManager.thread=new KahluaThread(LuaManager.platform,LuaManager.env);LuaManager.thread.debugOwnerThread=Thread.currentThread();
        LuaManager.caller=new LuaCaller(new KahluaConverterManager());
        helpers(original,fixed);
        String handler=Files.readString(externalVersion.resolve("media/lua/shared/PartSalvageRecipeHandler.lua"));
        events(fixed,handler,false);events(fixed,handler,true);
        require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,true)==BOMB,"unscoped input consumed");
        var previous=VehicleSalvageSandbox.begin(TARGET,false);
        try {require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,true)==BOMB,"unsupported loader consumed");}
        finally {VehicleSalvageSandbox.end(previous);}
        files.getModIDs().remove(VehicleSalvageSandbox.MOD_ID);unchangedScope(TARGET);files.getModIDs().add(VehicleSalvageSandbox.MOD_ID);
        Path foreign=root.resolve("foreign").resolve(TARGET);Files.createDirectories(foreign.getParent());Files.writeString(foreign,original);
        files.activeFileMap.put(KEY,foreign.toString());unchangedScope(TARGET);unchangedScope(pane.toString());unchangedScope(foreign.toString());
        files.activeFileMap.put(KEY,pane.toString());unchangedScope(foreign.toString());
        previous=VehicleSalvageSandbox.begin(TARGET,true);
        try {
            files.activeFileMap.put(KEY,foreign.toString());require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,true)==BOMB,"stale active provider accepted");
            files.activeFileMap.put(KEY,pane.toString());require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,true)==BOMB,"rejected scope reused");
        } finally {files.activeFileMap.put(KEY,pane.toString());VehicleSalvageSandbox.end(previous);}
        Boolean ignore=files.ignoreActiveFileMap.get();files.ignoreActiveFileMap.set(true);unchangedScope(TARGET);files.ignoreActiveFileMap.set(ignore);
        previous=VehicleSalvageSandbox.begin(TARGET,true);
        try {files.ignoreActiveFileMap.set(true);require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,true)==BOMB,"changed ignore mode accepted");}
        finally {files.ignoreActiveFileMap.set(ignore);VehicleSalvageSandbox.end(previous);}
        previous=VehicleSalvageSandbox.begin(TARGET,true);
        try {
            for(String name:new String[]{"Other.lua","/foreign/"+NAME,"C:\\foreign\\"+NAME,"C:/foreign\\"+NAME})
                require(VehicleSalvageSandbox.compilerInput(BOMB,name,true)==BOMB,"foreign compiler label accepted");
            require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,false)==BOMB,"unsupported compiler consumed");
            require(text(VehicleSalvageSandbox.compilerInput(new StringReader(changed),NAME,true)).equals(changed),"unknown source replay changed");
            require(VehicleSalvageSandbox.compilerInput(BOMB,NAME,true)==BOMB,"claimed scope reused");
        } finally {VehicleSalvageSandbox.end(previous);}
        readerChecks();
        byte[] expected=compiled(fixed),ordinary=compiled(original);require(!Arrays.equals(expected,ordinary),"prototype unchanged");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",VehicleSalvageSandboxChecks.class.getClassLoader());
        previous=VehicleSalvageSandbox.begin(TARGET,true);
        try {require(Arrays.equals(compiled(original),expected),"woven compiler did not replace Reader");}
        finally {VehicleSalvageSandbox.end(previous);}
        require(Arrays.equals(compiled(original),ordinary),"unscoped prototype changed");
        LuaManager.loaded.remove(TARGET);lua("VRO=nil;SandboxVars={VSO_EnableFullVehicleSalvaging=false,VSO_SalvageTime_Doors=120}");
        LuaManager.RunLua(TARGET,false);
        require(Boolean.TRUE.equals(lua("return VRO.IsFullVehicleSalvagingEnabled()==false and VRO.GetSalvageTime('VRO_SalvageTime_Doors',600)==120")),"real RunLua did not load corrected helper");
        require(scope()==null,"real load leaked scope");LuaManager.RunLua(TARGET,false);require(scope()==null,"cached load leaked scope");
        Path inner=root.resolve("inner.lua");Files.writeString(inner,"return salvageInnerProbe()\n");files.activeFileMap.put("salvage-inner.lua",inner.toString());
        AtomicReference<Throwable> failure=new AtomicReference<>();
        LuaManager.env.rawset("salvageInnerProbe",(JavaFunction)(frame,count)->{
            try {require(scope()!=null && field(VehicleSalvageSandbox.Scope.class,"target").get(scope())==null,"nested load inherited ownership");frame.push(19.0);return 1;}
            catch(Throwable error){failure.set(error);throw new RuntimeException(error);}
        });
        LuaManager.env.rawset("salvageScopeProbe",(JavaFunction)(frame,count)->{
            try {
                Object active=scope();require(active!=null && field(VehicleSalvageSandbox.Scope.class,"claimed").getBoolean(active),"woven load scope unclaimed");
                require(Double.valueOf(19).equals(LuaManager.RunLua("salvage-inner.lua",false)),"nested RunLua failed");require(scope()==active,"nested scope not restored");
                try {LuaManager.RunLua(null,false);}catch(NullPointerException expectedError){}
                require(scope()==active,"throwing nested scope not restored");frame.push(71.0);return 1;
            }catch(Throwable error){failure.set(error);throw new RuntimeException(error);}
        });
        Files.writeString(pane,"return salvageScopeProbe()\n");LuaManager.loaded.remove(TARGET);
        require(Double.valueOf(71).equals(LuaManager.RunLua(TARGET,false)),"woven unknown-source probe failed: "+failure.get());
        require(failure.get()==null && scope()==null,"woven nested/error scope failed: "+failure.get());
        require(Arrays.equals(sourceBytes,Files.readAllBytes(externalSource)),"upstream Workshop bytes changed");
        System.out.println("VEHICLE_SALVAGE_SANDBOX_CHECKS_PASS (reviewed source, native Kahlua options and real handler events, woven RunLua/loadis, provider and replay guards)");
    }
}
