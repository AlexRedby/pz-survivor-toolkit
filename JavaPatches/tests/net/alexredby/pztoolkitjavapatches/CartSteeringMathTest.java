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
        for (double[] geometry : new double[][]{{1.0224308175, .033440793}, {1.1691522, -.0017422512}}) {
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
                        check(Math.abs(step.travel()) >= budget * .5 - 1e-12,
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
                for (int load : new int[]{0, 1}) {
                    double speed = load == 0 ? 1.3 : .83;
                    double[] reference = null;
                    for (int fps : new int[]{30, 60, 144}) {
                        double heading = 0, x = 0, y = 0;
                        int settled = 0;
                        double previousTravel = 0;
                        for (int frame = 0; frame < fps * 4; frame++) {
                            var step = CartSteeringMath.step(heading, sign * Math.PI / 2, speed / fps,
                                    1.0 / fps, load, axle, new CartSteeringMath.Step());
                            rolling(heading, step.turn(), axle, side, step.x(), step.y());
                            x += step.x(); y += step.y(); heading += step.turn();
                            check(sign * y >= -.58, "initial outside handle step stays below .58 tiles");
                            check(sign * heading <= Math.PI / 2, "wheelbarrow cannot overshoot the held direction");
                            if (frame > 0) check(Math.abs(step.travel() - previousTravel) < .3 * speed / fps,
                                    "settling does not abruptly release sideways motion");
                            previousTravel = step.travel();
                            if (settled == 0 && heading == sign * Math.PI / 2) settled = frame + 1;
                      }
                        check(settled > 0 && settled <= fps * (load == 0 ? 2 : 3),
                                "wheelbarrow reaches 90 degrees in two seconds empty or three loaded");
                        check(sign * y > 0, "wheelbarrow rolls into held turn");
                        if (reference == null) reference = new double[]{heading, x, y};
                        else {
                            check(Math.abs(heading - reference[0]) < .002, "wheelbarrow yaw is stable across FPS");
                            check(Math.hypot(x - reference[1], y - reference[2]) < .015,
                                  "wheelbarrow rolling trajectory is stable across FPS");
                      }
                  }
                }
            }
        }
        close(CartSteeringMath.acceptedTurn(0, 0, .02, .01), 0, "invalid axle cannot steer");
    }

    private static void wallClockChecks() {
        double cadence=.7,motionScale=1.6,worldSpeed=cadence*motionScale,normalDt=1.0/60;
        close(CartSteeringMath.wallStepSeconds(worldSpeed*normalDt,cadence,motionScale,normalDt),normalDt,
            "steady wall cadence keeps the original steering interval and includes native motion scale");
        close(CartSteeringMath.wallStepSeconds(0,cadence,motionScale,normalDt),0,"zero root budget cannot advance wall yaw");
        close(CartSteeringMath.wallStepSeconds(Double.NaN,cadence,motionScale,normalDt),0,"invalid root budget cannot advance wall yaw");
        close(CartSteeringMath.wallStepSeconds(1,cadence,motionScale,normalDt),.1,"deferred wall clock keeps the existing interval cap");
        for(double speed:new double[]{0,-1,Double.NaN,Double.POSITIVE_INFINITY,1e-12})
            close(CartSteeringMath.wallStepSeconds(.02,speed,motionScale,normalDt),normalDt,
                "missing or vanishing native cadence falls back to current time");
        for(double scale:new double[]{0,-1,Double.NaN,Double.POSITIVE_INFINITY})
            close(CartSteeringMath.wallStepSeconds(.02,cadence,scale,normalDt),normalDt,
                "invalid motion scale falls back without introducing a new movement budget");
        close(CartSteeringMath.wallStepSeconds(.02,0,motionScale,Double.NaN),0,"nonfinite fallback time is safe");
        close(CartSteeringMath.wallStepSeconds(.02,0,motionScale,-1),0,"negative fallback time is safe");
        close(CartSteeringMath.wallStepSeconds(.02,0,motionScale,1),.1,"fallback time retains the existing cap");
        // native01 Walk-slide grounding rows 62.20-62.55s: root distance follows the preceding animator interval.
        double[] currentDt={.016669,.021717,.011625,.016658,.025816,.007516,.016668,.016667};
        for(int sign:new int[]{-1,1}) for(int load:new int[]{0,1}) {
            double heading=0,referenceHeading=0,wrongHeading=0,rate=0,referenceRate=0,wrongRate=0;
            double previousCurvature=0,previousWrongCurvature=0;
            int trend=0,wrongTrend=0,curvatureReversals=0,wrongCurvatureReversals=0;
            double axle=1.13599443394,target=sign*Math.PI/4;
            for(int frame=0;frame<160;frame++) {
                int index=frame%currentDt.length;
                double producerDt=currentDt[(index+currentDt.length-1)%currentDt.length];
                double distance=worldSpeed*producerDt;
                double seconds=CartSteeringMath.wallStepSeconds(distance,cadence,motionScale,currentDt[index]);
                var step=CartSteeringMath.woodenStep(heading,target,distance,seconds,load,axle,rate,false,new CartSteeringMath.Step());
                var reference=CartSteeringMath.woodenStep(referenceHeading,target,distance,producerDt,load,axle,referenceRate,false,
                    new CartSteeringMath.Step());
                var wrong=CartSteeringMath.woodenStep(wrongHeading,target,distance,currentDt[index],load,axle,wrongRate,false,
                    new CartSteeringMath.Step());
                close(step.turn(),reference.turn(),"deferred root cadence preserves spatial yaw against its producer-interval reference");
                close(step.x(),reference.x(),"deferred root cadence preserves rolling X");
                close(step.y(),reference.y(),"deferred root cadence preserves rolling Y");
                check(step.turn()*sign>=0,"a continuous wall guide must not reverse its yaw");
                double curvature=Math.abs(step.turn())/distance,wrongCurvature=Math.abs(wrong.turn())/distance;
                int nextTrend=Math.abs(curvature-previousCurvature)>.01?(curvature>previousCurvature?1:-1):0;
                int nextWrongTrend=Math.abs(wrongCurvature-previousWrongCurvature)>.01?(wrongCurvature>previousWrongCurvature?1:-1):0;
                if(nextTrend!=0) {if(trend!=0 && trend!=nextTrend) curvatureReversals++;trend=nextTrend;}
                if(nextWrongTrend!=0) {if(wrongTrend!=0 && wrongTrend!=nextWrongTrend) wrongCurvatureReversals++;wrongTrend=nextWrongTrend;}
                previousCurvature=curvature;previousWrongCurvature=wrongCurvature;
                heading=CartSteeringMath.wrap(heading+step.turn());referenceHeading=CartSteeringMath.wrap(referenceHeading+reference.turn());
                wrongHeading=CartSteeringMath.wrap(wrongHeading+wrong.turn());
                // The next guide rate must use the same spatial interval, rather than reintroducing wall-clock jitter.
                rate=step.turn()/seconds;referenceRate=reference.turn()/producerDt;wrongRate=wrong.turn()/currentDt[index];
            }
            check(curvatureReversals<=1,"wall curvature may accelerate then settle, without repeated clock-induced reversals");
            check(wrongCurvatureReversals>5,"lagged-budget regression must expose the original current-dt curvature chatter");
            close(heading,target,"irregular native cadence still completes the guided turn");
        }
    }

    private static void woodenArc() {
        double axle=1.0224308175;
        for(int load:new int[]{0,1}) for(int sign:new int[]{-1,1}) {
            double[] reference=null;
            for(int fps:new int[]{30,60,144}) {
                double speed=load==0?1.3:.83, h=0,x=0,y=0,settled=0;
                for(int frame=0;frame<fps*4;frame++) {
                    var step=CartSteeringMath.step(h,sign*Math.PI/2,speed/fps,1.0/fps,
                        load,axle,45,new CartSteeringMath.Step());
                    double chord=2*axle*Math.sin(step.turn()/2);
                    check(Math.abs(step.travel())>=Math.abs(chord)-1e-10,
                        "wooden wheel keeps advancing at least as far as the sideways handle movement");
                    close(Math.hypot(step.x(),step.y()),speed/fps,"wooden arc preserves walking speed");
                    rolling(h,step.turn(),axle,.033440793,step.x(),step.y());
                    double bank=CartSteeringMath.rollingLean(step.turn(),step.travel(),1.0/fps);
                    check(sign*bank>=0 && Math.abs(bank)<=Math.toRadians(7),"wooden bank follows its turn within the calibrated grip range");
                    x+=step.x();y+=step.y();h+=step.turn();
                    check(sign*y>=-.47,"wooden arc avoids a large outside lunge");
                    if(settled==0 && h==sign*Math.PI/2) settled=(frame+1.0)/fps;
                }
                check(settled>0 && settled<(load==0?2.3:3.6),"rolling arc still responds promptly");
                if(reference==null) reference=new double[]{x,y,h};
                else check(Math.hypot(x-reference[0],y-reference[1])<.015
                    && Math.abs(h-reference[2])<.002,"wooden arc is frame-rate independent");
            }
        }
        close(CartSteeringMath.rollingLean(.01,0,1.0/60),0,"blocked wheel cannot bank");
        close(CartSteeringMath.rollingLean(0,.03,1.0/60),0,"straight wheel cannot sway");
        close(CartSteeringMath.rollingLean(.01,.02,0),0,"paused wheel cannot bank");
        close(CartSteeringMath.rollingLean(.01,-.02,1.0/60),
            -CartSteeringMath.rollingLean(.01,.02,1.0/60),"reverse bank follows rolling direction");
        close(CartSteeringMath.rollingLean(.01,.02,1.0/60),
            CartSteeringMath.rollingLean(.02,.04,1.0/30),"bank is frame-rate independent");
    }

    private static void woodenTransitions() {
        for(int fps:new int[]{30,60,144}) {
            var bank=new CartSteeringMath.Bank();
            double dt=1.0/fps,cap=Math.toRadians(7);
            for(int frame=0;frame<fps*2;frame++) {
                bank.update(cap,dt);
                close(Math.max(bank.pressure,Math.abs(bank.angle)),bank.angle,"single-sided bank must preserve the accepted pose");
            }
            double minimum=cap;
            for(int frame=0;frame<fps*3;frame++) {
                bank.update((frame/(fps/3))%2==0?-cap:cap,dt);
                check(bank.pressure>=0 && bank.pressure<=cap+1e-12,
                    "slalom pressure must retain the clearance envelope without exceeding seven degrees");
                if(Math.abs(bank.angle)<Math.toRadians(1)) minimum=Math.min(minimum,bank.pressure);
            }
            check(minimum>Math.toRadians(3.5),"changing bank must not retract the handles through neutral");
            for(int frame=0;frame<fps;frame++) bank.update(0,dt);
            check(bank.pressure<.00035,"straight input must release slalom pressure promptly");
            double pressure=bank.pressure;
            bank.update(cap,0);
            close(bank.pressure,pressure,"pause cannot change clearance pressure");
            bank=new CartSteeringMath.Bank();
            for(int frame=0;frame<fps*2;frame++) bank.update(Math.toRadians(frame%2==0?1:-1),dt);
            check(Math.max(bank.pressure,Math.abs(bank.angle))<Math.toRadians(.01),
                "alternating coordinate noise must not accumulate clearance pressure");
        }
        for(int sign:new int[]{-1,1}) {
            close(CartSteeringMath.woodenBankExtra((float)Math.toRadians(sign*3)),0,"small bank preserves the accepted arm pose");
            check(Math.abs(CartSteeringMath.woodenBankExtra((float)Math.toRadians(sign*5))-.5)<1e-6,"extra arm compensation reaches its midpoint smoothly");
            close(CartSteeringMath.woodenBankExtra((float)Math.toRadians(sign*7)),1,"seven-degree bank has full shoulder/elbow compensation");
            check(Math.abs(CartSteeringMath.woodenShift((float)Math.toRadians(sign*7),-.12f)+.205f)<1e-7,
                "strong bank keeps the selected longitudinal hand clearance and native gait shift");
            for(int edge:new int[]{3,7}) {
                float before=CartSteeringMath.woodenBankExtra((float)Math.toRadians(sign*(edge-.001)));
                float after=CartSteeringMath.woodenBankExtra((float)Math.toRadians(sign*(edge+.001)));
                check(Math.abs(after-before)<1e-6,"shoulder/elbow compensation has no velocity corner at its endpoints");
            }
        }
        double axle=1.0224308175;
        for(int load:new int[]{0,1}) for(int sign:new int[]{-1,1}) {
            double[] reference=null;
            for(int fps:new int[]{30,60,144}) {
                double dt=1.0/fps,speed=load==0?1.3:.83,h=0,x=0,y=0,rate=0,settled=0;
                var bank=new CartSteeringMath.Bank();
                var step=new CartSteeringMath.Step();
                for(int frame=0;frame<fps*4;frame++) {
                    CartSteeringMath.woodenStep(h,sign*Math.PI/2,speed*dt,dt,load,axle,rate,step);
                    double nextRate=step.turn()/dt;
                    if(frame==0) check(Math.abs(nextRate)<=6*dt+1e-10,"wood turn builds pressure instead of jumping to full yaw rate");
                    check(Math.abs(nextRate-rate)<=8*dt+.015,"entry and exit have bounded angular acceleration");
                    rate=nextRate;
                    close(Math.hypot(step.x(),step.y()),speed*dt,"smooth steering preserves native speed");
                    rolling(h,step.turn(),axle,.033440793,step.x(),step.y());
                    double before=bank.angle;
                    bank.update(CartSteeringMath.rollingLean(step.turn(),step.travel(),dt),dt);
                    check(sign*bank.angle>=-1e-10 && Math.abs(bank.angle)<=Math.toRadians(7),"bank stays inside held turn without overshoot");
                    check(Math.abs(bank.angle-before)<.7*dt,"hand pressure transition stays continuous");
                    h+=step.turn();x+=step.x();y+=step.y();
                    check(sign*h<=Math.PI/2+1e-10,"smooth turn cannot overshoot the held heading");
                    if(settled==0 && Math.abs(h-sign*Math.PI/2)<1e-9) settled=(frame+1.0)/fps;
                }
                check(settled>0 && settled<(load==0?2.5:3.8),"smoothing keeps wooden steering responsive");
                if(reference==null) reference=new double[]{x,y};
                else check(Math.hypot(x-reference[0],y-reference[1])<.035,"smooth wood trajectory is stable across FPS");
                // A quick opposite input must pass through zero turn rate, not flip its sign at full speed.
                rate=sign*.45;
                CartSteeringMath.woodenStep(h,h-sign*Math.PI/2,speed*dt,dt,load,axle,rate,step);
                check(sign*step.turn()>0 && Math.abs(step.turn()/dt-rate)<=6*dt+1e-10,
                    "quick reversal releases previous steering pressure first");
            }
        }
        double reference=0;
        for(int fps:new int[]{30,60,144}) {
            var bank=new CartSteeringMath.Bank();
            double dt=1.0/fps;
            close(bank.update(.18,0),0,"pause cannot change bank");
            for(int i=0;i<fps;i++) bank.update(.18,dt);
            if(reference==0) reference=bank.angle;else close(bank.angle,reference,"bank dynamics are frame-rate independent");
            check(bank.angle>.179 && bank.angle<=.18,"bank reaches pressure promptly without oscillating");
            for(int i=0;i<fps/2;i++) bank.update(0,dt);
            check(bank.angle>=0 && bank.angle<.004,"stopping smoothly rights the cart within half a second");
            for(int i=0;i<fps;i++) bank.update(-.18,dt);
            check(bank.angle<-.179 && bank.angle>=-.18,"opposite bank remains bounded");
        }
    }

    private static void reversalChecks() {
        check(CartSteeringMath.directionIntent(0,Math.toRadians(136),0)==-1,"initial reverse keeps the native135 boundary");
        check(CartSteeringMath.directionIntent(0,Math.toRadians(136),1)==1,"forward intent cannot chatter inside the deadband");
        check(CartSteeringMath.directionIntent(0,Math.toRadians(141),1)==-1,"forward intent enters reverse beyond140 degrees");
        check(CartSteeringMath.directionIntent(0,Math.toRadians(134),-1)==-1,"reverse intent stays latched inside the deadband");
        check(CartSteeringMath.directionIntent(0,Math.toRadians(129),-1)==1,"reverse exits below130 degrees");
        for(boolean reverse:new boolean[]{false,true}) {
            var step=CartSteeringMath.woodenStep(0,Math.toRadians(134),.02,1.0/60,0,1.1,0,reverse,new CartSteeringMath.Step());
            check((step.travel()<0)==reverse,"latched travel sign must not be reclassified at135 degrees");
            close(Math.hypot(step.x(),step.y()),.02,"latched reversal retains the native movement budget");
            rolling(0,step.turn(),1.1,0,step.x(),step.y());
        }
        for(int sign:new int[]{-1,1}) for(int fps:new int[]{10,30,60,144}) for(double load:new double[]{0,1}) {
            var mode=new CartSteeringMath.Reversal();mode.direction=sign;
            var pace=new CartLegPace.Ramp();pace.reset(3);
            check(mode.request(-sign,false),"a moving sign change must brake first");
            double previous=pace.speed,zeroTime=0;
            boolean crossed=false;
            for(int frame=0;frame<fps*4;frame++) {
                boolean braking=mode.braking;
                double speed=pace.update(braking?0:.8,1.0/fps,load);
                if(braking && pace.settled(0)) {pace.reset(0);speed=0;}
                if(braking) {
                    check(speed<=previous+1e-10,"braking cannot accelerate the old direction");
                    if(speed==0 && previous==0)zeroTime+=1.0/fps;
                    mode.stopped(1.0/fps,speed==0,previous==0);
                    if(!mode.braking) {
                        check(zeroTime>=.08-1e-10,"native needs an evaluated neutral pose before changing sign");
                        check(speed==0 && mode.direction==-sign,"direction changes only at exactly zero root speed");
                        crossed=true;
                    }
                } else check(speed>=previous-1e-10 && speed<=.8,"new direction accelerates without overshoot");
                previous=speed;
            }
            check(crossed && pace.settled(.8),"both loaded directions must complete at every supported FPS");
        }
        var mode=new CartSteeringMath.Reversal();
        mode.request(-1,false);mode.stopped(.1,true,false);
        check(mode.direction==1 && mode.braking,"collision/root disagreement cannot commit a sign change");
        mode.request(1,false);
        check(mode.active && !mode.braking && mode.direction==1,"repeated input can resume the original direction while braking");
        mode.request(-1,false);mode.request(0,false);
        check(!mode.active && !mode.braking && mode.direction==1,"released input cannot leave a delayed reverse request");
        mode.request(-1,true);
        check(mode.direction==-1 && !mode.active,"starting backwards from rest needs no artificial brake");
    }

    private static void stationaryChecks() {
        for(int fps:new int[]{30,60,144}) for(int sign:new int[]{-1,1}) for(double load:new double[]{0,1}) {
            double heading=.3,initial=heading,x=0,y=0,rate=0,axle=1.01,dt=1.0/fps;
            var step=new CartSteeringMath.Step();
            for(int frame=0;frame<fps*4;frame++) {
                double budget=(load==0?1.3:.83)*dt;
                CartSteeringMath.stationaryStep(heading,initial+sign*Math.PI/2,budget,dt,load,axle,rate,step);
                check(Math.hypot(step.x(),step.y())<=budget+1e-12,"stationary turn cannot invent native root movement");
                close(step.travel(),0,"stationary turn keeps the wheel planted");
                close(CartSteeringMath.acceptedTurn(heading,axle,step.x(),step.y()),step.turn(),"accepted chord determines stationary yaw");
                check(sign*step.turn()>=0,"stationary turn cannot move in the opposite direction");
                x+=step.x();y+=step.y();heading+=step.turn();rate=step.turn()/dt;
                close(x+axle*Math.cos(heading),axle*Math.cos(initial),"stationary wheel X stays fixed");
                close(y+axle*Math.sin(heading),axle*Math.sin(initial),"stationary wheel Y stays fixed");
            }
            close(heading,initial+sign*Math.PI/2,"stationary turn finishes at every cargo/FPS");
            CartSteeringMath.stationaryStep(heading,heading+1,0,dt,load,axle,rate,step);
            check(step.x()==0 && step.y()==0 && step.turn()==0,"without a native step the planted character cannot yaw");
            CartSteeringMath.stationaryStep(heading,heading,1,dt,load,axle,.4,step);
            check(step.turn()==0,"release consumes no residual strafe budget");
        }
    }

    public static void main(String[] args) {
        stationaryChecks();
        reversalChecks();
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
        check(!CartSteeringMath.reversing(0,Math.PI*.75),"135 degrees remains a forward arc");
        check(CartSteeringMath.reversing(0,Math.PI),"opposite input requests reverse, not an instant U-turn");
        wheelbarrowChecks();
        woodenArc();
        wallClockChecks();
        woodenTransitions();
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
