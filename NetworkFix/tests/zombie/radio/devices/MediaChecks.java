package zombie.radio.devices;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.util.ArrayList;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.core.raknet.UdpEngine;
import zombie.iso.IsoGridSquare;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.radio.ZomboidRadio;
import zombie.radio.media.MediaData;

public final class MediaChecks {
    static final class Device implements WaveSignalDevice {
        DeviceData data;
        int staticLines;
        public DeviceData getDeviceData() { return data; }
        public void setDeviceData(DeviceData value) { data = value; }
        public float getDelta() { return 0; }
        public void setDelta(float value) { }
        public IsoGridSquare getSquare() { return null; }
        public float getX() { return 0; }
        public float getY() { return 0; }
        public float getZ() { return 0; }
        public boolean HasPlayerInRange() { return false; }
        public void AddDeviceText(String text, float r, float g, float b, String guid, String codes, int distance) {
            if (guid == null) staticLines++;
        }
    }

    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    static DeviceData device(MediaData media) {
        Device parent = new Device();
        DeviceData data = new DeviceData(parent);
        parent.data = data;
        data.isTelevision = true;
        data.isTurnedOn = true;
        data.mediaType = 1;
        data.mediaIndex = media.getIndex();
        return data;
    }

    static void drainStopTail(DeviceData data) {
        for (int i = 0; i < 1000 && data.isStoppingMedia; i++) data.updateMediaPlaying();
        require(!data.isStoppingMedia, "native stop tail did not finish");
    }

    static void firstLine(DeviceData data) {
        for (int i = 0; i < 1000 && data.mediaLineIndex == 0; i++) data.updateMediaPlaying();
        require(data.isPlayingMedia() && data.mediaLineIndex == 1,
            "restart failed to deliver the first native media line");
    }

    static void restart(MediaData media, boolean patched) {
        DeviceData data = device(media);
        data.StartPlayMedia();
        require(data.isPlayingMedia(), "initial native start");
        data.StopPlayMedia();
        require(!data.isPlayingMedia() && data.isStoppingMedia && data.playingMedia == null,
            "native stop state");
        data.StartPlayMedia();
        require(data.isPlayingMedia(), "native immediate restart");
        if (patched) {
            require(!data.isStoppingMedia, "woven patch left the old stop tail active");
            firstLine(data);
        } else {
            require(data.isStoppingMedia, "baseline did not retain the old stop tail");
            drainStopTail(data);
            require(!data.isPlayingMedia() && data.mediaLineIndex == 0,
                "baseline did not reproduce the silent restart loss");
        }
        require(((Device)data.parent).staticLines > 0, "native TV media switch did not run");
    }

    static void ordinaryPlayback(MediaData media) {
        DeviceData data = device(media);
        data.StartPlayMedia();
        firstLine(data);
        float counter = data.lineCounter;
        data.StartPlayMedia();
        require(data.mediaLineIndex == 1 && data.lineCounter == counter,
            "duplicate start reset the tape");
        for (int i = 0; i < 2000 && data.isPlayingMedia(); i++) data.updateMediaPlaying();
        require(!data.isPlayingMedia() && data.isStoppingMedia && data.mediaLineIndex == media.getLineCount(),
            "automatic end did not preserve native stopping behavior");
        drainStopTail(data);
        require(!data.isPlayingMedia(), "automatic end restarted the tape");
        data.StartPlayMedia();
        firstLine(data);
        data.StopPlayMedia();
        data.StopPlayMedia();
        require(!data.isPlayingMedia() && data.isStoppingMedia && data.playingMedia == null,
            "repeated stop lost the native stop state");
        drainStopTail(data);
        require(!data.isPlayingMedia(), "explicit stop restarted the tape");
    }

    static void invalidStarts(MediaData media) {
        for (int mode = 0; mode < 3; mode++) {
            DeviceData data = device(media);
            data.StartPlayMedia();
            data.StopPlayMedia();
            if (mode == 0) data.isTurnedOn = false;
            if (mode == 1) data.mediaIndex = -1;
            if (mode == 2) data.mediaIndex = Short.MAX_VALUE;
            data.StartPlayMedia();
            require(!data.isPlayingMedia() && data.isStoppingMedia,
                "invalid start changed native stopping state: " + mode);
        }
    }

    static void standaloneGuard(MediaData media) {
        DeviceData data = device(media);
        data.mediaType = -1; // Avoid starting the standalone sound engine in this state-only fixture.
        GameServer.server = false;
        try {
            data.StartPlayMedia();
            firstLine(data);
            data.StopPlayMedia();
            require(data.isPlayingMedia() && data.isStoppingMedia && data.playingMedia == null,
                "native standalone stop state");
            data.StartPlayMedia();
            require(data.isStoppingMedia && data.playingMedia == null,
                "server patch cleared a standalone no-op start's stop tail");
            drainStopTail(data);
            require(!data.isPlayingMedia(), "standalone stop no longer finishes");
        } finally {
            GameServer.server = true;
        }
    }

    static void clientGuard(MediaData media) throws Exception {
        DeviceData data = device(media);
        data.StartPlayMedia();
        data.StopPlayMedia();
        data.isPlayingMedia = true; // State received from a server; client Start must not modify it.
        GameClient.client = true;
        GameServer.server = false;
        PrintStream output = System.out;
        try (PrintStream captured = new PrintStream(new ByteArrayOutputStream())) {
            System.setOut(captured);
            // Native transmit catches the missing player/connection before any networking occurs.
            data.StartPlayMedia();
        } finally {
            System.setOut(output);
            GameClient.client = false;
            GameServer.server = true;
        }
        require(data.isPlayingMedia() && data.isStoppingMedia,
            "authority patch modified client media state");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        GameTime.setInstance(new GameTime());
        GameTime.getInstance().setMultiplier(1);
        GameClient.client = false;
        GameServer.server = true;
        Field field = Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        UdpEngine engine = (UdpEngine)((Unsafe)field.get(null)).allocateInstance(UdpEngine.class);
        field = UdpEngine.class.getDeclaredField("connections");
        field.setAccessible(true);
        field.set(engine, new ArrayList<>()); // Real native send path with no network peers or sockets.
        GameServer.udpEngine = engine;
        MediaData media = ZomboidRadio.getInstance().getRecordedMedia()
            .register("Retail-VHS", "native-check-vhs", "Native check VHS", 0);
        media.addLine("Native line one", 1, 1, 1, null);
        media.addLine("Native line two", 1, 1, 1, null);
        restart(media, false);
        ordinaryPlayback(media);
        invalidStarts(media);
        standaloneGuard(media);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pznetworkfix", MediaChecks.class.getClassLoader());
        net.alexredby.pznetworkfix.Main.main(new String[0]);
        require(net.alexredby.pznetworkfix.Main.MEDIA_SUPPORTED, "unsupported native media engine");
        restart(media, true); // Real woven StartPlayMedia; no test clears the stop flag.
        ordinaryPlayback(media);
        invalidStarts(media);
        clientGuard(media);
        standaloneGuard(media);
        require(!net.alexredby.pznetworkfix.Main.supports("zombie/radio/devices/DeviceData.class", "unknown"),
            "unknown engine fingerprint accepted");
        System.out.println("MEDIA_CHECKS_PASS (native restart race, woven restart, line progression, duplicate start, stop, invalid start, client/standalone guards, automatic end)");
    }
}
