package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.WeakHashMap;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.VertexBufferObject;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.core.skinnedmodel.shader.ShaderManager;

/** Draw each calibrated wheel separately without changing its shared mesh. */
public final class CartWheelSpin {
    // shortcut: source vertex ordering is calibrated to this exact Workshop mesh; a changed mesh falls back to native drawing.

    static final int WHEEL_VERTICES=1114, VERTICES=8116, STRIDE=32;
    static final float CENTER_X=-6.642862e-6f, CENTER_Y=-.0041269097f, CENTER_Z=-.0010569958f;
    static final float RADIUS=.001062454f;
    static final double WORLD_RADIUS=RADIUS*76.5*1.5;
    private static final WeakHashMap<ModelInstanceRenderData, Double> phases=new WeakHashMap<>();
    private record Mesh(CartWheelbarrow profile, int[][] runs) {}
    private static final WeakHashMap<VertexBufferObject, Mesh> meshes=new WeakHashMap<>();
    private record Pose(double x, double y, double forwardX, double forwardY, double pitch, double radius) {}
    private record Wheel(CartWheelbarrow profile, double phase, Pose pose) {}
    // Cosmetic continuity follows the exact item while it moves between world and hands.
    private static final WeakHashMap<InventoryItem, Wheel> wheels=new WeakHashMap<>();
    private static final Matrix4f wheelTransform=new Matrix4f();
    private static boolean errorLogged;

    static double advance(double phase, double acceptedTravel) {
        return advance(CartWheelbarrow.WOOD,phase,acceptedTravel);
    }

    static double advance(CartWheelbarrow profile, double phase, double acceptedTravel) {
        if(profile==null || !Double.isFinite(acceptedTravel) || Math.abs(acceptedTravel)>1) return phase;
        return Math.IEEEremainder(phase-acceptedTravel/profile.worldRadius(),Math.PI*2);
    }

    public static synchronized double itemPhase(InventoryItem item) {
        var wheel=wheels.get(item);
        return wheel==null || wheel.profile!=CartWheelbarrow.forItem(item)?0:wheel.phase;
    }

    private static Pose pose(CartWheelbarrow profile, float x, float y, float angle, Matrix4f cart) {
        if(profile==null || !Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(angle) || cart==null || !cart.isFinite()) return null;
        var center=cart.transformPosition(profile.center(new Vector3f()));
        var axle=cart.getColumn(0,new Vector3f());
        if(axle.lengthSquared()<1e-12f) return null;
        axle.normalize();
        var up=new Vector3f(0,1,0).fma(-axle.y,axle);
        if(up.lengthSquared()<1e-8f) return null;
        up.normalize();
        var radial=cart.getColumn(1,new Vector3f());
        double pitch=Math.atan2(radial.dot(new Vector3f(axle).cross(up)),radial.dot(up));
        double c=Math.cos(angle),s=Math.sin(angle);
        double sideX=-(c*axle.x+s*axle.z),sideY=-s*axle.x+c*axle.z;
        double length=Math.hypot(sideX,sideY);
        if(length<1e-6) return null;
        return new Pose(x-1.5*(c*center.x+s*center.z),y-1.5*s*center.x+1.5*c*center.z,
            -sideY/length,sideX/length,pitch,radial.length()*profile.radius()*1.5);
    }

    public static synchronized double follow(InventoryItem item, float x, float y, float angle, Matrix4f cart) {
        var profile=CartWheelbarrow.forItem(item);
        if(profile==null) return Double.NaN;
        var pose=pose(profile,x,y,angle,cart);
        if(pose==null) return Double.NaN;
        var previous=wheels.get(item);
        if(previous!=null && previous.profile!=profile) previous=null;
        double phase=previous==null?0:previous.phase;
        if(previous!=null) {
            double fx=previous.pose.forwardX+pose.forwardX,fy=previous.pose.forwardY+pose.forwardY;
            double length=Math.hypot(fx,fy);
            double dx=pose.x-previous.pose.x,dy=pose.y-previous.pose.y;
            if(length>1e-6 && Math.hypot(dx,dy)<=1 && pose.radius>1e-6 && previous.pose.radius>1e-6)
                phase-=(dx*fx+dy*fy)/length/((pose.radius+previous.pose.radius)*.5);
            // Rotation is relative to the cart; lifting its handles must leave a stationary tire still.
            phase=Math.IEEEremainder(phase-Math.IEEEremainder(pose.pitch-previous.pose.pitch,Math.PI*2),Math.PI*2);
        }
        wheels.put(item,new Wheel(profile,phase,pose));
        return phase;
    }

