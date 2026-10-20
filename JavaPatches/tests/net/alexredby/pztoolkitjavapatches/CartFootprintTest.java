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

    private static void effortContactChecks(double axle) {
        for(float origin:new float[]{8192f,10825.5f}) {
            float x=origin,y=10142.5f;double front=CartFootprint.WALK_FRONT,nose=x+front-.28;
            boolean[] closed={true};
            CartFootprint.Query wall=(x1,y1,x2,y2)->closed[0] && Math.max(x1,x2)>=nose+.0003;
            for(int frame=0;frame<240;frame++) {
                double accepted=frame%2==0?0:Math.ulp(x);
                check(CartSteeringHooks.braceContact(wall,x,y,0,.03,0,axle,front,accepted,true),
                    "continuous forward contact must keep effort through zero/one-ULP accepted jitter");
            }
            closed[0]=false;
            check(!CartSteeringHooks.braceContact(wall,x,y,0,.03,0,axle,front,0,true),
                "opening the obstacle releases effort even with a static zero-root stance");
            closed[0]=true;
            check(!CartSteeringHooks.braceContact(wall,x,y,0,.03,0,axle,front,.012,true),
                "real accepted tangent/partial travel must not enter a stationary effort pose");
            check(!CartSteeringHooks.braceContact(wall,x,y,0,-.03,0,axle,front,0,false)
                && !CartSteeringHooks.braceContact(wall,x,y,0,.03,0,axle,front,0,false),
                "reverse, released input, braking and stationary-turn gates release forward effort");
            check(!CartSteeringHooks.braceContact(wall,x,y,0,.03,0,axle,front,Double.NaN,true),
                "invalid accepted distance cannot invent contact effort");
            var tiny=CartSteeringMath.step(0,0,Math.ulp(x),1./60,0);
            check(!CartSteeringHooks.blockedStep(tiny,x,y,0),
                "cosmetic contact tolerance must not redefine an accepted one-ULP physical step as blocked");
        }
    }

    private static void relativeReverseContactChecks(double axle) {
        double dt=1.0/60,front=CartFootprint.WALK_FRONT;
        for(double origin:new double[]{0,8192,10825.5,16384}) for(int normal:new int[]{-1,1})
            for(int side:new int[]{-1,1}) for(boolean released:new boolean[]{false,true}) {
                double localHeading=side*(released?1.7:1.575);
                double heading=normal>0?localHeading:Math.PI-localHeading;
                int yaw=normal*side;
                double x=(float)(origin+normal*1.6599903106689453),y=(float)origin;
                CartFootprint.Query wall=(x1,y1,x2,y2)->
                    Math.max(normal*(x1-origin),normal*(x2-origin))+.3>=2;
                // Start at the nearest representable clear position without waiving the envelope.
                for(int retreat=0;!CartFootprint.clear(wall,x,y,heading,front) && retreat<4;retreat++)
                    x=Math.nextAfter((float)x,normal>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY);
                String context=origin+"/"+normal+"/"+side+"/released="+released;
                check(CartFootprint.clear(wall,x,y,heading,front),"reverse contact must start clear: "+context);
                double target=heading+Math.PI+(released?0:yaw*Math.PI/4);
                var requested=CartSteeringMath.woodenStep(heading,target,.02,dt,0,axle,0,true,new CartSteeringMath.Step());
                double fraction=CartFootprint.limit(wall,x,y,heading,requested.x(),requested.y(),axle,front);
                check(fraction<1,"reverse contact regression must exercise the blocked path: "+context);
                var slide=CartFootprint.steeredSlide(wall,x,y,heading,requested.x(),requested.y(),front,fraction,released?0:requested.turn());
                check(slide!=null && Math.hypot(slide.x(),slide.y())>.01,
                    "relative contact must retain clear manual reverse progress: "+context);
                check(released?slide.turn()==0:slide.turn()*yaw>=0 && Math.abs(slide.turn())<=Math.abs(requested.turn())+1e-12,
                    "relative contact must not introduce opposite or released yaw: "+context+" slide="+slide);
                check(CartFootprint.rigidLimit(wall,x,y,heading,slide.x(),slide.y(),heading+slide.turn(),front)==1,
                    "relative reverse correction must retain native-coordinate swept clearance: "+context);
                check(Math.abs(slide.x())<1e-9,
                    "relative contact must remove inward travel instead of inventing an automatic escape: "+context);
            }
    }

    private static void relativeBlockedTurnContactChecks(double axle) {
        double dt=1.0/60,front=CartFootprint.FAST_FRONT;
        for(double origin:new double[]{0,8192,10825.5,16384}) for(int normal:new int[]{-1,1})
            for(int side:new int[]{-1,1}) {
                double localHeading=side*.7,heading=normal>0?localHeading:Math.PI-localHeading;
                int yaw=-normal*side;
                double contact=2-.3-(front-.28)*Math.cos(localHeading)-.00001;
                double x=(float)(origin+normal*contact),y=(float)origin;
                CartFootprint.Query wall=(x1,y1,x2,y2)->
                    Math.max(normal*(x1-origin),normal*(x2-origin))+.3>=2;
                for(int retreat=0;!CartFootprint.clear(wall,x,y,heading,front) && retreat<4;retreat++)
                    x=Math.nextAfter((float)x,normal>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY);
                String context=origin+"/"+normal+"/"+side;
                check(CartFootprint.clear(wall,x,y,heading,front),"blocked-turn contact must start clear: "+context);
                var requested=CartSteeringMath.woodenStep(heading,heading+yaw*Math.PI/4,.02,dt,0,axle,0,false,
                    new CartSteeringMath.Step());
                double fraction=CartFootprint.rigidLimit(wall,x,y,heading,requested.x(),requested.y(),
                    heading+requested.turn(),front);
                check(fraction<1,"blocked-turn regression must contact the wall: "+context);
                check(CartFootprint.rigidLimit(wall,x,y,heading,0,requested.y(),heading,front)==1,
                    "straight tangent must remain clear when the requested yaw is blocked: "+context);
                var slide=CartFootprint.steeredSlide(wall,x,y,heading,requested.x(),requested.y(),front,fraction,requested.turn());
                check(slide!=null && Math.abs(slide.y())>.01,
                    "collision-blocked yaw must not discard clear tangent progress: "+context+" slide="+slide);
                check(slide.turn()*yaw>=0 && Math.abs(slide.turn())<=Math.abs(requested.turn())+1e-12,
                    "blocked yaw may stop but must not reverse steering: "+context);
                check(CartFootprint.rigidLimit(wall,x,y,heading,slide.x(),slide.y(),heading+slide.turn(),front)==1,
                    "blocked-yaw fallback must retain its complete swept clearance: "+context);
            }
    }

    private static void relativeWallGuideChecks() {
        for(double origin:new double[]{8192,10825.5,16384}) for(int normal:new int[]{-1,1})
            for(int direction:new int[]{-1,1}) {
                double x=(float)(origin+normal*1.6),y=(float)origin,tangent=direction*Math.PI/2;
                double near=tangent-normal*direction*.04,away=tangent+normal*direction*.04;
                CartFootprint.Query wall=(x1,y1,x2,y2)->
                    Math.max(normal*(x1-origin),normal*(x2-origin))+.3>=2;
                CartFootprint.Query empty=(x1,y1,x2,y2)->false;
                String context=origin+"/"+normal+"/"+direction;
                for(double heading:new double[]{near,tangent,away})
                    check(CartFootprint.clear(wall,x,y,heading,CartFootprint.FAST_FRONT),
                        "relative guide regression must retain a clear cart envelope: "+context);
                check(CartFootprint.followWall(wall,x,y,near,near,tangent,normal,0,CartFootprint.FAST_FRONT,true),
                    "relative contact must finish aligning from within the old pressure cutoff: "+context);
                check(CartFootprint.followWall(wall,x,y,tangent,tangent,tangent,normal,0,CartFootprint.FAST_FRONT,true),
                    "relative tangent contact must retain its established guide: "+context);
                check(!CartFootprint.followWall(wall,x,y,away,away,tangent,normal,0,CartFootprint.FAST_FRONT,true),
                    "relative outward intent must release wall guidance immediately: "+context);
                check(!CartFootprint.followWall(empty,x,y,near,near,tangent,normal,0,CartFootprint.FAST_FRONT,true)
                    && !CartFootprint.followWall(empty,x,y,tangent,tangent,tangent,normal,0,CartFootprint.FAST_FRONT,true),
                    "relative guidance must end when the wall ends: "+context);
                check(!CartFootprint.followWall(wall,x-normal,y,near,near,tangent,normal,0,CartFootprint.FAST_FRONT,true),
                    "relative guidance must end after leaving wall contact: "+context);
                check(!CartFootprint.followWall(wall,x,y,near,near,tangent,normal,0,CartFootprint.FAST_FRONT)
                    && !CartFootprint.followWall(wall,x,y,tangent,tangent,tangent,normal,0,CartFootprint.FAST_FRONT),
                    "absolute guidance must preserve its existing pressure threshold: "+context);
                double pressing=tangent-normal*direction*.08;
                check(CartFootprint.followWall(wall,x,y,tangent,pressing,tangent,normal,0,CartFootprint.FAST_FRONT),
                    "absolute guidance must still accept pressure above its established cutoff: "+context);
            }
    }

    private record WallWalk(int contactFrames,int acquisitions,int releases,int sideFlips,double progress,double heading) {}

    /** Exercise the relative Forward feedback loop, rather than only a single slide or guide predicate. */
    private static WallWalk relativeWallWalk(double axle,int normal,int direction,double distance) {
        double origin=10825.5,y=10142.5,front=CartFootprint.WALK_FRONT,dt=1.0/60;
        double heading=normal>0?direction*.6:Math.PI-direction*.6;
        double tangent=direction*Math.PI/2;
        double x=(float)(origin+normal*(1.7-(front-.28)*Math.cos(.6)-.00001));
        CartFootprint.Query wall=(x1,y1,x2,y2)->
            Math.max(normal*(x1-origin),normal*(x2-origin))+.3>=2;
        for(int retreat=0;!CartFootprint.clear(wall,x,y,heading,front) && retreat<4;retreat++)
            x=Math.nextAfter((float)x,normal>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY);
        String context=normal+"/"+direction+"/"+distance;
        check(CartFootprint.clear(wall,x,y,heading,front),"relative wall Walk must start clear: "+context);
        double startY=y,wallHeading=Double.NaN,wallRate=0;
        int contactFrames=0,acquisitions=0,releases=0,sideFlips=0,previousSide=0;
        for(int frame=0;frame<600;frame++) {
            boolean hadGuide=Double.isFinite(wallHeading);
            // Forward with released steering follows accepted yaw, while contact alignment keeps its own rate.
            double target=heading;
            boolean guided=hadGuide && CartFootprint.followWall(wall,x,y,heading,target,wallHeading,normal,0,front,true);
            if(hadGuide && !guided) releases++;
            if(!guided) wallHeading=Double.NaN;
            var requested=CartSteeringMath.woodenStep(heading,guided?wallHeading:target,distance,dt,0,axle,
                guided?wallRate:0,false,new CartSteeringMath.Step());
            double dx=(float)requested.x(),dy=(float)requested.y(),turn=requested.turn();
            if(guided) {
                double inward=Math.max(0,dx*normal),rounding=Math.ulp((float)x);
                var contact=CartFootprint.contactStep(wall,x,y,heading,dx,dy,turn,normal,0,front);
                check(contact!=null,"established relative contact must return a checked step: "+context+" frame="+frame);
                dx=contact.x();dy=contact.y();turn=contact.turn();contactFrames++;
                check(dx*normal<=inward+rounding && dx*normal>=-rounding,
                    "contact alignment may accept requested inward travel but must not invent advance or automatic backoff: "+context+" frame="+frame);
            } else {
                double fraction=CartFootprint.rigidLimit(wall,x,y,heading,dx,dy,heading+turn,front);
                var slide=CartFootprint.steeredSlide(wall,x,y,heading,dx,dy,front,fraction,turn);
                if(slide==null) {dx*=fraction;dy*=fraction;turn*=fraction;}
                else {
                    dx=slide.x();dy=slide.y();turn=slide.turn();
                    if(CartFootprint.pressingWall(target,slide.target(),slide.normalX(),slide.normalY())) {
                        wallHeading=slide.target();acquisitions++;
                    }
                }
            }
            // Native commits root XY as floats before the post-update yaw and gait hooks run.
            double actualX=(float)(x+dx)-x,actualY=(float)(y+dy)-y;
            double planned=dx*dx+dy*dy;
            turn*=planned>0?Math.max(0,Math.min(1,(actualX*dx+actualY*dy)/planned)):0;
            double allowed=CartFootprint.rigidLimit(wall,x,y,heading,actualX,actualY,heading+turn,front);
            actualX=(float)(x+actualX*allowed)-x;actualY=(float)(y+actualY*allowed)-y;turn*=allowed;
            check(CartFootprint.rigidLimit(wall,x,y,heading,actualX,actualY,heading+turn,front)==1,
                "every relative wall Walk step needs float-coordinate swept clearance: "+context+" frame="+frame);
            check(turn*normal*direction>=-1e-12,"relative contact alignment must not reverse yaw: "+context+" frame="+frame);
            x+=actualX;y+=actualY;heading=CartSteeringMath.wrap(heading+turn);
            wallRate=Double.isFinite(wallHeading)?turn/dt:0;
            double length=Math.hypot(actualX,actualY);
            if(length>1e-6) {
                double stepX=.8*(-actualX*Math.sin(heading)+actualY*Math.cos(heading))/length;
                // One world-coordinate ULP can perturb an almost-forward gait; catch the large opposite Strafe changes.
                int side=Math.abs(stepX)>.1?(stepX>0?1:-1):0;
                if(side!=0) {if(previousSide!=0 && side!=previousSide) sideFlips++;previousSide=side;}
            }
        }
        return new WallWalk(contactFrames,acquisitions,releases,sideFlips,(y-startY)*direction,
            Math.abs(CartSteeringMath.wrap(tangent-heading)));
    }

    private static void relativeWallWalkChecks(double axle) {
        for(int normal:new int[]{-1,1}) for(int direction:new int[]{-1,1}) for(double distance:new double[]{.02,.023}) {
            String context=normal+"/"+direction+"/"+distance;
            var walk=relativeWallWalk(axle,normal,direction,distance);
            System.out.println("CART_WALL_WALK "+context+" "+walk);
            check(walk.contactFrames()>20 && walk.progress()>2,"relative wall Walk must exercise sustained moving contact: "+context+" "+walk);
            // As yaw accelerates, handle rotation can overtake tangent translation and cross local sideways zero once.
            // Repeated reversals are the shaking regression, rather than that single geometric crossover.
            check(walk.sideFlips()<=1,"relative wall Walk must not repeatedly reverse native Strafe directions: "+context+" "+walk);
            check(walk.acquisitions()==1 && walk.releases()==0,
                "relative wall Walk must retain the same straight-wall contact throughout alignment: "+context+" "+walk);
            check(walk.heading()<.01,"relative wall Walk must finish its gradual tangent alignment: "+context+" "+walk);
        }
    }

    private static void contactRoundingChecks(double axle) {
        double originX=10825.5,originY=10142.5,front=CartFootprint.WALK_FRONT,dt=1.0/60;
        for(double angle:new double[]{-.7,-.3,.3,.7,2.4}) {
            double nx=-Math.sin(angle),ny=Math.cos(angle),tx=Math.cos(angle),ty=Math.sin(angle);
            double offset=1.7-(front-.28)*Math.sin(.6)-.0001;
            double x=(float)(originX+offset*nx),y=(float)(originY+offset*ny),heading=angle+.6,rate=0;
            CartFootprint.Query wall=(x1,y1,x2,y2)->Math.max((x1-originX)*nx+(y1-originY)*ny,
                (x2-originX)*nx+(y2-originY)*ny)+.3>=2;
            for(int retreat=0;!CartFootprint.clear(wall,x,y,heading,front) && retreat<4;retreat++) {
                x=Math.nextAfter((float)x,nx>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY);
                y=Math.nextAfter((float)y,ny>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY);
            }
            check(CartFootprint.clear(wall,x,y,heading,front),"diagonal contact must start clear: "+angle);
            for(int frame=0;frame<120;frame++) {
                var request=CartSteeringMath.woodenStep(heading,angle,.02,dt,0,axle,rate,false,new CartSteeringMath.Step());
                var contact=CartFootprint.contactStep(wall,x,y,heading,request.x(),request.y(),request.turn(),nx,ny,front);
                double rounding=Math.ulp((float)x)+Math.ulp((float)y);
                double inward=Math.max(0,request.x()*nx+request.y()*ny);
                check(contact!=null && Double.isFinite(contact.x()+contact.y()+contact.turn()),
                    "diagonal contact must return finite movement: "+angle+" frame="+frame);
                check(contact.x()*nx+contact.y()*ny<=inward+rounding && contact.x()*nx+contact.y()*ny>=-rounding,
                    "diagonal rounding must not invent inward progress or automatic backoff: "+angle+" frame="+frame);
                check(Math.abs((contact.x()-request.x())*tx+(contact.y()-request.y())*ty)<=rounding,
                    "diagonal contact must preserve its full tangent within native coordinate precision: "+angle+" frame="+frame);
                check(CartFootprint.rigidLimit(wall,x,y,heading,contact.x(),contact.y(),heading+contact.turn(),front)==1,
                    "diagonal contact must retain the complete rounded swept clearance: "+angle+" frame="+frame);
                x+=contact.x();y+=contact.y();heading=CartSteeringMath.wrap(heading+contact.turn());rate=contact.turn()/dt;
            }
        }
    }

    private static void contactCornerChecks(double axle) {
        double originX=10825.5,originY=10142.5,dt=1.0/60;
        for(double front:new double[]{CartFootprint.WALK_FRONT,CartFootprint.FAST_FRONT})
            for(int normal:new int[]{-1,1}) for(int direction:new int[]{-1,1}) {
                double heading=normal>0?direction*.7:Math.PI-direction*.7,tangent=direction*Math.PI/2;
                double x=(float)(originX+normal*(1.7-(front-.28)*Math.cos(.7)-.0001)),y=(float)originY;
                var request=CartSteeringMath.woodenStep(heading,tangent,.02,dt,0,axle,0,false,new CartSteeringMath.Step());
                double along=(float)(y+request.y())-y;
                // The established wall stays beside the cart; a second wall blocks only the yaw sweep at its nose.
                double ceiling=(front-.28)*Math.sin(.7)+along*direction+.3+.0002;
                CartFootprint.Query corner=(x1,y1,x2,y2)->
                    Math.max(normal*(x1-originX),normal*(x2-originX))+.3>=2
                    || Math.max(direction*(y1-originY),direction*(y2-originY))+.3>=ceiling;
                for(int retreat=0;!CartFootprint.clear(corner,x,y,heading,front) && retreat<4;retreat++)
                    x=Math.nextAfter((float)x,normal>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY);
                String context=front+"/"+normal+"/"+direction;
                check(CartFootprint.clear(corner,x,y,heading,front),"corner contact must start clear: "+context);
                check(CartFootprint.followWall(corner,x,y,heading,heading,tangent,normal,0,front,true),
                    "corner fallback must start with a valid established Forward wall guide: "+context);
                check(CartFootprint.rigidLimit(corner,x,y,heading,0,along,heading,front)==1,
                    "corner must leave the full tangent clear without yaw: "+context);
                check(CartFootprint.rigidLimit(corner,x,y,heading,0,along,heading+request.turn(),front)<1,
                    "corner regression must exercise the yaw-blocked fallback: "+context);
                var contact=CartFootprint.contactStep(corner,x,y,heading,request.x(),request.y(),request.turn(),normal,0,front);
                check(contact!=null && contact.turn()==0 && Math.abs(contact.y()-along)<=Math.ulp((float)y),
                    "blocked yaw must preserve clear tangent travel: "+context+" "+contact);
                check(contact.x()==0,"corner fallback must not invent inward travel or automatic reverse: "+context);
                check(CartFootprint.rigidLimit(corner,x,y,heading,contact.x(),contact.y(),heading,front)==1,
                    "corner fallback must retain the complete swept clearance: "+context);
            }
    }

    public static void main(String[] args) {
        CartFootprint.Query empty=(x1,y1,x2,y2)->false;
        double axle=CartSteeringMath.woodenAxle(0,0);
        blockedProbeChecks(axle);
        effortContactChecks(axle);
        relativeReverseContactChecks(axle);
        relativeBlockedTurnContactChecks(axle);
        relativeWallGuideChecks();
        relativeWallWalkChecks(axle);
        contactRoundingChecks(axle);
        contactCornerChecks(axle);
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
