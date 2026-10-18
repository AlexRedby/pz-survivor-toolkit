package net.alexredby.pztoolkitjavapatches;

public final class CartFootprintTest {
    private static void check(boolean value,String message) {
        if(!value) throw new AssertionError(message);
    }

    private static void blockedProbeChecks(double axle) {
        float x=10825.5f,y=10142.5f;
        double front=CartFootprint.WALK_FRONT,nose=x+front-.21;
        boolean[] closed={true};
        int[] queries={0};
        CartFootprint.Query contact=(x1,y1,x2,y2)-> {
            queries[0]++;
            return closed[0] && Math.max(x1,x2)>=nose+.0003;
        };
        check(CartFootprint.clear(contact,x,y,0,front),"contact probe starts with a clear cart footprint");
        check(CartSteeringHooks.blockedProbe(contact,x,y,0,.03,0,axle,front),
            "less than two world-coordinate ULPs of permitted travel is a hard stop");
        check(CartSteeringHooks.blockedProbe(contact,x,y,0,.03,0,axle,front)
            && CartFootprint.clear(contact,x,y,0,front) && queries[0]>0,
            "repeated queries must retain the contact position without moving the cart");
        closed[0]=false;
        check(!CartSteeringHooks.blockedProbe(contact,x,y,0,.03,0,axle,front),
            "opening the obstacle must release the brace without an existing root budget");
        closed[0]=true;
        check(!CartSteeringHooks.blockedProbe(contact,x,y,0,-.03,0,axle,front),
            "a cart at wall contact can reverse away immediately");
        CartFootprint.Query partial=(x1,y1,x2,y2)->Math.max(x1,x2)>=nose+.012;
        double fraction=CartFootprint.limit(partial,x,y,0,.03,0,axle,front);
        check(fraction>0 && fraction<1 && !CartSteeringHooks.blockedProbe(partial,x,y,0,.03,0,axle,front),
            "partial representable travel must not settle a moving cart into idle");
        CartFootprint.Query parallel=(x1,y1,x2,y2)->Math.max(x1,x2)>=x+.121;
        check(!CartSteeringHooks.blockedProbe(parallel,x,y,Math.PI/2,0,.03,axle,front),
            "clear travel parallel to the wall must retain its native slide");
        CartFootprint.Query overlap=(x1,y1,x2,y2)->Math.max(x1,x2)>=nose-.01;
        check(!CartFootprint.clear(overlap,x,y,0,front),"escape probe starts in an overlapped footprint");
        check(CartSteeringHooks.blockedProbe(overlap,x,y,0,.03,0,axle,front)
            && CartSteeringHooks.blockedProbe(overlap,x,y,0,0,.03,axle,front),
            "an overlapped nose must not push forward or sweep sideways");
        check(!CartSteeringHooks.blockedProbe(overlap,x,y,0,-.03,0,axle,front),
            "an overlapped cart retains its existing backward escape");
    }

