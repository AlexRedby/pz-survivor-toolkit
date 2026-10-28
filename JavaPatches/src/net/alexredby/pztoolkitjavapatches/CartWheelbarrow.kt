package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.inventory.InventoryItem

/** Geometry of the two supported wheelbarrows in their original native mesh coordinates. */
internal class CartWheelbarrow
private constructor(
    private val model: String,
    private val centerX: Float,
    private val centerY: Float,
    private val centerZ: Float,
    private val radius: Float,
    private val halfWidth: Float,
    private val axle: Double,
    private val lateral: Double,
    private val front: Double,
    private val fastFront: Double,
    private val heldScale: Float,
    private val held: Matrix4f,
    private val meshHash: String,
    private val vertices: Int,
    private val wheelStart: Int,
    private val wheelEnd: Int,
) {
    companion object {
        // The wood pose is the shipped calibration. Metal uses its measured native idle attachment,
        // its relaxed side grip, and the same cylindrical .008 floor support.
        @JvmField
        val WOOD =
            CartWheelbarrow(
                "WheelbarrowWood",
                -6.642862e-6f,
                -.0041269097f,
                -.0010569958f,
                .001062454f,
                .00024333253f,
                1.0084944326,
                .00984276836,
                1.26,
                1.62,
                76.5f,
                Matrix4f()
                    .set(
                        76.5f,
                        -3.9394883e-5f,
                        -1.4673389e-5f,
                        0f,
                        2.8023098e-5f,
                        20.771942f,
                        73.62592f,
                        0f,
                        -2.4333809e-5f,
                        -73.625916f,
                        20.771938f,
                        0f,
                        -.0060535767f,
                        .097179376f,
                        -.34652624f,
                        1f,
                    ),
                "0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948",
                8116,
                0,
                1114,
            )
        @JvmField
        val METAL =
            CartWheelbarrow(
                "WheelbarrowMetal",
                -23.54235f,
                -11.737464f,
                .78115034f,
                12.154752f,
                3.7870514f,
                1.002699624,
                -.001741625,
                1.36,
                1.78,
                .0091743395f,
                Matrix4f()
                    .set(
                        .0091743395f,
                        -4.611793e-9f,
                        -2.036815e-9f,
                        0f,
                        2.9182563e-9f,
                        .008961861f,
                        -.0019630573f,
                        0f,
                        3.3606993e-9f,
                        .001963058f,
                        .008961861f,
                        0f,
                        .21714664f,
                        .22316784f,
                        -.6985083f,
                        1f,
                    ),
                "34c9a265bfacdd9235f9094fc7ae158fe5a50d73d6d12b0acc73e007dbecd932",
                3688,
                2135,
                2995,
            )

        @JvmStatic
        fun forModel(model: String?): CartWheelbarrow? =
            when (model) {
                "WheelbarrowWood" -> WOOD
                "WheelbarrowMetal" -> METAL
                else -> null
            }

        @JvmStatic
        fun forType(type: String?): CartWheelbarrow? =
            when (type) {
                "SaucedWheelbarrow.WheelbarrowWood" -> WOOD
                "SaucedWheelbarrow.WheelbarrowMetal" -> METAL
                else -> null
            }

        @JvmStatic
        fun forItem(item: InventoryItem?): CartWheelbarrow? =
            if (item == null) null else forType(item.getFullType())
    }

    fun model(): String = model

    // Match the authored pose to the handles after all three ground supports are seated.
    fun pickupHingeDegrees(): Float = if (this === METAL) 65f else 60f

    fun pickupLowering(): Float = if (this === METAL) .08f else .03f

    // Preserve the accepted grounded pickup position while the lifted metal grips settle alongside
    // the body.
    fun pickupStanceBack(): Float = if (this === METAL) .076406125f else .06f

    fun handleLoweringDegrees(): Float = if (this === METAL) 11.3f else 7.9f

    fun neutralAdvance(): Float = if (this === METAL) .10f else .05f

    // Keep the neutral metal grips beside the thighs; native fast strides need their own measured
    // clearance.
    fun motionShift(pressure: Float, gaitShift: Float): Float =
        CartSteeringMath.woodenShift(pressure, gaitShift) * (if (this === METAL) 1.15f else 1f)

    fun centerX(): Float = centerX

    fun centerY(): Float = centerY

    fun centerZ(): Float = centerZ

    fun radius(): Float = radius

    fun halfWidth(): Float = halfWidth

    fun axle(): Double = axle

    fun lateral(): Double = lateral

    fun front(): Double = front

    fun fastFront(): Double = fastFront

    fun worldRadius(): Double = radius * heldScale.toDouble() * 1.5

    fun held(out: Matrix4f?): Matrix4f = (out ?: throw NullPointerException()).set(held)

    fun center(out: Vector3f?): Vector3f =
        (out ?: throw NullPointerException()).set(centerX, centerY, centerZ)

    fun meshHash(): String = meshHash

    fun vertices(): Int = vertices

    fun wheelVertex(index: Int): Boolean = index >= wheelStart && index < wheelEnd
}
