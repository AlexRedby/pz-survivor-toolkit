package net.alexredby.drivingperf;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import org.joml.Vector3f;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.pathfind.VehiclePoly;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.VehicleScript;
import zombie.vehicles.BaseVehicle;

/** Seed-only observations of already loaded state. Never loads cells or changes actors/vehicles. */
public final class ApproachClearance {
    static final double CLEARANCE=.25, EPS=1e-7, MAX_COORDINATE=1_000_000;
    private static final int MAX_VEHICLES=8192;
    private ApproachClearance() { }

    record Dimensions(double halfWidth,double halfLength,double extentX,double extentZ,
                      double offsetX,double offsetZ,double modelScale) { }
    record Corridor(double minX,double maxX,double minY,double maxY) { }
    record Coverage(boolean startReady,boolean complete,double checkedDistance) { }
    record Footprint(double x1,double y1,double x2,double y2,double x3,double y3,double x4,double y4) {
        double[] coordinates() { return new double[]{x1,y1,x2,y2,x3,y3,x4,y4}; }
    }
    record VehicleSnapshot(long sqlId,int nativeId,String script,double z,Footprint polygon) { }
    record Assessment(String status,String reason,Coverage coverage,Corridor corridor,
                      List<VehicleSnapshot> blockers,int knownVehicles,int malformedVehicles) { }
    @FunctionalInterface interface LoadedFloor { boolean loaded(int x,int y); }

