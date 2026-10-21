package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.MessageDigest;
import java.util.*;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import zombie.inventory.InventoryItem;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.*;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.core.skinnedmodel.shader.ShaderManager;

/** Cosmetic four-wheel motion follows the exact rendered cart, without changing shared GPU geometry. */
public final class CartShoppingWheels {
    static final class Frame {
        final InventoryItem item;
        final Matrix4f[] relative;
        final double[] phases,casters;
        Frame(InventoryItem item,Matrix4f[] relative,double[] phases,double[] casters) {
            this.item=item;this.relative=relative;this.phases=phases;this.casters=casters;
        }
    }
    private static final class State {
        final double[] phase=new double[4],x=new double[4],y=new double[4],heading=new double[4];
        final double[] pivotX=new double[2],pivotY=new double[2],caster=new double[2];
        double x0,y0;long time;
    }
    private record Mesh(int[][] runs) {}
    private record Point(int x,int y,int z) implements Comparable<Point> {
        Point(float x,float y,float z){this(Float.floatToIntBits(x),Float.floatToIntBits(y),Float.floatToIntBits(z));}
        public int compareTo(Point b){int c=Integer.compareUnsigned(x,b.x);if(c==0)c=Integer.compareUnsigned(y,b.y);return c==0?Integer.compareUnsigned(z,b.z):c;}
    }
    private record Part(int part,int vertex) {}
    private static final WeakHashMap<InventoryItem,State> states=new WeakHashMap<>();
    private static final WeakHashMap<ModelInstanceRenderData,Frame> frames=new WeakHashMap<>();
    private static final WeakHashMap<VertexBufferObject,Mesh> meshes=new WeakHashMap<>();
    private static final Matrix4f BASIS=CartShopping.worldModel(new Matrix4f());
    private static final Matrix4f NORMAL=normalization();
    private static boolean errorLogged;

