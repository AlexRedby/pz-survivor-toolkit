package net.alexredby.pztoolkitjavapatches;

import zombie.pathfind.VehiclePoly;

public final class CartFootprintTest {
    private static void check(boolean value,String message) {
        if(!value) throw new AssertionError(message);
    }

    private static VehiclePoly hull(double angle,double length,double offset) {
        var p=new VehiclePoly();double tx=Math.cos(angle),ty=Math.sin(angle),nx=ty,ny=-tx;
        p.x1=(float)(-tx*length+nx*offset);p.y1=(float)(-ty*length+ny*offset);
        p.x2=(float)(tx*length+nx*offset);p.y2=(float)(ty*length+ny*offset);
        p.x3=(float)(tx*length+nx*(offset+2));p.y3=(float)(ty*length+ny*(offset+2));
        p.x4=(float)(-tx*length+nx*(offset+2));p.y4=(float)(-ty*length+ny*(offset+2));
        p.borders[0].set(p.x1,p.y1);p.borders[1].set(p.x2,p.y2);
        p.borders[2].set(p.x3,p.y3);p.borders[3].set(p.x4,p.y4);
        return p;
    }

    private static void vehicleChecks(double axle) {
        var p=hull(0,2,0);
        check(CartFootprint.vehicleBlocked(p,0,-1,0,-1),"stationary point inside a vehicle must collide");
        check(CartFootprint.vehicleBlocked(p,-1,-1,1,-1),"segment wholly inside a hull must collide");
        check(CartFootprint.vehicleBlocked(p,0,1,0,-3),"crossing a vehicle with both endpoints outside must collide");
        check(CartFootprint.vehicleBlocked(p,-3,.299,3,.299),"vehicle edge needs the full .3 rail radius");
        check(!CartFootprint.vehicleBlocked(p,-3,.301,3,.301),"vehicle clearance must not inflate beyond .3");
        check(!CartFootprint.vehicleBlocked(p,2.25,.25,2.25,.25),"vehicle corner uses a round cap, not an oversized box");
        check(CartFootprint.vehicleBlocked(p,2.2,.2,2.2,.2),"stationary point near a hull corner must collide");
        for(double angle:new double[]{Math.PI/6,Math.PI/4,-Math.PI/4}) for(double origin:new double[]{0,8192,10825.5,16384}) {
            var poly=hull(angle,50,0);
            poly.x1+=origin;poly.x2+=origin;poly.x3+=origin;poly.x4+=origin;
            poly.y1+=origin;poly.y2+=origin;poly.y3+=origin;poly.y4+=origin;
            poly.borders[0].set(poly.x1,poly.y1);poly.borders[1].set(poly.x2,poly.y2);
            poly.borders[2].set(poly.x3,poly.y3);poly.borders[3].set(poly.x4,poly.y4);
            CartFootprint.Query vehicle=new CartFootprint.Query() {
                public boolean blocked(double x1,double y1,double x2,double y2) {
                    return CartFootprint.vehicleBlocked(poly,x1,y1,x2,y2);
                }
                public double tangent(int axis) {return axis<2?CartFootprint.Query.super.tangent(axis):angle+(axis-2)*Math.PI/2;}
            };
            double nx=Math.sin(angle),ny=-Math.cos(angle),x=(float)(origin-.345*nx),y=(float)(origin-.345*ny),heading=angle;
            boolean slid=false;
            for(int step=0;step<120;step++) {
                double dx=.08*Math.signum(nx),dy=0;
                double fraction=CartFootprint.limit(vehicle,x,y,heading,dx,dy,axle,CartFootprint.FAST_FRONT);
                var slide=CartFootprint.slide(vehicle,x,y,heading,dx,dy,CartFootprint.FAST_FRONT,fraction,-.025,.025);
                if(slide==null) {
                    dx=(float)(x+dx*fraction)-x;dy=(float)(y+dy*fraction)-y;
                    double allowed=CartFootprint.limit(vehicle,x,y,heading,dx,dy,axle,CartFootprint.FAST_FRONT);
                    dx=(float)(x+dx*allowed)-x;dy=(float)(y+dy*allowed)-y;
                    double turn=CartSteeringMath.acceptedTurn(heading,axle,dx,dy);
                    check(Math.hypot(dx,dy)>0 && CartFootprint.rigidLimit(vehicle,x,y,heading,dx,dy,heading+turn,CartFootprint.FAST_FRONT)==1,
                        "the preferred rolling fallback must still make safe representable progress");
                    x+=dx;y+=dy;heading=CartSteeringMath.wrap(heading+turn);continue;
                }
                slid=true;
                check(Math.abs(CartSteeringMath.wrap(slide.target()-angle))<1e-12,
                    "world-coordinate rounding must not change the retained hull tangent");
                check(Math.abs(slide.normalX()-nx)<1e-6 && Math.abs(slide.normalY()-ny)<1e-6,
                    "the contact guide must retain the real vehicle normal, not a tile axis");
                check(Math.abs(slide.x()*nx+slide.y()*ny)<Math.max(1e-5,2*Math.ulp((float)x)),"vehicle slide must reject inward travel within world precision");
                check(CartFootprint.rigidLimit(vehicle,x,y,heading,slide.x(),slide.y(),heading+slide.turn(),CartFootprint.FAST_FRONT)==1,
                    "every committed vehicle slide must pass the float-rounded swept envelope: angle="+angle+" step="+step+" x="+x+" y="+y+" heading="+heading+" slide="+slide);
                x+=slide.x();y+=slide.y();heading=CartSteeringMath.wrap(heading+slide.turn());
            }
            check(slid,"axis-aligned input must exercise sliding along every tested vehicle yaw and world origin");
            check(CartFootprint.followWall(vehicle,x,y,heading,0,angle,nx,ny,CartFootprint.FAST_FRONT)==(nx>0),
                "vehicle guidance must retain only input pressing into the contacted side");
        }
    }