    public static void main(String[] args) {
        CartFootprint.Query empty=(x1,y1,x2,y2)->false;
        double axle=CartSteeringMath.woodenAxle(0,0);
        blockedProbeChecks(axle);
        for(double heading:new double[]{0,.3,Math.PI/2,Math.PI,-Math.PI/2}) {
            for(double dx:new double[]{-.2,0,.2}) for(double dy:new double[]{-.2,0,.2})
                check(CartFootprint.limit(empty,10825.5,10142.5,heading,dx,dy,axle,1.62)==1,
                    "clear world must retain the native movement budget");
        }
        CartFootprint.Query eastWall=(x1,y1,x2,y2)->Math.max(x1,x2)+.3>=2;
        for(double front:new double[]{CartFootprint.WALK_FRONT,CartFootprint.FAST_FRONT}) {
            double allowed=CartFootprint.limit(eastWall,0,0,0,1.5,0,axle,front);
            check(allowed>0 && allowed<1,"frontal wall must shorten a crossing step");
            check(1.5*allowed+front+.09<2 && 1.5*allowed+front+.09>1.99,
                "clip must stop at the checked front cap rather than freeze early");
            check(CartFootprint.clear(eastWall,1.5*allowed,0,0,front),"clipped footprint remains clear");
            check(CartFootprint.limit(eastWall,1.5*allowed,0,0,-.1,0,axle,front)==1,
                "a valid stopped cart can immediately reverse away");
        }
        check(CartFootprint.clear(eastWall,.5,0,0,CartFootprint.WALK_FRONT)
            && !CartFootprint.clear(eastWall,.5,0,0,CartFootprint.FAST_FRONT),
            "gait promotion needs its larger envelope even before root motion");
        CartFootprint.Query passage=(x1,y1,x2,y2)->Math.max(Math.abs(y1),Math.abs(y2))+.3>=.5;
        check(CartFootprint.limit(passage,0,0,0,2,0,axle,1.62)==1,
            "the conservative footprint still fits a centered one-tile passage");
        check(!CartFootprint.clear(passage,0,0,Math.PI/4,1.62),
            "a diagonal cart must not fit through a narrower opening");
        CartFootprint.Query sideWall=(x1,y1,x2,y2)->Math.max(y1,y2)+.3>=.46;
        var pivot=CartSteeringMath.stationaryStep(0,Math.PI/2,.5,.1,0,axle,1.6,new CartSteeringMath.Step());
        double turn=CartFootprint.limit(sideWall,0,0,0,pivot.x(),pivot.y(),axle,1.62);
        check(turn<1,"sideways nose sweep must clip a turn into the wall");
        double h=CartSteeringMath.acceptedTurn(0,axle,pivot.x()*turn,pivot.y()*turn);
        check(CartFootprint.clear(sideWall,pivot.x()*turn,pivot.y()*turn,h,1.62),
            "accepted clipped turn remains inside the clear envelope");
        double slide=CartFootprint.limit(eastWall,.648,0,0,0,-.1,axle,1.26);
        check(slide<1,"native wall sliding must recheck the resulting rolling yaw");
        boolean[] closed={true};
        CartFootprint.Query door=(x1,y1,x2,y2)->closed[0] && eastWall.blocked(x1,y1,x2,y2);
        check(CartFootprint.limit(door,0,0,0,1.5,0,axle,1.26)<1,"closed door blocks the cart");
        closed[0]=false;
        check(CartFootprint.limit(door,0,0,0,1.5,0,axle,1.26)==1,"opening the same door releases the cart");
        CartFootprint.Query rearOnly=(x1,y1,x2,y2)->Math.abs(y1)>.1;
        check(!CartFootprint.clear(rearOnly,0,0,0,1.26),"both rail starts must participate in validation");
        check(CartFootprint.limit(eastWall,1,0,0,.1,0,axle,1.26)==0,
            "ordinary forward clipping must not waive an existing overlap");
        for(double bad:new double[]{Double.NaN,Double.POSITIVE_INFINITY})
            check(CartFootprint.limit(empty,0,0,0,bad,0,axle,1.26)==0,"invalid movement fails closed");
        check(CartFootprint.limit(empty,0,0,0,100,0,axle,1.26)==0,"unbounded sweeps fail closed");
        CartFootprint.Query roundedWall=(x1,y1,x2,y2)->Math.max((float)x1,(float)x2)>=(float)(10828-.3);
        for(double[] example:new double[][]{
            {10826.4599609375,-.590038008344458,.10638530070086012,.09627626195628909},
            {10827.5673828125,1.562924403531673,-.0006353829521685839,.10575318336486816}}) {
            double x=example[0],y=10142.5,heading=example[1],dx=example[2],dy=example[3];
            for(int pass=0;pass<2;pass++) {
                double fraction=CartFootprint.limit(roundedWall,x,y,heading,dx,dy,axle,1.62);
                dx=(float)(x+dx*fraction)-x;dy=(float)(y+dy*fraction)-y;
                check(CartFootprint.clear(roundedWall,x+dx,y+dy,
                    heading+CartSteeringMath.acceptedTurn(heading,axle,dx,dy),1.62),
                    "rounded world coordinates and their resulting yaw must remain clear after each pass");
            }
        }
        for(double heading:new double[]{0,.3,Math.PI/2,Math.PI,-Math.PI/2})
            for(double dx:new double[]{-.2,0,.2}) for(double dy:new double[]{-.2,0,.2})
                for(double target:new double[]{heading,heading+Math.PI/2,heading-Math.PI})
                    check(CartFootprint.rigidLimit(empty,10825.5,10142.5,heading,dx,dy,target,1.62)==1,
                        "native rigid routes must retain independent displacement and facing in open space");
        check(CartFootprint.rigidLimit(sideWall,0,0,0,0,0,Math.PI/2,1.62)<1,
            "a pure native yaw must sweep its nose even with no root movement");
        double yaw=CartFootprint.rigidLimit(sideWall,0,0,0,0,0,Math.PI/2,1.62);
        check(CartFootprint.clear(sideWall,0,0,Math.PI/2*yaw,1.62),"clipped native yaw must retain a clear pose");
        check(CartFootprint.rigidLimit(eastWall,.648,0,0,0,-.1,0,1.26)==1,
            "native lateral displacement must not invent rolling yaw into a nearby wall");
        double rigidSlide=CartFootprint.rigidLimit(sideWall,0,0,0,0,1,0,1.62);
        check(rigidSlide>0 && rigidSlide<1,"actual native slide still needs a footprint translation sweep");
        for(double bad:new double[]{Double.NaN,Double.POSITIVE_INFINITY})
            check(CartFootprint.rigidLimit(empty,0,0,0,0,0,bad,1.26)==0,"invalid native yaw fails closed");
        System.out.println("CART_FOOTPRINT_PASS (native budget, wall/door contact, brace probes, passage, swept turn, slide, promotion, rear caps)");
    }
}