    static boolean finite(double value) { return Double.isFinite(value) && Math.abs(value)<=MAX_COORDINATE; }
    static Dimensions dimensions(double ex,double ey,double ez,double ox,double oy,double oz,double scale) {
        if (!finite(ex) || !finite(ey) || !finite(ez) || !finite(ox) || !finite(oy) || !finite(oz)
                || !finite(scale) || ex<=0 || ey<=0 || ez<=0 || ex>32 || ey>32 || ez>32 || scale<=0
                || Math.abs(ox)>16 || Math.abs(oy)>16 || Math.abs(oz)>16)
            throw new IllegalArgumentException("Malformed SportsCar dimensions");
        // VehiclePoly.init uses getExtents/centerOfMassOffset directly, then getWorldPos;
        // getWorldPos adds the physics world offset and performs no modelScale multiplication.
        // Abs(offset) makes the north-facing swept box conservative about its origin.
        return new Dimensions(ex/2+Math.abs(ox),ez/2+Math.abs(oz),ex,ez,ox,oz,scale);
    }
    /** Exact saved bounds must match the factory-validated current script bounds. */
    static boolean receiptDimensions(Dimensions current,double halfWidth,double halfLength,double clearance) {
        return current!=null && finite(current.halfWidth) && finite(current.halfLength)
                && current.halfWidth>0 && current.halfLength>0
                && finite(halfWidth) && halfWidth>0 && finite(halfLength) && halfLength>0
                && finite(clearance) && clearance>0
                && Double.compare(current.halfWidth,halfWidth)==0
                && Double.compare(current.halfLength,halfLength)==0
                && Double.compare(CLEARANCE,clearance)==0;
    }
    static Dimensions dimensions(VehicleScript script) {
        if (script==null) throw new IllegalArgumentException("Missing SportsCar script");
        Vector3f extents=script.getExtents(),offset=script.getCenterOfMassOffset();
        if (extents==null || offset==null) throw new IllegalArgumentException("Missing SportsCar dimensions");
        return dimensions(extents.x,extents.y,extents.z,offset.x,offset.y,offset.z,script.getModelScale());
    }
    /** Suspension may move the physics origin fractionally around floor zero. */
    static boolean northGround(double forwardX,double forwardY,double distance,int squareZ,double actualZ) {
        if (!Double.isFinite(forwardX) || !Double.isFinite(forwardY) || !Double.isFinite(distance)
                || distance<10 || distance>500 || squareZ!=0 || !Double.isFinite(actualZ) || Math.abs(actualZ)>.5)
            return false;
        double horizontalLength=Math.hypot(forwardX,forwardY);
        if (horizontalLength<.99 || horizontalLength>1.01 || forwardY>=0) return false;
        // Bound the accumulated geometric mismatch, rather than accepting a fixed angle
        // whose lateral error grows with the approach length. This spends .05 of .25 clearance.
        return Math.abs(forwardX/horizontalLength)*distance<=.05;
    }
    static boolean northGroundWithinClearance(double forwardX,double forwardY,double distance,
                                              int squareZ,double actualZ,Dimensions size) {
        if (!northGround(forwardX,forwardY,distance,squareZ,actualZ) || size==null
                || !finite(size.halfWidth) || !finite(size.halfLength) || size.halfWidth<=0 || size.halfLength<=0)
            return false;
        double length=Math.hypot(forwardX,forwardY);
        double sine=Math.abs(forwardX/length),cosine=Math.min(1,-forwardY/length);
        // For either box axis, rotating any corner moves it by at most this sum.
        // The small north-facing angle also makes longitudinal course error <= distance*sine.
        double cornerShift=(size.halfWidth+size.halfLength)*(sine+1-cosine);
        double courseShift=distance*sine;
        // Lua separately requires each initial position error < .05 tile. Reserve that
        // budget here, rather than spending the full clearance on course alone.
        return .05+courseShift+cornerShift<=CLEARANCE;
    }
    static Corridor northCorridor(double x,double y,double distance,Dimensions size,double clearance) {
        if (!finite(x) || !finite(y) || !Double.isFinite(distance) || distance<0 || distance>500
                || size==null || !finite(size.halfWidth) || !finite(size.halfLength)
                || size.halfWidth<=0 || size.halfLength<=0 || !finite(clearance) || clearance<0 || clearance>2)
            throw new IllegalArgumentException("Malformed north corridor");
        Corridor box=new Corridor(x-size.halfWidth-clearance,x+size.halfWidth+clearance,
                y-distance-size.halfLength-clearance,y+size.halfLength+clearance);
        if (!valid(box)) throw new IllegalArgumentException("Malformed corridor bounds");
        return box;
    }
    static boolean valid(Corridor box) {
        return box!=null && finite(box.minX) && finite(box.maxX) && finite(box.minY) && finite(box.maxY)
                && box.minX<box.maxX && box.minY<box.maxY;
    }
    static boolean valid(Footprint footprint) {
        if (footprint==null) return false;
        double[] p=footprint.coordinates();
        for (double value:p) if (!finite(value)) return false;
        double sign=0;
        for (int i=0;i<4;i++) {
            int a=2*i,b=2*((i+1)%4),c=2*((i+2)%4);
            double cross=(p[b]-p[a])*(p[c+1]-p[b+1])-(p[b+1]-p[a+1])*(p[c]-p[b]);
            if (Math.abs(cross)<=EPS || sign!=0 && Math.signum(cross)!=sign) return false;
            sign=Math.signum(cross);
        }
        return true;
    }
    static boolean separated(double[] p,Corridor box,double ax,double ay) {
        double pMin=Double.POSITIVE_INFINITY,pMax=Double.NEGATIVE_INFINITY;
        for (int i=0;i<8;i+=2) {
            double projection=p[i]*ax+p[i+1]*ay;
            pMin=Math.min(pMin,projection); pMax=Math.max(pMax,projection);
        }
        double c1=box.minX*ax+box.minY*ay,c2=box.maxX*ax+box.minY*ay;
        double c3=box.maxX*ax+box.maxY*ay,c4=box.minX*ax+box.maxY*ay;
        double bMin=Math.min(Math.min(c1,c2),Math.min(c3,c4)),bMax=Math.max(Math.max(c1,c2),Math.max(c3,c4));
        // Touching is blocked. Scale tolerance with the axis to keep its units consistent.
        double tolerance=EPS*Math.hypot(ax,ay);
        return pMax<bMin-tolerance || bMax<pMin-tolerance;
    }
    static boolean overlaps(Footprint footprint,Corridor box) {
        if (!valid(footprint) || !valid(box)) throw new IllegalArgumentException("Malformed overlap geometry");
        double[] p=footprint.coordinates();
        if (separated(p,box,1,0) || separated(p,box,0,1)) return false;
        for (int i=0;i<4;i++) {
            int a=2*i,b=2*((i+1)%4);
            if (separated(p,box,-(p[b+1]-p[a+1]),p[b]-p[a])) return false;
        }
        return true;
    }

