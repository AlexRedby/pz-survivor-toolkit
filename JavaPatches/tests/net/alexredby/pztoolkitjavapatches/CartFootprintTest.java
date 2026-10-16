package net.alexredby.pztoolkitjavapatches;

public final class CartFootprintTest {
    private static void check(boolean value,String message) {
        if(!value) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        CartFootprint.Query empty=(x1,y1,x2,y2)->false;
        double axle=CartSteeringMath.woodenAxle(0,0);
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
        System.out.println("CART_FOOTPRINT_PASS (native budget, wall/door contact, passage, swept turn, slide, promotion, rear caps)");
    }
}
