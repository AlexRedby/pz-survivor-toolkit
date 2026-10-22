package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.joml.Matrix4f;

/** Analytic geometry and captured-pose source-cage replay; no game or render context. */
public final class CartLegClearanceTest {
    private static final double EPS=1e-6;
    private static final double[] TETRA={0,0,0, 1,0,0, 0,1,0, 0,0,1};
    private static final double[] INSIDE={.2,.1,.1, .2,.2,.1, .2,.1,.2};
    private static final double[] XY={0,0,0, 1,0,0, 0,1,0};
    private static final int[][] TRI_ORDERS={{0,1,2},{0,2,1},{1,0,2},{1,2,0},{2,0,1},{2,1,0}};

    private static void check(boolean condition,String message) {
        if(!condition) throw new AssertionError(message);
    }
    private static void close(double actual,double expected,double tolerance,String message) {
        check(Double.isFinite(actual) && Math.abs(actual-expected)<=tolerance,
            message+": actual="+actual+" expected="+expected);
    }
    private static double[] translated(double[] points,double x,double y,double z) {
        var out=points.clone();
        for(int i=0;i<out.length;i+=3) {out[i]+=x;out[i+1]+=y;out[i+2]+=z;}
        return out;
    }
    private static double[] scaled(double[] points,double scale) {
        var out=points.clone();for(int i=0;i<out.length;i++) out[i]*=scale;return out;
    }
    private static double[] ordered(double[] points,int... order) {
        var out=new double[order.length*3];
        for(int i=0;i<order.length;i++) System.arraycopy(points,order[i]*3,out,i*3,3);
        return out;
    }
    private static double[] range(double[] body,double[] cart,double margin,String message) {
        var bodyBefore=body.clone();var cartBefore=cart.clone();var out=new double[2];
        check(CartLegClearance.interval(body,cart,margin,out),message+": interval missing");
        check(Double.isFinite(out[0]) && Double.isFinite(out[1]) && out[0]<=out[1],message+": invalid interval");
        check(Arrays.equals(body,bodyBefore) && Arrays.equals(cart,cartBefore),message+": input geometry mutated");
        return out;
    }
    private static void expectedRange(double[] body,double[] cart,double low,double high,String message) {
        var out=range(body,cart,0,message);
        close(out[0],low,1e-8,message+" lower");close(out[1],high,1e-8,message+" upper");
    }
    private static void separated(double[] body,double[] cart,String message) {
        check(!CartLegClearance.interval(body,cart,0,new double[2]),message);
    }

    private static void tetrahedra() {
        // The body triangle is wholly inside a solid tetrahedron, with no surface
        // edge crossing. Body x=.2-d and minimum y+z=.2 give -.6 <= d <= .2.
        expectedRange(INSIDE,TETRA,-.6,.2,"solid containment, cart+X/body-X sign");
        expectedRange(translated(INSIDE,2,0,0),TETRA,1.4,2.2,"far positive sweep is not capped by the runtime corridor");
        expectedRange(translated(INSIDE,-2,0,0),TETRA,-2.6,-1.8,"far negative sweep");
        // All three vertices lie outside, but an edge crosses the tetra interior.
        expectedRange(new double[]{.2,-.5,.2, .2,1.5,.2, .2,.5,.8},TETRA,-.6,.2,"edge/face overlap with no contained vertex");
        separated(translated(INSIDE,0,2,0),TETRA,"Y separation cannot be repaired by X");
        separated(translated(INSIDE,0,0,-2),TETRA,"Z separation cannot be repaired by X");
        for(int a=0;a<4;a++) for(int b=0;b<4;b++) if(b!=a)
            for(int c=0;c<4;c++) if(c!=a && c!=b) {
                int d=6-a-b-c;
                for(var order:TRI_ORDERS) expectedRange(ordered(INSIDE,order),ordered(TETRA,a,b,c,d),-.6,.2,
                    "winding/vertex permutation invariance");
            }
        for(double scale:new double[]{.1,1,10})
            expectedRange(translated(scaled(INSIDE,scale),17,-11,4),translated(scaled(TETRA,scale),17,-11,4),
                -.6*scale,.2*scale,"common translation and uniform scale");
        var reflected=INSIDE.clone();var reflectedCart=TETRA.clone();
        for(int i=0;i<reflected.length;i+=3) reflected[i]=-reflected[i];
        for(int i=0;i<reflectedCart.length;i+=3) reflectedCart[i]=-reflectedCart[i];
        expectedRange(reflected,reflectedCart,-.2,.6,"mirrored X reverses both interval endpoints");
        var padded=range(INSIDE,TETRA,.001,"positive clearance margin");
        check(padded[0]<=-.601+1e-10 && padded[1]>=.201-1e-10,"margin must expand both escape directions");
    }

