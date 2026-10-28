package zombie.core.fonts;

import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;
import zombie.GameWindow;
import zombie.ZomboidFileSystem;
import zombie.asset.AssetManagers;
import zombie.core.textures.Texture;
import zombie.core.textures.TextureAssetManager;
import zombie.core.textures.TextureID;
import zombie.core.textures.TextureIDAssetManager;
import zombie.fileSystem.FileSystemImpl;

final class FontColdSupport {
    static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    static void finish() throws Exception {
        long deadline = System.nanoTime() + 10_000_000_000L;
        while (GameWindow.fileSystem.hasWork() && System.nanoTime() < deadline) {
            GameWindow.fileSystem.updateAsyncTransactions();
            Thread.sleep(1);
        }
        require(!GameWindow.fileSystem.hasWork(), "native texture jobs timed out");
    }

    static void glyphs(String fnt, String image) throws Exception {
        var font = new AngelCodeFont(fnt, image);
        finish();
        require(!font.isLoading(), "font remains loading: " + fnt);
        String key = Path.of(image).getFileName().toString().replace(".png", "");
        var entry = GameWindow.texturePackTextures.get(key);
        require(entry == null || entry.info.ox == 0 && entry.info.oy == 0, "font atlas has trimmed origin");
        int originX = entry == null ? 0 : entry.info.x;
        int originY = entry == null ? 0 : entry.info.y;
        java.awt.image.BufferedImage expected;
        try (var stream = entry == null ? Files.newInputStream(Path.of(image))
                : GameWindow.fileSystem.openStream(GameWindow.fileSystem.getTexturePackDevice(entry.packName), entry.pageName)) {
            expected = ImageIO.read(stream);
        }
        require(expected != null, "native UI page is not a PNG");
        int visible = 0;
        for (var glyph : font.chars) {
            if (glyph == null || glyph.width == 0 || glyph.height == 0) continue;
            require(glyph.image != null && glyph.image.isReady(), "missing native glyph: " + glyph.id);
            var texture = glyph.image;
            var data = texture.getTextureId().getImageData();
            require(data != null, "decoded atlas pixels unavailable");
            int x = Math.round(texture.xStart * texture.getWidthHW());
            int y = Math.round(texture.yStart * texture.getHeightHW());
            require(x == originX + glyph.x && y == originY + glyph.y,
                "native glyph atlas region differs from FNT: " + glyph.id);
            require(x >= 0 && y >= 0 && x + glyph.width <= data.getWidth()
                && y + glyph.height <= data.getHeight(), "glyph region outside atlas: " + glyph.id);
            ByteBuffer pixels = data.getData().getBuffer();
            boolean opaque = false;
            for (int dy = 0; dy < glyph.height; dy++) {
                for (int dx = 0; dx < glyph.width; dx++) {
                    int offset = ((y + dy) * data.getWidthHW() + x + dx) * 4;
                    int argb = expected.getRGB(originX + glyph.x + dx, originY + glyph.y + dy);
                    // ImageIO getRGB color-converts grayscale; the engine PNG decoder uses raw channels.
                    if (expected.getColorModel().getColorSpace().getType() == java.awt.color.ColorSpace.TYPE_GRAY) {
                        int gray = expected.getRaster().getSample(x + dx, y + dy, 0);
                        int alpha = expected.getColorModel().hasAlpha() ? expected.getRaster().getSample(x + dx, y + dy, 1) : 255;
                        argb = alpha << 24 | gray * 0x010101;
                    }
                    int alpha = Byte.toUnsignedInt(pixels.get(offset + 3));
                    require(alpha == (argb >>> 24), "native glyph alpha differs from UI PNG: " + glyph.id);
                    if (alpha != 0) {
                        require(Byte.toUnsignedInt(pixels.get(offset)) == ((argb >>> 16) & 255)
                            && Byte.toUnsignedInt(pixels.get(offset + 1)) == ((argb >>> 8) & 255)
                            && Byte.toUnsignedInt(pixels.get(offset + 2)) == (argb & 255),
                            "native glyph color differs from PNG: " + glyph.id + ": "
                                + Byte.toUnsignedInt(pixels.get(offset)) + ","
                                + Byte.toUnsignedInt(pixels.get(offset + 1)) + ","
                                + Byte.toUnsignedInt(pixels.get(offset + 2)) + "," + alpha + " expected "
                                + Integer.toHexString(argb));
                        opaque = true;
                    }
                }
            }
            if (opaque) visible++;
        }
        require(visible > 80, "font has insufficient visible glyphs: " + fnt + ": " + visible);
        System.out.println("GLYPHS " + fnt + ": " + visible);
    }

    static void setup() throws Exception {
        ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        ZomboidFileSystem.instance.init();
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        GameWindow.fileSystem = new FileSystemImpl();
        GameWindow.assetManagers = new AssetManagers(GameWindow.fileSystem);
        TextureAssetManager.instance.create(Texture.ASSET_TYPE, GameWindow.assetManagers);
        TextureIDAssetManager.instance.create(TextureID.ASSET_TYPE, GameWindow.assetManagers);
        // Keep native decoding and font regions; queue GPU uploads without creating a window.
        var initialized = zombie.core.opengl.RenderThread.class.getDeclaredField("isInitialized");
        initialized.setAccessible(true);
        initialized.setBoolean(null, true);
    }

}
