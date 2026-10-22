package net.alexredby.pztoolkitjavapatches;

/** Continuous forward-gait picker direction, independent of accepted cart movement. */
final class CartLocomotionBlend {
    static final int WALK=1,RUN=2,SPRINT=3;
    private static final double RESPONSE_SECONDS=.05;
    private double angle;
    private int gait;
    float x,y;

    void update(float targetX,float targetY,double seconds,int forwardGait) {
        x=targetX;y=targetY;
        double radius=Math.hypot(targetX,targetY);
        if(forwardGait<WALK || forwardGait>SPRINT || !Double.isFinite(radius)
            || radius<1e-6 || !(targetY>1e-6f)) {
            gait=0;
            return;
        }
        // Interpolate the direction, not the Cartesian coordinates: opposite steering
        // must pass through a full forward stride rather than a shorter idle blend.
        double target=Math.atan2(targetX,targetY);
        if(gait!=forwardGait) {angle=target;gait=forwardGait;return;}
        if(Double.isFinite(seconds) && seconds>0)
            angle+=(target-angle)*-Math.expm1(-Math.min(.1,seconds)/RESPONSE_SECONDS);
        // Both angles are in the forward half-plane; there is no wrapped/sign-flip path.
        x=(float)(radius*Math.sin(angle));y=(float)(radius*Math.cos(angle));
    }
}
