if not NativeActionRoot then print('Recovery adapters SKIP (pass --game or --native-action-root).');return end
local customLightSwitchSource=CustomLightSwitchSource or os and os.getenv and os.getenv('PZ_CUSTOM_LIGHT_SWITCH_SOURCE')
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local f=assert(io.open(path));local text=f:read('*a');f:close();return text:gsub('\r','')
end
local function reader(text)
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local function setup(changed,binding,loadQueue,lightSwitch)
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/TimedActions/ISTransferAction.lua');f.native('shared/TimedActions/ISEatFoodAction.lua')
    f.native('shared/TimedActions/ISDrinkFluidAction.lua');f.native('shared/RadioCom/ISRadioAction.lua')
    f.native('client/TimedActions/WalkToTimedAction.lua')
    f.native('shared/TimedActions/ISDeviceBatteryAction.lua');f.native('shared/TimedActions/ISDeviceMediaAction.lua')
    isClient,isServer=function()return false end,function()return false end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        if changed=='reader'then return {readLine=12,close=function()end}end
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if changed and path:find(changed,1,true)then text=text..'-- changed source\n'end
        return reader(text)
    end
    getModFileReader=function(id,path)
        if id=='CustomLightSwitch'then
            assert(customLightSwitchSource,'CustomLightSwitch checks require PZ_CUSTOM_LIGHT_SWITCH_SOURCE')
            assert(path=='media/lua/shared/TimedActions/CustomLightSwitch_ReadFix.lua')
            local text=read(customLightSwitchSource)
            if changed=='custom-source'then text=text..'-- changed source\n'end
            return reader(text)
        end
        return reader(read(ProjectRoot..'/PZSurvivorToolkit/42/'..path))
    end
    getTimestampMs=function()return 1 end
    getCore=function()return {getGameMode=function()return 'Sandbox'end}end
    getSandboxOptions=function()return {getOptionByName=function()return {getValue=function()return 2 end}end}end
    getGameTime=function()return {getMinutesPerDay=function()return 60 end}end
    CharacterTrait={DEXTROUS=1,ALL_THUMBS=2,ILLITERATE=3,FAST_READER=4,SLOW_READER=5}
    ItemTag={FAST_READ='fastread'};ItemBodyLocation={EYES=1}
    SkillBook={Woodwork={perk=1,maxMultiplier1=3}}
    local state={writes=0,items={},nextId=0,squares={}}
    f.player.class='IsoPlayer';f.player.getVehicle=function(self)return self.vehicle end
    f.player.hasTrait=function()return false end;f.player.isWearingAwkwardGloves=function()return false end
    f.player.isEquipped=function()return false end;f.player.isSitting=function()return false end
    f.player.getPerkLevel=function()return 0 end
    f.player.getWornItems=function()return {getItem=function()end}end
    f.player.getAlreadyReadPages=function(_,kind)return state.pages and state.pages[kind]or 0 end
    f.player.setAlreadyReadPages=function(_,kind,value)state.writes=state.writes+1;state.pages=state.pages or {};state.pages[kind]=value end
    local originalInstanceof=instanceof
    instanceof=function(value,kind)
        return originalInstanceof(value,kind)or type(value)=='table'and
            (kind=='InventoryItem'and(value.class=='Literature'or value.class=='ComboItem')
                or kind=='IsoGameCharacter'and value.class=='IsoPlayer')
    end
    getClassSimpleName=function(value)return value.class end
    local function square(x)
        local s={class='IsoGridSquare',x=x or 0}
        s.getX=function(self)return self.x end;s.getY=function()return 0 end;s.getZ=function()return 0 end
        s.getObjects=function()return {contains=function(_,object)return object:getSquare()==s and not object.gone end}end
        s.getDeviceData=function(self)return self.deviceData end
        state.squares[s.x]=s
        return s
    end
    local origin=square(0)
    f.player.getCurrentSquare=function()return origin end
    getCell=function()return {getGridSquare=function(_,x,y,z)if y==0 and z==0 then return state.squares[x]end end}end
    local function container(world)
        local c={class='ItemContainer',world=world,capacity=50,load=0}
        c.getType=function(self)return self.world and 'crate'or 'none'end
        c.getContainingItem=function()end;c.getVehiclePart=function()end;c.getAcceptItemFunction=function()end;c.getOnlyAcceptCategory=function()end
        c.isExistYet=function(self)return not self.gone end;c.isVehicleSeat=function()return false end
        c.isInCharacterInventory=function(self)return not self.world end
        c.getCapacityWeight=function(self)return self.load end;c.getEffectiveCapacity=function(self)return self.capacity end
        c.getMaxWeight=function(self)return self.capacity end
        c.contains=function(self,item)return item.container==self end
        c.getItemById=function(self,id)for _,item in ipairs(state.items)do if item.id==id and item.container==self then return item end end end
        c.getItems=function(self)
            local values={};for _,item in ipairs(state.items)do if item.container==self then values[#values+1]=item end end
            return {size=function()return #values end,get=function(_,i)return values[i+1]end}
        end
        c.isRemoveItemAllowed=function()return true end;c.isItemAllowed=function()return true end
        c.getSourceGrid=function()return world and origin or nil end
        local parent={class='IsoObject',getSquare=function()return origin end,getContainerCount=function()return 1 end,
            getContainerByIndex=function()return c end}
        c.getParent=function()return world and parent or f.player end
        c.getOutermostContainer=function(self)return self end
        return c
    end
    local root,world=container(),container(true);f.player.inventory=root
    local function item(kind,where)
        state.nextId=state.nextId+1
        local value={class='ComboItem',id=state.nextId,kind=kind or 'Base.VHS',container=where or root,weight=1,media=7,pages=100}
        value.getID=function(self)return self.id end;value.getFullType=function(self)return self.kind end
        value.getType=function(self)return self.kind:match('[^.]+$')end
        value.getContainer=function(self)return self.container end
        value.getNumberOfPages=function(self)return self.pages end;value.getSkillTrained=function()return 'Woodwork'end
        value.getLvlSkillTrained=function()return 1 end;value.getMaxLevelTrained=function()return 2 end
        value.getAlreadyReadPages=function(self)return self.readPages or 0 end
        value.setAlreadyReadPages=function(self,pages)self.readPages=pages;state.writes=state.writes+1 end
        value.hasTag=function()return false end
        value.getIsCraftingConsumed=function(self)return self.consumed or false end
        value.getWorldItem=function()end;value.getEquipParent=function()end;value.getAttachedSlot=function()return -1 end
        value.getFluidContainer=function()end;value.isFavorite=function()return false end
        value.getActualWeight=function(self)return self.weight end;value.getUnequippedWeight=function(self)return self.weight end
        value.isRecordedMedia=function()return true end;value.getMediaType=function()return 1 end
        value.getRecordedMediaIndex=function(self)return self.media end
        state.items[#state.items+1]=value
        return value
    end
    local function tv(kind)
        local s=square(1)
        local d={class='DeviceData',on=true,power=1,volume=0.5,channel=200,mic=false,media=false,playing=false}
        local t={class=kind or 'IsoTelevision'}
        t.getObjectIndex=function(self)return self.gone and -1 or 0 end;t.getSquare=function(self)return not self.noSquare and s or nil end
        t.getDeviceData=function()return d end
        d.getParent=function(self)return self.wrongParent or t end;d.isIsoDevice=function()return true end;d.isVehicleDevice=function()return false end
        d.getIsTurnedOn=function(self)return self.on end;d.getPower=function(self)return self.power end
        d.getDeviceVolume=function(self)return self.volume end;d.getChannel=function(self)return self.channel end;d.getMicIsMuted=function(self)return self.mic end
        d.getIsBatteryPowered=function()return false end;d.canBePoweredHere=function(self)return self.powerable~=false end
        d.getMinChannelRange=function()return 100 end;d.getMaxChannelRange=function()return 1000 end
        d.getMediaType=function()return 1 end;d.hasMedia=function(self)return self.media~=false end
        d.getMediaIndex=function(self)return self.media or -1 end;d.isPlayingMedia=function(self)return self.playing end
        for _,name in ipairs({'setIsTurnedOn','setDeviceVolume','setChannel','setMicIsMuted','removeMediaItem','addMediaItem','StartPlayMedia','StopPlayMedia'})do
            d[name]=function()state.writes=state.writes+1;error('planning executed a device effect: '..name)end
        end
        s.deviceData=d
        return t,d,s
    end
    -- Shared mods run before client Policy snapshots the actual action bindings.
    if lightSwitch then assert(loadstring(read(assert(customLightSwitchSource)),'@'..customLightSwitchSource))()end
    local definitions=f.project('ActionQueueDefinitions')
    local operations=f.project('ActionQueueOperations')
    local radio=f.project('ActionQueueEditAdapters')
    local itemAdapters=f.project('ActionQueueItemEditAdapters')
    local weights=PZSurvivorToolkit.ActionQueueWeights or f.project('ActionQueueWeights')
    local savedRequire=require
    require=function(module)
        if module=='PZSurvivorToolkit/ActionQueueItemEditAdapters'then return itemAdapters end
        if module=='PZSurvivorToolkit/ActionQueueEditAdapters'then return radio end
        if module=='PZSurvivorToolkit/ActionQueueWeights'then return weights end
        return savedRequire(module)
    end
    f.project('ActionQueueEditModel')
    local policy=f.project('ActionQueuePolicy');policy.installContracts()
    if loadQueue then f.project('ActionQueueLabels');f.project('ActionQueue')end
    getActivatedMods=function()return {contains=function()return binding==true end}end
    if binding then assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/TVMediaAction.lua'))()end
    local media=f.project('ActionQueueMedia')
    local installed=media.install()
    if changed~='ISBaseTimedAction.lua'and changed~='reader'then assert(installed,'actual media sources must install')end
    local recovery=f.project('ActionQueueRecoveryAdapters')
    local function radioAction(mode,value,target)return ISRadioAction:new(mode,f.player,target,value)end
    local function mediaAction(tape,target,remove)return ISDeviceMediaAction:new(f.player,remove==true,tape,target:getSquare())end
    local function book(where)
        local b=item('Base.BookCarpentry1',where);b.class='Literature'
        local action=ISReadABook:new(f.player,b)
        return action,b
    end
    return {f=f,recovery=recovery,operations=operations,state=state,root=root,world=world,item=item,tv=tv,square=square,
        radio=radioAction,media=mediaAction,book=book,itemAdapters=itemAdapters}
end
local function capture(s,action,active)
    local record,reason=s.recovery.capture(action,active)
    assert(record,reason or 'capture failed')
    assert(record.action==nil and record.toolkitQueueOperation==nil and record.receipt==nil)
    return record
end

-- Planning and recapturing a recovered read are pure; its actual constructor is delayed.
do
    local s=setup();local action,book=s.book()
    action.action={isStarted=function()return true end}
    s.state.pages={['Base.BookCarpentry1']=25}
    local record=capture(s,action,true)
    local writes=s.state.writes
    local planned=assert(s.recovery.plan({record},s.f.player))
    assert(s.state.writes==writes and #planned==1 and planned[1].Type=='ISQueueActionsAction')
    local again=capture(s,planned[1],false)
    assert(again~=record and again.kind=='read'and again.itemId==book.id)
    local nextPlan=assert(s.recovery.plan({again},s.f.player))
    assert(nextPlan[1]~=planned[1]and nextPlan[1].toolkitQueueOperation==nil)
    -- Run only the owned deferred callback; native constructor must honor saved pages now.
    local added;ISTimedActionQueue.add=function(value)added=value end
    nextPlan[1].addActionsFunction(s.f.player,unpack(nextPlan[1].args))
    assert(added and added.Type=='ISReadABook'and added.startPage==25 and added~=action and s.state.writes>writes)
    s.state.pages['Base.BookCarpentry1']=100
    assert(not s.recovery.plan({record},s.f.player),'completed persistent books are not replayed')
end
do
    local s=setup();local action,book=s.book()
    book.getSkillTrained=function()return 'unknown'end
    assert(not s.recovery.capture(action,true),'active non-skill literature has no audited resume')
    assert(s.recovery.capture(action,false),'never-started positive-page reading can be reconstructed')
    action.onCompleteFunc=function()error('capture invoked a callback')end
    assert(not s.recovery.capture(action,false),'callback-bearing reading is unsupported')
end

-- Real controls are projected in order without mutating their actual device.
do
    local s=setup();local tv,data=s.tv();data.on=false
    local records={capture(s,s.radio('ToggleOnOff',nil,tv)),capture(s,s.radio('SetVolume',0.25,tv)),
        capture(s,s.radio('MuteVolume',nil,tv)),capture(s,s.radio('UnMuteVolume',0.4,tv)),
        capture(s,s.radio('SetChannel',300,tv)),capture(s,s.radio('MuteMicrophone',false,tv))}
    local planned=assert(s.recovery.plan(records,s.f.player))
    assert(#planned==6 and data.on==false and data.volume==0.5 and data.channel==200 and s.state.writes==0)
    assert(planned[2].secondaryItem==0.25 and planned[6].secondaryItem==false and planned[1].maxTime==30)
    assert(not s.recovery.plan({records[2]},s.f.player),'a pending setter cannot assume the TV is on')
    data.on=true
    assert(not s.recovery.plan({records[4]},s.f.player),'unmute requires projected zero volume')
    data.power=0
    assert(not s.recovery.plan({records[2]},s.f.player),'setters retain their native power requirement')
    data.power=1;data.powerable=false
    assert(not s.recovery.plan({records[1]},s.f.player),'mains powerability is live')
    data.powerable=true;tv.gone=true
    assert(not s.recovery.plan(records,s.f.player),'gone exact target cannot recover')
end
do
    local s=setup();local tv,data=s.tv('IsoRadio')
    assert(s.recovery.plan({capture(s,s.radio('SetVolume',0.3,tv))},s.f.player))
    assert(not s.recovery.capture(s.radio('ToggleOnOff',nil,tv)),'battery/radio power toggles remain unsupported')
    assert(not s.recovery.capture(s.radio('SetVolume',0.3,tv),true),'active controls are never replayed')
    assert(not s.recovery.capture(s.radio('AddHeadphones',s.item(),tv)),'paid equipment is unsupported')
end

-- TV insert/play/eject use projected media, including the installed ownership wrapper.
for _,binding in ipairs({false,true})do
    local s=setup(nil,binding);local tv,data=s.tv();local tape=s.item()
    local insert=capture(s,s.media(tape,tv,false))
    local play=capture(s,s.radio('TogglePlayMedia',nil,tv))
    local eject=capture(s,s.media(nil,tv,true))
    local planned=assert(s.recovery.plan({insert,play,eject},s.f.player))
    assert(#planned==3 and planned[1].secondaryItem==tape and planned[3].isRemove==true
        and tape.container==s.root and data.media==false and s.state.writes==0)
    assert(not s.recovery.plan({play},s.f.player),'play needs a real or preceding inserted cassette')
    assert(not s.recovery.plan({eject},s.f.player),'empty-at-capture eject needs the captured prefix insertion')
    assert(not s.recovery.plan({insert,insert},s.f.player),'one exact tape cannot be debited twice')
    data.media=11
    local occupiedEject=capture(s,s.media(nil,tv,true))
    assert(s.recovery.plan({occupiedEject,insert},s.f.player),'prior eject can make room for a real tape')
    data.media=12
    assert(not s.recovery.plan({occupiedEject},s.f.player),'a different live VHS is not the old ejection target')
    assert(not s.recovery.capture(s.media(tape,tv,false),true),'active media has uncertain paid effects')
end

-- Pending singleton transfers use the actual native constructor and existing helper guards.
do
    local s=setup();local tv,data=s.tv();local tape=s.item('Base.VHS',s.world)
    local transfer=ISInventoryTransferAction:new(s.f.player,tape,s.world,s.root)
    local pickup=capture(s,transfer)
    local insert=capture(s,s.media(tape,tv,false))
    local play=capture(s,s.radio('TogglePlayMedia',nil,tv))
    local planned=assert(s.recovery.plan({pickup,insert,play},s.f.player))
    assert(#planned==3 and planned[1]~=transfer and planned[1].queueList~=transfer.queueList
        and planned[1].maxTime==transfer.maxTime and tape.container==s.world and s.state.writes==0)
    assert(not s.recovery.plan({insert,play},s.f.player),'projected pickup is required before insertion')
    s.root.capacity=1
    assert(not s.recovery.plan({pickup,insert},s.f.player),'planned media consumption cannot finance the pickup')
    s.root.capacity=50
    data.media=4
    local eject=capture(s,s.media(nil,tv,true))
    assert(not s.recovery.plan({eject,pickup},s.f.player),'unproven ejection output cannot certify later pickup capacity')
    transfer.queueList[1].items[2]=s.item()
    assert(not s.recovery.capture(transfer),'merged native transfer membership is unsupported')
end
do
    local s=setup();local item=s.item('Base.A',s.world)
    local original=ISInventoryTransferAction:new(s.f.player,item,s.world,s.root)
    local record=capture(s,original)
    item.weight=2
    local planned=assert(s.recovery.plan({record},s.f.player))
    local fresh=ISInventoryTransferAction:new(s.f.player,item,s.world,s.root)
    assert(planned[1].maxTime==fresh.maxTime and planned[1].maxTime~=original.maxTime,'transfer duration uses current native constructor inputs')
end
do
    local s=setup();local action,book=s.book(s.world)
    local pickup=capture(s,ISInventoryTransferAction:new(s.f.player,book,s.world,s.root))
    local reading=capture(s,action)
    local writes=s.state.writes
    assert(s.recovery.plan({pickup,reading},s.f.player),'projected existing book pickup satisfies reading')
    assert(s.state.writes==writes and book.container==s.world)
    assert(not s.recovery.plan({reading},s.f.player),'reading cannot invent the absent pickup')
    book.container=nil
    assert(not s.recovery.plan({pickup,reading},s.f.player),'missing item cannot be substituted')
end
do
    local s=setup();local a,b=s.item('Base.A',s.world),s.item('Base.B',s.world)
    local ra=capture(s,ISInventoryTransferAction:new(s.f.player,a,s.world,s.root))
    local rb=capture(s,ISInventoryTransferAction:new(s.f.player,b,s.world,s.root))
    s.root.capacity=1.5
    assert(s.recovery.plan({ra},s.f.player)and not s.recovery.plan({ra,rb},s.f.player),'cumulative incoming load is bounded')
end

do
    local s=setup();local target=s.square(5)
    local walk=ISWalkToTimedAction:new(s.f.player,target)
    local record=capture(s,walk)
    local planned=assert(s.recovery.plan({record},s.f.player))
    assert(planned[1]~=walk and planned[1].location==target and planned[1].maxTime==-1 and planned[1].stopOnRun==false)
    assert(not s.recovery.capture(walk,true),'active movement is not an audited paid-state resume')
    walk.additionalTest=function()error('capture invoked walk callback')end
    assert(not s.recovery.capture(walk),'walk callbacks cannot reconstruct arbitrary follow-up actions')
    s.state.squares[5]=s.square(5)
    assert(not s.recovery.plan({record},s.f.player),'replacement square identity is rejected')
end

-- Production hook order installs Queue's begin/stop before Media and Recovery.
do
    local s=setup(nil,true,true);local action=s.book();local tv=s.tv()
    local records={capture(s,action),capture(s,s.radio('SetVolume',0.3,tv)),capture(s,s.media(s.item(),tv,false))}
    local writes=s.state.writes
    assert(s.recovery.plan(records,s.f.player),'actual Queue/Policy begin and stop adoption retains recovery')
    assert(s.state.writes==writes,'production hooks do not make a read preview effectful')
end

-- A locally replaced command lifecycle must not escape the deferred-read guard.
do
    local s=setup();local action=s.book();local record=capture(s,action)
    local writes=s.state.writes
    ISQueueActionsAction.isValid=function()s.state.writes=s.state.writes+1;error('foreign command validity must not execute')end
    assert(not s.recovery.plan({record},s.f.player),'canonical command lifecycle is required after command construction')
    assert(s.state.writes==writes)
end

if customLightSwitchSource then
    local s=setup(nil,false,true,true)
    local action,book=s.book();local record=capture(s,action)
    action.action={isStarted=function()return true end}
    local active=capture(s,action,true)
    local writes=s.state.writes
    local planned=assert(s.recovery.plan({active},s.f.player))
    assert(s.recovery.plan({record},s.f.player)and s.state.writes==writes,'exact upstream complete wrapper retains pure active/pending reconstruction')
    local wrapper=ISReadABook.complete
    local added;ISTimedActionQueue.add=function(value)added=value end
    planned[1].addActionsFunction(s.f.player,unpack(planned[1].args))
    assert(added and added.complete==wrapper,'reconstructed native reading keeps the real installed completion wrapper')
    local paid,syncs,items=0,0,0
    addXpMultiplier=function()paid=paid+1 end
    sendSyncPlayerFields=function()syncs=syncs+1 end
    syncItemFields=function()items=items+1 end
    book.setJobDelta=function()end;book.getLearnedRecipes=function()end;book.hasModData=function()return false end
    s.f.player.getXp=function()return {getMultiplier=function()return 3 end}end
    s.f.player.isRecipeActuallyKnown=function()error('ordinary skill book must not enter the magazine recipe branch')end
    HaloTextHelper={addGoodText=function()error('ordinary skill book must not announce the magazine recipe')end}
    assert(added:complete()==true and paid==1 and syncs==1 and items==1 and book.readPages==100,
        'actual upstream wrapper delegates the native completion once without its magazine effects')
    book.kind='Base.Mag_LightSwitch'
    assert(not s.recovery.capture(action,true)and not s.recovery.capture(action,false),'the special magazine branch is unsupported')
    local generic,genericItem=s.book();genericItem.getSkillTrained=function()return 'unknown'end
    assert(not s.recovery.capture(generic,true),'generic active literature remains uncertain under the wrapper')
    for _,changed in ipairs({'custom-source','unknown-wrapper'})do
        local other=setup(changed=='custom-source'and changed or nil,false,true,true)
        local reading=other.book();local captured
        if changed=='unknown-wrapper'then
            captured=capture(other,reading)
            ISReadABook.complete=function()error('unknown wrapper must not execute')end
            assert(not other.recovery.plan({captured},other.f.player),'a later unknown completion wrapper revokes the plan')
        end
        assert(not other.recovery.capture(reading),'changed/unknown completion proof is rejected')
    end
    print('Recovery CustomLightSwitch: actual source, native delegation, pure reconstruction, magazine exclusion and closed changed wrappers passed.')
else
    print('Recovery CustomLightSwitch SKIP (set PZ_CUSTOM_LIGHT_SWITCH_SOURCE to the upstream CustomLightSwitch_ReadFix.lua).')
end

-- Source/callback failures are closed before any new constructor can execute.
for _,file in ipairs({'ISReadABook.lua','WalkToTimedAction.lua','ISBaseTimedAction.lua'})do
    local s=setup(file);local action=s.book()
    local walk=ISWalkToTimedAction:new(s.f.player,s.square(5))
    if file~='WalkToTimedAction.lua'then assert(not s.recovery.capture(action))end
    if file~='ISReadABook.lua'then assert(not s.recovery.capture(walk))end
end
do
    local s=setup('reader');local book=s.book();local tv=s.tv()
    local writes=s.state.writes
    assert(not s.recovery.capture(book)and not s.recovery.capture(s.radio('SetVolume',0.2,tv)))
    assert(not s.recovery.capture(s.media(s.item(),tv,false)))
    assert(s.state.writes==writes,'malformed source readers fail without item or device effects')
end
for _,kind in ipairs({'read','walk','radio','media','transfer'})do
    local s=setup();local tv=s.tv();local action
    if kind=='read'then action=s.book()
    elseif kind=='walk'then action=ISWalkToTimedAction:new(s.f.player,s.square(5))
    elseif kind=='radio'then action=s.radio('SetVolume',0.2,tv)
    elseif kind=='media'then action=s.media(s.item(),tv,false)
    else action=ISInventoryTransferAction:new(s.f.player,s.item('Base.A',s.world),s.world,s.root)end
    local record=capture(s,action)
    local class=getmetatable(action)
    local writes=s.state.writes
    class.new=function()s.state.writes=s.state.writes+1;error('foreign constructor must not execute')end
    assert(not s.recovery.plan({record},s.f.player),kind..' changed constructor is rejected before invocation')
    assert(s.state.writes==writes,kind..' rejected constructor has no effects')
end
do
    local s=setup();local tv=s.tv()
    local record=capture(s,s.media(s.item(),tv,false))
    ISDeviceBatteryAction.getDeviceDataFromParameter=function()s.state.writes=s.state.writes+1;error('foreign helper')end
    assert(not s.recovery.plan({record},s.f.player)and s.state.writes==0,'changed constructor helper is rejected without effects')
end
print('Recovery adapters: actual native reconstruction, pure preview, projected TV/item dependencies, repeated recovery and closed unsupported effects passed.')
