package toolkit.warehousewalking;

import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

/** Executes the installed game's Kahlua with the real ZombieBuddy weaver; no game launch. */
public final class ProfileChecks {
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    static void eq(long a,long b,String message){check(a==b,message+": "+a+" != "+b);}
    static LuaClosure compile(String code,String name,KahluaTable env)throws Exception{return LuaCompiler.loadstring(code,name,env);}
    static void focused()throws Exception {
        var platform=new J2SEPlatform();var env=platform.newTable();var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
        var p=new Profile();var c=compile("return 1","unit",env);p.bind("outer",c);
        var co=thread.currentCoroutine;var frame=co.pushNewCallFrame(c,null,0,0,0,false,false);
        p.begin();p.init(frame,100);p.shrink(co,0,200);p.finish();eq(1,p.calls[0],"one invocation");eq(100,p.inclusive[0],"inclusive");eq(100,p.exclusive[0],"exclusive");
        p=new Profile();p.bind("outer",c);p.begin();p.init(frame,100);p.init(frame,120);p.shrink(co,0,160);p.finish();eq(2,p.calls[0],"tail replacement calls");eq(60,p.inclusive[0],"tail no double counting");
        p=new Profile();p.bind("outer",c);p.begin();p.init(frame,100);p.shrink(co,0,99);boolean failed=false;try{p.finish();}catch(IllegalStateException e){failed=true;}check(failed,"clock violation fails closed");
        p=new Profile();p.bind("outer",c);p.begin();p.init(frame,100);failed=false;try{p.finish();}catch(IllegalStateException e){failed=true;}check(failed,"open stack fails closed");
        p=new Profile();p.bind("outer",c);p.begin();failed=false;try{p.finish();}catch(IllegalStateException e){failed=true;}check(failed,"missing instrumentation rejected");
        co.popCallFrame();
    }
    static void nativeCalls()throws Exception {
        var platform=new J2SEPlatform();var env=platform.newTable();var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
        env.rawset("work",(JavaFunction)(f,n)->{long end=System.nanoTime()+1_000_000;while(System.nanoTime()<end)Thread.onSpinWait();return 0;});
        var child=compile("work(); return 9,nil,11","child.lua",env);env.rawset("child",child);
        var parent=compile("local a,b,c=child(); work(); return a,b,c","parent.lua",env);
        var p=new Profile();p.bind("parent",parent);p.bind("child",child);Main.owner=Thread.currentThread();Main.profile=p;p.begin();
        Object[] returned=thread.pcall(parent,new Object[]{});p.finish();
        check(returned.length==4&&returned[0]==Boolean.TRUE&&returned[1].equals(9.0)&&returned[2]==null&&returned[3].equals(11.0),"native multireturn/nil preserved");
        int parentId=p.labels.get(parent.prototype),childId=p.labels.get(child.prototype);
        eq(1,p.calls[parentId],"real Lua-to-Lua parent");eq(1,p.calls[childId],"real Lua-to-Lua child");
        check(p.inclusive[parentId]>=p.inclusive[childId]&&p.exclusive[parentId]>0,"nested native timings");
        eq(p.inclusive[parentId],p.exclusive[parentId]+p.inclusive[childId],"nested exclusive partition");
        var recursive=compile("function recurse(n) if n==0 then return 17 end return recurse(n-1) end return recurse","tail.lua",env);
        LuaClosure tail=(LuaClosure)thread.call(recursive,new Object[]{});p=new Profile();p.bind("tail",tail);Main.profile=p;p.begin();
        Object value=thread.call(tail,new Object[]{30.0});p.finish();check(value.equals(17.0),"native tail return");eq(31,p.calls[0],"native tail invocation count");eq(p.inclusive[0],p.exclusive[0],"tail replacements disjoint");
        var boom=(JavaFunction)(f,n)->{throw new RuntimeException("observer-test-original-error");};env.rawset("boom",boom);
        var failing=compile("boom(); return 0","failing.lua",env);p=new Profile();p.bind("failing",failing);Main.profile=p;p.begin();
        Object[] error=thread.pcall(failing,new Object[]{});p.finish();
        check(error[0]==Boolean.FALSE&&error[1].toString().contains("observer-test-original-error"),"native exception preserved");eq(1,p.calls[0],"exception unwinds measured native frame");
        p=new Profile();p.bind("child",child);Main.profile=p;p.begin();
        Thread foreign=new Thread(()->Main.initialized(null));foreign.start();foreign.join();
        thread.call(child,new Object[]{});p.finish();eq(1,p.calls[0],"foreign thread inert");
        check(env.rawget("child")==child,"closure identity unchanged");
        var overflow=new Profile();overflow.bind("recursive",tail);Main.profile=overflow;
        // Non-tail recursion must exceed the bounded observer stack before native stack capacity.
        var recurseChunk=compile("function deep(n) if n==0 then return 1 end local result=deep(n-1) return result+1 end return deep","depth.lua",env);
        LuaClosure deep=(LuaClosure)thread.call(recurseChunk,new Object[]{});overflow.bind("deep",deep);overflow.begin();
        check(thread.call(deep,new Object[]{260.0}).equals(261.0),"observer overflow preserves native return");
        boolean rejected=false;try{overflow.finish();}catch(IllegalStateException e){rejected=true;}check(rejected&&overflow.error.contains("overflow"),"overflow rejects capture");
        Main.profile=null;
    }
    public static void main(String[] args)throws Exception {
        PatchEngine.applyPatches("toolkit.warehousewalking",ProfileChecks.class.getClassLoader());
        focused();nativeCalls();System.out.println("WAREHOUSE_WALKING_PROFILE_NATIVE_PASS nested_lua_calls=true tail_calls=true exceptions=true native_returns=true thread_guard=true bounds=true");
    }
}
