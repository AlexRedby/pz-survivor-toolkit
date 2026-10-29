import zombie.iso.*;
import zombie.iso.fboRenderChunk.*;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelData;

/** Test-only repair of the pinned replay; the dirty/missing-cache path remains native. */
public final class RepairedCache {
    public static void resetValidity(IsoChunk chunk){java.util.Arrays.fill(CacheChecks.state(chunk).repairedSet,0L);}
    public static void calculateOccludingSquares(CacheChecks.Cell cell,int playerIndex) {
        CacheChecks.PlayerData player=cell.perPlayerData[playerIndex];
        int width=player.occludedGridX2-player.occludedGridX1+1;
        for(int i=0;i<player.onScreenChunks.size();i++) {
            IsoChunk chunk=player.onScreenChunks.get(i);
            FBORenderLevels render=chunk.getRenderLevels(playerIndex);
            CacheChecks.State state=CacheChecks.state(chunk);
            for(int z=chunk.minLevel;z<=chunk.maxLevel;z++) {
                if(!render.isOnScreen(z))continue;
                int slot=z+32;
                if(CacheChecks.fast && (state.repairedSet[playerIndex]&(1L<<slot))!=0 && !render.isDirty(z,1.0f)) {
                    ChunkLevelData level=CacheChecks.level(CacheChecks.levels(chunk),z);
                    long previous=level.occludingSquares[playerIndex],clipped=0L;
                    long mask=state.repairedMask[playerIndex][slot];
                    while(mask!=0L) {
                        int bit=Long.numberOfTrailingZeros(mask);mask&=mask-1L;
                        int x=chunk.wx*8+(bit&7)-z*3-player.occludedGridX1;
                        int y=chunk.wy*8+(bit>>3)-z*3-player.occludedGridY1;
                        if(x>=0 && y>=0 && x<width && y<=player.occludedGridY2-player.occludedGridY1) {
                            int index=x+y*width;
                            player.occludedGrid[index]=zombie.core.math.PZMath.max(player.occludedGrid[index],z);
                            // Preserve the native int-shift wrap and sign extension, including bits 31/32/63.
                            clipped|=(long)(1<<bit);
                        }
                    }
                    level.occludingSquares[playerIndex]=clipped;
                    if(clipped!=previous)CacheChecks.invalidate(null,playerIndex,chunk,z);
                    continue;
                }
                ChunkLevelData level=CacheChecks.level(CacheChecks.levels(chunk),z);
                boolean changed=level.calculateOccludingSquares(playerIndex,player.occludedGridX1,player.occludedGridY1,
                    player.occludedGridX2,player.occludedGridY2,player.occludedGrid);
                if(CacheChecks.fast) {
                    if(state.repairedMask[playerIndex]==null)state.repairedMask[playerIndex]=new long[64];
                    state.repairedMask[playerIndex][slot]=PinnedCache.pzoptExactOccluderMask(playerIndex,chunk,z,level);
                    state.repairedSet[playerIndex]|=1L<<slot;
                }
                if(changed)CacheChecks.invalidate(null,playerIndex,chunk,z);
            }
        }
    }
}
