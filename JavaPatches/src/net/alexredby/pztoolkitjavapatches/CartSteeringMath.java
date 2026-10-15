package net.alexredby.pztoolkitjavapatches;

/** Kinematic handle/axle pivot. Native character collision remains authoritative. */
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
        if (!(distance > 0) || !(seconds > 0)) return result.set(0, 0, 0, 0);
        load = Math.max(0, Math.min(1, load));
        double error = wrap(target - heading);
        boolean reverse = Math.abs(error) > Math.PI * 0.75;
        if (reverse) error = wrap(error + Math.PI);
        double limit = Math.min(distance / AXLE_DISTANCE,
                                Math.min(0.1, seconds) * (1.2 - 0.65 * load));
        double turn = Math.max(-limit, Math.min(limit, error));
        double alignment = Math.max(0, Math.cos(error));
        if (alignment < 1e-10) alignment = 0;
        double travel = Math.max(0, distance - AXLE_DISTANCE * Math.abs(turn)) * alignment;
        if (reverse) travel = -travel;
        double next = heading + turn;
        return result.set(travel * Math.cos(heading + turn / 2)
                                  - AXLE_DISTANCE * (Math.cos(next) - Math.cos(heading)),
                          travel * Math.sin(heading + turn / 2)
                                  - AXLE_DISTANCE * (Math.sin(next) - Math.sin(heading)),
                          turn, travel);
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
