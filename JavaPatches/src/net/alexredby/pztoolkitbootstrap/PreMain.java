package net.alexredby.pztoolkitbootstrap;

public final class PreMain {
    public static void premain(String[] args) throws ClassNotFoundException {
        LotLocks.install();
        if (FontAssets.SUPPORTED)
            Class.forName("zombie.core.textures.Texture", false, PreMain.class.getClassLoader());
        System.out.println("[PZToolkitJavaPatches] Early font phase enabled="
            + FontAssets.SUPPORTED);
    }
}
