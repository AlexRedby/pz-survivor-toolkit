package zombie.core.fonts;

import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import me.zed_0xff.zombie_buddy.Agent;
import me.zed_0xff.zombie_buddy.Loader;
import net.alexredby.pztoolkitbootstrap.FontAssets;
import zombie.GameWindow;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

public final class FontColdChecks {
    public static void main(String[] args) throws Exception {
        FontColdSupport.setup();
        var logger = DebugLog.getInstance();
        var log = new ByteArrayOutputStream();
        DebugType.General.setLogSeverity(LogSeverity.Error);
        logger.setStdOut(log);
        logger.setStdErr(log);
        try {
            FontColdSupport.require(Agent.arguments.getOrDefault("patches_jar", "")
                .endsWith(":net.alexredby.pztoolkitbootstrap"), "font check did not use isolated premain bootstrap");
            FontColdSupport.require(FontAssets.SUPPORTED, "unsupported font bytecode");
            FontColdSupport.require(FontColdChecks.class.getClassLoader().getResource(
                "net/alexredby/pztoolkitjavapatches/Main.class") == null,
                "normal patch JAR was already on the startup classpath");
            FontColdSupport.require(GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                "cold fonts started with UI already mounted");
            FontColdSupport.glyphs("media/mainfont.fnt", "media/mainfont_0.png");
            FontColdSupport.glyphs("media/mainfont2.fnt", "media/mainfont2_0.png");
            FontColdSupport.glyphs("media/fonts/zomboidDialogue.fnt", "media/fonts/zomboidDialogue_0.png");
            FontColdSupport.require(GameWindow.texturePackTextures.size() == 2, "early mount exposed unrelated UI entries");
            var device = GameWindow.fileSystem.getTexturePackDevice("UI");
            GameWindow.setTexturePackLookup();
            FontColdSupport.require(GameWindow.texturePackTextures.isEmpty(), "native lookup reset retained early entries");
            FontColdSupport.glyphs("media/mainfont.fnt", Path.of("media/mainfont_0.png").toAbsolutePath().toString());
            FontColdSupport.glyphs("media/mainfont2.fnt", Path.of("media/mainfont2_0.png").toAbsolutePath().toString());
            FontColdSupport.require(GameWindow.fileSystem.getTexturePackDevice("UI") == device,
                "second font initialization remounted UI");
            FontColdSupport.require(!log.toString().contains("failed to load page") && !log.toString().contains("Exception"),
                "native font failure after premain advice: " + log);
            Class<?> phase = Class.forName("me.zed_0xff.zombie_buddy.Loader$Phase");
            var load = Loader.class.getDeclaredMethod("loadJar", Path.class, String.class, String.class, phase);
            load.setAccessible(true);
            var mainField = phase.getDeclaredField("MAIN");
            mainField.setAccessible(true);
            Object mainPhase = mainField.get(null);
            Path jar = Path.of(System.getProperty("pz.test.patch.jar"));
            String approvedHash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(jar)));
            FontColdSupport.require(Boolean.TRUE.equals(load.invoke(null, jar, "net.alexredby.pztoolkitjavapatches",
                approvedHash, mainPhase)), "ordinary mod JAR was not appended and loaded");
            FontColdSupport.require(me.zed_0xff.zombie_buddy.Exposer.getClassesWithGlobalLuaMethod().stream()
                .anyMatch(type -> type.getName().equals("net.alexredby.pztoolkitjavapatches.VideoRecording")),
                "ordinary mod load lost Lua exports");
            String property = new String("WindowShape");
            FontColdSupport.require(zombie.core.properties.IsoPropertyType.lookupOrDefaultStr(property) == property,
                "ordinary bootstrap changed native string property identity");
            FontColdSupport.require(!log.toString().contains("Property Name not found"),
                "ordinary loader phase did not install existing property advice: " + log);
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
            System.out.println("FONT_COLD_CHECKS_PASS (premain loader, native fonts, exact glyph pixels, no page errors, ordinary mod phase)");
        } catch (Throwable error) {
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
            error.printStackTrace();
            System.exit(1);
        }
        System.exit(0);
    }
}
