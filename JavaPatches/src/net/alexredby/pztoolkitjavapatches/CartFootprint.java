package net.alexredby.pztoolkitjavapatches;

import zombie.characters.IsoPlayer;
import zombie.pathfind.PolygonalMap2;
import zombie.pathfind.VehiclePoly;
import java.awt.geom.Line2D;
import java.util.ArrayList;

/** Conservative wooden-cart envelope; the native world remains the obstacle oracle. */
final class CartFootprint {
    // shortcut: original wooden mesh/rigs and +/-7deg bank; recalibrate if the mesh or authored pose changes.
    static final double WALK_FRONT=1.26, FAST_FRONT=1.62;
    // Native wall queries already add radius .3; only the tilted body needs extra width.
    private static final double RAIL=.04, NOSE_INSET=.28, TAPER=.30;

    @FunctionalInterface
    interface Query {
        boolean blocked(double x1,double y1,double x2,double y2);
        default double tangent(int axis) { return axis<2?axis*Math.PI/2:Double.NaN; }
    }

    static Query world(IsoPlayer player) {
        int z=(int)Math.floor(player.getZ());
        var vehicles=new ArrayList<VehiclePoly>();
        for(var vehicle:player.getCell().getVehicles())
            if(vehicle.addedToWorld && vehicle.getScript()!=null && Math.floor(vehicle.getZ())==z)
                vehicles.add(vehicle.getPoly());
        return new Query() {
            private VehiclePoly contact;
            public double tangent(int axis) {
                if(axis<2) return Query.super.tangent(axis);
                if(contact==null) return Double.NaN;
                return axis==2?Math.atan2(contact.y2-contact.y1,contact.x2-contact.x1)
                    :Math.atan2(contact.y3-contact.y2,contact.x3-contact.x2);
            }
            public boolean blocked(double x1,double y1,double x2,double y2) {
                // Native vehicle queries use .15 rather than the wall query's .3 radius.
                for(var poly:vehicles) if(vehicleBlocked(poly,x1,y1,x2,y2)) {contact=poly;return true;}
                var map=PolygonalMap2.instance;
                // The line query checks only its destination. Validate the rear cap as well.
                if(!map.canStandAt((float)x1,(float)y1,z,player,false,false)) return true;
                if(x1==x2 && y1==y2) return false;
                // Short overloads ignore doors; the explicit zero mask includes them.
                return map.lineClearCollide((float)x1,(float)y1,(float)x2,(float)y2,z,player,PolygonalMap2.LCC_ZERO);
            }
        };
    }

    static boolean vehicleBlocked(VehiclePoly p,double x1,double y1,double x2,double y2) {
        if(Math.max(x1,x2)+.3<Math.min(Math.min(p.x1,p.x2),Math.min(p.x3,p.x4))
            || Math.min(x1,x2)-.3>Math.max(Math.max(p.x1,p.x2),Math.max(p.x3,p.x4))
            || Math.max(y1,y2)+.3<Math.min(Math.min(p.y1,p.y2),Math.min(p.y3,p.y4))
            || Math.min(y1,y2)-.3>Math.max(Math.max(p.y1,p.y2),Math.max(p.y3,p.y4))) return false;
        return p.containsPoint((float)x1,(float)y1) || p.containsPoint((float)x2,(float)y2)
            || near(x1,y1,x2,y2,p.x1,p.y1,p.x2,p.y2) || near(x1,y1,x2,y2,p.x2,p.y2,p.x3,p.y3)
            || near(x1,y1,x2,y2,p.x3,p.y3,p.x4,p.y4) || near(x1,y1,x2,y2,p.x4,p.y4,p.x1,p.y1);
    }

    private static boolean near(double ax,double ay,double bx,double by,double cx,double cy,double dx,double dy) {
        return Line2D.linesIntersect(ax,ay,bx,by,cx,cy,dx,dy)
            || Line2D.ptSegDistSq(ax,ay,bx,by,cx,cy)<=.09 || Line2D.ptSegDistSq(ax,ay,bx,by,dx,dy)<=.09
            || Line2D.ptSegDistSq(cx,cy,dx,dy,ax,ay)<=.09 || Line2D.ptSegDistSq(cx,cy,dx,dy,bx,by)<=.09;
    }

    static boolean clear(Query query,double x,double y,double heading,double front) {
        double cos=Math.cos(heading),sin=Math.sin(heading),length=front-NOSE_INSET;
        for(int side=-1;side<=1;side+=2) {
            double rearX=x-sin*side*RAIL,rearY=y+cos*side*RAIL;
            double shoulderX=rearX+cos*(length-TAPER),shoulderY=rearY+sin*(length-TAPER);
            if(query.blocked(rearX,rearY,shoulderX,shoulderY)
                || query.blocked(shoulderX,shoulderY,x+cos*length,y+sin*length)) return false;
        }
        return true;
    }

    private static boolean sweep(Query query,double x,double y,double heading,double dx,double dy,
                                 double axle,double front,double from,double to,double turn,boolean rolling) {
        double ax=(float)(x+dx*from),ay=(float)(y+dy*from);
        double bx=(float)(x+dx*to),by=(float)(y+dy*to);
        // Native position rounding can change rolling yaw; verify the coordinates we will actually commit.
        double a=heading+(rolling?CartSteeringMath.acceptedTurn(heading,axle,ax-x,ay-y):turn*from);
        double b=heading+(rolling?CartSteeringMath.acceptedTurn(heading,axle,bx-x,by-y):turn*to);
        if(!clear(query,bx,by,b,front)) return false;
        for(int side=-1;side<=1;side+=2) for(int end=0;end<=2;end++) {
            double length=end==0?0:front-NOSE_INSET-(end==1?TAPER:0),offset=end==2?0:side*RAIL;
            double x1=ax+Math.cos(a)*length-Math.sin(a)*offset;
            double y1=ay+Math.sin(a)*length+Math.cos(a)*offset;
            double x2=bx+Math.cos(b)*length-Math.sin(b)*offset;
            double y2=by+Math.sin(b)*length+Math.cos(b)*offset;
            if(query.blocked(x1,y1,x2,y2)) return false;
        }
        return true;
    }