    static synchronized void record(InventoryItem item, float x, float y, float angle, Matrix4f cart, double phase) {
        var profile=CartWheelbarrow.forItem(item);
        var pose=pose(profile,x,y,angle,cart);
        if(profile!=null && pose!=null && Double.isFinite(phase)) wheels.put(item,new Wheel(profile,phase,pose));
    }

    /** Snapshot the simulation angle; NaN clears recycled render data before eligibility checks. */
    public static synchronized void prepare(ModelSlotRenderData slot, double phase) {
        for(var data:slot.modelData) {
            phases.remove(data);
            if(Double.isFinite(phase) && data.modelInstance!=null && data.modelInstance.modelScript!=null
                && CartWheelbarrow.forModel(data.modelInstance.modelScript.getName())!=null) phases.put(data,phase);
        }
    }

    private static synchronized Double phase(ModelInstanceRenderData data) { return phases.get(data); }

    static Matrix4f transform(Matrix4f cart, double phase, Matrix4f out) {
        return transform(CartWheelbarrow.WOOD,cart,phase,out);
    }

    static Matrix4f transform(CartWheelbarrow profile, Matrix4f cart, double phase, Matrix4f out) {
        return out.set(cart).transpose().translate(profile.centerX(),profile.centerY(),profile.centerZ())
            .rotateX((float)phase).translate(-profile.centerX(),-profile.centerY(),-profile.centerZ()).transpose();
    }

    /** Each run is [first index, index count, wheel flag]; every triangle belongs to one part. */
    static int[][] ranges(int[] elements) {
        return ranges(CartWheelbarrow.WOOD,elements);
    }

    static int[][] ranges(CartWheelbarrow profile, int[] elements) {
        if(profile==null || elements==null || elements.length==0 || elements.length%3!=0) return null;
        var result=new ArrayList<int[]>();
        int[] run=null;
        boolean wheel=false, body=false;
        for(int i=0;i<elements.length;i+=3) {
            int part=profile.wheelVertex(elements[i])?1:0;
            for(int j=0;j<3;j++) if(elements[i+j]<0 || elements[i+j]>=profile.vertices()
                || (profile.wheelVertex(elements[i+j])?1:0)!=part) return null;
            if(part==1) wheel=true; else body=true;
            if(run==null || run[2]!=part) { run=new int[]{i,0,part};result.add(run); }
            run[1]+=3;
        }
        return wheel && body?result.toArray(int[][]::new):null;
    }

    private static Object field(VertexBufferObject buffer, String name) throws ReflectiveOperationException {
        Field field=VertexBufferObject.class.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(buffer);
    }

