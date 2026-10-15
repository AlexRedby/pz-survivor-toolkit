package net.alexredby.pztoolkitjavapatches;

public final class CartSteeringMathTest {
    private static final double L = 0.8;
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void close(double actual, double expected, String message) {
        check(Math.abs(actual - expected) < 1e-10, message + ": " + actual + " != " + expected);
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
        var wheel=CartSteeringMath.step(0,Math.PI/2,.03,1.0/60,0,true,new CartSteeringMath.Step());
        check(wheel.travel()>0 && wheel.turn()<pivot.turn(),"wheelbarrow rolls around its single wheel while shop shifts rear");
        close(Math.hypot(wheel.x(),wheel.y()),.03,"wheelbarrow turn retains native handle speed");
        for(int degrees=-180;degrees<=180;degrees++) {
            var step=CartSteeringMath.step(.3,.3+Math.toRadians(degrees),.03,1.0/60,.7,true,new CartSteeringMath.Step());
            close(Math.hypot(step.x(),step.y()),.03,"wheelbarrow steering cannot halve movement budget");
        }
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
