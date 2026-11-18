package net.alexredby.lootdemand;

import java.util.ArrayList;
import java.util.IdentityHashMap;

/** Test-only bounded observation; it never authorizes or performs gameplay work.
 * CSV schema 1 retains original automatic-visit identities only. All methods that
 * touch the ledger are synchronized because native Host packet fills may arrive
 * outside the fixture's strict gameplay authority thread. Unknown identities do
 * not inherit coordinates/visits from a former container at the same position.
 * first_auto_ns/first_fill_ns use the JVM-local monotonic clock; fill_ns is -1
 * until the first outer native call completes. Foreign-thread observations never
 * enable state guards, overlay refresh, explored writes or deferred generation.
 */
final class DemandCensus<C> {
    private static final class Row<C> {
        C identity; String type,sprite,kind="none",firstThread="none";
        int x,y,z,index,depth,ownerDepth,id;
        long firstAuto,firstFill,elapsed=-1,visits,reentries,repeats,concurrent;
        boolean failed,firstAuthority;
        Thread owner,firstOwner;
        // Allocated only if native code actually overlaps different threads.
        IdentityHashMap<Thread,Integer> otherDepths;
    }
    private final String arm;
    private final int capacity;
    private final IdentityHashMap<C,Row<C>> identities=new IdentityHashMap<>();
    private final ArrayList<Row<C>> ordered=new ArrayList<>();
    private long overflow;
    private C automaticNext;
    private Thread automaticThread;
    private final int watchLimit;
    private final IdentityHashMap<C,Row<C>> watched = new IdentityHashMap<>();
    DemandCensus(String arm,int capacity) {
        this(arm, capacity, 1);
    }
    DemandCensus(String arm,int capacity,int watchLimit) {
        if (watchLimit < 1 || watchLimit > 2) throw new IllegalArgumentException("Invalid observer capacity");
        this.watchLimit = watchLimit;
        if (!arm.equals("legacy") && !arm.equals("observe") && !arm.equals("defer")) throw new IllegalArgumentException("Unknown census arm");
        if (capacity<1) throw new IllegalArgumentException("Census capacity");
        this.arm=arm;this.capacity=capacity;
    }
    boolean observing() { return arm.equals("observe"); }
    boolean capturing() { return !arm.equals("legacy"); }
    private Row<C> row(C container,String type,int x,int y,int z,int index,String sprite) {
        Row<C> row=new Row<>();row.identity=container;row.type=type;row.x=x;row.y=y;row.z=z;row.index=index;row.sprite=sprite;return row;
    }
    synchronized void automatic(C container,String type,int x,int y,int z,int index,String sprite,long now) {
        if (!capturing()) return;
        Row<C> row=identities.get(container);
        if (row==null) {
            if (ordered.size()==capacity) { overflow++;return; }
            // A selected watch becomes an automatic observation only on a real visit.
            // Reuse its row so an overlapping native fill keeps its timer and depth.
            row=watched.get(container);
            if (row==null) row=row(container,type,x,y,z,index,sprite);
            row.type=type;row.x=x;row.y=y;row.z=z;row.index=index;row.sprite=sprite;
            row.firstAuto=now;row.id=ordered.size()+1;
            identities.put(container,row);ordered.add(row);
        }
        row.visits++;
        automaticNext=observing()?container:null;automaticThread=observing()?Thread.currentThread():null;
    }
    /** Optional separately labelled selected target; it has no inherited automatic visits. */
    synchronized boolean watch(C container,String type,int x,int y,int z,int index,String sprite) {
        if (!capturing() || observing()) return false;
        if (watched.containsKey(container)) return true;
        if (watched.size() == watchLimit) return false;
        Row<C> selected = identities.get(container);
        watched.put(container, selected != null ? selected : row(container,type,x,y,z,index,sprite));
        return true;
    }
    private Row<C> known(C container) {
        Row<C> row=identities.get(container);return row!=null?row:watched.get(container);
    }
    private boolean automatic(C container,Thread thread) {
        if (automaticThread!=thread) return false;
        boolean result=automaticNext==container;automaticNext=null;automaticThread=null;return result;
    }
    private void enter(Row<C> row,long now,boolean authority,Thread thread,boolean automatic) {
        int depth=thread==row.owner?row.ownerDepth:row.otherDepths==null?0:row.otherDepths.getOrDefault(thread,0);
        if (depth>0) row.reentries++;
        else {
            if (row.depth>0) row.concurrent++;
            if (row.firstFill!=0) row.repeats++;
        }
        if (row.owner==null && depth==0) { row.owner=thread;row.ownerDepth=1; }
        else if (row.owner==thread) row.ownerDepth++;
        else {
            if (row.otherDepths==null) row.otherDepths=new IdentityHashMap<>();
            row.otherDepths.put(thread,depth+1);
        }
        row.depth++;
        if (row.firstFill==0) {
            row.firstFill=now;row.kind=automatic?"automatic":"demand";row.firstOwner=thread;
            row.firstThread=thread.getName();row.firstAuthority=authority;
        }
    }
    synchronized void enter(C container,long now) {
        if (!capturing()) return;
        Thread thread=Thread.currentThread();boolean automatic=automatic(container,thread);
        Row<C> row=known(container);if (row!=null) enter(row,now,true,thread,automatic);
    }
    /** Lookup precedes the clock, so unrelated fills allocate nothing and are not timed. */
    synchronized void nativeEnter(C container,boolean authority) {
        if (!capturing()) return;
        Thread thread=Thread.currentThread();boolean automatic=automatic(container,thread);
        Row<C> row=known(container);if (row!=null) enter(row,System.nanoTime(),authority,thread,automatic);
    }
    synchronized void suppressedReentry(C container) {
        if (!capturing()) return;
        Row<C> row=known(container);if (row!=null) row.reentries++;
    }
    private void exit(Row<C> row,long now,boolean failed,Thread thread) {
        int depth=thread==row.owner?row.ownerDepth:row.otherDepths==null?0:row.otherDepths.getOrDefault(thread,0);
        if (depth==0) return;
        if (row.elapsed<0 && thread==row.firstOwner) {
            if (failed) row.failed=true;
            if (depth==1) { row.elapsed=now-row.firstFill;row.firstOwner=null; }
        }
        if (thread==row.owner) {
            if (--row.ownerDepth==0) row.owner=null;
        } else if (depth==1) row.otherDepths.remove(thread);else row.otherDepths.put(thread,depth-1);
        row.depth--;
    }
    synchronized void exit(C container,long now,boolean failed) {
        if (!capturing()) return;
        Row<C> row=known(container);if (row!=null) exit(row,now,failed,Thread.currentThread());
    }
    synchronized void nativeExit(C container,boolean failed) {
        if (!capturing()) return;
        Row<C> row=known(container);if (row!=null) exit(row,System.nanoTime(),failed,Thread.currentThread());
    }
    private static String text(String value) {
        StringBuilder out=new StringBuilder("\"");
        for (int i=0;i<value.length();i++) {
            char c=value.charAt(i);
            if (c=='"') out.append("\"\"");
            else if (c>127 || c<32) { out.append("\\u");String h=Integer.toHexString(c);out.append("0".repeat(4-h.length())).append(h); }
            else out.append(c);
        }
        return out.append('"').toString();
    }
    synchronized String witness(C container) {
        Row<C> row=known(container);
        if (row==null) return "known=false\nidentity=0\norigin=unknown\n";
        return "known=true\nidentity="+row.id+"\norigin="+(row.id==0?"selected-watch":"automatic-visit")
            +"\nauto_visits="+row.visits+"\nselected_watch="+watched.containsKey(container)+"\nfirst_fill_thread="+text(row.firstThread)+"\nfirst_fill_authority_thread="+row.firstAuthority
            +"\nconcurrent_fills="+row.concurrent+"\nfill_kind="+row.kind+"\nfirst_fill_ns="+row.firstFill+"\nfill_ns="+row.elapsed
            +"\nfill_failed="+(row.failed?1:0)+"\nreentries="+row.reentries+"\nrepeat_fills="+row.repeats+"\nactive_depth="+row.depth+"\n";
    }
    synchronized String csv() {
        StringBuilder out=new StringBuilder("type,x,y,z,object_index,sprite,auto_visits,first_auto_ns,first_fill_ns,fill_kind,fill_ns,fill_failed,reentries,repeat_fills,active_depth\n");
        for (Row<C> r:ordered) out.append(text(r.type)).append(',').append(r.x).append(',').append(r.y).append(',').append(r.z).append(',').append(r.index).append(',')
            .append(text(r.sprite)).append(',').append(r.visits).append(',').append(r.firstAuto).append(',').append(r.firstFill).append(',').append(r.kind).append(',')
            .append(r.elapsed).append(',').append(r.failed?1:0).append(',').append(r.reentries).append(',').append(r.repeats).append(',').append(r.depth).append('\n');
        return out.toString();
    }
    synchronized String status() {
        int active=0;
        for (Row<C> r:watched.values()) if (r.id==0 && r.depth!=0) active++;
        for (Row<C> r:ordered) if(r.depth!=0) active++;
        return "schema=1\narm="+arm+"\ncapacity="+capacity+"\nobjects="+ordered.size()+"\noverflow="+overflow+"\nactive="+active+"\nwatched="+watched.size()+"\n";
    }
}
