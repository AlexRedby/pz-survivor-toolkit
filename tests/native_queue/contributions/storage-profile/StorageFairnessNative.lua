-- Correctness-only native stress: observations are not CPU or FPS measurements.
require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
local Fairness={}
local COUNT=3000
local function now()return getTimestampMs()end
local function idle()
    return #ISTimedActionQueue.getTimedActionQueue(getPlayer()).queue==0 and not getPlayer():hasTimedActions()
end
function Fairness.new(origin,setFeatures,features,log)
    setFeatures('off-empty')
    return setmetatable({origin=origin,setFeatures=setFeatures,features=features,log=log,
        items={},stage='fill',control=1,since=now(),removed=0},{__index=Fairness})
end
function Fairness:cleanup()
    for _,item in ipairs(self.items)do
        local object=assert(item:getWorldItem(),'fairness object disappeared')
        object:getSquare():transmitRemoveItemFromSquare(object)
        self.removed=self.removed+1
    end
    self.items={}
    return self.removed
end
function Fairness:walk()
    self.actions=self.actions+1
    local x=self.actions%2==1 and self.origin.x+2 or self.origin.x-2
    self.goal=assert(getCell():getGridSquare(x,self.origin.y,self.origin.z))
    self.action=ISWalkToTimedAction:new(getPlayer(),self.goal)
    assert(self.action.Type=='ISWalkToTimedAction')
    ISTimedActionQueue.add(self.action)
end
function Fairness:begin()
    assert(idle(),'fairness native route not idle')
    self.name=self.control==1 and 'normal-only' or 'wishlist-only'
    self.setFeatures(self.name)
    local f=self.features()
    assert(f.radius>=3 and f.normal==(self.control==1) and f.wanted==(self.control==2))
    self.started=now();self.actions=0;self.reached=0;self.ticks=0;self.moving=0
    self.tiles=0;self.distance=0;self.maxTileGap=0;self.lastTileTick=0
    self.seen={};self.eligible={};self.seenCount=0;self.eligibleCount=0;self.samples=0
    self.x,self.y=getPlayer():getX(),getPlayer():getY()
    self.stage='walk';self:walk()
end
function Fairness:sample()
    self.samples=self.samples+1
    for _,item in ipairs(self.items)do
        local object=assert(item:getWorldItem(),'native pile lost a physical object')
        local square=object:getSquare()
        if square and square:isCanSee(0) and object:getDoRender() and object:getTargetAlpha(0)>0 then
            if not self.eligible[object]then self.eligible[object]=true;self.eligibleCount=self.eligibleCount+1 end
            if object:isHighlighted(0) and object:isOutlineHighlight(0) and not self.seen[object]then
                self.seen[object]=true;self.seenCount=self.seenCount+1
            end
        end
    end
end
function Fairness:tick()
    local status=PZSurvivorToolkit.Highlighter.getStatus()
    assert(not status.lastError,'native fairness highlighter error')
    if self.stage=='fill'then
        local square=assert(getCell():getGridSquare(self.origin.x,self.origin.y,self.origin.z))
        for _=1,50 do
            if #self.items>=COUNT then break end
            local i=#self.items
            local item=assert(square:AddWorldInventoryItem('Base.Nails',.2+(i%6)*.1,.2+(math.floor(i/6)%6)*.1,0))
            assert(item:getWorldItem() and item:getScriptItem():isWorldRender())
            self.items[#self.items+1]=item
        end
        if #self.items==COUNT then self.stage='off';self.since=now()end
    elseif self.stage=='off'then
        assert(now()-self.since<20000,'fairness disabled cleanup exceeded deadline')
        if now()-self.since>=2000 and not status.clearing and status.highlightedObjects==0 then
            for _,item in ipairs(self.items)do
                local object=item:getWorldItem()
                assert(not object:isHighlighted(0) and not object:isOutlineHighlight(0),'disabled control retained foreign/native outline')
            end
            if self.control>2 then return true end
            self:begin()
        end
    elseif self.stage=='walk'then
        assert(now()-self.started<90000,'fairness native traversal exceeded deadline')
        self.ticks=self.ticks+1
        local player=getPlayer();local x,y=player:getX(),player:getY()
        assert(math.floor(player:getZ())==self.origin.z,'fairness native walk changed floor')
        local dx,dy=x-self.x,y-self.y
        if dx*dx+dy*dy>.000001 then
            self.moving=self.moving+1;self.distance=self.distance+math.sqrt(dx*dx+dy*dy)
            -- Sample only while the actual native walk changes the player's position.
            if self.moving%10==0 then self:sample()end
        end
        if math.floor(x)~=math.floor(self.x) or math.floor(y)~=math.floor(self.y)then
            self.tiles=self.tiles+1;self.maxTileGap=math.max(self.maxTileGap,self.ticks-self.lastTileTick)
            self.lastTileTick=self.ticks
        end
        self.x,self.y=x,y
        if idle()then
            assert(math.floor(x)==self.goal:getX() and math.floor(y)==self.goal:getY(),'native fairness walk did not reach its target')
            self.reached=self.reached+1
            if self.reached<12 then self:walk()
            else
                assert(self.distance>=40 and self.tiles>=40 and self.moving>=100,'fairness movement was not observed')
                assert(self.eligibleCount==COUNT and self.seenCount==COUNT,'moving native pile discovery incomplete: '..self.seenCount..'/'..COUNT..', eligible='..self.eligibleCount)
                self.log('FAIRNESS',{control=self.name,objects=COUNT,eligible=self.eligibleCount,outlinedDuringMovement=self.seenCount,
                    nativeActions=self.actions,reached=self.reached,distance=self.distance,tileChanges=self.tiles,movementTicks=self.moving,
                    maxTileGapTicks=self.maxTileGap,samples=self.samples,elapsedMs=now()-self.started,
                    features=self.features(),teleports=0,disabledBefore=true,observationalTiming=false})
                self.control=self.control+1;self.setFeatures('off-empty');self.stage='off';self.since=now()
            end
        end
    end
    return false
end
return Fairness
