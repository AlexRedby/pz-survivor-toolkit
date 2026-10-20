package net.alexredby.pztoolkitjavapatches;

public final class CartObserverPoseTest {
    private static void check(boolean yes,String message) {if(!yes) throw new AssertionError(message);}
    private static void near(double actual,double expected,double tolerance,String message) {
        check(Math.abs(actual-expected)<=tolerance,message+": "+actual+" vs "+expected);
    }
    private static CartObserverPose.Pose valid(CartObserverPose.State state,CartFootprint.Query query,
            double x,double y,double heading,double front) {
        var p=state.update(query,x,y,heading,front,1./60);
        check(p!=null,"bounded clear pose must exist: "+x+","+y+" heading="+heading+" front="+front);
        check(CartFootprint.clear(query,p.x(),p.y(),p.heading(),front),"accepted pose intersects obstacle");
        check(Math.hypot(p.x()-(float)x,p.y()-(float)y)<=CartObserverPose.MAX_OFFSET,"unbounded visual displacement");
        return p;
    }
    private static void historicalPrediction() {
        // Native Host left-wall captures: one position-dominated and one yaw-dominated overreach.
        for(double[] sample:new double[][]{{10832.752,10146.532,3.914688},{10832.313,10147.547,3.4634652}}) {
            CartFootprint.Query wall=(x1,y1,x2,y2)->Math.min(x1,x2)-.3<=10832;
            double heading=sample[2]-Math.PI/2;
            check(!CartFootprint.clear(wall,(float)sample[0],(float)sample[1],heading,CartFootprint.WALK_FRONT),
                "saved native pose must reproduce penetration");
            var state=new CartObserverPose.State();
            var p=valid(state,wall,sample[0],sample[1],heading,CartFootprint.WALK_FRONT);
            check(p.x()>sample[0],"left wall correction must move the complete actor away from wall");
            near(p.y(),(float)sample[1],.001,"wall correction must not add tangent movement");
            near(p.heading(),heading,1e-9,"initial overlap must preserve observed heading where translation suffices");
        }
    }
    private static void mirroredApproachAndRelease() {
        for(double origin:new double[]{0,8192,10825.5,16384}) for(int normal:new int[]{-1,1}) {
            CartFootprint.Query wall=(x1,y1,x2,y2)->Math.max(normal*(x1-origin),normal*(x2-origin))+.3>=2;
            var state=new CartObserverPose.State();double front=CartFootprint.WALK_FRONT;
            double heading=normal>0?Math.PI/4:3*Math.PI/4;
            CartObserverPose.Pose p=null;
            for(int frame=0;frame<90;frame++) {
                double x=origin+normal*(.5+frame*.009),y=origin+frame*.012;
                p=valid(state,wall,x,y,heading,front);
            }
            double x=origin+normal*1.301,y=origin+1.068;
            var contact=valid(state,wall,x,y,heading,front);
            for(int frame=0;frame<120;frame++) {
                p=valid(state,wall,x,y,heading,front);
                near(p.x(),contact.x(),.004,"stationary contact must not oscillate");
                near(p.y(),contact.y(),.004,"stationary contact must not drift sideways");
            }
            // Manual reverse makes room: retained cosmetic offset decays instead of snapping to zero.
            double lastOffset=Math.abs(p.x()-(float)x);
            check(lastOffset>.15,"test must exercise a material correction");
            for(int frame=1;frame<=180;frame++) {
                double retreat=x-normal*frame*.015;
                p=valid(state,wall,retreat,y,heading,front);
                double offset=Math.abs(p.x()-(float)retreat);
                check(offset<=lastOffset+.004,"release must decay monotonically within world-coordinate precision");
                check(lastOffset-offset<.065,"release must not discard correction in one frame");
                lastOffset=offset;
            }
            check(lastOffset<.005,"clearance correction must release after leaving wall");
        }
    }
    private static void cornersAndChanges() {
        for(int sx:new int[]{-1,1}) for(int sy:new int[]{-1,1}) {
            CartFootprint.Query corner=(x1,y1,x2,y2)->Math.max(sx*x1,sx*x2)+.3>=2 || Math.max(sy*y1,sy*y2)+.3>=2;
            double heading=Math.atan2(sy,sx);
            var state=new CartObserverPose.State();
            var p=valid(state,corner,sx*1.2,sy*1.2,heading,CartFootprint.WALK_FRONT);
            check(sx*p.x()<1.2 && sy*p.y()<1.2,"every corner quadrant needs joint outward correction");
        }
        boolean[] closed={false};
        CartFootprint.Query changed=(x1,y1,x2,y2)->closed[0] && Math.max(x1,x2)+.3>=2;
        var state=new CartObserverPose.State();
        valid(state,changed,1,0,0,CartFootprint.WALK_FRONT);
        closed[0]=true;
        valid(state,changed,1,0,0,CartFootprint.WALK_FRONT);
        valid(state,changed,1,0,0,CartFootprint.FAST_FRONT);
        state.clear();
        var raw=valid(state,(a,b,c,d)->false,1,0,0,CartFootprint.WALK_FRONT);
        near(raw.x(),1,0,"reset must discard previous item/connection correction");
        check(state.update((a,b,c,d)->true,1,0,0,CartFootprint.WALK_FRONT,.016)==null,
            "fully obstructed region must fail bounded, not teleport to distant clearance");
        raw=valid(state,(a,b,c,d)->false,40,50,1,CartFootprint.WALK_FRONT);
        near(raw.x(),40,0,"failed solve must not retain stale anchor");
        check(state.update(changed,Double.NaN,0,0,CartFootprint.WALK_FRONT,.016)==null,"invalid coordinate must clear state");
    }
    private static void releaseRateBound() {
        for(double origin:new double[]{0,10825.5}) for(double dt:new double[]{0,1./120,1./60,.049,.1,.25}) {
            CartFootprint.Query wall=(x1,y1,x2,y2)->Math.max(x1-origin,x2-origin)+.3>=2;
            var state=new CartObserverPose.State();double x=origin+1,y=origin;
            var p=valid(state,wall,x,y,0,CartFootprint.WALK_FRONT);
            double before=Math.hypot(p.x()-(float)x,p.y()-(float)y);
            for(int frame=0;frame<5;frame++) {
                // Native travel is unrestricted; limit only the independently retained visual offset.
                x+=.02;y+=.01;
                p=state.update((a,b,c,d)->false,x,y,0,CartFootprint.WALK_FRONT,dt);
                double after=Math.hypot(p.x()-(float)x,p.y()-(float)y);
                double tolerance=2*Math.hypot(Math.ulp((float)x),Math.ulp((float)y))+1e-6;
                check(before-after<=CartObserverPose.RELEASE_SPEED*Math.min(dt,.1)+tolerance,
                    "free visual correction released faster than cap at dt="+dt+" origin="+origin);
                check(after<=before+tolerance,"free release must not grow correction");
                before=after;
            }
        }
    }

