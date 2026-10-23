package net.alexredby.javapatchfixture

import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoZombie
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.NetworkVariables
import zombie.network.packets.character.ZombiePacket

object Main {
    @JvmStatic
    @LuaMethod(name = "javaPatchesProbe", global = true)
    fun probe(): String {
        val patched = java.lang.Boolean.getBoolean("pz.javapatches.expected")
        val z = IsoZombie(IsoWorld.instance.currentCell)
        val packet = ZombiePacket()
        packet.target = -1
        packet.walkType = NetworkVariables.WalkType.values()[0]
        packet.realState = NetworkVariables.ZombieState.values()[0]
        packet.realX = z.getX()
        packet.realY = z.getY()
        packet.realZ = z.getZ().toInt().toByte()
        for (encoded in shortArrayOf(0, 550, 850, 1200)) {
            z.setOwner(null)
            z.setSpeedMod(0.25f)
            packet.speedMod = encoded
            z.getNetworkCharacterAI().parse(packet)
            val expected = if (patched) encoded / 1000.0f else encoded.toFloat()
            if (z.getSpeedMod() != expected) throw AssertionError("remote decode " + z.getSpeedMod() + " expected " + expected)
            z.setOwner(GameClient.connection)
            z.setSpeedMod(0.25f)
            z.getNetworkCharacterAI().parse(packet)
            if (z.getSpeedMod() != 0.25f) throw AssertionError("owned zombie changed")
            if (packet.speedMod != encoded) throw AssertionError("wire packet changed")
        }
        return "packet850=" + (if (patched) "0.85" else "850") + ", four values checked, owned unchanged, packet unchanged"
    }

    @JvmStatic
    @LuaMethod(name = "javaPatchesObserve", global = true)
    fun observe(): String {
        val list = IsoWorld.instance.currentCell.getZombieList()
        var remote = 0
        var owned = 0
        var max = 0f
        var i = 0
        while (i < list.size) {
            val z = list[i]
            if (z.isRemoteZombie()) remote++ else owned++
            max = Math.max(max, z.getSpeedMod())
            i++
        }
        return "remote=" + remote + ",owned=" + owned + ",maxSpeed=" + max
    }
}
