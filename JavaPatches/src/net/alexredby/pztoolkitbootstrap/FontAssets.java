package net.alexredby.pztoolkitbootstrap;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import zombie.GameWindow;
import zombie.ZomboidFileSystem;
import zombie.fileSystem.FileSystem;
import zombie.fileSystem.TexturePackDevice;

public final class FontAssets {
    public static final boolean SUPPORTED = supports("zombie/core/textures/Texture.class",
        "2f4fba9ad6c33a9ba0763a68d16164833a682f7645e61a061f70bfdca33c1f8f")
        && supports("zombie/core/fonts/AngelCodeFont.class",
            "f8fc7fd358c97fb99280ff4987cddad17ad9b057b6bc13520bf7c104400875b1")
        && supports("zombie/GameWindow.class",
            "c3a3583923191b6aea23a74e6b05e2b53302bbcded7f89cae930e364a409dfb2")
        && supports("zombie/fileSystem/FileSystemImpl.class",
            "6486a2122ff3bc51ad502bb2df0a6ad4b19f112d0c885b8b802f05096c52ae84");

    private FontAssets() { }

    private static boolean supports(String resource, String expected) {
        try (var stream = FontAssets.class.getClassLoader().getResourceAsStream(resource)) {
            return stream != null && expected.equals(HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes())));
        } catch (Exception error) {
            return false;
        }
    }

    private static void beforeFonts() {
        if (GameWindow.fileSystem == null || GameWindow.texturePackTextures.containsKey("mainfont_0")
            && GameWindow.texturePackTextures.containsKey("mainfont2_0")) return;
        if (Files.isRegularFile(Path.of(ZomboidFileSystem.instance.getString("media/mainfont_0.png")))
            || Files.isRegularFile(Path.of(ZomboidFileSystem.instance.getString("media/mainfont2_0.png")))) return;
        if (!matches("media/mainfont.fnt", "de5192f3338de13bfc59bb095561617a7f963bea0727842c7280aa2935827dd5")
            || !matches("media/mainfont2.fnt", "c3a1f68e8c28e334947e4fb0c7f08eb96553b8db37618fbb2563fe4c081ef6c4")
            || !matches("media/texturepacks/UI.pack", "47adb45d5c51d89d225d008c08d54eb4b118623b9dcda06e6095bd11e00a8e37")) return;
        // Initial fonts precede initShared; LoadTexturePack itself draws text and would recurse.
        var entries = new FileSystem.TexturePackTextures();
        if (GameWindow.fileSystem.getTexturePackDevice("UI") == null) {
            GameWindow.fileSystem.mountTexturePack("UI", entries, 2);
        } else {
            // Mod-pack lookup rebuilding clears these entries before the second font initialization.
            try {
                new TexturePackDevice("UI", 2).getSubTextureInfo(entries);
            } catch (java.io.IOException error) {
                return;
            }
        }
        for (String name : new String[]{"mainfont_0", "mainfont2_0"}) {
            var texture = entries.get(name);
            if (texture != null) GameWindow.texturePackTextures.putIfAbsent(name, texture);
        }
    }

    public static String pageName(String name, boolean supported) {
        if (!supported || name == null) return name;
        if (name.endsWith("mainfont_0.png") || name.endsWith("mainfont2_0.png")) {
            for (String relative : new String[]{"media/mainfont_0.png", "media/mainfont2_0.png"}) {
                if (nativePath(name, relative)
                    && !Files.isRegularFile(Path.of(ZomboidFileSystem.instance.getString(relative)))) {
                    beforeFonts();
                    break;
                }
            }
            return name;
        }
        if (!name.endsWith("zomboidDialogue.bmfc_0.png")) return name;
        String original = ZomboidFileSystem.instance.getString("media/fonts/zomboidDialogue.bmfc_0.png");
        if (!nativePath(name, original) || Files.isRegularFile(Path.of(original))
            || !matches("media/fonts/zomboidDialogue.fnt", "88e77f8683e2b8599c6e4cd9ed29beb3852e8e947c3d7f8ca501bcfa0e5dcd20")) return name;
        String corrected = ZomboidFileSystem.instance.getString("media/fonts/zomboidDialogue_0.png");
        return Files.isRegularFile(Path.of(corrected)) ? corrected : name;
    }

    private static boolean nativePath(String name, String relative) {
        String normalized = name.replace('\\', '/');
        return normalized.equals(relative.replace('\\', '/'))
            || normalized.equals(Path.of(relative).toAbsolutePath().normalize().toString().replace('\\', '/'));
    }

    private static boolean matches(String relative, String expected) {
        try (var stream = Files.newInputStream(Path.of(ZomboidFileSystem.instance.getString(relative)))) {
            var digest = MessageDigest.getInstance("SHA-256");
            try (var input = new java.security.DigestInputStream(stream, digest)) {
                input.transferTo(java.io.OutputStream.nullOutputStream());
            }
            return expected.equals(HexFormat.of().formatHex(digest.digest()));
        } catch (Exception error) {
            return false;
        }
    }
}
