package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.inventory.InventoryItem;

/** Geometry of the two supported wheelbarrows in their original native mesh coordinates. */
final class CartWheelbarrow {
    // The wood pose is the shipped calibration. Metal uses its measured native idle attachment,
    // its relaxed side grip, and the same cylindrical .008 floor support.
    static final CartWheelbarrow WOOD=new CartWheelbarrow("WheelbarrowWood",
        -6.642862e-6f,-.0041269097f,-.0010569958f,.001062454f,.00024333253f,
        1.0084944326,.00984276836,1.26,1.62,76.5f,
        new Matrix4f().set(76.5f,-3.9394883e-5f,-1.4673389e-5f,0,2.8023098e-5f,20.771942f,73.62592f,0,
            -2.4333809e-5f,-73.625916f,20.771938f,0,-.0060535767f,.097179376f,-.34652624f,1),
        "0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948",8116,0,1114);
    static final CartWheelbarrow METAL=new CartWheelbarrow("WheelbarrowMetal",
        -23.54235f,-11.737464f,.78115034f,12.154752f,3.7870514f,
        1.002699624,-.001741625,1.36,1.78,.0091743395f,
        new Matrix4f().set(.0091743395f,-4.611793e-9f,-2.036815e-9f,0,2.9182563e-9f,.008961861f,-.0019630573f,0,
            3.3606993e-9f,.001963058f,.008961861f,0,.21714664f,.22316784f,-.6985083f,1),
        "34c9a265bfacdd9235f9094fc7ae158fe5a50d73d6d12b0acc73e007dbecd932",3688,2135,2995);

    private final String model,meshHash;
    private final float centerX,centerY,centerZ,radius,halfWidth,heldScale;
    private final double axle,lateral,front,fastFront;
    private final Matrix4f held;
    private final int vertices,wheelStart,wheelEnd;

    private CartWheelbarrow(String model,float centerX,float centerY,float centerZ,float radius,float halfWidth,
        double axle,double lateral,double front,double fastFront,float heldScale,Matrix4f held,String meshHash,
        int vertices,int wheelStart,int wheelEnd) {
        this.model=model;this.centerX=centerX;this.centerY=centerY;this.centerZ=centerZ;
        this.radius=radius;this.halfWidth=halfWidth;this.axle=axle;this.lateral=lateral;
        this.front=front;this.fastFront=fastFront;this.heldScale=heldScale;this.held=held;
        this.meshHash=meshHash;this.vertices=vertices;this.wheelStart=wheelStart;this.wheelEnd=wheelEnd;
    }
    static CartWheelbarrow forModel(String model) {
        if(model==null) return null;
        return switch(model) {case "WheelbarrowWood" -> WOOD;case "WheelbarrowMetal" -> METAL;default -> null;};
    }
    static CartWheelbarrow forType(String type) {
        if(type==null) return null;
        return switch(type) {
            case "SaucedWheelbarrow.WheelbarrowWood" -> WOOD;
            case "SaucedWheelbarrow.WheelbarrowMetal" -> METAL;
            default -> null;
        };
    }
    static CartWheelbarrow forItem(InventoryItem item) {return item==null?null:forType(item.getFullType());}
    String model() {return model;}
    // Match the authored pose to the handles after all three ground supports are seated.
    float pickupHingeDegrees() {return this==METAL?65:60;}
    float pickupLowering() {return this==METAL?.08f:.03f;}
    // Preserve the accepted grounded pickup position while the lifted metal grips settle alongside the body.
    float pickupStanceBack() {return this==METAL?.076406125f:.06f;}
    float handleLoweringDegrees() {return this==METAL?11.3f:7.9f;}
    float neutralAdvance() {return this==METAL?.10f:.05f;}
    // Keep the neutral metal grips beside the thighs; native fast strides need their own measured clearance.
    float motionShift(float pressure,float gaitShift) {
        return CartSteeringMath.woodenShift(pressure,gaitShift)*(this==METAL?1.15f:1);
    }
    float centerX() {return centerX;}
    float centerY() {return centerY;}
    float centerZ() {return centerZ;}
    float radius() {return radius;}
    float halfWidth() {return halfWidth;}
    double axle() {return axle;}
    double lateral() {return lateral;}
    double front() {return front;}
    double fastFront() {return fastFront;}
    double worldRadius() {return radius*(double)heldScale*1.5;}
    Matrix4f held(Matrix4f out) {return out.set(held);}
    Vector3f center(Vector3f out) {return out.set(centerX,centerY,centerZ);}
    String meshHash() {return meshHash;}
    int vertices() {return vertices;}
    boolean wheelVertex(int index) {return index>=wheelStart && index<wheelEnd;}
}
