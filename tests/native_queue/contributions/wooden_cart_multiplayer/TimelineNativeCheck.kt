import java.nio.ByteBuffer
import java.nio.file.Path
import net.alexredby.cartlab.Multiplayer
import sun.misc.Unsafe
import zombie.characters.IsoPlayer

object TimelineNativeCheck {
    class Owner : IsoPlayer(null, null, 0, 0, 0) {
        override fun getUsername() = "client1"

        override fun getOnlineID(): Short = 7

        override fun isLocalPlayer() = true
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        for (name in
            arrayOf(
                "zombie.characters.IsoGameCharacter",
                "zombie.network.packets.VariableSyncPacket",
                "zombie.network.packets.character.PlayerPacket",
                "zombie.network.fields.character.Prediction",
                "net.alexredby.pztoolkitjavapatches.CartMotionSync",
                "zombie.network.packets.service.TimeSyncPacket",
                "zombie.GameTime",
                "zombie.iso.PlayerCamera",
            )) Class.forName(name)
        val unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
                as Unsafe
        val owner = unsafe.allocateInstance(Owner::class.java) as Owner
        val pan =
            unsafe.allocateInstance(zombie.iso.PlayerCamera::class.java) as zombie.iso.PlayerCamera
        pan.offX = 10f
        pan.offY = 20f
        pan.rightClickX = 30f
        pan.rightClickY = 40f
        check(pan.getOffX() == 40f && pan.getOffY() == 60f) { "Native pan offsets not consumed" }
        zombie.network.GameServer.server = true
        zombie.ZomboidFileSystem.instance.setCacheDir(
            Path.of(System.getenv("PZ_CART_RUNTIME_FILE")).parent.parent.toString(),
        )
        val raw = "1,42,3,0,0,0,1,0,0,0,0,0,0"
        Multiplayer.timelineVariable(owner, "publish", "ToolkitCartPose", raw)
        val packet = zombie.network.packets.VariableSyncPacket()
        packet.key = "ToolkitCartPose"
        packet.value = raw
        packet.varType = zombie.network.packets.VariableSyncPacket.VariableType.String
        packet.player.setID(7.toShort())
        zombie.network.fields.character.PlayerID::class
            .java
            .getDeclaredField("player")
            .apply { isAccessible = true }
            .set(packet.player, owner)
        packet.write(zombie.core.network.ByteBufferWriter(ByteBuffer.allocate(1024)))
        Multiplayer.timelineStop()
        Multiplayer.timelineVariable(owner, "publish", "ToolkitCartPose", raw)
        val thread =
            Multiplayer::class
                .java
                .getDeclaredField("timelineThread")
                .apply { isAccessible = true }
                .get(null) as Thread
        thread.join(2000)
        check(!thread.isAlive) { "Timeline writer failed to drain" }
        println("TIMELINE_NATIVE_PASS")
    }
}