    private static void nativePredictedActorOverlap() {
        CartFootprint.Query wall=(x1,y1,x2,y2)->Math.min(x1,x2)-.3<=10832;
        double[][] nativeFrames={{10832.345,10146.881,3.4556804},{10832.325,10146.906,3.4556746},
            {10832.296,10146.944,3.4556704},{10832.296,10146.969,3.455669},
            {10832.284,10147.002,3.455668},{10832.284,10147.033,3.4556675},
            {10832.291,10147.07,3.379479},{10832.309,10147.125,3.2449832},{10832.319,10147.181,3.1865268}};
        var state=new CartObserverPose.State();CartObserverPose.Pose previous=null;
        for(double[] frame:nativeFrames) {
            var p=valid(state,wall,frame[0],frame[1],frame[2]-Math.PI/2,CartFootprint.WALK_FRONT);
            if(previous!=null) check(Math.hypot(p.x()-previous.x(),p.y()-previous.y())<.16,
                "predicted actor-cap overlap must not drop the correction or jump back");
            previous=p;
        }
        // Joining with the actor already slightly inside the expanded cap must also recover locally.
        valid(new CartObserverPose.State(),wall,10832.284,10147.033,3.4556675-Math.PI/2,CartFootprint.WALK_FRONT);
        CartFootprint.Query finite=(x1,y1,x2,y2)->Math.min(x1,x2)<=.3 && Math.max(x1,x2)>=-.3;
        state.clear();valid(state,(a,b,c,d)->false,.31,0,0,CartFootprint.WALK_FRONT);
        var p=valid(state,finite,-.284,0,Math.PI,CartFootprint.WALK_FRONT);
        check(p.x()<-.3,"local recovery must discard an old anchor across a newly closed wall");
        check(new CartObserverPose.State().update(finite,0,0,0,CartFootprint.WALK_FRONT,.016)==null,
            "deep actor overlap has no justified same-side anchor and must fail bounded");
    }

