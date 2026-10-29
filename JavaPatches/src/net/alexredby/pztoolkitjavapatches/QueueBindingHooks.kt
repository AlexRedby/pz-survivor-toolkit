package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.io.Reader
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.LuaClosure

/** Shared native implementation gate; Java advice is only the argument write-back bridge. */
internal object QueueBindingHooks {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/Lua/LuaManager.class",
            "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d",
        ) &&
            BytecodeSupport.supports(
                "zombie/ZomboidFileSystem.class",
                "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750",
            ) &&
            BytecodeSupport.supports(
                "zombie/gameStates/ChooseGameInfo.class",
                "8c4b47ba966f071120feeec090202967e414246e28b5b6fd6a622a6a266af651",
            ) &&
            BytecodeSupport.supports(
                "zombie/gameStates/ChooseGameInfo\$Mod.class",
                "c91e48400b77015c450a696f2d7c5665fa872f1a76fc05d2c38e72ba2928dc69",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/luaj/compiler/LuaCompiler.class",
                "dd2b68ac4ce7a8e65cd7c3b11a3c1672a2471b824a675d4085e7b07041d4cbad",
            ) &&
            BytecodeSupport.supports(
                "org/luaj/kahluafork/compiler/LexState.class",
                "ac20f3e0f8369a9914a215bd3e320a34772e931dcac57ad4c0fc3d0d448f6c95",
            ) &&
            BytecodeSupport.supports(
                "org/luaj/kahluafork/compiler/FuncState.class",
                "2f7eff5b60db6f4ba5ae9c778b654b2a3d039be184629d9fe46ca55904a7bb2e",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/vm/Prototype.class",
                "5e31f0809512e9cfbc9a8fff5a932e35cdc7f1ebb4a0ea146a2f9a207a23fcf4",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/vm/KahluaThread.class",
                "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/vm/LuaClosure.class",
                "92acfa5288c7bc6ab568a180140c20c5186b723ec2b38adafb2ef807b955b0cd",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/vm/LuaCallFrame.class",
                "7d910d19d1008b2427f4e1409e6c0eb1f8c40e32132fce176b5123ae27192e30",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/vm/Coroutine.class",
                "b0ecb5f6f004ed43e356d5177403fee4b190e58f659709cc34b9bc89beb6dfa4",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/j2se/KahluaTableImpl.class",
                "101df1481366f976f76c037094e29f5ad21c71f5026dc3d0693f25d68b1c79f7",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/stdlib/TableLib.class",
                "97c294f5c050c48b901315eaa737f0d12587185554923d01e5c9f25602e51156",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/vm/KahluaUtil.class",
                "5e4d5bea56fedc34a332780aff73bd9abd9c6e3209200aa0bdd1eae3ad029f6e",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/stdlib/BaseLib.class",
                "03816f584acbe2ef78e167f3e7ef4773865adc5a68c7ee9732cfa7ba81f4a927",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/Core.class",
                "8f5c69740c8bf2181123a831ab68d1dfb047453687cca6dc62c77816d76ab360",
            )

    data class Compilation(val reader: Reader, val closure: LuaClosure?)

    @JvmStatic
    @Throws(IOException::class)
    fun compilerInput(
        reader: Reader,
        name: String?,
        environment: KahluaTable?,
        supported: Boolean,
    ): Compilation {
        val prepared = QueueBindingSource.prepare(reader, name, supported)
        val source = prepared.text
        if (source == null || environment !is KahluaTableImpl || prepared.module == null) {
            return Compilation(prepared.reader, null)
        }
        // This recursive native compilation cannot claim the already-consumed outer source scope.
        val closure = QueueBindingCompiler.compile(source, name!!, environment, true)
        return Compilation(prepared.reader, closure)
    }
}
