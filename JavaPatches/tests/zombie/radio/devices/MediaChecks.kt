package zombie.radio.devices

import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.util.ArrayList
import sun.misc.Unsafe
import zombie.GameTime
import zombie.core.raknet.UdpEngine
import zombie.iso.IsoGridSquare
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.radio.ZomboidRadio
import zombie.radio.media.MediaData

object MediaChecks {
    class Device : WaveSignalDevice {
        @JvmField var data: DeviceData? = null
        @JvmField var staticLines = 0
        override fun getDeviceData(): DeviceData? = data
        override fun setDeviceData(value: DeviceData?) { data = value }
        override fun getDelta(): Float = 0f
        override fun setDelta(value: Float) {}
        override fun getSquare(): IsoGridSquare? = null
        override fun getX(): Float = 0f
        override fun getY(): Float = 0f
        override fun getZ(): Float = 0f
        override fun HasPlayerInRange(): Boolean = false
        override fun AddDeviceText(text: String?, r: Float, g: Float, b: Float, guid: String?, codes: String?, distance: Int) {
            if (guid == null) staticLines++
        }
    }

    @JvmStatic
    fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    @JvmStatic
    fun device(media: MediaData): DeviceData {
        val parent = Device()
        val data = DeviceData(parent)
        parent.data = data
        data.isTelevision = true
        data.isTurnedOn = true
        data.mediaType = 1
        data.mediaIndex = media.getIndex()
        return data
    }

    @JvmStatic
    fun drainStopTail(data: DeviceData) {
        var i = 0
        while (i < 1000 && data.isStoppingMedia) { data.updateMediaPlaying(); i++ }
        require(!data.isStoppingMedia, "native stop tail did not finish")
    }

    @JvmStatic
    fun firstLine(data: DeviceData) {
        var i = 0
        while (i < 1000 && data.mediaLineIndex == 0) { data.updateMediaPlaying(); i++ }
        require(data.isPlayingMedia() && data.mediaLineIndex == 1,
            "restart failed to deliver the first native media line")
    }

    @JvmStatic
    fun restart(media: MediaData, patched: Boolean) {
        val data = device(media)
        data.StartPlayMedia()
        require(data.isPlayingMedia(), "initial native start")
        data.StopPlayMedia()
        require(!data.isPlayingMedia() && data.isStoppingMedia && data.playingMedia == null,
            "native stop state")
        data.StartPlayMedia()
        require(data.isPlayingMedia(), "native immediate restart")
        if (patched) {
            require(!data.isStoppingMedia, "woven patch left the old stop tail active")
            firstLine(data)
        } else {
            require(data.isStoppingMedia, "baseline did not retain the old stop tail")
            drainStopTail(data)
            require(!data.isPlayingMedia() && data.mediaLineIndex == 0,
                "baseline did not reproduce the silent restart loss")
        }
        require((data.parent as Device).staticLines > 0, "native TV media switch did not run")
    }

    @JvmStatic
    fun ordinaryPlayback(media: MediaData) {
        val data = device(media)
        data.StartPlayMedia()
        firstLine(data)
        val counter = data.lineCounter
        data.StartPlayMedia()
        require(data.mediaLineIndex == 1 && data.lineCounter == counter,
            "duplicate start reset the tape")
        var i = 0
        while (i < 2000 && data.isPlayingMedia()) { data.updateMediaPlaying(); i++ }
        require(!data.isPlayingMedia() && data.isStoppingMedia && data.mediaLineIndex == media.getLineCount(),
            "automatic end did not preserve native stopping behavior")
        drainStopTail(data)
        require(!data.isPlayingMedia(), "automatic end restarted the tape")
        data.StartPlayMedia()
        firstLine(data)
        data.StopPlayMedia()
        data.StopPlayMedia()
        require(!data.isPlayingMedia() && data.isStoppingMedia && data.playingMedia == null,
            "repeated stop lost the native stop state")
        drainStopTail(data)
        require(!data.isPlayingMedia(), "explicit stop restarted the tape")
    }