    private static void rotatedContact() {
        for(double origin:new double[]{0,10825.5}) for(double angle:new double[]{Math.PI/6,Math.PI/4,-Math.PI/4}) {
            double nx=-Math.sin(angle),ny=Math.cos(angle);
            CartFootprint.Query contact=new CartFootprint.Query() {
                public boolean blocked(double x1,double y1,double x2,double y2) {
                    return Math.max((x1-origin)*nx+(y1-origin)*ny,(x2-origin)*nx+(y2-origin)*ny)+.3>=2;
                }
                public double tangent(int axis) {return axis<2?CartFootprint.Query.super.tangent(axis):angle+(axis-2)*Math.PI/2;}
            };
            for(double front:new double[]{CartFootprint.WALK_FRONT,CartFootprint.FAST_FRONT}) {
                var p=valid(new CartObserverPose.State(),contact,origin+nx*1.1,origin+ny*1.1,angle+Math.PI/2,front);
                check((p.x()-origin)*nx+(p.y()-origin)*ny<1.1,"rotated contact must correct along real hull normal");
            }
        }
    }
    private static void stationaryCostAndOpening() {
        int[] calls={0};boolean[] closed={true};
        CartFootprint.Query wall=(x1,y1,x2,y2)-> {calls[0]++;return closed[0] && Math.min(x1,x2)-.3<=10832;};
        var state=new CartObserverPose.State();double x=10832.752,y=10146.532,h=3.914688-Math.PI/2;
        var first=valid(state,wall,x,y,h,CartFootprint.WALK_FRONT);
        for(int i=0;i<30;i++) {
            calls[0]=0;var p=valid(state,wall,x,y,h,CartFootprint.WALK_FRONT);
            near(p.x(),first.x(),.004,"stationary revalidation retains contact");
            check(calls[0]<40,"stationary contact must not repeat full projection search: "+calls[0]);
        }
        closed[0]=false;CartObserverPose.Pose p=first;
        for(int i=0;i<90;i++) p=valid(state,wall,x,y,h,CartFootprint.WALK_FRONT);
        near(p.x(),(float)x,.005,"opening geometry releases an unchanged native pose");
    }
    private static void finiteWallCannotSwapSides() {
        CartFootprint.Query wall=(x1,y1,x2,y2)->Math.min(x1,x2)<=.3 && Math.max(x1,x2)>=-.3;
        var state=new CartObserverPose.State();
        check(state.update(wall,.31,0,Math.PI,CartFootprint.WALK_FRONT,1./60)==null,
            "bounded projection must not jump actor through a thin wall to its nearer clear side");
        var p=valid(state,wall,.7,0,Math.PI,CartFootprint.WALK_FRONT);
        check(p.x()>.7,"reachable-side correction must retreat on original side of finite wall");
        state.clear();
        valid(state,(a,b,c,d)->false,.31,0,0,CartFootprint.WALK_FRONT);
        p=valid(state,wall,-.31,0,Math.PI,CartFootprint.WALK_FRONT);
        near(p.x(),(float)-.31,0,"new obstacle must discard an old anchor across it, even within the offset limit");
    }
    private static void turningAndFreeMotion() {
        CartFootprint.Query wall=(x1,y1,x2,y2)->Math.max(x1,x2)+.3>=2;
        var state=new CartObserverPose.State();
        valid(state,wall,1.5,0,Math.PI/2,CartFootprint.WALK_FRONT);
        for(int frame=1;frame<=60;frame++)
            valid(state,wall,1.5,frame*.01,Math.PI/2-frame*.012,CartFootprint.WALK_FRONT);
        for(int frame=0;frame<120;frame++) {
            double x=-5+frame*.02,y=frame*.01,heading=CartSteeringMath.wrap(3+frame*.02);
            var p=valid(state,(a,b,c,d)->false,x,y,heading,CartFootprint.WALK_FRONT);
            near(p.x(),(float)x,0,"free native motion must stay unchanged");
            near(p.y(),(float)y,0,"free native motion must stay unchanged");
            near(p.heading(),heading,1e-9,"angle wrap must preserve native facing");
        }
    }
    public static void main(String[] args) {
        historicalPrediction();mirroredApproachAndRelease();cornersAndChanges();finiteWallCannotSwapSides();stationaryCostAndOpening();rotatedContact();nativePredictedActorOverlap();releaseRateBound();turningAndFreeMotion();
        System.out.println("CART_OBSERVER_POSE_PASS");
    }
}
