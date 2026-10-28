package net.alexredby.drivingperf;

import java.nio.file.Path;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.Prototype;

/** Focused interval accounting and bounded failure checks, independent of wall-clock speed. */
public final class LuaCallbacksChecks {
    static void check(boolean value,String label) { if(!value) throw new AssertionError(label); }
    static void eq(long expected,long actual,String label) { check(expected==actual,label+": "+actual+" != "+expected); }
    static void nested() {
        var c=new LuaCallbacks.Capture(); Object a=new Object(),b=new Object();
        c.begin(7,100);
        int outer=c.enter(a,110),inner=c.enter(b,120),recursive=c.enter(a,130);
        c.exit(recursive,140); c.exit(inner,150); c.exit(outer,160); c.end(200,true);
        eq(1,c.frames,"complete frame"); eq(2,c.rows,"two identities");
        eq(50,c.rowInclusive[0],"recursive identity is union"); eq(30,c.rowExclusive[0],"outer excludes reentry");
        eq(30,c.rowInclusive[1],"nested inclusive"); eq(20,c.rowExclusive[1],"nested excludes recursion");
        eq(2,c.rowCalls[0],"recursive entries counted"); eq(50,c.rowMax[0],"largest invocation");
        eq(50,c.totals[0],"exclusive callbacks partition active intervals");
        c.begin(8,210); c.end(250,true); eq(2,c.frames,"empty frame retained"); eq(0,c.frameRows[1],"empty rows");
        c.begin(9,260); int trailing=c.enter(a,270); c.end(300,false); c.exit(trailing,310);
        eq(1,c.omitted,"incomplete frame discarded"); eq(2,c.frames,"partial not emitted"); check(c.error==null,"known omission valid");
    }
    static void metadata() {
        var p=new Prototype();p.filename="mods/example.lua";p.file="example.lua";p.name="shared";p.lines=new int[]{23};
        var c=new LuaCallbacks.Capture(); var a=new LuaClosure(p,null); var b=new LuaClosure(p,null);
        c.begin(1,0); int one=c.enter(a,1);c.exit(one,2);int two=c.enter(b,3);c.exit(two,4);c.end(5,true);
        eq(2,c.identities,"different closure upvalues retain identities"); check(c.sources[0][4].equals("23"),"first instruction metadata");
        check(c.sources[0][1].equals("mods/example.lua"),"raw metadata only");
    }
    static void failures() {
        var c=new LuaCallbacks.Capture();c.begin(1,0);Object a=new Object();
        int old=c.enter(a,1);c.exit(old,2);c.end(3,true);c.begin(2,4);c.enter(a,5);c.exit(old,6);
        check("callback-token-order".equals(c.error),"stale frame token rejected");
        c=new LuaCallbacks.Capture();c.begin(1,0);for(int i=0;i<LuaCallbacks.MAX_DEPTH;i++)c.enter(a,i+1);
        eq(0,c.enter(a,100),"depth overflow inactive token"); check(c.error!=null,"depth bound visible");
        c=new LuaCallbacks.Capture();c.begin(1,10);c.enter(a,9);check(c.error!=null,"backward time rejected");
        c=new LuaCallbacks.Capture();c.begin(1,0);c.enter(a,1);c.end(2,true);check(c.error!=null,"unbalanced complete frame rejected");
        c=new LuaCallbacks.Capture();c.begin(1,0);c.rows=LuaCallbacks.MAX_ROWS;int token=c.enter(a,1);c.exit(token,2);c.end(3,true);
        check("row-capacity".equals(c.error) && c.frames==0,"row cap retains incomplete evidence");
        c=new LuaCallbacks.Capture();c.begin(1,0);for(int i=0;i<LuaCallbacks.MAX_IDENTITIES;i++){token=c.enter(new Object(),i*2+1);c.exit(token,i*2+2);}
        c.enter(new Object(),5000);check("identity-capacity".equals(c.error),"identity cap visible");
    }
    static void window() {
        var c=new LuaCallbacks.Capture();
        for(int i=0;i<LuaCallbacks.MAX_FRAMES;i++){c.begin(i+1,i*2);c.end(i*2+1,true);}
        c.begin(LuaCallbacks.MAX_FRAMES+1,LuaCallbacks.MAX_FRAMES*2);eq(0,c.enter(new Object(),LuaCallbacks.MAX_FRAMES*2+1),"window stops without additional hook activity");
        eq(LuaCallbacks.MAX_FRAMES,c.frames,"bounded window");check(c.error==null,"intentional cap is not failure");
    }
    public static void main(String[] args) throws Exception { nested();metadata();failures();window();System.out.println("LUA_CALLBACK_INTERVAL_CHECKS_PASS"); }
}