    private static void blockedProbeChecks(double axle) {
        float x=10825.5f,y=10142.5f;
        double front=CartFootprint.WALK_FRONT,nose=x+front-.28;
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
        CartFootprint.Query parallel=(x1,y1,x2,y2)->Math.max(x1,x2)>=x+.041;
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
            check(1.5*allowed+front+.02<2 && 1.5*allowed+front+.02>1.99,
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
        CartFootprint.Query sideWall=(x1,y1,x2,y2)->Math.max(y1,y2)+.3>=.345;
        var pivot=CartSteeringMath.stationaryStep(0,Math.PI/2,.5,.1,0,axle,1.6,new CartSteeringMath.Step());
        double turnFraction=CartFootprint.limit(sideWall,0,0,0,pivot.x(),pivot.y(),axle,1.62);
        check(turnFraction<1,"sideways nose sweep must clip a turn into the wall");
        double h=CartSteeringMath.acceptedTurn(0,axle,pivot.x()*turnFraction,pivot.y()*turnFraction);
        check(CartFootprint.clear(sideWall,pivot.x()*turnFraction,pivot.y()*turnFraction,h,1.62),
            "accepted clipped turn remains inside the clear envelope");
        double slideFraction=CartFootprint.limit(eastWall,1.65,0,Math.PI/2,.1,0,axle,1.26);
        check(slideFraction<1,"native wall sliding must recheck the resulting rolling yaw");
        boolean[] closed={true};
        CartFootprint.Query door=(x1,y1,x2,y2)->closed[0] && eastWall.blocked(x1,y1,x2,y2);
        check(CartFootprint.limit(door,0,0,0,1.5,0,axle,1.26)<1,"closed door blocks the cart");
        closed[0]=false;
        check(CartFootprint.limit(door,0,0,0,1.5,0,axle,1.26)==1,"opening the same door releases the cart");
        CartFootprint.Query rearOnly=(x1,y1,x2,y2)->Math.abs(y1)>.03;
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
        for(double sign:new double[]{-1,1}) for(double front:new double[]{CartFootprint.WALK_FRONT,CartFootprint.FAST_FRONT}) {
            double x=(float)(2-front-.022),dx=.08,dy=.04*sign;
            double fraction=CartFootprint.limit(eastWall,x,0,0,dx,dy,axle,front);
            var slide=CartFootprint.slide(eastWall,x,0,0,dx,dy,front,fraction,-.025,.025);
            check(slide!=null && slide.x()==0 && Math.abs(slide.y()-dy)<1e-8,
                "wall contact must preserve the full available tangent: "+sign+"/"+front+" fraction="+fraction+" slide="+slide);
            check(slide.turn()*sign>0 && Math.abs(slide.turn())<=.025,
                "contact should guide the cart toward the wall tangent within its turn-rate budget");
            check(CartFootprint.rigidLimit(eastWall,x,0,0,slide.x(),slide.y(),slide.turn(),front)==1,
                "the deflected translation and yaw must retain a fully swept clear envelope");
            CartFootprint.Query corner=(x1,y1,x2,y2)->eastWall.blocked(x1,y1,x2,y2)
                || Math.max(y1*sign,y2*sign)+.3>=.342;
            var blocked=CartFootprint.slide(corner,x,0,0,dx,dy,front,0,-.025,.025);
            check(blocked==null || Math.abs(blocked.y())<Math.abs(dy),"a second wall must stop the tangent too");
            check(CartFootprint.slide(empty,x,0,0,dx,dy,front,1,-.025,.025)==null,
                "unobstructed rolling must retain its original path and yaw");
            check(CartFootprint.slide(eastWall,x,0,0,dx,0,front,0,-.025,.025)==null,
                "head-on intent must not invent a sideways escape");
        }
        // Repeat at native world precision: each wall-guided step must commit its checked float XY and yaw.
        for(double sign:new double[]{-1,1}) {
            double x=10826,y=10142.5,heading=sign*.6;
            CartFootprint.Query wall=(x1,y1,x2,y2)->Math.max(x1,x2)+.3>=10828;
            boolean slid=false;
            for(int step=0;step<240;step++) {
                double dx=.04,dy=.02*sign;
                double fraction=CartFootprint.limit(wall,x,y,heading,dx,dy,axle,1.62);
                var slide=CartFootprint.slide(wall,x,y,heading,dx,dy,1.62,fraction,-.025,.025);
                double turn;
                if(slide==null) {
                    dx=(float)(x+dx*fraction)-x;dy=(float)(y+dy*fraction)-y;
                    turn=CartSteeringMath.acceptedTurn(heading,axle,dx,dy);
                } else {dx=slide.x();dy=slide.y();turn=slide.turn();slid=true;}
                check(CartFootprint.rigidLimit(wall,x,y,heading,dx,dy,heading+turn,1.62)==1,
                    "repeated rounded wall slides must retain a fully checked sweep");
                x+=dx;y+=dy;heading=CartSteeringMath.wrap(heading+turn);
            }
            check(slid,"native-coordinate contact must actually exercise the deflection path");
        }
        double heading=Math.PI/4,dt=1.0/60,previousRate=-.5,front=CartFootprint.FAST_FRONT;
        double wallX=Math.cos(heading)*(front-.28)+.301;
        CartFootprint.Query closeWall=(x1,y1,x2,y2)->Math.max(x1,x2)+.3>=wallX;
        var approach=CartSteeringMath.woodenStep(heading,0,.02,dt,0,axle,previousRate,new CartSteeringMath.Step());
        double fraction=CartFootprint.limit(closeWall,0,0,heading,approach.x(),approach.y(),axle,front);
        var redirected=CartFootprint.slide(closeWall,0,0,heading,approach.x(),approach.y(),front,fraction,
            (previousRate-6*dt)*dt,(previousRate+6*dt)*dt);
        check(redirected==null || redirected.turn()==0 || Math.abs(redirected.turn()/dt-previousRate)<=6*dt+1e-9,
            "wall guidance must brake an incoming turn before reversing its angular velocity");
        check(redirected==null || CartFootprint.rigidLimit(closeWall,0,0,heading,redirected.x(),redirected.y(),
            heading+redirected.turn(),front)==1,"angular braking must not bypass the swept tangent checks");
        double parallelX=(float)1.65;
        check(CartFootprint.followWall(eastWall,parallelX,0,Math.PI/2,Math.PI/4,Math.PI/2,1,0,front),
            "diagonal pressure into a nearby wall must retain the contact tangent");
        check(!CartFootprint.followWall(empty,parallelX,0,Math.PI/2,Math.PI/4,Math.PI/2,1,0,front),
            "a wall guide must end when the obstacle ends");
        for(double target:new double[]{Math.PI*3/4,-Math.PI/4,Math.PI/2})
            check(!CartFootprint.followWall(eastWall,parallelX,0,Math.PI/2,target,Math.PI/2,1,0,front),
                "away, opposite and wall-parallel input must release the contact-only guide");
        vehicleChecks(axle);
        System.out.println("CART_FOOTPRINT_PASS (native budget, wall/door/vehicle contact, brace probes, passage, swept turn, slide, promotion, rear caps)");
    }
}
