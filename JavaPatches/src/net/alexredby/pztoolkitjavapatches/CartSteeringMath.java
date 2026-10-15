package net.alexredby.pztoolkitjavapatches;

/** Shopping-cart axle pivot and rolling wheelbarrow arc; native collision stays authoritative. */
public final class CartSteeringMath {
    // shortcut: selected models use an approximate axle offset; recalibrate when their geometry changes.
    private static final double AXLE_DISTANCE = 0.8;

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

    public static double wrap(double angle) {
        return Math.atan2(Math.sin(angle), Math.cos(angle));
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
        if (!(distance > 0) || !(seconds > 0)) return result.set(0, 0, 0, 0);
        load = Math.max(0, Math.min(1, load));
        double error = wrap(target - heading);
        boolean reverse = Math.abs(error) > Math.PI * 0.75;
        if (reverse) error = wrap(error + Math.PI);
        boolean wheelbarrow = axleDistance > 0;
        double axle = wheelbarrow ? axleDistance : AXLE_DISTANCE;
        double limit = wheelbarrow
                ? 2 * Math.asin(Math.min(1, distance * Math.sin(Math.toRadians(52 - 2 * load)) / (2 * axle)))
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

    /** Wall slides cannot count sideways displacement as forward steering progress. */
    public static double acceptedFraction(Step requested, double actualX, double actualY) {
        double lengthSquared = requested.x * requested.x + requested.y * requested.y;
        if (!(lengthSquared > 0)) return 0;
        return Math.max(0, Math.min(1,
                (actualX * requested.x + actualY * requested.y) / lengthSquared));
    }

    private CartSteeringMath() {}
}
