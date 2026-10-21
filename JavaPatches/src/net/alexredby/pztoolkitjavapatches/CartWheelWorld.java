package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Accessor;
import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.inventory.InventoryItem;

/** Carry the exact item's wheel angle into native world rendering without replacing its material setup. */
public final class CartWheelWorld {
    private record Snapshot(InventoryItem item, Model model, Matrix4f transform, double phase, CartShoppingWheels.Frame shopping) {}
    private record Draw(ItemModelRenderer renderer, InventoryItem item, ModelMesh mesh, Matrix4f transform, double phase, CartShoppingWheels.Frame shopping) {}
    public record Receipt(InventoryItem item, double phase, Matrix4fc cart) {}
    private static final WeakHashMap<ItemModelRenderer, Snapshot> snapshots = new WeakHashMap<>();
    private static final WeakHashMap<ItemModelRenderer, Receipt> receipts = new WeakHashMap<>();
    private static final ThreadLocal<Draw> drawing = new ThreadLocal<>();

    private static boolean worldCart(InventoryItem item) {
        return CartTransition.supported(item) && item.getWorldItem()!=null && item.getWorldItem().getItem()==item;
    }

    public static synchronized void snapshot(ItemModelRenderer renderer, InventoryItem item, Matrix4f transform) {
        snapshots.remove(renderer);
        receipts.remove(renderer);
        if(!worldCart(item) || transform==null || !transform.isFinite()) return;
        var model=Accessor.tryGet(renderer,"model",(Model)null);
        if(model!=null && model.isStatic)
            snapshots.put(renderer,new Snapshot(item,model,transform,Double.NaN,null));
    }

    static Matrix4f worldTransform(ItemModelRenderer renderer, Matrix4f transform, Matrix4f out) {
        return out.rotationXYZ((float)Math.toRadians(renderer.angle.x),(float)Math.toRadians(renderer.angle.y),
            (float)Math.toRadians(renderer.angle.z)).mul(transform);
    }

    /** renderMain assigns item rotation and model/world scale after init returns. */
    public static synchronized void ready(ItemModelRenderer renderer) {
        var snapshot=snapshots.get(renderer);
        if(snapshot==null) return;
        if(!worldCart(snapshot.item)) {clear(renderer);return;}
        var transform=worldTransform(renderer,snapshot.transform,new Matrix4f());
        if(!transform.isFinite()) {clear(renderer);return;}
        // Virtual actor angle PI gives the native world camera's +X/-Z tile projection.
        var shopping=CartShopping.item(snapshot.item)?CartShoppingWheels.follow(snapshot.item,renderer.x,renderer.y,(float)Math.PI,transform):null;
        double phase=shopping!=null?shopping.phases[0]:CartWheelSpin.follow(snapshot.item,renderer.x,renderer.y,(float)Math.PI,transform);
        if(Double.isFinite(phase)) snapshots.put(renderer,new Snapshot(snapshot.item,snapshot.model,snapshot.transform,phase,shopping));
        else clear(renderer);
    }

    public static synchronized void clear(ItemModelRenderer renderer) {snapshots.remove(renderer);receipts.remove(renderer);}

    /** Null until the current root pass actually completed the verified split draw. */
    public static synchronized Receipt rendered(ItemModelRenderer renderer) {return receipts.get(renderer);}

    private static synchronized void recorded(Draw draw) {
        receipts.put(draw.renderer,new Receipt(draw.item,draw.phase,new Matrix4f(draw.transform)));
    }

    private static synchronized void clearReceipt(ItemModelRenderer renderer) {receipts.remove(renderer);}

    private static synchronized Snapshot snapshot(ItemModelRenderer renderer) {return snapshots.get(renderer);}

    /** Every nested call masks the outer scope, including foreign models and weapon parts. */
    public static Object begin(ItemModelRenderer renderer, Model model, Matrix4f transform, boolean weaponPart) {
        var previous=drawing.get();
        var snapshot=snapshot(renderer);
        if(!weaponPart) clearReceipt(renderer);
        if(!weaponPart && snapshot!=null && snapshot.model==model && Double.isFinite(snapshot.phase)
            && model.mesh!=null && transform!=null && transform.isFinite())
            drawing.set(new Draw(renderer,snapshot.item,model.mesh,transform,snapshot.phase,snapshot.shopping));
        else drawing.remove();
        return previous;
    }

    public static void end(Object previous) {
        if(previous==null) drawing.remove();
        else drawing.set((Draw)previous);
    }

    public static boolean render(ModelMesh mesh, Shader shader) {
        var draw=drawing.get();
        if(draw==null || draw.mesh!=mesh || shader==null)return false;
        boolean rendered=draw.shopping!=null?CartShoppingWheels.draw(mesh.vb,shader,draw.transform,draw.shopping,false)
            :CartWheelSpin.draw(CartWheelbarrow.forItem(draw.item),mesh.vb,shader,draw.transform,draw.phase,false);
        if(!rendered)return false;
        recorded(draw);
        return true;
    }

    private CartWheelWorld() {}
}