    private static void triangles() {
        expectedRange(XY,translated(XY,2,0,0),-3,-1,"coplanar separated triangles meet under negative cart shift");
        expectedRange(XY,translated(XY,-2,0,0),1,3,"coplanar separated triangles meet under positive cart shift");
        expectedRange(XY,XY,-1,1,"coplanar overlapping triangles require in-plane separating axes");
        separated(XY,translated(XY,0,2,0),"coplanar disjoint Y ranges remain separated");
        separated(XY,translated(XY,0,0,.25),"parallel separated planes remain separated");
        // The vertical primitive intersects z=0 over y=[.25,1]. The body's
        // right edge x+y=2 gives the independent upper bound d=1.25.
        var vertical=new double[]{.5,.25,-1, .5,.25,1, .5,1,0};
        var wide=scaled(XY,2);
        expectedRange(wide,vertical,-.5,1.25,"noncoplanar triangle/triangle intersection");
        for(var bodyOrder:TRI_ORDERS) for(var cartOrder:TRI_ORDERS)
            expectedRange(ordered(wide,bodyOrder),ordered(vertical,cartOrder),-.5,1.25,"noncoplanar winding invariance");
    }

    private static void domainWrapper() {
        var out=new double[2];
        check(!CartLegClearance.intervalWithinDomain(translated(INSIDE,2,0,0),TETRA,0,-.03,.03,out),
            "domain broadphase skips a strictly positive distant sweep");
        check(!CartLegClearance.intervalWithinDomain(translated(INSIDE,-2,0,0),TETRA,0,-.03,.03,out),
            "domain broadphase skips a strictly negative distant sweep");
        var smallTetra=scaled(TETRA,.01);var smallBody=scaled(INSIDE,.01);
        for(double offset:new double[]{.035,-.031}) {
            var body=translated(smallBody,offset,0,0);var generic=range(body,smallTetra,0,"domain-edge interval");
            check(generic[0]<=.03 && generic[1]>=-.03,"edge control actually intersects the legal corridor");
            check(CartLegClearance.intervalWithinDomain(body,smallTetra,0,-.03,.03,out),
                "thin collision at either domain edge must survive the broadphase");
            close(out[0],generic[0],1e-12,"domain wrapper preserves lower endpoint");
            close(out[1],generic[1],1e-12,"domain wrapper preserves upper endpoint");
        }
        var touching=new double[]{.04,0,0, .04,.001,0, .04,0,.001};
        check(CartLegClearance.intervalWithinDomain(touching,smallTetra,0,-.03,.03,out),
            "exact positive-domain contact is retained");
        close(out[0],.03,1e-9,"exact edge contact lower endpoint");
        var marginOnly=translated(touching,.0005,0,0);
        check(!CartLegClearance.intervalWithinDomain(marginOnly,smallTetra,0,-.03,.03,out),
            "unpadded control is beyond the domain");
        check(CartLegClearance.intervalWithinDomain(marginOnly,smallTetra,.001,-.03,.03,out)
            && out[0]<=.03 && out[1]>=-.03,"margin-only in-domain contact survives the broadphase");
        // Compare the wrapper with the unbounded SAT oracle over both directions,
        // margins and domain boundaries; no second geometry algorithm is copied.
        int retained=0;
        for(int i=-20;i<=20;i++) for(double margin:new double[]{0,.001}) {
            var body=translated(smallBody,i*.0025,0,0);var generic=new double[2];
            boolean exists=CartLegClearance.interval(body,smallTetra,margin,generic);
            boolean filtered=CartLegClearance.intervalWithinDomain(body,smallTetra,margin,-.03,.03,out);
            if(exists && generic[0]<=.03 && generic[1]>=-.03) {
                retained++;check(filtered,"domain broadphase lost an in-domain collision");
                close(out[0],generic[0],1e-12,"filtered lower endpoint matches generic SAT");
                close(out[1],generic[1],1e-12,"filtered upper endpoint matches generic SAT");
            }
            if(!exists) check(!filtered,"domain wrapper must not invent a generic interval");
        }
        check(retained>20,"domain-retention controls exercise a useful sweep");
    }

