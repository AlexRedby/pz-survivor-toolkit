package net.alexredby.pztoolkitjavapatches;

/** Shopping-cart axle pivot and rolling wheelbarrow arc; native collision stays authoritative. */
public final class CartSteeringMath {
    // shortcut: selected models use an approximate axle offset; recalibrate when their geometry changes.
    static final double AXLE_DISTANCE = 0.8;

    public static final class Step {
        private double x, y, turn, travel;
        public double x() { return x; }
        public double y() { return y; }
        public double turn() { return turn; }
        public double travel() { return travel; }
        private Step set(double x, double y, double turn, double travel) {
            this.x = x; this.y = y; this.turn = turn; this.travel = travel;
            return this;
        }
    }

    static final class Bank {
        double angle, velocity, pressure, pressureVelocity;

        double update(double target, double seconds) {
            if (!(seconds > 0)) return angle;
            // Critical damping starts and releases hand pressure without a first-frame angular jerk.
            double frequency = 1 / .085;
            double offset = angle - target;
            double rate = velocity + frequency * offset;
            double decay = Math.exp(-frequency * seconds);
            angle = target + (offset + rate * seconds) * decay;
            velocity = (velocity - frequency * rate * seconds) * decay;
            // Retain clearance through a bank reversal without rectifying raw coordinate noise.
            double magnitude = Math.abs(angle);
            offset = pressure - magnitude;
            rate = pressureVelocity + frequency * offset;
            pressure = magnitude + (offset + rate * seconds) * decay;
            pressureVelocity = (pressureVelocity - frequency * rate * seconds) * decay;
            return angle;
        }
    }

    static final class Reversal {
        int direction=1, requested;
        boolean active, braking;
        double neutral;

        boolean request(int intent, boolean atRest) {
            requested=intent;
            if(intent==0) { active=braking=false;neutral=0;return false; }
            if(!active && atRest) { direction=intent;return false; }
            if(intent!=direction && !braking) {
                active=braking=true;neutral=0;return true;
            }
            if(intent==direction && braking) { braking=false;neutral=0; }
            return false;
        }

        void stopped(double seconds, boolean rootStopped, boolean actualStopped) {
            if(!active || !braking) return;
            if(!rootStopped || !actualStopped) { neutral=0;return; }
            neutral+=Math.max(0,Math.min(.1,seconds));
            // The native picker must evaluate its Idle center before the travel sign changes.
            if(neutral>=.08) { direction=requested;braking=false;neutral=0; }
        }
    }

    public static double wrap(double angle) {
        return Math.atan2(Math.sin(angle), Math.cos(angle));
    }

    static double keyboardTarget(double heading, int travel, int steering) {
        return heading+(travel<0?Math.PI:0)
            +steering*(travel<0?-1:1)*(travel==0?Math.PI/2:Math.PI/4);
    }

    static boolean reversing(double heading, double target) {
        return Math.abs(wrap(target-heading))>Math.PI*.75;
    }

    static int directionIntent(double heading, double target, int previous) {
        double threshold=Math.toRadians(previous<0?130:previous>0?140:135);
        return Math.abs(wrap(target-heading))>threshold?-1:1;
    }

    public static Step step(double heading, double target, double distance,
                            double seconds, double load) {
        return step(heading, target, distance, seconds, load, new Step());
    }

    public static Step step(double heading, double target, double distance,
                            double seconds, double load, Step result) {
        return step(heading,target,distance,seconds,load,0,result);
    }

    public static Step step(double heading, double target, double distance,
                            double seconds, double load, double axleDistance, Step result) {
        return step(heading,target,distance,seconds,load,axleDistance,52,result);
    }

    static Step step(double heading, double target, double distance,
                     double seconds, double load, double axleDistance, double lateralDegrees, Step result) {
        return step(heading,target,distance,seconds,load,axleDistance,lateralDegrees,reversing(heading,target),result);
    }

    static Step step(double heading, double target, double distance,
                     double seconds, double load, double axleDistance, double lateralDegrees, boolean reverse, Step result) {
        if (!(distance > 0) || !(seconds > 0)) return result.set(0, 0, 0, 0);
        load = Math.max(0, Math.min(1, load));
        double error = wrap(target - heading);
        if (reverse) error = wrap(error + Math.PI);
        boolean wheelbarrow = axleDistance > 0;
        double axle = wheelbarrow ? axleDistance : AXLE_DISTANCE;
        double limit = wheelbarrow
                ? 2 * Math.asin(Math.min(1, distance * Math.sin(Math.toRadians(lateralDegrees - 2 * load)) / (2 * axle)))
                : distance * Math.abs(Math.sin(error)) / axle;
        limit = Math.min(limit, Math.min(0.1, seconds) * (wheelbarrow ? 1.6 - 0.3 * load : 3.8 - load));
        // Square-root easing settles in finite time instead of crawling through a sine tail.
        if (wheelbarrow) limit *= Math.min(1, Math.sqrt(Math.abs(error) * seconds / (limit * 0.1)));
        double turn = Math.max(-limit, Math.min(limit, error));
        if (wheelbarrow) {
            double half = turn / 2;
            double sideways = 2 * axle * Math.sin(half);
            double travel = Math.sqrt(Math.max(0, distance * distance - sideways * sideways));
            if (reverse) travel = -travel;
            // The handles step outside so the front wheel stays in its rolling plane.
            return result.set(travel * Math.cos(heading + half) + sideways * Math.sin(heading + half),
                              travel * Math.sin(heading + half) - sideways * Math.cos(heading + half),
                              turn, travel);
        }
        // Handle translation and the turn chord are perpendicular, not additive costs.
        double chord = 2 * axle * Math.sin(turn / 2);
        double travel = Math.sqrt(Math.max(0, distance * distance - chord * chord));
        if(Math.abs(Math.cos(error)) < 1e-10) travel=0;
        if (reverse) travel = -travel;
        double next = heading + turn;
        return result.set(travel * Math.cos(heading + turn / 2)
                                  - axle * (Math.cos(next) - Math.cos(heading)),
                          travel * Math.sin(heading + turn / 2)
                                  - axle * (Math.sin(next) - Math.sin(heading)),
                          turn, travel);
    }

