package net.alexredby.pztoolkitjavapatches;

import zombie.characters.IsoPlayer;
import zombie.pathfind.PolygonalMap2;

/** Conservative wooden-cart envelope; the native world remains the obstacle oracle. */
final class CartFootprint {
    // shortcut: original wooden mesh/rigs and +/-7deg bank; recalibrate if the mesh or authored pose changes.
    static final double WALK_FRONT=1.26, FAST_FRONT=1.62;
    // Native wall queries already add radius .3; only the tilted body needs extra width.
    private static final double RAIL=.04, NOSE_INSET=.28, TAPER=.30;

    @FunctionalInterface
    interface Query { boolean blocked(double x1,double y1,double x2,double y2); }

    static Query world(IsoPlayer player) {
        return (x1,y1,x2,y2)-> {
            var map=PolygonalMap2.instance;
            int z=(int)Math.floor(player.getZ());
            // The line query checks only its destination. Validate the rear cap as well.
            if(!map.canStandAt((float)x1,(float)y1,z,player,false,false)) return true;
            if(x1==x2 && y1==y2) return false;
            // Short overloads ignore doors; the explicit zero mask includes them.
            return map.lineClearCollide((float)x1,(float)y1,(float)x2,(float)y2,z,player,PolygonalMap2.LCC_ZERO);
        };
    }

    static boolean clear(Query query,double x,double y,double heading,double front) {
        double cos=Math.cos(heading),sin=Math.sin(heading),length=front-NOSE_INSET;
        // shortcut: calibrated tile walls/doors; the native vehicle sweep has a narrower side margin.
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

    record Slide(double x,double y,double turn,double target) {}

    /** Deflect along a clear tile axis and face along it, within the existing turn-rate budget. */
    static Slide slide(Query query,double x,double y,double heading,double dx,double dy,
                       double front,double fraction,double minTurn,double maxTurn) {
        if(dx==0 || dy==0 || fraction>=1 || !Double.isFinite(dx+dy+minTurn+maxTurn) || minTurn>maxTurn) return null;
        double best=(dx*dx+dy*dy)*fraction;
        Slide result=null;
        for(int axis=0;axis<2;axis++) {
            double sx=axis==0?dx:0,sy=axis==1?dy:0;
            double target=Math.atan2(sy,sx);
            if(dx*Math.cos(heading)+dy*Math.sin(heading)<0) target+=Math.PI;
            double turn=Math.max(minTurn,Math.min(maxTurn,CartSteeringMath.wrap(target-heading)));
            double allowed=rigidLimit(query,x,y,heading,sx,sy,heading+turn,front);
            double acceptedTurn=turn*allowed;
            if(acceptedTurn<minTurn || acceptedTurn>maxTurn) {
                // Contact can stop angular motion while the clear tangent keeps moving.
                allowed=rigidLimit(query,x,y,heading,sx,sy,heading,front);acceptedTurn=0;
            }
            sx=(float)(x+sx*allowed)-x;sy=(float)(y+sy*allowed)-y;
            double progress=sx*dx+sy*dy;
            if(progress>best+1e-12) {best=progress;result=new Slide(sx,sy,acceptedTurn,target);}
        }
        return result;
    }

    private CartFootprint() {}
}
