package toolkit.warehousewalking;

import java.util.Arrays;
import java.util.IdentityHashMap;
import se.krka.kahlua.vm.*;

/** Bounded timings of real VM invocations; never installs a Lua wrapper. */
public final class Profile {
    static final int MAX_LABELS=2048, MAX_DEPTH=256;
    final IdentityHashMap<Prototype,Integer> labels=new IdentityHashMap<>();
    final IdentityHashMap<LuaClosure,Boolean> visited=new IdentityHashMap<>();
    final String[] names=new String[MAX_LABELS], sources=new String[MAX_LABELS];
    final int[] lines=new int[MAX_LABELS], ids=new int[MAX_DEPTH], frameDepths=new int[MAX_DEPTH];
    final LuaCallFrame[] frames=new LuaCallFrame[MAX_DEPTH];
    final long[] starts=new long[MAX_DEPTH], children=new long[MAX_DEPTH];
    final long[] calls=new long[MAX_LABELS], inclusive=new long[MAX_LABELS], exclusive=new long[MAX_LABELS], max=new long[MAX_LABELS];
    int count, depth;
    long initHooks, shrinkHooks;
    boolean active;
    String error;

    void bind(String name, LuaClosure closure) {
        if (active) throw new IllegalStateException("Cannot register during measurement");
        visit(name,closure,0);
    }
    private void visit(String name,LuaClosure closure,int nesting) {
        if (visited.put(closure,Boolean.TRUE)!=null) return;
        if (visited.size()>MAX_LABELS || nesting>32) throw new IllegalStateException("Closure registration bound exceeded");
        Prototype p=closure.prototype;
        if (!labels.containsKey(p)) {
            if (count==MAX_LABELS) throw new IllegalStateException("Prototype registration bound exceeded");
            int id=count++; labels.put(p,id); names[id]=name;
            sources[id]=p.filename!=null?p.filename:p.file!=null?p.file:"<unknown>";
            lines[id]=p.lines!=null&&p.lines.length>0?p.lines[0]:0;
        }
        if (closure.upvalues!=null) for (int i=0;i<closure.upvalues.length;i++) {
            UpValue up=closure.upvalues[i];
            if (up!=null && up.getValue() instanceof LuaClosure child) visit(name+".upvalue"+i,child,nesting+1);
        }
    }
    void begin() {
        if (active || error!=null || depth!=0) throw new IllegalStateException("Invalid observer state: "+error);
        for(long[] values:new long[][]{calls,inclusive,exclusive,max})Arrays.fill(values,0);
        initHooks=shrinkHooks=0; active=true;
    }
    void init(LuaCallFrame frame,long now) {
        if (!active) return;
        initHooks++;
        // OP_TAILCALL reuses its current frame and calls init again.
        if(depth>0 && frames[depth-1]==frame) close(now);
        Integer id=frame.closure==null?null:labels.get(frame.closure.prototype);
        if(id==null || !active)return;
        if(depth==MAX_DEPTH){fail("Timing stack overflow");return;}
        if(depth>0 && frames[depth-1].coroutine!=frame.coroutine){fail("Cross-coroutine timing unsupported");return;}
        if(depth>0 && now<starts[depth-1]){fail("Nonmonotonic entry");return;}
        ids[depth]=id;frames[depth]=frame;frameDepths[depth]=frame.coroutine.getCallframeTop();
        starts[depth]=now;children[depth]=0;depth++;
    }
    void shrink(Coroutine coroutine,int target,long now) {
        if(!active)return;
        shrinkHooks++;
        while(depth>0 && frames[depth-1].coroutine==coroutine && frameDepths[depth-1]>target)close(now);
    }
    private void close(long now) {
        int i=--depth,id=ids[i];long elapsed=now-starts[i];
        if(elapsed<0 || elapsed<children[i]){fail("Nonmonotonic exit");return;}
        calls[id]++;inclusive[id]+=elapsed;exclusive[id]+=elapsed-children[i];max[id]=Math.max(max[id],elapsed);
        frames[i]=null;if(depth>0)children[depth-1]+=elapsed;
    }
    void finish() {
        active=false;
        if(depth!=0)fail("Unbalanced timing stack at finish");
        if(error!=null)throw new IllegalStateException(error);
        if(initHooks==0 || shrinkHooks==0)throw new IllegalStateException("Native observer advice was not invoked");
    }
    private void fail(String message){if(error==null)error=message;active=false;depth=0;Arrays.fill(frames,null);}
}
