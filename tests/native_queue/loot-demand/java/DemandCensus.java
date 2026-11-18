package net.alexredby.lootdemand;

import java.util.ArrayList;
import java.util.IdentityHashMap;

/** Test-only authority ledger, bounded and exported only on explicit demand.
 * CSV schema 1: one row per identity first seen at an eligible automatic visit.
 * first_auto_ns/first_fill_ns are JVM-local System.nanoTime timestamps, not durations;
 * fill_ns is first outer native-fill elapsed time, -1 until that fill completes.
 * fill_kind is none, automatic (observe visit immediately preceding fill), or demand.
 * Recursive actual fills are included in the first outer interval and counted separately.
 * overflow counts unrecorded eligible visits, not distinct omitted objects.
 * Sprite/type text uses ordinary CSV quotes; non-ASCII chars become literal \\uXXXX.
 */
final class DemandCensus<C> {
    private static final class Row<C> {
        C identity; String type,sprite,kind="none";
        int x,y,z,index,depth; long firstAuto,firstFill,elapsed=-1,visits,reentries,repeats;
        boolean failed;
    }
    private final String arm;
    private final int capacity;
    private final IdentityHashMap<C,Row<C>> identities=new IdentityHashMap<>();
    private final ArrayList<Row<C>> ordered=new ArrayList<>();
    private long overflow;
    private C automaticNext;
    DemandCensus(String arm,int capacity) {
        if (!arm.equals("legacy") && !arm.equals("observe") && !arm.equals("defer")) throw new IllegalArgumentException("Unknown census arm");
        if (capacity<1) throw new IllegalArgumentException("Census capacity");
        this.arm=arm;this.capacity=capacity;
    }
    boolean observing() { return arm.equals("observe"); }
    boolean capturing() { return !arm.equals("legacy"); }
    void automatic(C container,String type,int x,int y,int z,int index,String sprite,long now) {
        if (!capturing()) return;
        Row<C> row=identities.get(container);
        if (row==null) {
            if (ordered.size()==capacity) { overflow++;return; }
            row=new Row<>();row.identity=container;row.type=type;row.x=x;row.y=y;row.z=z;row.index=index;row.sprite=sprite;row.firstAuto=now;
            identities.put(container,row);ordered.add(row);
        }
        row.visits++;
        // checkObject/doOverlaySprite call fill immediately after shouldDefer returns false.
        automaticNext=observing()?container:null;
    }
    void enter(C container,long now) {
        if (!capturing()) return;
        boolean automatic=automaticNext==container;automaticNext=null;
        Row<C> row=identities.get(container);if (row==null) return;
        if (row.depth++>0) { row.reentries++;return; }
        if (row.firstFill!=0) { row.repeats++;return; }
        row.firstFill=now;row.kind=automatic?"automatic":"demand";
    }
    void suppressedReentry(C container) {
        if (!capturing()) return;
        Row<C> row=identities.get(container);if (row!=null) row.reentries++;
    }
    void exit(C container,long now,boolean failed) {
        if (!capturing()) return;
        Row<C> row=identities.get(container);if (row==null || row.depth==0) return;
        // Preserve nested failures even if a native caller catches the exception.
        if (row.elapsed<0 && failed) row.failed=true;
        if (--row.depth==0 && row.elapsed<0) row.elapsed=now-row.firstFill;
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
    String csv() {
        StringBuilder out=new StringBuilder("type,x,y,z,object_index,sprite,auto_visits,first_auto_ns,first_fill_ns,fill_kind,fill_ns,fill_failed,reentries,repeat_fills,active_depth\n");
        for (Row<C> r:ordered) out.append(text(r.type)).append(',').append(r.x).append(',').append(r.y).append(',').append(r.z).append(',').append(r.index).append(',')
            .append(text(r.sprite)).append(',').append(r.visits).append(',').append(r.firstAuto).append(',').append(r.firstFill).append(',').append(r.kind).append(',')
            .append(r.elapsed).append(',').append(r.failed?1:0).append(',').append(r.reentries).append(',').append(r.repeats).append(',').append(r.depth).append('\n');
        return out.toString();
    }
    String status() {
        int active=0;for (Row<C> r:ordered) if(r.depth!=0) active++;
        return "schema=1\narm="+arm+"\ncapacity="+capacity+"\nobjects="+ordered.size()+"\noverflow="+overflow+"\nactive="+active+"\n";
    }
}
