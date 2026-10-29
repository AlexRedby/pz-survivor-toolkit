package pzresearch;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.Arrays;
import java.util.Map;
import java.util.TreeMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.core.properties.PropertyContainer;

/** Test-only bounded invocation scratch. No fields are added to native world objects. */
public final class AggregationScope {
    public static final int LIMIT=64;
    public static final boolean OBSERVE=Boolean.parseBoolean(System.getProperty("recalc.observe","true"));
    private static final ThreadLocal<Scope> ACTIVE=new ThreadLocal<>();
    private static final ThreadLocal<TreeMap<String,Integer>> COUNTS=ThreadLocal.withInitial(TreeMap::new);
    private static final VarHandle CAPTURE,FLAGS1,FLAGS2;
    public static long hits,misses,scopes,invalidations;
    static {
        try {
            FLAGS1=MethodHandles.privateLookupIn(PropertyContainer.class,MethodHandles.lookup()).findVarHandle(PropertyContainer.class,"spriteFlags1",long.class);
            FLAGS2=MethodHandles.privateLookupIn(PropertyContainer.class,MethodHandles.lookup()).findVarHandle(PropertyContainer.class,"spriteFlags2",long.class);
            CAPTURE=Boolean.getBoolean("recalc.official") ? MethodHandles.publicLookup().findStaticVarHandle(
                Class.forName("pzopt.HandoffRecalc"),"capture",boolean.class) : null;
        } catch(Exception e) {throw new ExceptionInInitializerError(e);}
    }
    private static final ClassValue<Boolean> ELIGIBLE=new ClassValue<>() {
        protected Boolean computeValue(Class<?> c) {
            try {return c.getMethod("getProperties").getDeclaringClass()==IsoObject.class
                && c.getMethod("getType").getDeclaringClass()==IsoObject.class;}
            catch(Exception e){return false;}
        }
    };
    private static final class Scope {
        final Scope previous;
        final IsoGridSquare[] squares=new IsoGridSquare[LIMIT];
        final int[] masks=new int[LIMIT];
        final long[] flags1=new long[LIMIT],flags2=new long[LIMIT];
        int size,depth;boolean invalid,route;
        Scope(Scope p){previous=p;invalid=p!=null;}
        void clear(){Arrays.fill(squares,null);size=0;}
    }
    public static void enter() {
        Scope previous=ACTIVE.get();
        if(previous!=null){previous.invalid=true;previous.clear();}
        ACTIVE.set(new Scope(previous));if(OBSERVE)scopes++;
    }
    public static void enterCandidate(){enter();ACTIVE.get().route=true;}
    public static boolean route(){Scope s=ACTIVE.get();return s!=null && s.route && !s.invalid && !(CAPTURE!=null && (boolean)CAPTURE.get());}
    public static void exit() {
        Scope s=ACTIVE.get();if(s==null)throw new IllegalStateException("No scope");
        s.clear();if(s.previous==null)ACTIVE.remove();else ACTIVE.set(s.previous);
    }
    public static boolean active(){return ACTIVE.get()!=null;}
    public static int retained(){Scope s=ACTIVE.get();return s==null?0:s.size;}
    public static void count(String s){COUNTS.get().merge(s,1,Integer::sum);}
    public static Map<String,Integer> counts(){return new TreeMap<>(COUNTS.get());}
    public static void resetCounts(){COUNTS.get().clear();}
    public static void startCall(){Scope s=ACTIVE.get();if(s!=null && ++s.depth>1)invalidate();}
    public static void endCall(){Scope s=ACTIVE.get();if(s!=null)s.depth--;}
    public static void invalidate(){Scope s=ACTIVE.get();if(s!=null){s.invalid=true;s.clear();if(OBSERVE)invalidations++;}}
    private static boolean eligible(IsoGridSquare square) {
        Scope s=ACTIVE.get();
        if(s==null || s.invalid || s.depth!=1 || CAPTURE!=null && (boolean)CAPTURE.get())return false;
        // This deliberate per-call scan is part of the prototype's real storage/eligibility cost.
        // It does not pretend to detect supported mutations within the invocation.
        for(int i=0;i<square.getObjects().size();i++) {
            IsoObject object=square.getObjects().get(i);
            if(object!=null && !ELIGIBLE.get(object.getClass())){invalidate();return false;}
        }
        return true;
    }
    public static int lookup(IsoGridSquare square) {
        if(!eligible(square)){if(OBSERVE)misses++;return -1;}
        Scope s=ACTIVE.get();
        for(int i=0;i<s.size;i++)if(s.squares[i]==square){
            // Restore pre-suffix aggregate flags, otherwise repeated unsets are skipped.
            PropertyContainer properties=square.getProperties();FLAGS1.set(properties,s.flags1[i]);FLAGS2.set(properties,s.flags2[i]);
            if(OBSERVE)hits++;return s.masks[i];}
        if(OBSERVE)misses++;return -1;
    }
    public static void remember(IsoGridSquare square,int mask) {
        if(!eligible(square))return;Scope s=ACTIVE.get();
        for(int i=0;i<s.size;i++)if(s.squares[i]==square)return;
        if(s.size==LIMIT){invalidate();return;}
        s.squares[s.size]=square;s.masks[s.size]=mask;
        PropertyContainer properties=square.getProperties();
        s.flags1[s.size]=(long)FLAGS1.get(properties);s.flags2[s.size]=(long)FLAGS2.get(properties);s.size++;
    }
}
