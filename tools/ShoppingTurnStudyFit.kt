import java.nio.file.Files
import java.nio.file.Path
import java.util.HashMap
import net.alexredby.pztoolkitjavapatches.CartGrip
import net.alexredby.pztoolkitjavapatches.CartShopping
import net.alexredby.pztoolkitjavapatches.CartShoppingStance
import net.alexredby.pztoolkitjavapatches.CartShoppingWheelMesh
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.core.skinnedmodel.model.SkinningData

/** Offline study: use the production shopping geometry and grip without launching the game. */
object ShoppingTurnStudyFit {
    private fun matrix(values: List<String>, offset: Int) =
        Matrix4f().set(FloatArray(16) { values[offset + it].toFloat() })

    private fun json(m: Matrix4f) = FloatArray(16).also { m.get(it) }.joinToString(",", "[", "]")

    @JvmStatic
    fun main(args: Array<String>) {
        val lines = Files.readAllLines(Path.of(args[1]))
        val names = lines[0].split(',')
        val parents = lines[1].split(',').map(String::toInt)
        val indices =
            HashMap<String, Int>().apply { names.forEachIndexed { i, name -> put(name, i) } }
        val offsets = names.map { org.lwjgl.util.vector.Matrix4f() }
        val actor = SkinningData(HashMap(), offsets, offsets, offsets, parents, indices)
        fun poses(line: String): Pair<Double, Array<Matrix4f>> {
            val cells = line.split(',')
            require(cells.size == 1 + 16 * names.size)
            return cells[0].toDouble() to Array(names.size) { matrix(cells, 1 + 16 * it) }
        }
        val identity = Matrix4f()
        if (args[0] == "geometry") {
            val (_, seed) = poses(lines[2])
            val cart = CartShopping.held(Matrix4f()) ?: error("Missing held cart geometry")
            require(CartShoppingStance.apply(seed, actor, false, identity, cart, 1f))
            val rear = Vector3f()
            for (point in CartShoppingWheelMesh.CENTERS.take(2)) rear.add(
                point[0],
                point[1],
                point[2],
            )
            cart.transformPosition(rear.mul(.5f))
            Files.writeString(
                Path.of(args[2]),
                "{\"cart\":${json(cart)},\"rear\":[${rear.x},${rear.y},${rear.z}]}",
            )
            return
        }
        require(args[0] == "fit")
        val cart = matrix(Files.readString(Path.of(args[3])).trim().split(','), 0)
        var maxContact = 0f
        var maxLength = 0f
        val output = StringBuilder("[")
        lines.drop(2).forEachIndexed { row, line ->
            val (time, pose) = poses(line)
            val original = pose.map(::Matrix4f)
            require(CartGrip.grip(pose, actor, "ShoppingCartModel", false, identity, cart)) {
                "Production grip refused study frame $row"
            }
            for (side in listOf("L", "R")) {
                val ids =
                    listOf("UpperArm", "Forearm", "Hand").map {
                        indices.getValue("Bip01_${side}_$it")
                    }
                fun at(i: Int, before: Boolean = false) =
                    (if (before) original[i] else pose[i]).getTranslation(Vector3f())
                for (link in 0..1) maxLength =
                    maxOf(
                        maxLength,
                        kotlin.math.abs(
                            at(ids[link]).distance(at(ids[link + 1])) -
                                at(ids[link], true).distance(at(ids[link + 1], true)),
                        ),
                    )
                val grip = CartGrip.grasp(false, "ShoppingCartModel")
                val palm =
                    pose[ids[2]].transformPosition(Vector3f(grip.palmX(), 0f, grip.palmDepth()))
                val station = Vector3f()
                require(CartGrip.handle("ShoppingCartModel", side == "L", station))
                cart.transformPosition(station)
                maxContact = maxOf(maxContact, palm.distance(station))
            }
            for (i in names.indices) if (
                !names[i].contains("_UpperArm") &&
                    !names[i].contains("_Forearm") &&
                    !names[i].contains("_Hand") &&
                    !names[i].contains("_Finger")
            )
                require(pose[i] == original[i]) { "Grip changed unrelated bone ${names[i]}" }
            if (row > 0) output.append(',')
            output.append("{\"time\":$time,\"bones\":{")
            names.forEachIndexed { i, name ->
                if (i > 0) output.append(',')
                output.append('"').append(name).append("\":").append(json(pose[i]))
            }
            output.append("}}")
        }
        output.append(']')
        require(maxContact < 2e-5 && maxLength < 2e-5)
        Files.writeString(Path.of(args[2]), output)
        println(
            "SHOPPING_STUDY_GRIP_PASS frames=${lines.size - 2} contact=$maxContact armLength=$maxLength",
        )
    }
}
