package net.alexredby.pztoolkitjavapatches

/** Audited native queue contracts; the game supplies ownership and completion behavior. */
object QueueManagerSupport {
    private val PLAYER_SUPPORTED = arrayOf(
        "zombie/network/fields/character/ConnectionPlayer.class" to "de2a38e738bc7fb888c04432e6a9290d52e7393b43485364c297cb5bf476252b",
        "zombie/network/fields/character/Player.class" to "8042efcd5036116a3b0e3550334f9a68c871870619ac03958696f8959c8e6c05",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    @JvmField
    val ITEM_SUPPORTED = PLAYER_SUPPORTED && arrayOf(
        "zombie/core/TransactionManager.class" to "fafb0528b0fa7e664a8e440a8d10a2fca40cde46c1dfd711ca36caab93cb5508",
        "zombie/core/Transaction.class" to "7d114ae5008c978aea646b2508c9f644d1791b782e8c83747395efffc439a78a",
        "zombie/network/packets/ItemTransactionPacket.class" to "696ef78beba003df4d30bea4dccd680314f978c236462050a5451360aac91493",
        "zombie/core/raknet/UdpConnection.class" to "9efbe65d4d728cb3b1e7827e4f639bab3aae049f910343c9b9a1c7b4fe228622",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    @JvmField
    val ACTION_SUPPORTED = PLAYER_SUPPORTED && arrayOf(
        "zombie/core/ActionManager.class" to "499b2d6179fc96a49e150f5dcb92ee813973491e4abd50335249430080d7cf25",
        "zombie/core/Action.class" to "19eac0c47039721228c35bc23204a34899a7bee4ea97a0564e0d1f8254a3ac31",
        "zombie/characters/IsoPlayer.class" to "643585044a88ad1b29e8d5173774f66085c685c363ed10a89c0b79018de2874e",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }
}