    private static Matrix4f normalization() {
        var b=new Matrix4f(BASIS).setTranslation(0,0,0);
        var w=new Matrix4f().m00(CartShoppingWheelMesh.NORMALIZE[0]).m10(CartShoppingWheelMesh.NORMALIZE[1])
            .m01(CartShoppingWheelMesh.NORMALIZE[2]).m11(CartShoppingWheelMesh.NORMALIZE[3]);
        return new Matrix4f(b).invert().mul(w).mul(b);
    }
    private static Vector3f point(float[] v){return new Vector3f(v[0],v[1],v[2]);}
    private static Matrix4f around(Vector3f c,Matrix4f linear) {
        return new Matrix4f().translation(c).mul(linear).translate(-c.x,-c.y,-c.z);
    }
    private static double[] world(float x,float y,float angle,Vector3f p) {
        double c=Math.cos(angle),s=Math.sin(angle);
        return new double[]{x-1.5*(c*p.x+s*p.z),y+1.5*(-s*p.x+c*p.z)};
    }
    private static double wrap(double v){return Math.IEEEremainder(v,Math.PI*2);}
    static synchronized Frame follow(InventoryItem item,float x,float y,float angle,Matrix4f cart,long now) {
        if(!CartShopping.item(item) || !Float.isFinite(x+y+angle) || cart==null || !cart.isFinite() || now<0)return null;
        var residual=new Matrix4f(cart).mul(new Matrix4f(BASIS).invert());
        if(!CartTransitionMath.blend(residual,residual,0,new Matrix4f()))return null;
        double radius=CartShoppingWheelMesh.RADIUS*residual.getColumn(0,new Vector3f()).length()*1.5;
        if(!Double.isFinite(radius) || radius<1e-6)return null;
        var axle=cart.transformDirection(new Vector3f(0,0,1)).normalize();
        var forward=new Vector3f(0,1,0).cross(axle).normalize();
        if(!axle.isFinite() || !forward.isFinite())return null;
        double[] direction=world(0,0,angle,forward);
        double heading=Math.atan2(direction[1],direction[0]);
        var old=states.get(item);boolean reset=old==null || Math.hypot(x-old.x0,y-old.y0)>1;
        var next=new State();next.x0=x;next.y0=y;next.time=now;
        double dt=old==null?0:Math.max(0,Math.min(.1,(now-old.time)/1e9));
        var transforms=new Matrix4f[7];transforms[0]=new Matrix4f();
        var inverse=new Matrix4f(cart).invert();
        for(int i=0;i<4;i++) {
            var raw=point(CartShoppingWheelMesh.CENTERS[i]);var center=cart.transformPosition(raw,new Vector3f());
            Matrix4f swivel=new Matrix4f();double rollingHeading=heading;
            if(i>=2) {
                int front=i-2;var pivot=cart.transformPosition(point(CartShoppingWheelMesh.SWIVELS[front]),new Vector3f());
                double[] p=world(x,y,angle,pivot);next.pivotX[front]=p[0];next.pivotY[front]=p[1];
                rollingHeading=reset?heading+(old==null?0:old.caster[front]):old.heading[i];
                if(!reset) {
                    double dx=p[0]-old.pivotX[front],dy=p[1]-old.pivotY[front],distance=Math.hypot(dx,dy);
                    if(distance>1e-7 && distance<=1) {
                        double change=wrap(Math.atan2(dy,dx)-rollingHeading)*(1-Math.exp(-distance/.035));
                        rollingHeading+=Math.max(-10*dt,Math.min(10*dt,change));
                    }
                }
                next.caster[front]=wrap(rollingHeading-heading);
                swivel=around(pivot,new Matrix4f().rotationY((float)next.caster[front]));
            }
            center=swivel.transformPosition(center);double[] p=world(x,y,angle,center);
            next.x[i]=p[0];next.y[i]=p[1];next.heading[i]=rollingHeading;
            double phase=old==null?0:old.phase[i];
            if(!reset) {
                double dx=p[0]-old.x[i],dy=p[1]-old.y[i];
                double fx=Math.cos(old.heading[i])+Math.cos(rollingHeading),fy=Math.sin(old.heading[i])+Math.sin(rollingHeading);
                double length=Math.hypot(fx,fy);
                if(Math.hypot(dx,dy)<=1 && length>1e-6)phase=wrap(phase-(dx*fx+dy*fy)/length/radius);
            }
            next.phase[i]=phase;
            // Round the imported ellipse once, then rotate a rigid tire around its own axle.
            var baseCenter=cart.transformPosition(raw,new Vector3f());
            var roll=around(baseCenter,new Matrix4f().rotation((float)phase,axle));
            var shape=around(raw,NORMAL);
            var tire=new Matrix4f(swivel).mul(roll).mul(cart).mul(shape);
            transforms[i+1]=new Matrix4f(inverse).mul(tire);
            if(i>=2)transforms[i+3]=new Matrix4f(inverse).mul(swivel).mul(cart);
        }
        states.put(item,next);
        return new Frame(item,transforms,next.phase.clone(),next.caster.clone());
    }
    static Frame follow(InventoryItem item,float x,float y,float angle,Matrix4f cart) {
        return follow(item,x,y,angle,cart,System.nanoTime());
    }
    static synchronized void clear(ModelSlotRenderData slot){for(var data:slot.modelData)frames.remove(data);}
    static synchronized void prepare(ModelSlotRenderData slot,InventoryItem item,ModelInstanceRenderData data,Matrix4f cart) {
        frames.remove(data);var frame=follow(item,slot.x,slot.y,slot.animPlayerAngle,cart);
        if(frame!=null)frames.put(data,frame);
    }
    static synchronized Frame frame(ModelInstanceRenderData data){return frames.get(data);}
    static Matrix4f transform(Matrix4f cart,Frame frame,int part,boolean transpose,Matrix4f out) {
        if(transpose)return out.set(cart).transpose().mul(frame.relative[part]).transpose();
        return out.set(cart).mul(frame.relative[part]);
    }