    private static double choice(double[] low,double[] high,int count,double min,double max,String message) {
        double value=CartLegClearance.choose(low,high,count,min,max);
        check(Double.isFinite(value) && value>=min && value<=max,message+": no bounded solution");
        for(int i=0;i<count;i++) check(value<=low[i]-EPS+1e-10 || value>=high[i]+EPS-1e-10,
            message+": selected point enters a forbidden interval or its epsilon clearance");
        return value;
    }
    private static void choices() {
        close(choice(new double[0],new double[0],0,-.03,.03,"empty union"),0,0,"neutral zero");
        close(choice(new double[]{.01,-.03},new double[]{.02,-.02},2,-.03,.03,"disjoint clear intervals"),0,0,
            "a bounding hull must not close a real free gap");
        close(choice(new double[]{1.5*EPS},new double[]{.01},1,-.03,.03,"near but clear zero"),0,0,
            "epsilon merging must not invent an initial zero collision");
        close(choice(new double[]{-.01},new double[]{.02},1,-.03,.03,"shorter negative escape"),-.010001,1e-12,"nearest negative");
        close(choice(new double[]{-.02},new double[]{.01},1,-.03,.03,"shorter positive escape"),.010001,1e-12,"nearest positive");
        close(choice(new double[]{0},new double[]{.01},1,-.03,.03,"zero on forbidden boundary"),-EPS,1e-12,"closed boundary escape");
        close(choice(new double[]{.005,-.004,.001},new double[]{.02,.002,.006},3,-.03,.03,"unsorted transitive union"),
            -.004001,1e-12,"must escape the complete connected component");
        close(choice(new double[]{-.01,.0100015},new double[]{.01,.03},2,-.005,.04,"epsilon gap between neighbours"),
            .030001,1e-12,"epsilon exit must not enter the next forbidden component");
        close(choice(new double[]{-.004},new double[]{.02},1,-.003,.03,"negative side outside budget"),.020001,1e-12,"bounded positive alternative");
        close(choice(new double[]{-.02},new double[]{.004},1,-.03,.003,"positive side outside budget"),-.020001,1e-12,"bounded negative alternative");
        double tie=choice(new double[]{-.01},new double[]{.01},1,-.03,.03,"symmetric alternatives");
        close(Math.abs(tie),.010001,1e-12,"either nearest symmetric side is valid");
        check(Double.isNaN(CartLegClearance.choose(new double[]{-.02},new double[]{.02},1,-.01,.01)),"covered corridor must refuse");
        check(Double.isNaN(CartLegClearance.choose(new double[]{-.0299995},new double[]{.04},1,-.03,.03)),
            "sub-epsilon boundary sliver is not a safe corridor");
        close(choice(new double[]{Double.NEGATIVE_INFINITY},new double[]{.01},1,-.03,.03,"unbounded half-axis"),
            .010001,1e-12,"finite escape from half-axis");
        check(Double.isNaN(CartLegClearance.choose(new double[]{Double.NEGATIVE_INFINITY},new double[]{Double.POSITIVE_INFINITY},1,-.03,.03)),
            "whole-axis obstruction refuses");
        close(CartLegClearance.choose(new double[]{.02,Double.NaN},new double[]{.03,Double.NaN},1,-.03,.03),0,0,
            "unused scratch tail does not poison the live prefix");
        close(CartLegClearance.choose(new double[0],new double[0],0,0,0),0,0,"unblocked singleton corridor");
    }