    private static int[][] mesh(CartWheelbarrow profile, VertexBufferObject buffer) {
        var cached=meshes.get(buffer);
        if(cached!=null) return cached.profile==profile?cached.runs:null;
        int[][] runs=null;
        boolean ready=false;
        int binding=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        try {
            var handle=(VertexBufferObject.Vbo)field(buffer,"handle");
            var format=(VertexBufferObject.VertexFormat)field(buffer,"vertexFormat");
            int position=format.indexOf(VertexBufferObject.VertexType.VertexArray);
            if(handle==null || handle.vboId<=0 || handle.eboId<=0) return null;
            ready=true;
            if(format.getStride()!=STRIDE || position<0 || format.getElement(position).byteOffset!=0) return null;
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,handle.vboId);
            int bytes=GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER,GL15.GL_BUFFER_SIZE);
            if(bytes!=profile.vertices()*STRIDE) return null;
            ByteBuffer raw=BufferUtils.createByteBuffer(bytes);
            GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER,0,raw);
            byte[] vertices=new byte[bytes];raw.get(vertices);
            if(!profile.meshHash().equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(vertices)))) return null;
            var elements=(int[])field(buffer,"elements");
            if(elements!=null && elements.length==handle.numElements) runs=ranges(profile,elements);
            if(runs!=null) System.out.println("[PZToolkitJavaPatches] Wheelbarrow wheel mesh verified: "+profile.model()+" "+runs.length+" original index ranges");
        } catch(Exception error) {
            ready=true;
            if(!errorLogged) { errorLogged=true;System.err.println("[PZToolkitJavaPatches] Wheelbarrow wheel disabled: "+error); }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,binding);
            if(ready) meshes.put(buffer,new Mesh(profile,runs));
            if(ready && runs==null && !errorLogged) {
                errorLogged=true;
                System.err.println("[PZToolkitJavaPatches] Wheelbarrow wheel disabled: source mesh does not match calibrated geometry");
            }
        }
        return runs;
    }

    /** OnEnter for Model.DrawSolid; true skips the original draw after rendering both parts. */
    public static boolean render(Model model, ModelSlotRenderData slot, ModelInstanceRenderData data) {
        if(CartShoppingWheels.render(model,slot,data))return true;
        if(!(slot.character instanceof IsoPlayer) || data.modelInstance==null
            || data.modelInstance.modelScript==null
            || CartWheelbarrow.forModel(data.modelInstance.modelScript.getName())==null
            || data.modelInstance.parent==null || !model.isStatic || model.mesh==null || model.mesh.vb==null) return false;
        Double phase=phase(data);
        if(phase==null) return false;
        var profile=CartWheelbarrow.forModel(data.modelInstance.modelScript.getName());
        int[][] runs=mesh(profile,model.mesh.vb);
        if(runs==null) return false;
        Shader shader=ShaderManager.instance.getOrCreateShader("basicEffect",true,false);
        if(shader==null || shader.getID()==0) return false;
        shader.Start();
        try {
            shader.startCharacter(slot,data);
            shader.setScale(slot.finalScale);
            return draw(profile,model.mesh.vb,shader,data.xfrm,phase,true);
        } finally {
            shader.setScale(1);
            shader.End();
        }
    }

    /** Draw within the caller's native shader/material scope. */
    public static boolean draw(VertexBufferObject buffer, Shader shader, Matrix4f cart, double phase, boolean transpose) {
        return draw(CartWheelbarrow.WOOD,buffer,shader,cart,phase,transpose);
    }

    static boolean draw(CartWheelbarrow profile, VertexBufferObject buffer, Shader shader, Matrix4f cart, double phase, boolean transpose) {
        if(profile==null || buffer==null || shader==null || cart==null || !cart.isFinite() || !Double.isFinite(phase)) return false;
        int[][] runs=mesh(profile,buffer);
        if(runs==null) return false;
        int oldArray=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        int oldElements=GL11.glGetInteger(GL15.GL_ELEMENT_ARRAY_BUFFER_BINDING);
        if(transpose) transform(profile,cart,phase,wheelTransform);
        else wheelTransform.set(cart).translate(profile.centerX(),profile.centerY(),profile.centerZ())
            .rotateX((float)phase).translate(-profile.centerX(),-profile.centerY(),-profile.centerZ());
        try {
            boolean blend=buffer.BeginDraw(shader);
            try {
                for(int[] run:runs) {
                    shader.setTransformMatrix(run[2]==1?wheelTransform:cart,transpose);
                    GL11.glDrawElements(GL11.GL_TRIANGLES,run[1],GL11.GL_UNSIGNED_INT,(long)run[0]*Integer.BYTES);
                }
            } finally {
                shader.setTransformMatrix(cart,transpose);
                buffer.FinishDraw(shader,blend);
            }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,oldArray);
            GL15.glBindBuffer(GL15.GL_ELEMENT_ARRAY_BUFFER,oldElements);
        }
        return true;
    }

    private CartWheelSpin() {}
}
