package net.alexredby.cartlab;

import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Patch;

/** Offline provenance/schema checks; never starts the game or creates a player. */
public final class ImpactWatchChecks {
    static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
    static Object call(String name,Class<?>[] types,Object... args)throws Exception {
        Method method=Main.class.getDeclaredMethod(name,types);method.setAccessible(true);
        return method.invoke(null,args);
    }
    public static void main(String[] args)throws Exception {
        check(Main.impactOrigin(List.of("zombie.iso.IsoMovingObject.checkHitWall")).equals("native-checkHitWall"),"native provenance missing");
        check(Main.impactOrigin(List.of("zombie.iso.IsoMovingObject.checkHitWall","net.alexredby.cartlab.Main.wallEvent"))
            .equals("injected-cartLabWallEvent"),"injected call falsely natural during native update");
        check(Main.impactOrigin(List.of("other.IsoMovingObject.checkHitWall")).equals("other"),"class suffix spoofed native origin");
        check(Main.impactOrigin(List.of("zombie.iso.IsoMovingObject.postupdate")).equals("other"),"generic update falsely natural");
        check(Main.impactOrigin(List.of("zombie.iso.IsoMovingObject.checkHitWallExtra")).equals("other"),"method prefix spoofed native origin");
        Main.observeImpact(null,null,"collideWithWall"); // disabled guard must not touch any game object
        check(Main.impactReceipts().equals("[]"),"disabled watch recorded a receipt");
        var patch=Main.ImpactEventReceipt.class.getAnnotation(Patch.class);
        check(patch.strictMatch() && patch.className().equals("zombie.characters.action.ActionContext")
            && patch.methodName().equals("reportEvent"),"hook scope changed");
        var target=zombie.characters.action.ActionContext.class.getDeclaredMethod("reportEvent",String.class,String.class);
        check(target.getReturnType()==void.class,"native event overload changed");
        var advice=Main.ImpactEventReceipt.class.getDeclaredMethod("exit",zombie.characters.action.ActionContext.class,String.class,String.class);
        check(advice.isAnnotationPresent(Patch.OnExit.class),"event receipt must follow native reportEvent");
        @SuppressWarnings("unchecked") var fields=(Map<String,Object>)call("impactFields",new Class<?>[]{zombie.characters.IsoPlayer.class},new Object[]{null});
        for(String key:List.of("timeMs","state","action","run","sprint","ignore","getup","hit","knocked","ragdoll",
            "primary","secondary","dir","wallType","collidedN","collidedS","collidedE","collidedW","collideType",
            "naturalEvents","injectedEvents","otherEvents","origin")) check(fields.containsKey(key),"missing field "+key);
        check(fields.get("primary").equals(-1) && fields.get("secondary").equals(-1),"bare actor requires no item");
        var escaped=new LinkedHashMap<String,Object>();escaped.put("text","quote\" slash\\ line\n");escaped.put("count",2);escaped.put("flag",true);
        System.out.println("IMPACT_JSON_CHECK "+call("impactJson",new Class<?>[]{Map.class},escaped));
        String fingerprint=(String)call("classFingerprint",new Class<?>[]{Class.class},zombie.iso.IsoMovingObject.class);
        check(fingerprint.matches("[0-9a-f]{64}"),"native jar source fingerprint unavailable");
        System.out.println("CART_IMPACT_WATCH_CHECK_PASS (exact provenance, injected precedence, disabled guard, native overload, bare schema, JSON, source fingerprint)");
    }
}
