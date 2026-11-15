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
            "8613349b0e0fdb663fc16ef4397ca60ef7135925fa6116f92d958ea97d09eb32",
        ) &&
            BytecodeSupport.supports(
                "zombie/ZomboidFileSystem.class",
                "9f902cc912c7802a08f80614f5f8d3b74f249fc5f2c0204eb759f2e74dda175e",
            ) &&
            BytecodeSupport.supports(
                "zombie/gameStates/ChooseGameInfo.class",
                "5b124fe4e6f8525ed431e8c1ef62238597a7981276c13c3ddaa39c1ca1cee4b0",
            ) &&
            BytecodeSupport.supports(
                "zombie/gameStates/ChooseGameInfo\$Mod.class",
                "9f304e567f306ff43db87e85927b794be2727f5d5cb6bafbe9c6c3802de08224",
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
                "1e79dbff83e85c8863df63f7847d3a506fddbaefa423cb676734751599db1aea",
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
                "dcf8345b049013b0b40a768f7f1501bc595e5389ad6f20e3c83879dc98588f04",
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
