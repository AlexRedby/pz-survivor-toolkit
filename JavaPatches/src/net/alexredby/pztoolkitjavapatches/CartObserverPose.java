package net.alexredby.pztoolkitjavapatches;

/** A bounded cosmetic actor/cart pose. Never writes native movement or network state. */
final class CartObserverPose {
    static final double MAX_OFFSET=.75, RELEASE_SECONDS=.12, ANCHOR_RECOVERY=.10;
    record Pose(double x,double y,double heading) {}
    private static Pose rounded(double x,double y,double heading) {
        return new Pose((float)x,(float)y,CartSteeringMath.wrap(heading));
    }
    private static boolean clear(CartFootprint.Query query,Pose p,double front) {
        return CartFootprint.clear(query,p.x,p.y,p.heading,front);
    }
    private static double distance(Pose a,Pose b) {return Math.hypot(a.x-b.x,a.y-b.y);}
    private static double cost(Pose a,Pose b,double front) {
        double yaw=CartSteeringMath.wrap(a.heading-b.heading)*front;
        return Math.pow(a.x-b.x,2)+Math.pow(a.y-b.y,2)+yaw*yaw;
    }

    private static double[] directions(CartFootprint.Query query,Pose raw,Pose previous) {
        double[] angles=new double[14];int count=0;
        for(int axis=0;axis<4;axis++) {
            double tangent=query.tangent(axis);
            if(Double.isFinite(tangent)) {
                angles[count++]=tangent+Math.PI/2;
                angles[count++]=tangent-Math.PI/2;
            }
        }
        if(previous!=null && distance(raw,previous)>1e-6)
            angles[count++]=Math.atan2(previous.y-raw.y,previous.x-raw.x);
        angles[count++]=raw.heading+Math.PI;
        for(int corner=0;corner<4;corner++) angles[count++]=Math.PI/4+corner*Math.PI/2;
        return java.util.Arrays.copyOf(angles,count);
    }

    /** Recover a slightly predicted-overlapping actor cap without crossing the physical wall core. */
    private static Pose anchor(CartFootprint.Query query,Pose raw) {
        if(!query.blocked(raw.x,raw.y,raw.x,raw.y)) return raw;
        // Both world/vehicle oracles inflate the actor by .3. A standable point within .1
        // puts the original point at least .2 from the solid obstacle: this short segment
        // cannot cross its core. Use this local side even when an old accepted pose exists.
        Pose best=null;double nearest=ANCHOR_RECOVERY;
        for(double angle:directions(query,raw,null)) {
            double dx=Math.cos(angle),dy=Math.sin(angle),low=0;
            for(int step=1;step<=5;step++) {
                double high=ANCHOR_RECOVERY*step/5;
                Pose candidate=rounded(raw.x+dx*high,raw.y+dy*high,raw.heading);
                if(distance(raw,candidate)>ANCHOR_RECOVERY) {
                    high-=2*Math.max(Math.ulp((float)raw.x),Math.ulp((float)raw.y));
                    candidate=rounded(raw.x+dx*high,raw.y+dy*high,raw.heading);
                }
                if(distance(raw,candidate)>ANCHOR_RECOVERY || query.blocked(candidate.x,candidate.y,candidate.x,candidate.y)) {
                    low=high;continue;
                }
                for(int i=0;i<10;i++) {
                    double mid=(low+high)/2;
                    var probe=rounded(raw.x+dx*mid,raw.y+dy*mid,raw.heading);
                    if(query.blocked(probe.x,probe.y,probe.x,probe.y)) low=mid;
                    else {high=mid;candidate=probe;}
                }
                if(distance(raw,candidate)<=nearest) {best=candidate;nearest=distance(raw,candidate);}
                break;
            }
        }
        return best;
    }

