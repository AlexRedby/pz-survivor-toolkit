package zombie.core.fonts

import java.nio.file.Files
import java.nio.file.Path
import net.alexredby.pztoolkitbootstrap.FontAssets
import zombie.GameWindow
import zombie.ZomboidFileSystem
import zombie.core.textures.Texture

object FontChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        FontColdSupport.setup()
        try {
            FontColdSupport.require(
                Texture.getSharedTexture("media/mainfont_0.png", 0) == null,
                "baseline mainfont unexpectedly available before UI mount",
            )
            FontColdSupport.finish()
            Texture.onTexturePacksChanged()
            FontAssets.pageName("media/mainfont_0.png", false)
            FontColdSupport.require(
                GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                "unsupported engine mounted UI",
            )
            FontColdSupport.require(
                FontAssets.pageName("mods/custom/mainfont_0.png", true)
                    .equals("mods/custom/mainfont_0.png"),
                "custom mainfont page changed",
            )
            FontColdSupport.require(
                GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                "custom mainfont mounted UI",
            )
            val diskPage = Files.createTempFile("pz-custom-font-", ".png")
            try {
                ZomboidFileSystem.instance.activeFileMap.put(
                    "media/mainfont_0.png",
                    diskPage.toString(),
                )
                FontAssets.pageName("media/mainfont_0.png", true)
                FontColdSupport.require(
                    GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                    "existing disk page mounted UI",
                )
                FontAssets.pageName("media/mainfont2_0.png", true)
                FontColdSupport.require(
                    GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                    "other page shadowed existing disk font",
                )
                ZomboidFileSystem.instance.activeFileMap.remove("media/mainfont_0.png")
                val originalFnt =
                    ZomboidFileSystem.instance.activeFileMap.put(
                        "media/mainfont.fnt",
                        diskPage.toString(),
                    )
                try {
                    FontAssets.pageName("media/mainfont_0.png", true)
                    FontColdSupport.require(
                        GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                        "custom FNT mounted UI",
                    )
                } finally {
                    ZomboidFileSystem.instance.activeFileMap.put("media/mainfont.fnt", originalFnt)
                }
                val originalPack =
                    ZomboidFileSystem.instance.activeFileMap.put(
                        "media/texturepacks/ui.pack",
                        diskPage.toString(),
                    )
                try {
                    FontAssets.pageName("media/mainfont_0.png", true)
                    FontColdSupport.require(
                        GameWindow.fileSystem.getTexturePackDevice("UI") == null,
                        "custom/corrupt UI pack mounted early",
                    )
                } finally {
                    ZomboidFileSystem.instance.activeFileMap.put(
                        "media/texturepacks/ui.pack",
                        originalPack,
                    )
                }
            } finally {
                ZomboidFileSystem.instance.activeFileMap.remove("media/mainfont_0.png")
                Files.delete(diskPage)
            }
            FontAssets.pageName("media/mainfont_0.png", true)
            FontColdSupport.require(
                GameWindow.texturePackTextures.size == 2,
                "unexpected early UI texture exposure",
            )
            val device = GameWindow.fileSystem.getTexturePackDevice("UI")
            FontAssets.pageName("media/mainfont_0.png", true)
            FontColdSupport.require(
                GameWindow.fileSystem.getTexturePackDevice("UI") === device,
                "UI mounted twice",
            )
            FontColdSupport.glyphs("media/mainfont.fnt", "media/mainfont_0.png")
            FontColdSupport.glyphs("media/mainfont2.fnt", "media/mainfont2_0.png")
            GameWindow.setTexturePackLookup()
            FontColdSupport.require(
                GameWindow.texturePackTextures.isEmpty(),
                "native lookup reset retained early font entries",
            )
            FontAssets.pageName(Path.of("media/mainfont_0.png").toAbsolutePath().toString(), true)
            FontColdSupport.require(
                GameWindow.fileSystem.getTexturePackDevice("UI") === device,
                "lookup recovery remounted UI",
            )
            FontColdSupport.require(
                GameWindow.texturePackTextures.size == 2,
                "lookup recovery did not restore both font entries",
            )
            FontColdSupport.glyphs(
                "media/mainfont.fnt",
                Path.of("media/mainfont_0.png").toAbsolutePath().toString(),
            )
            FontColdSupport.glyphs(
                "media/mainfont2.fnt",
                Path.of("media/mainfont2_0.png").toAbsolutePath().toString(),
            )
            val missing =
                ZomboidFileSystem.instance.getString("media/fonts/zomboidDialogue.bmfc_0.png")
            val corrected = FontAssets.pageName(missing, true)
            FontColdSupport.require(
                !missing.equals(corrected) &&
                    Path.of(corrected).getFileName().toString().equals("zomboidDialogue_0.png"),
                "shipped Dialogue page not corrected",
            )
            FontColdSupport.require(
                FontAssets.pageName(missing, false).equals(missing),
                "unsupported page changed",
            )
            FontColdSupport.require(
                FontAssets.pageName("mods/custom/zomboidDialogue.bmfc_0.png", true)
                    .equals("mods/custom/zomboidDialogue.bmfc_0.png"),
                "custom page changed",
            )
            System.out.println("FONT_CHECKS_PASS")
        } catch (error: Throwable) {
            error.printStackTrace()
            kotlin.system.exitProcess(1)
        }
        kotlin.system.exitProcess(0)
    }
}