    /** Shorten only the supplied displacement, using its actual rolling yaw after native sliding. */
    static double limit(Query query,double x,double y,double heading,double dx,double dy,double axle,double front) {
        return limit(query,x,y,heading,dx,dy,axle,front,CartSteeringMath.acceptedTurn(heading,axle,dx,dy),true);
    }

    /** Native routes own displacement and facing independently, including turns without root motion. */
    static double rigidLimit(Query query,double x,double y,double heading,double dx,double dy,double target,double front) {
        return limit(query,x,y,heading,dx,dy,0,front,CartSteeringMath.wrap(target-heading),false);
    }

    private static double limit(Query query,double x,double y,double heading,double dx,double dy,
                                double axle,double front,double turn,boolean rolling) {
        double distance=Math.hypot(dx,dy);
        if(!Double.isFinite(x+y+distance+turn+heading+front) || rolling && !(axle>0)) return 0;
        if(!clear(query,x,y,heading,front)) return 0;
        if(distance==0 && turn==0) return 1;
        int steps=Math.max(1,(int)Math.ceil((distance+Math.abs(turn)*front)/.04));
        if(steps>(rolling?128:256)) return 0;
        double previous=0;
        for(int step=1;step<=steps;step++) {
            double next=step/(double)steps;
            if(!sweep(query,x,y,heading,dx,dy,axle,front,previous,next,turn,rolling)) {
                double low=previous,high=next;
                for(int i=0;i<12;i++) {
                    double mid=(low+high)/2;
                    if(sweep(query,x,y,heading,dx,dy,axle,front,previous,mid,turn,rolling)) low=mid;
                    else high=mid;
                }
                return low;
            }
            previous=next;
        }
        return 1;
    }

    static boolean pressingWall(double target,double tangent,double normalX,double normalY) {
        return Math.cos(target)*normalX+Math.sin(target)*normalY>.05 && Math.cos(target-tangent)>.1;
    }

    static boolean followWall(Query query,double x,double y,double heading,double target,
                              double tangent,double normalX,double normalY,double front) {
        return pressingWall(target,tangent,normalX,normalY)
            && rigidLimit(query,x,y,heading,normalX*.25,normalY*.25,heading,front)<1;
    }

    record Slide(double x,double y,double turn,double target,double normalX,double normalY) {}

    /** Deflect along a clear wall/vehicle edge, within the existing turn-rate budget. */
    static Slide slide(Query query,double x,double y,double heading,double dx,double dy,
                       double front,double fraction,double minTurn,double maxTurn) {
        if(fraction>=1 || !Double.isFinite(dx+dy+minTurn+maxTurn) || minTurn>maxTurn) return null;
        double best=(dx*dx+dy*dy)*fraction;
        Slide result=null;
        double vehicleAxis0=query.tangent(2),vehicleAxis1=query.tangent(3);
        for(int axis=0;axis<4;axis++) {
            double angle=axis<2?query.tangent(axis):axis==2?vehicleAxis0:vehicleAxis1;
            if(!Double.isFinite(angle)) continue;
            double tx=axis==0?1:axis==1?0:Math.cos(angle),ty=axis==0?0:axis==1?1:Math.sin(angle);
            double along=dx*tx+dy*ty,normal=-dx*ty+dy*tx;
            if(Math.abs(along)<1e-12 || Math.abs(normal)<1e-12) continue;
            double sx=tx*along,sy=ty*along;
            double nx=-ty*Math.signum(normal),ny=tx*Math.signum(normal);
            double target=Math.atan2(sy,sx);
            if(dx*Math.cos(heading)+dy*Math.sin(heading)<0) target+=Math.PI;
            sx=(float)(x+sx)-x;sy=(float)(y+sy)-y;
            // Nearest rounding otherwise creeps a diagonal tangent into the hull each frame.
            if(sx*nx+sy*ny>1e-12) {
                double outwardX=Math.nextAfter((float)(x+sx),nx>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY)-x;
                double outwardY=Math.nextAfter((float)(y+sy),ny>0?Double.NEGATIVE_INFINITY:Double.POSITIVE_INFINITY)-y;
                if(Math.abs((outwardX-sx)*nx)>=Math.abs((outwardY-sy)*ny)) sx=outwardX;
                else sy=outwardY;
            }
            double turn=Math.max(minTurn,Math.min(maxTurn,CartSteeringMath.wrap(target-heading)));
            double allowed=rigidLimit(query,x,y,heading,sx,sy,heading+turn,front);
            double acceptedTurn=turn*allowed;
            if(acceptedTurn<minTurn || acceptedTurn>maxTurn) {
                // Contact can stop angular motion while the clear tangent keeps moving.
                allowed=rigidLimit(query,x,y,heading,sx,sy,heading,front);acceptedTurn=0;
            }
            sx=(float)(x+sx*allowed)-x;sy=(float)(y+sy*allowed)-y;
            if(rigidLimit(query,x,y,heading,sx,sy,heading+acceptedTurn,front)<1) continue;
            double progress=sx*dx+sy*dy;
            if(progress>best+1e-12) {
                best=progress;result=new Slide(sx,sy,acceptedTurn,target,nx,ny);
            }
        }
        return result;
    }

    private CartFootprint() {}
}
