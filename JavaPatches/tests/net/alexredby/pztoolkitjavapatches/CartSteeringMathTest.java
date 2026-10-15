package net.alexredby.pztoolkitjavapatches;

public final class CartSteeringMathTest {
    private static final double L = 0.8;
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void close(double actual, double expected, String message) {
        check(Math.abs(actual - expected) < 1e-10, message + ": " + actual + " != " + expected);
    }

    private static void rolling(double heading, double turn, double axle, double side,
                                double dx, double dy) {
        double next = heading + turn, mid = heading + turn / 2;
        double wheelX = dx + axle * (Math.cos(next) - Math.cos(heading))
                           - side * (Math.sin(next) - Math.sin(heading));
        double wheelY = dy + axle * (Math.sin(next) - Math.sin(heading))
                           + side * (Math.cos(next) - Math.cos(heading));
        close(-wheelX * Math.sin(mid) + wheelY * Math.cos(mid), 0,
              "actual wheel displacement stays in its rolling plane");
    }

    private static void wheelbarrowChecks() {
        // Actual calibrated contact positions after native horizontal model-to-world scale 1.5.
        for (double[] geometry : new double[][]{{1.10976729, .033440793}, {1.1691522, -.0017422512}}) {
            double axle = geometry[0], side = geometry[1];
            var empty = CartSteeringMath.step(0, Math.PI / 2, .03, 1.0 / 60, 0, axle, new CartSteeringMath.Step());
            var full = CartSteeringMath.step(0, Math.PI / 2, .03, 1.0 / 60, 1, axle, new CartSteeringMath.Step());
            check(empty.turn() > full.turn() && full.turn() > 0, "wheelbarrow load tightens steering");
            for (double heading : new double[]{0, .3, Math.PI / 2, Math.PI, -Math.PI / 2}) {
                for (double budget : new double[]{0, .0001, .03, .5}) {
                    for (int degrees = -180; degrees <= 180; degrees++) {
                        var step = CartSteeringMath.step(heading, heading + Math.toRadians(degrees), budget,
                                1.0 / 60, .7, axle, new CartSteeringMath.Step());
                        close(Math.hypot(step.x(), step.y()), budget, "wheelbarrow preserves native walking budget");
                        check(Math.abs(step.travel()) >= budget * Math.cos(Math.toRadians(15)) - 1e-12,
                              "wheelbarrow keeps rolling instead of parking its wheel");
                        rolling(heading, step.turn(), axle, side, step.x(), step.y());
                        close(CartSteeringMath.acceptedTurn(heading, axle, step.x(), step.y()), step.turn(),
                              "fully accepted step keeps planned yaw");
                        close(CartSteeringMath.acceptedTurn(heading, axle, 0, 0), 0,
                              "fully blocked wheelbarrow cannot yaw");
                        for (double fraction : new double[]{.1, .5}) {
                            double dx = step.x() * fraction, dy = step.y() * fraction;
                            rolling(heading, CartSteeringMath.acceptedTurn(heading, axle, dx, dy), axle, side, dx, dy);
                        }
                    }
                }
                for (double[] slide : new double[][]{{.02, 0}, {0, -.02}, {-.01, .015}}) {
                    rolling(heading, CartSteeringMath.acceptedTurn(heading, axle, slide[0], slide[1]),
                            axle, side, slide[0], slide[1]);
                }
            }
            var reverse = CartSteeringMath.step(0, Math.PI, .03, 1.0 / 60, 0, axle, new CartSteeringMath.Step());
            close(reverse.x(), -.03, "wheelbarrow can back away from a wall");
            close(reverse.y(), 0, "straight reverse stays on wheel axis");
            close(reverse.turn(), 0, "straight reverse cannot make a U-turn");
            for (int sign : new int[]{-1, 1}) {
                double[] reference = null;
                for (int fps : new int[]{30, 60, 144}) {
                    double heading = 0, x = 0, y = 0;
                    for (int frame = 0; frame < fps * 8; frame++) {
                        var step = CartSteeringMath.step(heading, sign * Math.PI / 2, 1.2 / fps,
                                1.0 / fps, 0, axle, new CartSteeringMath.Step());
                        rolling(heading, step.turn(), axle, side, step.x(), step.y());
                        x += step.x(); y += step.y(); heading += step.turn();
                        check(sign * y >= -.17, "initial outside handle step stays below .17 tiles");
                    }
                    check(sign * y > 0 && sign * heading > 1.3, "wheelbarrow rolls into held turn");
                    if (reference == null) reference = new double[]{heading, x, y};
                    else {
                        check(Math.abs(heading - reference[0]) < .002, "wheelbarrow yaw is stable across FPS");
                        check(Math.hypot(x - reference[1], y - reference[2]) < .015,
                              "wheelbarrow rolling trajectory is stable across FPS");
                    }
                }
            }
        }
        close(CartSteeringMath.acceptedTurn(0, 0, .02, .01), 0, "invalid axle cannot steer");
    }