    private static void guards() {
        for(var body:new double[][]{null,new double[8],new double[9],{0,0,0,1,0,0,2,0,0}})
            check(!CartLegClearance.interval(body,TETRA,0,new double[2]),"invalid/degenerate body rejected");
        for(var cart:new double[][]{null,new double[8],new double[9],new double[12],
            {0,0,0,1,0,0,2,0,0},{0,0,0,1,0,0,0,1,0,1,1,0}})
            check(!CartLegClearance.interval(INSIDE,cart,0,new double[2]),"invalid/degenerate primitive rejected");
        for(var out:new double[][]{null,new double[0],new double[1]})
            check(!CartLegClearance.interval(INSIDE,TETRA,0,out),"undersized output rejected");
        for(double value:new double[]{Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY}) {
            for(int i=0;i<INSIDE.length;i++) {var body=INSIDE.clone();body[i]=value;separated(body,TETRA,"every body coordinate must be finite");}
            for(int i=0;i<TETRA.length;i++) {var cart=TETRA.clone();cart[i]=value;separated(INSIDE,cart,"every primitive coordinate must be finite");}
            check(!CartLegClearance.interval(INSIDE,TETRA,value,new double[2]),"nonfinite margin rejected");
            check(Double.isNaN(CartLegClearance.choose(new double[0],new double[0],0,value,.03)),"nonfinite lower corridor bound rejected");
            check(Double.isNaN(CartLegClearance.choose(new double[0],new double[0],0,-.03,value)),"nonfinite upper corridor bound rejected");
        }
        check(!CartLegClearance.interval(INSIDE,TETRA,-.001,new double[2]),"negative margin rejected");
        check(Double.isNaN(CartLegClearance.choose(null,new double[0],0,-.03,.03)),"null lower ranges rejected");
        check(Double.isNaN(CartLegClearance.choose(new double[0],null,0,-.03,.03)),"null upper ranges rejected");
        for(int count:new int[]{-1,2}) check(Double.isNaN(CartLegClearance.choose(new double[]{0},new double[]{0},count,-.03,.03)),"invalid count rejected");
        check(Double.isNaN(CartLegClearance.choose(new double[]{0},new double[0],1,-.03,.03)),"mismatched live prefix rejected");
        check(Double.isNaN(CartLegClearance.choose(new double[]{Double.NaN},new double[]{1},1,-.03,.03)),"NaN interval rejected");
        check(Double.isNaN(CartLegClearance.choose(new double[]{1},new double[]{0},1,-.03,.03)),"reversed interval rejected");
        check(Double.isNaN(CartLegClearance.choose(new double[0],new double[0],0,.01,-.01)),"reversed corridor rejected");
    }

    private static void footprints() {
        double front=CartFootprint.WALK_FRONT;
        for(double side:new double[]{-1,1}) {
            check(CartFootprint.contains(.3,side*.04,front,.001),"rail centre belongs to the native envelope");
            check(CartFootprint.contains(-.298,side*.04,front,.001),"rear rounded cap keeps its interior");
            check(!CartFootprint.contains(-.301,side*.04,front,.001),"point behind the rear cap is outside");
            check(CartFootprint.contains(.3,side*.338,front,.001),"rail radius admits a point with reserve");
            check(!CartFootprint.contains(.3,side*.341,front,.001),"point beyond the outer rail radius is outside");
            check(!CartFootprint.contains(-.25,side*.29,front,.001),"rounded rear corner is not an oversized box");
        }
        check(CartFootprint.contains(.98,0,front,.001),"tapered nose tip belongs to the envelope");
        check(CartFootprint.contains(1.26,0,front,.001),"existing forward cap contains its calibrated nose");
        check(!CartFootprint.contains(1.281,0,front,.001),"point beyond the nose cap is outside");
        check(CartFootprint.contains(.3,.3395,front,0) && !CartFootprint.contains(.3,.3395,front,.001),
            "one-millimetre reserve shrinks the native envelope");
        for(double value:new double[]{Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY}) {
            check(!CartFootprint.contains(value,0,front,.001),"nonfinite forward coordinate rejected");
            check(!CartFootprint.contains(0,value,front,.001),"nonfinite lateral coordinate rejected");
            check(!CartFootprint.contains(0,0,value,.001),"nonfinite forward budget rejected");
            check(!CartFootprint.contains(0,0,front,value),"nonfinite reserve rejected");
        }
        check(!CartFootprint.contains(0,0,.1,.001),"collapsed forward budget rejected");
        check(!CartFootprint.contains(0,0,front,-.001) && !CartFootprint.contains(0,0,front,.3),"invalid reserve rejected");
    }

