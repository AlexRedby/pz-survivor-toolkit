package net.alexredby.drivingperf;

import java.util.ArrayList;
import java.util.List;

/** Pure geometry/coverage/verdict checks; no game instance, native physics or map load. */
public final class ApproachClearanceChecks {
    static void check(boolean value,String message) { if (!value) throw new AssertionError(message); }
    static void eq(double expected,double actual,String message) { check(Math.abs(expected-actual)<1e-8,message+": "+actual); }
    static ApproachClearance.Footprint rectangle(double x1,double y1,double x2,double y2) {
        return new ApproachClearance.Footprint(x1,y1,x2,y1,x2,y2,x1,y2);
    }
    static void rejects(Runnable action,String label) {
        boolean rejected=false; try { action.run(); } catch (IllegalArgumentException expected) { rejected=true; }
        check(rejected,label);
    }
    static ApproachClearance.VehicleSnapshot vehicle(long id,ApproachClearance.Footprint polygon) {
        return new ApproachClearance.VehicleSnapshot(id,-1,"Base.CarStationWagon2",0,polygon);
    }
    public static void main(String[] args) {
        check(ApproachClearance.northGround(0,-1,120,0,0),"Exact north on ground");
        check(ApproachClearance.northGround(0,-1,120,0,.2),"Suspension origin need not equal floor zero");
        check(ApproachClearance.northGround(0,-1,120,0,-.05),"Small suspension displacement below zero accepted");
        check(!ApproachClearance.northGround(0,1,120,0,0),"Reversed heading rejected");
        check(!ApproachClearance.northGround(1,0,120,0,0),"East heading rejected");
        check(!ApproachClearance.northGround(Math.sin(.001),-Math.cos(.001),120,0,0),"Small rotation exceeding lateral clearance budget rejected");
        check(ApproachClearance.northGround(Math.sin(.0004),-Math.cos(.0004),120,0,0),"Bounded .048 tile north mismatch accepted");
        check(!ApproachClearance.northGround(Math.sin(.0004),-Math.cos(.0004),500,0,0),"Heading tolerance tightens with requested distance");
        check(!ApproachClearance.northGround(0,-1,120,1,1),"Upper floor rejected");
        check(!ApproachClearance.northGround(0,-1,120,0,.501),"Out-of-ground actual origin rejected");
        check(!ApproachClearance.northGround(0,-1,120,0,-.501),"Out-of-ground negative origin rejected");
        check(!ApproachClearance.northGround(Double.NaN,-1,120,0,0),"Nonfinite heading rejected");
        check(!ApproachClearance.northGround(0,-1,120,0,Double.NaN),"Nonfinite ground origin rejected");
        check(!ApproachClearance.northGround(0,-.5,120,0,0),"Nonunit/steep forward vector rejected");
        check(!ApproachClearance.northGround(0,-1,0,0,0),"Unqualified distance rejected");
        var box=new ApproachClearance.Corridor(0,10,0,10);
        check(ApproachClearance.overlaps(rectangle(2,2,3,3),box),"Vehicle inside corridor");
        check(ApproachClearance.overlaps(rectangle(-1,-1,11,11),box),"Corridor inside vehicle");
        check(ApproachClearance.overlaps(rectangle(10,3,12,4),box),"Touching edge rejects candidate");
        check(ApproachClearance.overlaps(rectangle(10,10,11,11),box),"Touching corner rejects candidate");
        check(!ApproachClearance.overlaps(rectangle(10.001,3,12,4),box),"Separated edge clear");
        check(!ApproachClearance.overlaps(new ApproachClearance.Footprint(11,9.8,12.2,11,11,12.2,9.8,11),box),
                "Rotated bounding box false positive separated by polygon edge");
        check(ApproachClearance.overlaps(new ApproachClearance.Footprint(11,9,13,11,11,13,9,11),box),"Rotated corner touches");
        var reversed=new ApproachClearance.Footprint(2,2,2,3,3,3,3,2);
        check(ApproachClearance.overlaps(reversed,box),"Either winding accepted");
        rejects(() -> ApproachClearance.overlaps(new ApproachClearance.Footprint(0,0,1,1,0,1,1,0),box),"Bow-tie rejected");
        rejects(() -> ApproachClearance.overlaps(new ApproachClearance.Footprint(0,0,2,0,1,.5,0,2),box),"Concave polygon rejected");
        rejects(() -> ApproachClearance.overlaps(rectangle(0,0,0,1),box),"Degenerate polygon rejected");
        rejects(() -> ApproachClearance.overlaps(rectangle(0,0,Double.NaN,1),box),"NaN rejected");
        rejects(() -> ApproachClearance.overlaps(rectangle(0,0,Double.POSITIVE_INFINITY,1),box),"Infinity rejected");
        var size=ApproachClearance.dimensions(2,1,4,.3,0,.5,2);
        eq(1.3,size.halfWidth(),"Extents already in native physics units; model scale not applied again");
        eq(2.5,size.halfLength(),"COM offset conservatively included");
        check(ApproachClearance.northGroundWithinClearance(Math.sin(.0004),-Math.cos(.0004),120,0,.2,size),
                "Ordinary SportsCar dimensions retain position/course/corner clearance");
        var exaggerated=ApproachClearance.dimensions(32,1,32,16,0,16,1);
        check(ApproachClearance.northGround(Math.sin(.0049),-Math.cos(.0049),10,0,0),
                "Marginal pose fits old heading-only course budget");
        check(!ApproachClearance.northGroundWithinClearance(Math.sin(.0049),-Math.cos(.0049),10,0,0,exaggerated),
                "Exaggerated valid dimensions cannot rotate corners beyond remaining clearance");
        check(ApproachClearance.northGroundWithinClearance(0,-1,10,0,0,exaggerated),
                "Aligned large dimensions do not spend rotation clearance");
        check(ApproachClearance.northGroundWithinClearance(Math.sin(.0023),-Math.cos(.0023),10,0,0,exaggerated),
                "Large dimensions accepted while combined bound fits clearance");
        check(!ApproachClearance.northGroundWithinClearance(Math.sin(.003),-Math.cos(.003),10,0,0,exaggerated),
                "Combined bound rejects before individual course limit");
        check(!ApproachClearance.northGroundWithinClearance(0,-1,120,0,0,null),"Missing clearance dimensions rejected");
        check(ApproachClearance.receiptDimensions(size,1.3,2.5,.25),"Exact saved/current dimensions accepted");
        check(!ApproachClearance.receiptDimensions(size,1.31,2.5,.25),"Changed saved width rejected");
        check(!ApproachClearance.receiptDimensions(size,1.3,2.51,.25),"Changed saved length rejected");
        check(!ApproachClearance.receiptDimensions(size,1.3,2.5,.251),"Changed clearance rejected");
        check(!ApproachClearance.receiptDimensions(ApproachClearance.dimensions(2.01,1,4,.3,0,.5,2),1.3,2.5,.25),
                "Updated same-name script width rejected");
        check(!ApproachClearance.receiptDimensions(ApproachClearance.dimensions(2,1,4.01,.3,0,.5,2),1.3,2.5,.25),
                "Updated same-name script length rejected");
        check(!ApproachClearance.receiptDimensions(ApproachClearance.dimensions(2,1,4,.31,0,.5,2),1.3,2.5,.25),
                "Updated script center offset rejected");
        check(!ApproachClearance.receiptDimensions(null,1.3,2.5,.25),"Missing current dimensions rejected");
        check(!ApproachClearance.receiptDimensions(size,Double.NaN,2.5,.25),"Nonfinite saved width rejected");
        check(!ApproachClearance.receiptDimensions(size,1.3,Double.POSITIVE_INFINITY,.25),"Nonfinite saved length rejected");
        check(!ApproachClearance.receiptDimensions(size,1.3,2.5,Double.NaN),"Nonfinite saved clearance rejected");
        check(!ApproachClearance.receiptDimensions(size,0,2.5,.25),"Missing saved width rejected");
        check(!ApproachClearance.receiptDimensions(size,1.3,-2.5,.25),"Negative saved length rejected");
        check(!ApproachClearance.receiptDimensions(size,1.3,2.5,0),"Missing saved clearance rejected");
        var corridor=ApproachClearance.northCorridor(0,100,120,size,.25);
        eq(-1.55,corridor.minX(),"Width plus clearance");
        eq(-22.75,corridor.minY(),"Northward swept front");
        eq(102.75,corridor.maxY(),"Initial rear extent covered");
        rejects(() -> ApproachClearance.dimensions(-2,1,4,0,0,0,1),"Negative size rejected");
        rejects(() -> ApproachClearance.northCorridor(0,100,501,size,.25),"Unbounded corridor rejected");
        var complete=ApproachClearance.coverage(corridor,120,(x,y) -> true);
        check(complete.startReady() && complete.complete(),"Complete loaded corridor"); eq(120,complete.checkedDistance(),"Complete distance");
        var partial=ApproachClearance.coverage(corridor,120,(x,y) -> y>=40);
        check(partial.startReady() && !partial.complete(),"Unvisited tail remains partial");
        eq(57.25,partial.checkedDistance(),"Contiguous swept footprint coverage");
        var missingStart=ApproachClearance.coverage(corridor,120,(x,y) -> y!=100);
        check(!missingStart.startReady(),"Start footprint unknown");
        var hole=ApproachClearance.coverage(corridor,120,(x,y) -> y!=80);
        eq(16.25,hole.checkedDistance(),"Coverage stops at first hole despite loaded area beyond");
        var sideHole=ApproachClearance.coverage(corridor,120,(x,y) -> !(x==1 && y==80));
        eq(hole.checkedDistance(),sideHole.checkedDistance(),"Whole swept width required");
        rejects(() -> ApproachClearance.coverage(new ApproachClearance.Corridor(0,1,0,10),10,(x,y) -> true),
                "Coverage cannot omit the initial footprint");
        rejects(() -> ApproachClearance.assess(corridor,new ApproachClearance.Coverage(true,false,Double.NaN),List.of()),
                "Nonfinite coverage cannot produce clear_loaded");
        rejects(() -> ApproachClearance.assess(corridor,new ApproachClearance.Coverage(false,true,120),List.of()),
                "Contradictory coverage rejected");
        var clear=ApproachClearance.assess(corridor,partial,List.of());
        check(clear.status().equals("clear_loaded") && clear.reason().equals("unvisited_tail_unqualified"),"Partial prefix does not claim full route clear");
        var far=vehicle(12,rectangle(-.5,-5,.5,-3));
        var near=vehicle(13,rectangle(-.5,40,.5,42));
        var blocked=ApproachClearance.assess(corridor,partial,List.of(near,far));
        check(blocked.status().equals("blocked") && blocked.blockers().size()==2,"All loaded polygons across requested corridor, including beyond prefix");
        check(blocked.blockers().get(0).sqlId()==12 && blocked.blockers().get(1).sqlId()==13,"Deterministic blocker order");
        var reordered=ApproachClearance.assess(corridor,partial,List.of(far,near));
        check(blocked.blockers().equals(reordered.blockers()),"Input set order cannot alter verdict/log order");
        var malformed=vehicle(99,rectangle(200,200,200,201));
        check(ApproachClearance.assess(corridor,partial,List.of(malformed)).status().equals("unknown"),"Malformed remote geometry cannot become clear");
        check(ApproachClearance.assess(corridor,missingStart,List.of()).status().equals("unknown"),"Missing initial footprint unknown");
        check(ApproachClearance.assess(corridor,missingStart,List.of(far,malformed)).status().equals("blocked"),"Known blocker takes precedence over unknown");
        var nulls=new ArrayList<ApproachClearance.VehicleSnapshot>(); nulls.add(null);
        check(ApproachClearance.assess(corridor,complete,nulls).status().equals("unknown"),"Missing vehicle data rejected");
        var scriptBad=new ApproachClearance.VehicleSnapshot(2,3,"bad\nscript",0,rectangle(200,200,201,201));
        check(ApproachClearance.assess(corridor,complete,List.of(scriptBad)).status().equals("unknown"),"Malformed script cannot forge log lines");
        System.out.println("APPROACH_CLEARANCE_CHECKS_PASS geometry=true coverage=true verdicts=true native_game_methods_invoked=0");
    }
}