    public static void main(String[] args) {
        var idle = CartSteeringMath.step(0, Math.PI / 2, 0, 1.0 / 60, 0);
        check(idle.turn() == 0 && idle.x() == 0 && idle.y() == 0, "idle cannot spin");
        var pivot = CartSteeringMath.step(0, Math.PI / 2, 0.03, 1.0 / 60, 0);
        close(pivot.travel(), 0, "lateral cart intent keeps axle stationary");
        close(pivot.x() + L * Math.cos(pivot.turn()), L, "pivot axle X");
        close(pivot.y() + L * Math.sin(pivot.turn()), 0, "pivot axle Y");
        check(pivot.y() < 0 && pivot.turn() > 0, "handle sidesteps opposite cart yaw");
        var fast = CartSteeringMath.step(0, Math.PI / 2, 0.08, 1.0 / 60, 0);
        var full = CartSteeringMath.step(0, Math.PI / 2, 0.08, 1.0 / 60, 1);
        check(fast.turn() > full.turn() && full.turn() > 0, "cargo limits yaw");
        wheelbarrowChecks();
        var reverse = CartSteeringMath.step(0, Math.PI, 0.03, 1.0 / 60, 0);
        close(reverse.x(), -0.03, "reverse escapes head-on wall");
        close(reverse.y(), 0, "reverse stays on axis");
        close(reverse.turn(), 0, "reverse cannot spin into U-turn");
        close(CartSteeringMath.acceptedFraction(pivot, 0, 0), 0, "wall stops yaw");
        close(CartSteeringMath.acceptedFraction(pivot, pivot.x() / 2, pivot.y() / 2), 0.5,
                "partial collision scales yaw");
        close(CartSteeringMath.acceptedFraction(pivot, -pivot.y(), pivot.x()), 0,
                "perpendicular wall slide cannot steer");
        var reusable = new CartSteeringMath.Step();
        for (double load : new double[]{-1, 0, 0.5, 1, 2}) {
            for (double budget : new double[]{0, 0.0001, 0.03, 0.5}) {
                for (int degrees = -180; degrees <= 180; degrees++) {
                    check(CartSteeringMath.step(0.7, 0.7 + Math.toRadians(degrees), budget,
                            1.0 / 60, load, reusable) == reusable, "result reused");
                    check(Math.hypot(reusable.travel(), 2*L*Math.sin(reusable.turn()/2)) <= budget + 1e-12,
                            "translation and yaw share native budget");
                    check(Math.hypot(reusable.x(), reusable.y()) <= budget + 1e-12,
                            "no displacement/speed gain");
                    double next = 0.7 + reusable.turn();
                    close(reusable.x() + L * Math.cos(next) - L * Math.cos(0.7),
                            reusable.travel() * Math.cos(0.7 + reusable.turn() / 2), "rolling axle X");
                    close(reusable.y() + L * Math.sin(next) - L * Math.sin(0.7),
                            reusable.travel() * Math.sin(0.7 + reusable.turn() / 2), "rolling axle Y");
                }
            }
        }
        for (int fps : new int[]{30, 60, 144}) {
            double h = 0, x = 0, y = 0;
            for (int i = 0; i < fps; i++) {
                var step = CartSteeringMath.step(h, h + Math.PI / 2, 1.8 / fps, 1.0 / fps, 0);
                x += step.x(); y += step.y(); h += step.turn();
            }
            close(h, 2.25, "frame-independent pivot yaw");
            close(x + L * Math.cos(h), L, "frame-independent fixed axle X");
            close(y + L * Math.sin(h), 0, "frame-independent fixed axle Y");
        }
        for (int fps : new int[]{30, 60, 144}) {
            double h = 0, previousTravel = 0, travelled = 0;
            int flat = 0;
            for (int frame = 0; frame < fps * 4; frame++) {
                var step = CartSteeringMath.step(h, Math.PI / 2, 1.8 / fps, 1.0 / fps, 0);
                h += step.turn(); travelled += step.travel();
                if (step.travel() < 1e-8) flat++;
                check(step.travel() + 1e-10 >= previousTravel, "turn rolls progressively, without stopping");
                check(step.travel() - previousTravel < 0.16 * 1.8 / fps,
                      "no sudden pivot-to-forward release");
                previousTravel = step.travel();
            }
            check(flat <= 1, "cart cannot stay parked while turning");
            check(travelled > 4 && h > Math.PI / 2 - 0.01, "held turn becomes forward rolling");
        }
        CartSteeringMath.step(0, Math.PI / 2, 0, 1.0 / 60, 0, reusable);
        check(reusable.x() == 0 && reusable.y() == 0 && reusable.turn() == 0 && reusable.travel() == 0,
                "idle clears reused result");
        System.out.println("CART_STEERING_MATH_PASS (pivot, reverse, budget, cargo, FPS, collision)");
    }
}