    private static final class Replay {
        final String name;
        final boolean female;
        final double expected;
        final Map<String,Matrix4f> bones=new HashMap<>();
        final List<double[]> points=new ArrayList<>();
        final CartLegClearanceData.Skin[] skins;
        final double[][] triangles,primitives;
        Matrix4f cart;
        Replay(String name,boolean female,double expected) {
            this.name=name;this.female=female;this.expected=expected;
            skins=new CartLegClearanceData.Skin[]{CartLegClearanceData.SKINS[female?1:0],CartLegClearanceData.SKINS[female?3:2]};
            int faces=0;
            for(var skin:skins) {points.add(new double[skin.vertexCount()*3]);faces+=skin.triangles().length/3;}
            triangles=new double[faces][9];primitives=new double[CartLegClearanceData.WOOD.primitives().length][];
            for(int i=0;i<primitives.length;i++) primitives[i]=new double[CartLegClearanceData.WOOD.primitives()[i].length];
        }
        void rebuild() {
            int face=0;
            for(int s=0;s<skins.length;s++) {
                var skin=skins[s];var vertices=points.get(s);Arrays.fill(vertices,0);
                for(int bone=0;bone<skin.bones().length;bone++) {
                    var pose=bones.get(skin.bones()[bone]);check(pose!=null,name+": missing captured bone "+skin.bones()[bone]);
                    CartLegClearance.accumulate(skin,bone,pose,vertices);
                }
                var indices=skin.triangles();
                for(int i=0;i<indices.length;i+=3) {
                    var triangle=triangles[face++];
                    for(int j=0;j<3;j++) System.arraycopy(vertices,indices[i+j]*3,triangle,j*3,3);
                }
            }
            var source=CartLegClearanceData.WOOD.primitives();
            for(int i=0;i<source.length;i++) for(int j=0;j<source[i].length;j+=3) {
                double x=source[i][j],y=source[i][j+1],z=source[i][j+2];var p=primitives[i];
                p[j]=cart.m00()*x+cart.m10()*y+cart.m20()*z+cart.m30();
                p[j+1]=cart.m01()*x+cart.m11()*y+cart.m21()*z+cart.m31();
                p[j+2]=cart.m02()*x+cart.m12()*y+cart.m22()*z+cart.m32();
            }
        }
    }
    private static Matrix4f matrix(String[] fields,int start) {
        check(fields.length==start+16,"captured matrix has exactly 16 column-major values");
        var values=new float[16];
        for(int i=0;i<16;i++) {values[i]=Float.parseFloat(fields[start+i]);check(Float.isFinite(values[i]),"finite captured matrix");}
        return new Matrix4f().set(values);
    }
    private static List<Replay> captures(Path path) throws Exception {
        var cases=new ArrayList<Replay>();Replay current=null;
        for(String line:Files.readAllLines(path)) {
            if(line.isBlank() || line.startsWith("#")) continue;
            String[] fields=line.split(",",-1);
            switch(fields[0]) {
                case "case" -> {check(current==null && fields.length==4,"nested/malformed replay case");
                    check(fields[2].equals("0") || fields[2].equals("1"),"captured sex must be exact");
                    current=new Replay(fields[1],fields[2].equals("1"),Double.parseDouble(fields[3]));}
                case "cart" -> {check(current!=null && current.cart==null,"duplicate/orphan cart matrix");current.cart=matrix(fields,1);}
                case "bone" -> {check(current!=null && current.bones.putIfAbsent(fields[1],matrix(fields,2))==null,"duplicate/orphan bone");}
                case "end" -> {check(current!=null && current.cart!=null && Double.isFinite(current.expected),"incomplete replay case");cases.add(current);current=null;}
                default -> throw new AssertionError("Unknown replay row "+fields[0]);
            }
        }
        check(current==null && !cases.isEmpty(),"unterminated/empty replay");return cases;
    }
    private static final class Solver {
        double[] low=new double[512],high=new double[512];
        final double[] out=new double[2];
        int count;
        double solve(Replay replay) {
            replay.rebuild();count=0;
            for(var triangle:replay.triangles) for(var primitive:replay.primitives)
                if(CartLegClearance.intervalWithinDomain(triangle,primitive,.001,-.030,.030,out)) {
                    if(count==low.length) {low=Arrays.copyOf(low,count*2);high=Arrays.copyOf(high,count*2);}
                    low[count]=out[0];high[count++]=out[1];
                }
            return CartLegClearance.choose(low,high,count,-.030,.030);
        }
    }
    private static void replay(Path path) throws Exception {
        var cases=captures(path);var solver=new Solver();int positives=0,neutrals=0,maxTriangles=0,maxRanges=0;
        for(var capture:cases) {
            double selected=solver.solve(capture);maxRanges=Math.max(maxRanges,solver.count);maxTriangles=Math.max(maxTriangles,capture.triangles.length);
            close(selected,capture.expected,3e-6,capture.name+": independent captured-pose nearest shift");
            if(capture.expected==0) {neutrals++;close(selected,0,0,capture.name+": clear control stays exactly neutral");}
            else {
                positives++;check(selected!=0,capture.name+": positive contact requires a fit");
                var fitted=new Matrix4f(capture.cart).m30(capture.cart.m30()+(float)selected);
                check(CartLegClearance.withinFootprint(fitted),capture.name+": calibrated nonzero fit leaves the native footprint");
            }
            for(float shift:new float[]{-.5f,.5f}) {
                var escaped=new Matrix4f(capture.cart).m30(capture.cart.m30()+shift);
                check(!CartLegClearance.withinFootprint(escaped),capture.name+": huge lateral shift bypasses footprint gate");
            }
            check(!CartLegClearance.withinFootprint(new Matrix4f(capture.cart).m30(Float.NaN)),capture.name+": nonfinite fitted transform rejected");
            for(int i=0;i<solver.count;i++) check(selected<solver.low[i] || selected>solver.high[i],capture.name+": selected fit still forbidden");
            // Physically move body -X as the cart moves +X; independently check
            // the solved pose, not only membership in the precomputed ranges.
            for(var triangle:capture.triangles) {
                var moved=translated(triangle,-selected,0,0);
                for(var primitive:capture.primitives) if(CartLegClearance.interval(moved,primitive,.001,solver.out))
                    check(solver.out[0]>0 || solver.out[1]<0,capture.name+": post-fit body/cart margin still intersects");
            }
        }
        check(positives>0 && neutrals>0,"replay needs contact positives and clear controls");
        check(cases.stream().anyMatch(c->c.female) && cases.stream().anyMatch(c->!c.female),"both source rigs replayed");
        for(int i=0;i<40;i++) check(Double.isFinite(solver.solve(cases.get(i%cases.size()))),"warmup fit finite");
        var times=new long[60];long total=0;double checksum=0;
        for(int i=0;i<times.length;i++) {
            long start=System.nanoTime();checksum+=solver.solve(cases.get(i%cases.size()));times[i]=System.nanoTime()-start;total+=times[i];
        }
        Arrays.sort(times);check(Double.isFinite(checksum),"benchmark work remains observable");
        System.out.printf(java.util.Locale.ROOT,
            "CART_LEG_CLEARANCE_REPLAY cases=%d positives=%d neutral=%d maxTriangles=%d primitives=%d maxRanges=%d warmup=40 measured=60 meanMs=%.3f p95Ms=%.3f%n",
            cases.size(),positives,neutrals,maxTriangles,CartLegClearanceData.WOOD.primitives().length,maxRanges,total/60e6,times[56]/1e6);
        System.out.println("Replay scope: headless source skin accumulation, cart transform and SAT/choose; excludes footprint gating, native slot guards, live IK coupling, garment GPU palettes and render upload.");
    }
    public static void main(String[] args) throws Exception {
        tetrahedra();triangles();domainWrapper();choices();guards();footprints();
        Path fixture=args.length>0?Path.of(args[0]):Path.of(System.getProperty("pz.test.project","."),"JavaPatches/tests/fixtures/cart-leg-clearance.csv");
        replay(fixture);System.out.println("CART_LEG_CLEARANCE_PASS");
    }
}