    /** Closest sampled outward ray, refined against the same native footprint oracle. */
    private static Pose project(CartFootprint.Query query,Pose raw,Pose previous,Pose anchor,double front) {
        if(clear(query,raw,front)) return raw;
        Pose best=null;
        double bestDistance=MAX_OFFSET+.001;
        // Keep every projection reachable from a clear anchor on the native actor's local side.
        double[] angles=directions(query,raw,previous);
        for(int direction=0;direction<angles.length;direction++) {
            double dx=Math.cos(angles[direction]),dy=Math.sin(angles[direction]);
            double low=0,high=0;Pose found=null;
            for(int step=1;step<=5;step++) {
                high=Math.min(bestDistance,MAX_OFFSET)*step/5;
                var candidate=rounded(raw.x+dx*high,raw.y+dy*high,raw.heading);
                // A diagonal .75 displacement can round outside the radius at map coordinates.
                if(distance(raw,candidate)>MAX_OFFSET) {
                    high-=2*Math.max(Math.ulp((float)raw.x),Math.ulp((float)raw.y));
                    candidate=rounded(raw.x+dx*high,raw.y+dy*high,raw.heading);
                }
                if(distance(raw,candidate)<=MAX_OFFSET && !query.blocked(anchor.x,anchor.y,candidate.x,candidate.y)
                    && clear(query,candidate,front)) {found=candidate;break;}
                low=high;
            }
            if(found==null) continue;
            for(int i=0;i<10;i++) {
                double mid=(low+high)/2;
                var candidate=rounded(raw.x+dx*mid,raw.y+dy*mid,raw.heading);
                if(!query.blocked(anchor.x,anchor.y,candidate.x,candidate.y) && clear(query,candidate,front)) {high=mid;found=candidate;} else low=mid;
            }
            // Leave a small subpixel margin so rounding does not toggle the contact every frame.
            var padded=rounded(raw.x+dx*(high+.003),raw.y+dy*(high+.003),raw.heading);
            if(distance(raw,padded)<=MAX_OFFSET && !query.blocked(anchor.x,anchor.y,padded.x,padded.y) && clear(query,padded,front)) found=padded;
            double d=distance(raw,found);
            if(d<bestDistance) {best=found;bestDistance=d;}
        }
        return best;
    }

    private static Pose step(CartFootprint.Query query,Pose from,Pose target,double front) {
        double fraction=CartFootprint.rigidLimit(query,from.x,from.y,from.heading,
            target.x-from.x,target.y-from.y,target.heading,front);
        var result=rounded(from.x+(target.x-from.x)*fraction,from.y+(target.y-from.y)*fraction,
            from.heading+CartSteeringMath.wrap(target.heading-from.heading)*fraction);
        return clear(query,result,front)?result:from;
    }

    static final class State {
        private Pose accepted,rawPrevious;
        void clear() {accepted=rawPrevious=null;}
        Pose update(CartFootprint.Query query,double x,double y,double heading,double front,double seconds) {
            if(query==null || !Double.isFinite(x+y+heading+front+seconds) || front<1 || front>2 || seconds<0) {
                clear();return null;
            }
            Pose raw=rounded(x,y,heading),previous=accepted;
            Pose anchor=anchor(query,raw);
            if(anchor==null) {clear();return null;}
            // A teleport, new geometry or larger gait envelope invalidates the old anchor.
            if(previous!=null && (distance(previous,raw)>MAX_OFFSET || query.blocked(anchor.x,anchor.y,previous.x,previous.y)
                || !CartObserverPose.clear(query,previous,front))) previous=null;
            Pose target;
            if(previous!=null && rawPrevious!=null) {
                double decay=Math.exp(-Math.min(seconds,.1)/RELEASE_SECONDS);
                target=rounded(raw.x+(previous.x-rawPrevious.x)*decay,
                    raw.y+(previous.y-rawPrevious.y)*decay,raw.heading);
                if(distance(raw,target)>MAX_OFFSET || !CartObserverPose.clear(query,target,front)) {
                    // Revalidated contact with unchanged native pose needs no repeated outward search.
                    target=raw.equals(rawPrevious)?previous:project(query,raw,previous,anchor,front);
                }
            } else target=project(query,raw,null,anchor,front);
            if(target==null) {clear();return null;}
            Pose result=target;
            if(previous!=null) {
                result=step(query,previous,target,front);
                if(cost(result,target,front)>1e-10) {
                    // Try both safe orders when rotation alone would push the long nose through a corner.
                    Pose translated=step(query,previous,rounded(target.x,target.y,previous.heading),front);
                    Pose translationFirst=step(query,translated,target,front);
                    Pose rotated=step(query,previous,rounded(previous.x,previous.y,target.heading),front);
                    Pose rotationFirst=step(query,rotated,target,front);
                    if(cost(translationFirst,target,front)<cost(result,target,front)) result=translationFirst;
                    if(cost(rotationFirst,target,front)<cost(result,target,front)) result=rotationFirst;
                }
            }
            if(distance(raw,result)>MAX_OFFSET || !CartObserverPose.clear(query,result,front)) {clear();return null;}
            accepted=result;rawPrevious=raw;return result;
        }
    }
    private CartObserverPose() {}
}
