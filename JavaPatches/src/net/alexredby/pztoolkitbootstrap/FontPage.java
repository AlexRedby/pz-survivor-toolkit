package net.alexredby.pztoolkitbootstrap;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className="zombie.core.textures.Texture", methodName="getSharedTextureInternal", strictMatch=true)
public final class FontPage {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(value=0, readOnly=false) String name) {
        name = FontAssets.pageName(name, FontAssets.SUPPORTED);
    }
}