    static String pointHash(float[] vertices) {
        try {
            var points=new TreeSet<Point>();
            for(int i=0;i<vertices.length;i+=3)points.add(new Point(vertices[i],vertices[i+1],vertices[i+2]));
            var digest=MessageDigest.getInstance("SHA-256");var bytes=ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN);
            for(var p:points){bytes.clear();bytes.putInt(p.x).putInt(p.y).putInt(p.z);digest.update(bytes.array());}
            return HexFormat.of().formatHex(digest.digest());
        }catch(Exception error){throw new IllegalStateException(error);}
    }
    private static long edge(int a,int b){return ((long)Math.min(a,b)<<32)|(Math.max(a,b)&0xffffffffL);}
    static boolean topology(float[][] points,int[][] polygons,List<int[]> triangles) {
        if(points==null || polygons==null || triangles==null)return false;
        for(var p:points)if(p==null || p.length!=3 || !Float.isFinite(p[0]+p[1]+p[2]))return false;
        for(var p:polygons){if(p==null || p.length<3)return false;for(int v:p)if(v<0 || v>=points.length)return false;}
        @SuppressWarnings("unchecked") var edges=(Map<Long,Integer>[])new Map<?,?>[polygons.length];
        int[] counts=new int[polygons.length];
        for(int i=0;i<edges.length;i++)edges[i]=new HashMap<>();
        for(int[] triangle:triangles) {
            if(triangle==null || triangle.length!=3)return false;
            for(int v:triangle)if(v<0 || v>=points.length)return false;
            if(triangle[0]==triangle[1] || triangle[1]==triangle[2] || triangle[2]==triangle[0])return false;
            int face=-1;
            for(int i=0;i<polygons.length;i++) {
                int found=0;for(int v:triangle){for(int p:polygons[i])if(v==p){found++;break;}}
                if(found==3){if(face!=-1)return false;face=i;}
            }
            if(face<0)return false;
            var a=point(points[triangle[0]]);var b=point(points[triangle[1]]);var c=point(points[triangle[2]]);
            if(b.sub(a).cross(c.sub(a)).lengthSquared()<1e-16f)return false;
            counts[face]++;
            for(int i=0;i<3;i++)edges[face].merge(edge(triangle[i],triangle[(i+1)%3]),1,Integer::sum);
        }
        for(int i=0;i<polygons.length;i++) {
            if(counts[i]!=polygons[i].length-2)return false;
            var boundary=new HashSet<Long>();
            for(int j=0;j<polygons[i].length;j++)boundary.add(edge(polygons[i][j],polygons[i][(j+1)%polygons[i].length]));
            for(var e:edges[i].entrySet())if(e.getValue()!=(boundary.remove(e.getKey())?1:2))return false;
            if(!boundary.isEmpty())return false;
        }
        return true;
    }
    static int[][] partition(float[] vertices,int[] elements) {
        if(vertices==null || vertices.length%3!=0 || elements==null || elements.length%3!=0)return null;
        String hash=pointHash(vertices);int expected=-1;
        for(int i=0;i<CartShoppingWheelMesh.POSITION_HASHES.length;i++)if(CartShoppingWheelMesh.POSITION_HASHES[i].equals(hash))expected=CartShoppingWheelMesh.TRIANGLES[i]*3;
        if(expected!=elements.length)return null;
        var parts=new HashMap<Point,Part>();
        for(int p=0;p<CartShoppingWheelMesh.PART_POINTS.length;p++)for(int v=0;v<CartShoppingWheelMesh.PART_POINTS[p].length;v++) {
            var q=CartShoppingWheelMesh.PART_POINTS[p][v];if(parts.put(new Point(q[0],q[1],q[2]),new Part(p+1,v))!=null)return null;
        }
        Part[] ids=new Part[vertices.length/3];
        for(int v=0;v<ids.length;v++) {
            for(int j=0;j<3;j++)if(!Float.isFinite(vertices[v*3+j]))return null;
            ids[v]=parts.getOrDefault(new Point(vertices[v*3],vertices[v*3+1],vertices[v*3+2]),new Part(0,-1));
        }
        var triangles=new ArrayList<List<int[]>>();for(int i=0;i<6;i++)triangles.add(new ArrayList<>());
        var runs=new ArrayList<int[]>();int[] run=null;
        for(int i=0;i<elements.length;i+=3) {
            Part[] t=new Part[3];
            for(int j=0;j<3;j++){int v=elements[i+j];if(v<0 || v>=ids.length)return null;t[j]=ids[v];}
            int part=t[0].part;if(t[1].part!=part || t[2].part!=part)return null;
            if(part>0)triangles.get(part-1).add(new int[]{t[0].vertex,t[1].vertex,t[2].vertex});
            if(run==null || run[2]!=part){run=new int[]{i,0,part};runs.add(run);}run[1]+=3;
        }
        for(int i=0;i<6;i++)if(!topology(CartShoppingWheelMesh.PART_POINTS[i],CartShoppingWheelMesh.PART_FACES[i],triangles.get(i)))return null;
        return runs.toArray(int[][]::new);
    }
    private static Object field(VertexBufferObject buffer,String name)throws Exception {
        Field f=VertexBufferObject.class.getDeclaredField(name);f.setAccessible(true);return f.get(buffer);
    }
    private static int[][] mesh(VertexBufferObject buffer) {
        var cached=meshes.get(buffer);if(cached!=null)return cached.runs;
        int[][] runs=null;boolean ready=false;int binding=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        try {
            var h=(VertexBufferObject.Vbo)field(buffer,"handle");var format=(VertexBufferObject.VertexFormat)field(buffer,"vertexFormat");
            int pos=format.indexOf(VertexBufferObject.VertexType.VertexArray);
            if(h==null || h.vboId<=0 || h.eboId<=0)return null;ready=true;
            if(format.getStride()!=32 || pos<0 || format.getElement(pos).byteOffset!=0)return null;
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,h.vboId);int size=GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER,GL15.GL_BUFFER_SIZE);
            if(size<=0 || size%32!=0 || size>2_000_000)return null;
            var raw=BufferUtils.createByteBuffer(size);GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER,0,raw);
            float[] vertices=new float[size/32*3];for(int i=0;i<vertices.length/3;i++)for(int j=0;j<3;j++)vertices[i*3+j]=raw.getFloat(i*32+j*4);
            int[] elements=(int[])field(buffer,"elements");if(elements!=null && elements.length==h.numElements)runs=partition(vertices,elements);
            if(runs!=null)System.out.println("[PZToolkitJavaPatches] Shopping cart wheels verified: "+runs.length+" original index ranges");
        }catch(Exception error){if(!errorLogged){errorLogged=true;System.err.println("[PZToolkitJavaPatches] Shopping cart wheels disabled: "+error);}}
        finally{GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,binding);if(ready)meshes.put(buffer,new Mesh(runs));}
        return runs;
    }
    public static boolean render(Model model,ModelSlotRenderData slot,ModelInstanceRenderData data) {
        if(!(slot.character instanceof IsoPlayer) || data.modelInstance==null || data.modelInstance.modelScript==null || !CartShopping.model(data.modelInstance.modelScript.getName())
            || data.modelInstance.parent==null || !model.isStatic || model.mesh==null || model.mesh.vb==null)return false;
        var frame=frame(data);if(frame==null || mesh(model.mesh.vb)==null)return false;
        var shader=ShaderManager.instance.getOrCreateShader("basicEffect",true,false);if(shader==null || shader.getID()==0)return false;
        shader.Start();try{shader.startCharacter(slot,data);shader.setScale(slot.finalScale);return draw(model.mesh.vb,shader,data.xfrm,frame,true);}
        finally{shader.setScale(1);shader.End();}
    }
    static boolean draw(VertexBufferObject buffer,Shader shader,Matrix4f cart,Frame frame,boolean transpose) {
        if(buffer==null || shader==null || cart==null || !cart.isFinite() || frame==null)return false;
        int[][] runs=mesh(buffer);if(runs==null)return false;
        int array=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING),elements=GL11.glGetInteger(GL15.GL_ELEMENT_ARRAY_BUFFER_BINDING);
        var parts=new Matrix4f[7];for(int i=0;i<parts.length;i++)parts[i]=transform(cart,frame,i,transpose,new Matrix4f());
        try{boolean blend=buffer.BeginDraw(shader);try{for(int[] run:runs){shader.setTransformMatrix(parts[run[2]],transpose);GL11.glDrawElements(GL11.GL_TRIANGLES,run[1],GL11.GL_UNSIGNED_INT,(long)run[0]*4);}}
            finally{shader.setTransformMatrix(cart,transpose);buffer.FinishDraw(shader,blend);}}
        finally{GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,array);GL15.glBindBuffer(GL15.GL_ELEMENT_ARRAY_BUFFER,elements);}return true;
    }
    private CartShoppingWheels(){}
}
