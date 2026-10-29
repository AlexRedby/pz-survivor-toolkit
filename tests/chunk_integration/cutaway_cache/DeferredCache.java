import zombie.iso.*;
import zombie.iso.fboRenderChunk.*;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelData;

/** Test-only deferred cache: dirty calls run native without constructing a reusable mask. */
public final class DeferredCache {
    public static final class State { final long[][] masks=new long[4][]; final long[] valid=new long[4]; }
    public static void resetValidity(IsoChunk chunk){State state=chunk.cutawayDeferredState;if(state!=null)java.util.Arrays.fill(state.valid,0L);}
    public static void calculateOccludingSquares(CacheChecks.Cell cell,int playerIndex) {
        CacheChecks.PlayerData player=cell.perPlayerData[playerIndex];
        int width=player.occludedGridX2-player.occludedGridX1+1;
        for(int i=0;i<player.onScreenChunks.size();i++) {
            IsoChunk chunk=player.onScreenChunks.get(i);
            FBORenderLevels render=chunk.getRenderLevels(playerIndex);
            State state=chunk.cutawayDeferredState;
            for(int z=chunk.minLevel;z<=chunk.maxLevel;z++) {
                if(!render.isOnScreen(z))continue;
                int slot=z+32;long bit=1L<<slot;
                boolean dirty=render.isDirty(z,1.0f);
                if(CacheChecks.fast && !dirty && state!=null && (state.valid[playerIndex]&bit)!=0) {
                    ChunkLevelData level=CacheChecks.level(CacheChecks.levels(chunk),z);
                    long previous=level.occludingSquares[playerIndex],clipped=0L,mask=state.masks[playerIndex][slot];
                    while(mask!=0L) {
                        int indexBit=Long.numberOfTrailingZeros(mask);mask&=mask-1L;
                        int x=chunk.wx*8+(indexBit&7)-z*3-player.occludedGridX1;
                        int y=chunk.wy*8+(indexBit>>3)-z*3-player.occludedGridY1;
                        if(x>=0 && y>=0 && x<width && y<=player.occludedGridY2-player.occludedGridY1) {
                            int index=x+y*width;
                            player.occludedGrid[index]=zombie.core.math.PZMath.max(player.occludedGrid[index],z);
                            clipped|=(long)(1<<indexBit);
                        }
                    }
                    level.occludingSquares[playerIndex]=clipped;
                    if(clipped!=previous)CacheChecks.invalidate(null,playerIndex,chunk,z);
                    continue;
                }
                // Invalidate before native: a native exception must never leave a stale slot publishable.
                if(state!=null)state.valid[playerIndex]&=~bit;
                ChunkLevelData level=CacheChecks.level(CacheChecks.levels(chunk),z);
                boolean changed=level.calculateOccludingSquares(playerIndex,player.occludedGridX1,player.occludedGridY1,
                    player.occludedGridX2,player.occludedGridY2,player.occludedGrid);
                if(changed)CacheChecks.invalidate(null,playerIndex,chunk,z);
                if(CacheChecks.fast && !dirty) {
                    // The optional unclipped helper may read cells the native clipped operation did not read.
                    // A failed extra build must not undo native output or publish a partial mask.
                    long mask;
                    try {mask=PinnedCache.pzoptExactOccluderMask(playerIndex,chunk,z,level);}
                    catch(RuntimeException rejectedBuild){continue;}
                    if(state==null){state=new State();chunk.cutawayDeferredState=state;}
                    if(state.masks[playerIndex]==null)state.masks[playerIndex]=new long[64];
                    state.masks[playerIndex][slot]=mask;state.valid[playerIndex]|=bit;
                }
            }
        }
    }
}