    @JvmStatic
    fun invalidStarts(media: MediaData) {
        for (mode in 0 until 3) {
            val data = device(media)
            data.StartPlayMedia()
            data.StopPlayMedia()
            if (mode == 0) data.isTurnedOn = false
            if (mode == 1) data.mediaIndex = -1
            if (mode == 2) data.mediaIndex = Short.MAX_VALUE
            data.StartPlayMedia()
            require(!data.isPlayingMedia() && data.isStoppingMedia,
                "invalid start changed native stopping state: " + mode)
        }
    }

    @JvmStatic
    fun standaloneGuard(media: MediaData) {
        val data = device(media)
        data.mediaType = -1 // Avoid starting the standalone sound engine in this state-only fixture.
        GameServer.server = false
        try {
            data.StartPlayMedia()
            firstLine(data)
            data.StopPlayMedia()
            require(data.isPlayingMedia() && data.isStoppingMedia && data.playingMedia == null,
                "native standalone stop state")
            data.StartPlayMedia()
            require(data.isStoppingMedia && data.playingMedia == null,
                "server patch cleared a standalone no-op start's stop tail")
            drainStopTail(data)
            require(!data.isPlayingMedia(), "standalone stop no longer finishes")
        } finally { GameServer.server = true }
    }

    @JvmStatic
    fun clientGuard(media: MediaData) {
        val data = device(media)
        data.StartPlayMedia()
        data.StopPlayMedia()
        data.isPlayingMedia = true // State received from a server; client Start must not modify it.
        GameClient.client = true
        GameServer.server = false
        val output = System.out
        try {
            PrintStream(ByteArrayOutputStream()).use { captured ->
                System.setOut(captured)
                // Native transmit catches the missing player/connection before any networking occurs.
                data.StartPlayMedia()
            }
        } finally {
            System.setOut(output)
            GameClient.client = false
            GameServer.server = true
        }
        require(data.isPlayingMedia() && data.isStoppingMedia,
            "authority patch modified client media state")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        GameTime.setInstance(GameTime())
        GameTime.getInstance().setMultiplier(1f)
        GameClient.client = false
        GameServer.server = true
        var field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.setAccessible(true)
        val engine = (field.get(null) as Unsafe).allocateInstance(UdpEngine::class.java) as UdpEngine
        field = UdpEngine::class.java.getDeclaredField("connections")
        field.setAccessible(true)
        field.set(engine, ArrayList<Any?>()) // Real native send path with no network peers or sockets.
        GameServer.udpEngine = engine
        val media = ZomboidRadio.getInstance().getRecordedMedia()
            .register("Retail-VHS", "native-check-vhs", "Native check VHS", 0)
        media.addLine("Native line one", 1f, 1f, 1f, null)
        media.addLine("Native line two", 1f, 1f, 1f, null)
        restart(media, false)
        ordinaryPlayback(media)
        invalidStarts(media)
        standaloneGuard(media)
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MediaChecks::class.java.classLoader)
        net.alexredby.pztoolkitjavapatches.Main.main(emptyArray())
        require(net.alexredby.pztoolkitjavapatches.Main.MEDIA_SUPPORTED, "unsupported native media engine")
        restart(media, true) // Real woven StartPlayMedia; no test clears the stop flag.
        ordinaryPlayback(media)
        invalidStarts(media)
        clientGuard(media)
        standaloneGuard(media)
        require(!net.alexredby.pztoolkitjavapatches.BytecodeSupport.supports("zombie/radio/devices/DeviceData.class", "unknown"),
            "unknown engine fingerprint accepted")
        println("MEDIA_CHECKS_PASS (native restart race, woven restart, line progression, duplicate start, stop, invalid start, client/standalone guards, automatic end)")
    }
}
