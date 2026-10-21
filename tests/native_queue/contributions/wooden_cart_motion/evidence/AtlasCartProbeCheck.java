import java.io.*;
import java.lang.reflect.*;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.*;
import zombie.inventory.InventoryItem;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.core.skinnedmodel.model.*;

/** Native atlas state extraction and advice binding only; no native draw, process or GL context. */
public final class AtlasCartProbeCheck {
    static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    static Field field(Class<?> type,String name)throws Exception{var f=type.getDeclaredField(name);f.setAccessible(true);return f;}
    static Object get(Object object,String name)throws Exception{return field(object.getClass(),name).get(object);}
    static void set(Object object,String name,Object value)throws Exception{field(object.getClass(),name).set(object,value);}
    static final sun.misc.Unsafe UNSAFE;
    static {try{UNSAFE=(sun.misc.Unsafe)field(sun.misc.Unsafe.class,"theUnsafe").get(null);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    static <T>T allocate(Class<T> type)throws Exception{return type.cast(UNSAFE.allocateInstance(type));}
    static final class Cart extends InventoryItem {
        String type; IsoWorldInventoryObject world;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return type;}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
    }
    static Cart item(String type)throws Exception{
        var c=allocate(Cart.class);c.type=type;c.world=allocate(IsoWorldInventoryObject.class);c.setID(73);return c;
    }
    static WorldItemAtlas.ItemTexture texture(Matrix4f matrix)throws Exception{
        var texture=allocate(WorldItemAtlas.ItemTexture.class);
        var params=allocate(Class.forName("zombie.core.skinnedmodel.model.WorldItemAtlas$ItemParams"));
        var model=allocate(Model.class);model.name="native-shopping-mesh";
        set(params,"model",model);set(params,"transform",matrix);set(params,"angle",new Vector3f(4,5,6));set(texture,"itemParams",params);
        var entry=allocate(Class.forName("zombie.core.skinnedmodel.model.WorldItemAtlas$AtlasEntry"));
        set(entry,"renderMainOk",true);set(texture,"entry",entry);return texture;
    }
    static void draw(WorldItemAtlas.ItemTexture texture)throws Exception{ClearanceProbe.atlasDraw(texture,11,22,7.00475f,333,444,.4f);}
    public static void main(String[] args)throws Exception{
        var drawer=Class.forName("zombie.core.skinnedmodel.model.WorldItemModelDrawer");
        check(new ByteBuddy().redefine(drawer).visit(Advice.to(ClearanceProbe.AtlasContextCapture.class)
            .on(named("renderAtlasTexture").and(takesArguments(8)))).make().getBytes().length>0,"atlas context advice");
        check(new ByteBuddy().redefine(WorldItemAtlas.ItemTexture.class).visit(Advice.to(ClearanceProbe.AtlasDrawCapture.class)
            .on(named("render").and(takesArguments(9)))).make().getBytes().length>0,"atlas draw advice");
        var out=new StringWriter();var writer=new BufferedWriter(out);field(ClearanceProbe.class,"worldOutput").set(null,writer);
        var matrix=new Matrix4f().translation(9,8,7).rotateXYZ(.2f,.3f,.4f).scale(.002f,.003f,.1f);var expected=new Matrix4f(matrix);
        var texture=texture(matrix);var cart=item("SaucedCarts.ShoppingCart");cart.atlasTexture=texture;
        var previous=ClearanceProbe.beginAtlas(cart);check(previous==null,"dirty initial context");
        try {
            draw(texture);var row=out.toString();
            check(row.lines().count()==1 && row.contains("\"source\":\"WorldItemAtlas.ItemTexture.render-exit\"")
                && row.contains("\"placementSource\":\"ItemTexture.render-arguments\"")
                && row.contains("\"nativeModel\":\"native-shopping-mesh\"")
                && row.contains("\"x\":11.0,\"y\":22.0,\"z\":7.00475")
                && row.contains("\"screenX\":333.0,\"screenY\":444.0")
                && row.contains("\"angle\":[4.0,5.0,6.0]") && row.contains("\"alpha\":0.4"),"native fields/provenance lost: "+row);
            check(matrix.equals(expected),"native transform mutated");
            var nested=ClearanceProbe.beginAtlas(item("Base.Hammer"));
            try{draw(texture);check(out.toString().equals(row),"unrelated nested draw captured");}
            finally{ClearanceProbe.endAtlas(nested);}
            var other=texture(new Matrix4f());
            try{draw(other);throw new AssertionError("different texture accepted");}catch(IllegalStateException expectedError){}
            check(out.toString().equals(row),"mismatched texture emitted pose");
            set(get(texture,"entry"),"renderMainOk",false);draw(texture);check(out.toString().equals(row),"loading texture emitted pose");
            set(get(texture,"entry"),"renderMainOk",true);
            matrix.m00(Float.NaN);
            try{draw(texture);throw new AssertionError("NaN native matrix accepted");}catch(IllegalStateException expectedError){}
            check(out.toString().equals(row),"invalid matrix emitted pose");matrix.set(expected);
            draw(texture);check(out.toString().lines().count()==2,"nested context not restored");
        }finally{ClearanceProbe.endAtlas(previous);}
        var before=out.toString();draw(texture);check(out.toString().equals(before),"stale call-stack context leaked");
        field(ClearanceProbe.class,"worldOutput").set(null,null);previous=ClearanceProbe.beginAtlas(cart);
        try{draw(texture);}finally{ClearanceProbe.endAtlas(previous);}
        check(out.toString().equals(before),"capture after stop");
        System.out.println("ATLAS_CART_PROBE_CHECK_PASS (native nonuniform matrix, final placement, item/texture identity, readiness, nested scope, malformed rejection, no mutations, advice bindings)");
    }
}