    /** Contiguous fully loaded swept footprint; null/unloaded tail never triggers a load. */
    static Coverage coverage(Corridor box,double requestedDistance,LoadedFloor floors) {
        if (!valid(box) || !Double.isFinite(requestedDistance) || requestedDistance<0 || requestedDistance>500 || floors==null)
            throw new IllegalArgumentException("Malformed coverage request");
        if (requestedDistance>=box.maxY-box.minY) throw new IllegalArgumentException("Missing initial footprint extent");
        int minX=(int)Math.floor(box.minX),maxX=(int)Math.floor(box.maxX);
        int minY=(int)Math.floor(box.minY),maxY=(int)Math.floor(box.maxY);
        double startFront=box.minY+requestedDistance;
        int startMinY=(int)Math.floor(startFront);
        for (int row=maxY;row>=minY;row--) {
            boolean loaded=true;
            for (int column=minX;column<=maxX;column++) if (!floors.loaded(column,row)) { loaded=false; break; }
            if (!loaded) {
                if (row>=startMinY) return new Coverage(false,false,0);
                double prefix=Math.max(0,Math.min(requestedDistance,startFront-(row+1)));
                return new Coverage(true,false,prefix);
            }
        }
        return new Coverage(true,true,requestedDistance);
    }
    private static String polygonKey(VehicleSnapshot value) { return String.valueOf(value.polygon); }
    private static final Comparator<VehicleSnapshot> ORDER=Comparator.comparingLong(VehicleSnapshot::sqlId)
            .thenComparingInt(VehicleSnapshot::nativeId).thenComparing(v -> v.script==null ? "" : v.script)
            .thenComparingDouble(VehicleSnapshot::z).thenComparing(ApproachClearance::polygonKey);
    static boolean valid(VehicleSnapshot vehicle) {
        return vehicle!=null && vehicle.script!=null && vehicle.script.matches("[A-Za-z0-9_.-]{1,160}")
                && finite(vehicle.z) && valid(vehicle.polygon);
    }
    /** Pure verdict. Known blockers take precedence even beyond the loaded-floor prefix. */
    static Assessment assess(Corridor box,Coverage coverage,List<VehicleSnapshot> input) {
        if (!valid(box) || coverage==null || input==null || !Double.isFinite(coverage.checkedDistance)
                || coverage.checkedDistance<0 || coverage.checkedDistance>500
                || !coverage.startReady && (coverage.complete || coverage.checkedDistance!=0))
            throw new IllegalArgumentException("Malformed assessment input");
        List<VehicleSnapshot> vehicles=new ArrayList<>(); int malformed=0;
        for (VehicleSnapshot vehicle:input) { if (vehicle==null) malformed++; else vehicles.add(vehicle); }
        vehicles.sort(ORDER);
        List<VehicleSnapshot> blockers=new ArrayList<>();
        for (VehicleSnapshot vehicle:vehicles) {
            if (!valid(vehicle)) malformed++;
            else if (overlaps(vehicle.polygon,box)) blockers.add(vehicle);
        }
        String status,reason;
        if (!blockers.isEmpty()) { status="blocked"; reason="known_vehicle_overlap"; }
        else if (malformed>0) { status="unknown"; reason="malformed_loaded_vehicle"; }
        else if (!coverage.startReady) { status="unknown"; reason="start_footprint_unloaded"; }
        else if (coverage.checkedDistance<=EPS) { status="unknown"; reason="no_contiguous_loaded_prefix"; }
        else { status="clear_loaded"; reason=coverage.complete ? "known_loaded_vehicles_clear" : "unvisited_tail_unqualified"; }
        return new Assessment(status,reason,coverage,box,List.copyOf(blockers),input.size(),malformed);
    }
    private static Assessment unknown(String reason,Corridor box) {
        return new Assessment("unknown",reason,new Coverage(false,false,0),box,List.of(),0,0);
    }
    private static VehicleSnapshot snapshot(BaseVehicle vehicle) {
        VehiclePoly p=vehicle.getPoly();
        Footprint polygon=p==null ? null : new Footprint(p.x1,p.y1,p.x2,p.y2,p.x3,p.y3,p.x4,p.y4);
        return new VehicleSnapshot(vehicle.getSqlId(),vehicle.getId(),vehicle.getScriptName(),vehicle.getZ(),polygon);
    }
    private static String number(double value) { return String.format(Locale.ROOT,"%.6f",value); }
    private static void log(double x,double y,double requested,Dimensions size,Assessment result) {
        System.out.println("[DRIVING_PERF_WORLD] APPROACH_CANDIDATE x="+number(x)+" y="+number(y)
                +" requested_distance="+number(requested)+" checked_distance="+number(result.coverage.checkedDistance)
                +" coverage="+(result.coverage.complete ? "complete" : "partial")+" status="+result.status
                +" blocker_count="+result.blockers.size()+" known_vehicle_count="+result.knownVehicles
                +" malformed_vehicle_count="+result.malformedVehicles+" reason="+result.reason
                +" target_script=Base.SportsCar target_half_width="+number(size==null ? 0 : size.halfWidth)
                +" target_half_length="+number(size==null ? 0 : size.halfLength)+" clearance="+number(CLEARANCE)
                +" target_extents_x="+number(size==null ? 0 : size.extentX)+" target_extents_z="+number(size==null ? 0 : size.extentZ)
                +" target_offset_x="+number(size==null ? 0 : size.offsetX)+" target_offset_z="+number(size==null ? 0 : size.offsetZ)
                +" model_scale_metadata="+number(size==null ? 0 : size.modelScale)+" source=live-loaded-vehicle-polygons");
        for (VehicleSnapshot blocker:result.blockers) {
            double[] p=blocker.polygon.coordinates(); StringBuilder geometry=new StringBuilder();
            for (int i=0;i<8;i+=2) geometry.append(" x").append(i/2+1).append('=').append(number(p[i]))
                    .append(" y").append(i/2+1).append('=').append(number(p[i+1]));
            System.out.println("[DRIVING_PERF_WORLD] APPROACH_BLOCKER candidate_x="+number(x)+" candidate_y="+number(y)
                    +" sql_id="+blocker.sqlId+" native_id="+blocker.nativeId+" script="+blocker.script
                    +" z="+number(blocker.z)+geometry);
        }
    }
    private static KahluaTable table(double requested,Dimensions size,Assessment value) {
        if (LuaManager.platform==null) throw new IllegalStateException("Lua platform unavailable");
        KahluaTable out=LuaManager.platform.newTable();
        out.rawset("status",value.status); out.rawset("reason",value.reason);
        out.rawset("coverage",value.coverage.complete ? "complete" : "partial");
        out.rawset("checked_distance",value.coverage.checkedDistance); out.rawset("requested_distance",requested);
        out.rawset("blocker_count",(double)value.blockers.size()); out.rawset("known_vehicle_count",(double)value.knownVehicles);
        out.rawset("malformed_vehicle_count",(double)value.malformedVehicles); out.rawset("start_ready",value.coverage.startReady);
        out.rawset("target_script","Base.SportsCar"); out.rawset("clearance",CLEARANCE);
        out.rawset("target_half_width",size==null ? 0.0 : size.halfWidth); out.rawset("target_half_length",size==null ? 0.0 : size.halfLength);
        if (value.corridor!=null) {
            out.rawset("min_x",value.corridor.minX); out.rawset("max_x",value.corridor.maxX);
            out.rawset("min_y",value.corridor.minY); out.rawset("max_y",value.corridor.maxY);
        }
        KahluaTable blockers=LuaManager.platform.newTable(); int index=0;
        for (VehicleSnapshot blocker:value.blockers) {
            KahluaTable row=LuaManager.platform.newTable();
            row.rawset("sql_id",(double)blocker.sqlId); row.rawset("native_id",(double)blocker.nativeId);
            row.rawset("script",blocker.script); row.rawset("z",blocker.z);
            double[] p=blocker.polygon.coordinates();
            for (int i=0;i<8;i+=2) { row.rawset("x"+(i/2+1),p[i]); row.rawset("y"+(i/2+1),p[i+1]); }
            blockers.rawset((double)++index,row);
        }
        out.rawset("blockers",blockers); return out;
    }
    public static KahluaTable assess(double x,double y,double requestedDistance) {
        Dimensions size=null; Corridor box=null; Assessment result;
        try {
            if (!finite(x) || !finite(y) || !Double.isFinite(requestedDistance) || requestedDistance<10 || requestedDistance>500)
                throw new IllegalArgumentException("invalid_request");
            IsoCell cell=IsoWorld.instance==null ? null : IsoWorld.instance.getCell();
            if (cell==null || ScriptManager.instance==null) throw new IllegalStateException("missing_world_or_scripts");
            VehicleScript script=ScriptManager.instance.getVehicle("Base.SportsCar");
            if (script==null) throw new IllegalStateException("missing_sports_car_script");
            size=dimensions(script);
            box=northCorridor(x,y,requestedDistance,size,CLEARANCE);
            Coverage covered=coverage(box,requestedDistance,(gx,gy) -> {
                var square=cell.getGridSquare(gx,gy,0);
                return square!=null && square.getFloor()!=null;
            });
            var loaded=cell.getVehicles();
            if (loaded==null || loaded.size()>MAX_VEHICLES) throw new IllegalStateException("missing_or_unbounded_vehicle_set");
            List<VehicleSnapshot> snapshots=new ArrayList<>();
            for (BaseVehicle vehicle:loaded) {
                try { snapshots.add(vehicle==null ? null : snapshot(vehicle)); }
                catch (RuntimeException malformed) { snapshots.add(new VehicleSnapshot(-1,-1,null,Double.NaN,null)); }
            }
            result=assess(box,covered,snapshots);
        } catch (RuntimeException failure) {
            result=unknown("native_data_unavailable_"+failure.getClass().getSimpleName(),box);
        }
        log(x,y,requestedDistance,size,result);
        return table(requestedDistance,size,result);
    }
}