    /** Derive wheelbarrow yaw from the displacement native collisions actually accepted. */
    public static double acceptedTurn(double heading, double axleDistance, double actualX, double actualY) {
        if (!(axleDistance > 0)) return 0;
        double cos = Math.cos(heading), sin = Math.sin(heading);
        double forward = actualX * cos + actualY * sin;
        double sideways = -actualX * sin + actualY * cos;
        return 2 * Math.atan2(-sideways, 2 * axleDistance - forward);
    }

    static double rollingLean(double turn, double forward, double seconds) {
        if (!(seconds > 0) || !Double.isFinite(turn) || !Double.isFinite(forward)) return 0;
        // Accepted motion drives load transfer; the native anchored torso's handle reach limits the bank.
        double cap=Math.toRadians(7);
        return Math.max(-cap,Math.min(cap,Math.atan(1.5*forward*turn/(5*seconds*seconds))));
    }

    static float woodenTurnAmount(float bank) {
        float x=(float)Math.min(1,Math.abs(bank)/Math.toRadians(2.5));
        return (float)Math.sin(x*Math.PI/2);
    }

    static float woodenBankExtra(float bank) {
        float x=(float)Math.max(0,Math.min(1,(Math.toDegrees(Math.abs(bank))-3)/4));
        return x*x*(3-2*x);
    }

    static float woodenShift(float bank, float gaitShift) {
        return -.065f*woodenTurnAmount(bank)-.020f*woodenBankExtra(bank)+gaitShift;
    }

    static double woodenAxle(float bank, float gaitShift) {
        // The same longitudinal hand-clearance shift must move the steering axle and rolling wheel.
        return 1.0084944326-1.5*woodenShift(bank,gaitShift);
    }

    static Step woodenStep(double heading, double target, double distance, double seconds,
                           double load, double axle, double previousRate, Step result) {
        return woodenStep(heading,target,distance,seconds,load,axle,previousRate,reversing(heading,target),result);
    }

    static Step woodenStep(double heading, double target, double distance, double seconds,
                           double load, double axle, double previousRate, boolean reverse, Step result) {
        step(heading,target,distance,seconds,load,axle,50,reverse,result);
        if (!(distance > 0) || !(seconds > 0)) return result;
        double dt=Math.min(.1,seconds), desiredRate=result.turn/dt;
        double error=wrap(target-heading);
        if(reverse) error=wrap(error+Math.PI);
        // Leave one step of braking distance so the final heading clamp cannot snap the yaw rate to zero.
        double stoppingRate=Math.sqrt(12*Math.abs(error)+36*dt*dt)-6*dt;
        desiredRate=Math.copySign(Math.min(Math.abs(desiredRate),stoppingRate),desiredRate);
        double rate=previousRate+Math.max(-6*dt,Math.min(6*dt,desiredRate-previousRate));
        double limit=2*Math.asin(Math.min(1,distance*Math.sin(Math.toRadians(45-2*Math.max(0,Math.min(1,load))))/(2*axle)));
        double turn=Math.max(-limit,Math.min(limit,rate*dt));
        if(turn*error>=0 && Math.abs(turn)>Math.abs(error)) turn=error;
        double sideways=2*axle*Math.sin(turn/2);
        double travel=Math.sqrt(Math.max(0,distance*distance-sideways*sideways));
        if(reverse) travel=-travel;
        return result.set(travel*Math.cos(heading+turn/2)+sideways*Math.sin(heading+turn/2),
                          travel*Math.sin(heading+turn/2)-sideways*Math.cos(heading+turn/2),turn,travel);
    }

    /** A native sidestep budget moves the handles around the planted front wheel. */
    static Step stationaryStep(double heading, double target, double distance, double seconds,
                               double load, double axle, double previousRate, Step result) {
        if (!(distance > 0) || !(seconds > 0) || !(axle > 0)) return result.set(0,0,0,0);
        double dt=Math.min(.1,seconds), error=wrap(target-heading);
        if(Math.abs(error)<1e-12) return result.set(0,0,0,0);
        double stoppingRate=Math.sqrt(12*Math.abs(error)+36*dt*dt)-6*dt;
        double desired=Math.copySign(Math.min(1.6-.3*Math.max(0,Math.min(1,load)),stoppingRate),error);
        double rate=previousRate+Math.max(-6*dt,Math.min(6*dt,desired-previousRate));
        double limit=2*Math.asin(Math.min(1,distance/(2*axle)));
        double turn=Math.max(-limit,Math.min(limit,rate*dt));
        if(turn*error>=0 && Math.abs(turn)>Math.abs(error)) turn=error;
        return result.set(-axle*(Math.cos(heading+turn)-Math.cos(heading)),
                          -axle*(Math.sin(heading+turn)-Math.sin(heading)),turn,0);
    }

    /** Wall slides cannot count sideways displacement as forward steering progress. */
    public static double acceptedFraction(Step requested, double actualX, double actualY) {
        double lengthSquared = requested.x * requested.x + requested.y * requested.y;
        if (!(lengthSquared > 0)) return 0;
        return Math.max(0, Math.min(1,
                (actualX * requested.x + actualY * requested.y) / lengthSquared));
    }

    private CartSteeringMath() {}
}
