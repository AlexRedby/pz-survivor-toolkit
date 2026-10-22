if not NativeActionRoot then print('Firearm queue native contracts SKIP (pass --native-action-root).');return end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function list(values)
    return {size=function()return #values end,get=function(_,index)return values[index+1]end,
        getItemByIndex=function(_,index)return values[index+1]end,isEmpty=function()return #values==0 end}
end
local function setup(changedSource,companionOrder,deletedBeforeCapture)
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local fixtureRequire=require
    local proof=fixtureRequire('PZSurvivorToolkit/SourceProof')
    local realMatches=proof.matches
    local companionPins={['media/lua/shared/WPANC_BowReload.lua']=3277238911,
        ['media/lua/shared/WPANC_ArcheryContract.lua']=848735890}
    local pinReads={}
    -- These unit cases exercise admission plumbing with filename-tagged fixture
    -- closures. Only companion file pins are stubbed; native files remain real.
    proof.matches=function(path,expected,mod,adler,limit)
        if mod then
            pinReads[path]=(pinReads[path]or 0)+1
            return mod=='WildernessProgressionArcheryNexusCompanion'and adler==true
                and companionPins[path]~=nil and companionPins[path]==expected
                and not (changedSource and path:find(changedSource,1,true))
        end
        return realMatches(path,expected,mod,adler,limit)
    end
    require=function(name)
        if name=='PZSurvivorToolkit/SourceProof'then return proof end
        if name=='PZSurvivorToolkit/ActionQueueFirearms' then return PZSurvivorToolkit.ActionQueueFirearms end
        return fixtureRequire(name)
    end
    WPANC=nil
    local function native(path)
        assert(loadstring(read(NativeActionRoot..'/'..path),'@media/lua/'..path))()
    end
    native('shared/TimedActions/ISBaseTimedAction.lua')
    native('shared/TimedActions/ISReadABook.lua')
    native('client/TimedActions/ISInventoryTransferAction.lua')
    Events.OnPressReloadButton={Add=function()end};Events.OnPressRackButton={Add=function()end}
    Events.OnWeaponSwingHitPoint={Add=function()end};Events.OnPlayerAttackFinished={Add=function()end}
    Hook={Attack={Add=function()end}}
    native('shared/TimedActions/ISReloadWeaponAction.lua')
    native('shared/TimedActions/ISRackFirearm.lua')
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if changedSource and path:find(changedSource,1,true) then text=text..'-- unreviewed source\n' end
        local offset=1
        return {close=function()end,readLine=function()
            if offset>#text then return end
            local boundary=text:find('\n',offset,true)or #text+1
            local line=text:sub(offset,boundary-1);offset=boundary+1;return line
        end}
    end
    local client,server=false,false
    isClient=function()return client end;isServer=function()return server end
    CharacterActionAnims={Reload='reload'};WeaponReloadType={SHOTGUN='shotgun',HANDGUN='handgun'}
    Perks={Reloading='reload'};MoodleType={PANIC='panic'}
    ItemBodyLocation={AMMO_STRAP='strap'}
    ItemTag={RELOAD_FAST_SHELLS='shells',RELOAD_FAST_BULLETS='bullets',RELOAD_FAST_MAGAZINES='magazines'}
    ItemType={NORMAL='base:normal'}
    local nativeGlobals={}
    getClassSimpleName=function(value)
        if nativeGlobals[value] then return 'LuaJavaInvoker' end
        if type(value)=='function' then return 'KahluaClosure' end
        return type(value)=='table'and value.class or nil
    end
    nativeGlobals[getClassSimpleName]=true
    local baseInstanceof=instanceof
    instanceof=function(value,name)
        return baseInstanceof(value,name)or type(value)=='table'and
            (name=='InventoryItem'and value.class=='HandWeapon'or name=='IsoGameCharacter'and value.class=='IsoPlayer')
    end
    local player=f.player;player.class='IsoPlayer';player.worn={};player.vars={}
    player.getPrimaryHandItem=function()return player.primary end
    player.getSecondaryHandItem=function()return player.secondary end
    player.getWornItems=function()return list(player.worn)end
    player.getWornItem=function()return player.strap end
    player.hasEquippedTag=function()return false end;player.hasWornTag=function()return false end
    player.getPerkLevel=function()return 0 end;player.getVehicle=function()end
    player.getVariableFloat=function(_,key,default)return player.vars[key]or default end
    player.setVariable=function(_,key,value)player.vars[key]=value end
    player.clearVariable=function(_,key)player.vars[key]=nil end
    player.isAiming=function()return false end;player.getAimingDelay=function()return 0 end
    player.setAimingDelay=function()end;player.reportEvent=function()end;player.playSound=function()end
    player.getEmitter=function()return {playSound=function()end}end
    player.setIsFarming=function()end
    local inventory={class='ItemContainer',items={}}
    player.inventory=inventory
    inventory.AddItem=function(_,item)inventory.items[#inventory.items+1]=item;return item end
    inventory.getItemById=function(_,id)for _,item in ipairs(inventory.items)do if item:getID()==id then return item end end end
    inventory.contains=function(_,wanted)for _,item in ipairs(inventory.items)do if item==wanted then return true end end;return false end
    inventory.getParent=function()return player end;inventory.getContainingItem=function()end
    inventory.getType=function()return 'inventory'end;inventory.getAcceptItemFunction=function()end
    inventory.getItems=function()return list(inventory.items)end
    inventory.getCapacityWeight=function()return #inventory.items end;inventory.getEffectiveCapacity=function()return 50 end
    local scripts={}
    ScriptManager={instance={getItem=function(_,key)return scripts[key]end,FindItem=function(_,key)return scripts[key]end}}
    local function script(key,count)
        local value={class='Item',key=key,count=count or 1}
        value.getFullName=function(self)return self.key end;value.getModuleName=function()return 'Base'end
        value.getName=function(self)return self.key:match('%.(.+)$')end
        value.getItemType=function()return ItemType.NORMAL end;value.getTypeString=value.getItemType
        value.getCount=function(self)return self.count end
        value.getObsolete=function(self)return self.obsolete or false end;value.isObsolete=value.getObsolete
        value.getLuaCreate=function(self)return self.luaCreate end;value.getItemConfig=function(self)return self.config end
        value.getItemConfigKey=function(self)return self.configKey end
        value.hasComponents=function(self)return self.components and #self.components>0 or false end
        value.getComponents=function(self)return list(self.components or {})end
        value.containsComponent=function(self)return self.components and #self.components>0 or false end
        for _,name in ipairs({'getReplaceOnUse','getReplaceOnDeplete','getReplaceOnUseOn','getOnCreate','getOnBreak'})do
            value[name]=function(self)return self[name..'Value']end
        end
        scripts[key]=value;return value
    end
    AmmoType={}
    local keys={BULLETS_9MM='Base.Bullets9mm',SHOTGUN_SHELLS='Base.ShotgunShells',BULLETS_38='Base.Bullets38',
        BULLETS_3030='Base.Bullets3030',BULLETS_308='Base.Bullets308',BULLETS_357='Base.Bullets357',
        BULLETS_44='Base.Bullets44',BULLETS_45='Base.Bullets45',BULLETS_556='Base.Bullets556',CAP_GUN_CAP='Base.CapGunCap'}
    for name,key in pairs(keys)do
        local ammo={class='AmmoType',key=key,getItemKey=function(self)return self.key end}
        AmmoType[name]=ammo;script(key,name=='BULLETS_9MM'and 5 or name=='SHOTGUN_SHELLS'and 6 or 1)
    end
    local created,synced,sent,scheduled=0,0,0,{}
    instanceItem=function(key)created=created+1;return f.item(key)end
    syncHandWeaponFields=function()synced=synced+1 end
    sendAddItemToContainer=function()sent=sent+1 end
    emulateAnimEventOnce=function(net,time,event,parameter)scheduled[#scheduled+1]={net=net,time=time,event=event,parameter=parameter}end
    for _,name in ipairs({'instanceItem','syncHandWeaponFields','sendAddItemToContainer','emulateAnimEventOnce'})do nativeGlobals[_G[name]]=true end
    local function gun(ammo)
        local value=f.item('Base.Pistol');value.class='HandWeapon';value.ammoType=ammo or AmmoType.BULLETS_9MM
        value.ammo=2;value.chamber=true;value.have=true;value.jammed=false;value.spent=0;value.spentChamber=false
        value.getAmmoType=function(self)return self.ammoType end
        value.getScriptItem=function()return scripts['Base.Pistol']or script('Base.Pistol')end
        value.getMagazineType=function()return 'Base.9mmClip'end
        value.haveChamber=function(self)return self.have end
        value.isRoundChambered=function(self)return self.chamber end;value.setRoundChambered=function(self,v)self.chamber=v end
        value.isSpentRoundChambered=function(self)return self.spentChamber end;value.setSpentRoundChambered=function(self,v)self.spentChamber=v end
        value.getSpentRoundCount=function(self)return self.spent end;value.setSpentRoundCount=function(self,v)self.spent=v end
        value.isJammed=function(self)return self.jammed end;value.setJammed=function(self,v)self.jammed=v end
        value.getCurrentAmmoCount=function(self)return self.ammo end;value.setCurrentAmmoCount=function(self,v)self.ammo=v end
        value.getAmmoPerShoot=function()return 1 end;value.getJamGunChance=function(self)return self.jamChance or 0 end
        value.checkUnJam=function(self)if not self.failUnjam then self.jammed=false end;return self.jammed end
        value.checkJam=function(self)self.jammed=true end
        value.getWeaponReloadType=function()return WeaponReloadType.HANDGUN end
        value.getAimingTime=function()return 10 end;value.getWeaponSprite=function()return 'pistol'end
        for _,name in ipairs({'getShellFallSound','getEjectAmmoStopSound','getRackSound','getEjectAmmoStartSound','getEjectAmmoSound'})do value[name]=function()end end
        inventory.items[#inventory.items+1]=value;return value
    end
    local function action(weapon)
        local value=ISRackFirearm:new(player,weapon)
        value.toolkitQueueOperation={}
        value.action={setAnimVariable=function()end,setOverrideHandModelsObject=function()end,setActionAnim=function()end,
            forceComplete=function()value.finished=(value.finished or 0)+1 end}
        value.netAction={forceComplete=function()value.finished=(value.finished or 0)+1 end}
        return value
    end
    local companionCalls={hook=0,bow=0,archery=0}
    local function installCompanion()
        local archery={BowFullType='Base.Primitive_Bow'}
        archery.isPrimitiveBow=assert(loadstring([[
            return function(ArcheryContract,calls)return function(item)
                calls.archery=calls.archery+1
                return item~=nil and type(item.getFullType)=='function'
                    and item:getFullType()==ArcheryContract.BowFullType
            end end]],'@media/lua/shared/WPANC_ArcheryContract.lua'))()(archery,companionCalls)
        local bow={}
        bow.isPrimitiveBow=assert(loadstring([[
            return function(ArcheryContract,calls)return function(item)
                calls.bow=calls.bow+1
                return ArcheryContract.isPrimitiveBow(item)
            end end]],'@media/lua/shared/WPANC_BowReload.lua'))()(archery,companionCalls)
        local original=ISReloadWeaponAction.canRack
        bow._originalCanRack=original
        bow._canRackHook=assert(loadstring([[
            return function(BowReload,originalCanRack,calls)return function(weapon)
                calls.hook=calls.hook+1
                if BowReload.isPrimitiveBow(weapon)then return false end
                return originalCanRack(weapon)
            end end]],'@media/lua/shared/WPANC_BowReload.lua'))()(bow,original,companionCalls)
        WPANC={BowReload=bow,ArcheryContract=archery}
        ISReloadWeaponAction.canRack=bow._canRackHook
        return WPANC
    end
    if companionOrder=='before'then installCompanion()end
    if deletedBeforeCapture then
        local owners={rack=ISRackFirearm,base=ISBaseTimedAction,reload=ISReloadWeaponAction}
        owners[deletedBeforeCapture.owner][deletedBeforeCapture.name]=nil
    end
    local firearms=f.project('ActionQueueFirearms');PZSurvivorToolkit.ActionQueueFirearms=firearms
    if companionOrder=='after'then installCompanion()end
    return {f=f,player=player,inventory=inventory,gun=gun,action=action,firearms=firearms,scripts=scripts,script=script,
        mode=function(c,s)client,server=c,s end,
        counts=function()return created,synced,sent end,scheduled=scheduled,nativeGlobals=nativeGlobals,
        proof=proof,pinReads=pinReads,companionCalls=companionCalls,installCompanion=installCompanion}
end

for owner,names in pairs({rack={'removeBullet','rackBullet','animEvent','stop'},
    base={'stop','perform','forceCancel'},reload={'canRack','setReloadSpeed','getReloadTime'}})do
    for _,name in ipairs(names)do
        local s=setup(nil,nil,{owner=owner,name=name});local gun=s.gun();local action=s.action(gun)
        if owner=='rack'and name=='stop'then
            assert(ISRackFirearm.stop==ISBaseTimedAction.stop,
                'fixture deletes the own rack stop while leaving the inherited native base stop visible')
        end
        assert(not s.firearms.rack(action),'missing '..owner..'.'..name..' before capture keeps fallback')
        local created,synced,sent=s.counts()
        assert(created==0 and synced==0 and sent==0 and gun.ammo==2 and gun.chamber,
            'missing callback proof does not execute native action effects')
    end
end

-- WPANC fixtures reproduce only its pure canRack delegation/predicates and
-- record invocation. They do not load the actual companion or its bow actions.
local function noCompanionEffects(s,gun)
    local created,synced,sent=s.counts()
    assert(created==0 and synced==0 and sent==0 and gun.ammo==2 and gun.chamber,
        'companion proof inspection does not mutate weapon/inventory or emit transport')
    assert(s.companionCalls.hook==0 and s.companionCalls.bow==0 and s.companionCalls.archery==0,
        'companion proof never executes canRack or either primitive-bow predicate')
end
for _,order in ipairs({'before','after'})do
    local s=setup(nil,order);local gun=s.gun();local action=s.action(gun)
    assert(s.firearms.rack(action),'verified companion canRack is admitted when loaded '..order..' capture')
    assert(s.firearms.rack(action),'cached companion proof preserves the next decision')
    assert(s.pinReads['media/lua/shared/WPANC_BowReload.lua']==1
        and s.pinReads['media/lua/shared/WPANC_ArcheryContract.lua']==1,'only exact companion file pins are cached')
    noCompanionEffects(s,gun)
    -- Execute the fixture wrapper separately to establish what the unit proof
    -- represents, without claiming this is the installed companion execution.
    assert(ISReloadWeaponAction.canRack(gun),'non-bow delegates to the real native canRack')
    assert(not ISReloadWeaponAction.canRack({getFullType=function()return 'Base.Primitive_Bow'end}),
        'the fixture wrapper excludes the exact primitive bow type')
end
for _,order in ipairs({'before','after'})do
    for _,path in ipairs({'WPANC_BowReload.lua','WPANC_ArcheryContract.lua','ISRackFirearm.lua'})do
        local s=setup(path,order);local gun=s.gun()
        assert(not s.firearms.rack(s.action(gun)),'changed '..path..' keeps fallback for companion loaded '..order)
        noCompanionEffects(s,gun)
    end
    for _,change in ipairs({'live-hook','hook-field','original','bow-predicate','archery-predicate',
        'wpanc-table','bow-table','archery-table','bow-type'})do
        local s=setup(nil,order);local gun=s.gun();local action=s.action(gun)
        assert(s.firearms.rack(action),'establish companion proof before '..change)
        local bow,archery=WPANC.BowReload,WPANC.ArcheryContract
        local function copy(value)local result={};for k,v in pairs(value)do result[k]=v end;return result end
        if change=='live-hook'then
            local replacement=assert(loadstring('return function()error("must not execute changed hook")end',
                '@media/lua/shared/WPANC_BowReload.lua'))()
            bow._canRackHook=replacement;ISReloadWeaponAction.canRack=replacement
        elseif change=='hook-field'then bow._canRackHook=function()error('must not execute changed hook field')end
        elseif change=='original'then bow._originalCanRack=ISReloadWeaponAction.getReloadTime
        elseif change=='bow-predicate'then
            bow.isPrimitiveBow=assert(loadstring('return function()error("must not execute changed bow predicate")end',
                '@media/lua/shared/WPANC_BowReload.lua'))()
        elseif change=='archery-predicate'then
            archery.isPrimitiveBow=assert(loadstring('return function()error("must not execute changed archery predicate")end',
                '@media/lua/shared/WPANC_ArcheryContract.lua'))()
        elseif change=='wpanc-table'then WPANC=copy(WPANC)
        elseif change=='bow-table'then WPANC.BowReload=copy(bow)
        elseif change=='archery-table'then WPANC.ArcheryContract=copy(archery)
        elseif change=='bow-type'then archery.BowFullType='Base.OtherBow'end
        assert(not s.firearms.rack(action),'cached companion identity/type change '..change..' keeps fallback')
        noCompanionEffects(s,gun)
    end
end
do
    local s=setup();local gun=s.gun();local action=s.action(gun)
    ISReloadWeaponAction.canRack=assert(loadstring('return function()error("must not execute unrelated predecessor")end',
        '@media/lua/shared/TimedActions/ISReloadWeaponAction.lua'))()
    s.installCompanion()
    assert(not s.firearms.rack(action),'the captured helper must equal the companion hook or its native predecessor')
    noCompanionEffects(s,gun)
end

do
    local s=setup();local gun=s.gun();local action=s.action(gun)
    local live=s.gun();live.id=gun.id;s.inventory.items={live}
    assert(s.firearms.rack(action),'same-ID/type/ammo replica preserves the resource contract')
    live.ammoType=AmmoType.SHOTGUN_SHELLS
    assert(not s.firearms.rack(action),'same-ID replica with different ammo cannot borrow the queued output proof')
    live.ammoType=gun.ammoType;live.getFullType=function()return 'Base.Shotgun'end
    assert(not s.firearms.rack(action),'same-ID replica with different type remains protected')
    s.inventory.items={}
    assert(s.firearms.rack(action),'a gun still awaiting transfer from a bag need not be in the main inventory')
    local wrong=s.f.item('Base.Nails');wrong.id=gun.id;s.inventory.items={wrong}
    assert(not s.firearms.rack(action),'a different item class cannot acquire a gun contract by ID reuse')
end

do
    local s=setup();local gun=s.gun();local action=s.action(gun)
    local secondary=s.f.item('Base.Torch');local worn=s.f.item('Base.AmmoStrap_Bullets')
    s.player.primary=gun;s.player.secondary=secondary;s.player.worn={worn}
    local contract=assert(s.firearms.rack(action),'verified native rack has an exact resource contract')
    assert(contract.items[gun:getID()]and contract.items[secondary:getID()]and contract.items[worn:getID()])
    assert(contract.itemTypes['Base.Pistol']and contract.outputTypes['Base.Bullets9mm'])
    assert(contract.equipment==s.player and not contract.hands and contract.targets[s.inventory])
    assert(contract.cancelWaiting==false and contract.cancelOperation==false and contract.interrupt=='finish-step')
    assert(not contract.unknownOutputs and not contract.capacityNonIncreasing)
    assert(s.counts()==0 and gun.chamber and gun.ammo==2,'inspection never creates ammo or runs the timed action')
    gun.chamber=false;gun.ammo=0
    assert(s.firearms.rack(action).outputTypes['Base.Bullets9mm'],'future gun state does not hide a possible live-round output')
    gun.ammoType=AmmoType.SHOTGUN_SHELLS
    assert(s.firearms.rack(action).outputTypes['Base.ShotgunShells'],'native script count six still creates one shell')
end

-- Source/identity checks fail closed without invoking unknown action or factory callbacks.
for _,path in ipairs({'ISRackFirearm.lua','ISReloadWeaponAction.lua','ISBaseTimedAction.lua'})do
    local s=setup(path);assert(not s.firearms.rack(s.action(s.gun())),'changed '..path..' is unsupported')
end
for _,name in ipairs({'rackBullet','removeBullet','ejectSpentRounds','initVars','start','animEvent','complete'})do
    local s=setup();local action=s.action(s.gun());local previous=ISRackFirearm[name]
    ISRackFirearm[name]=function()error('must not execute replaced '..name)end
    assert(not s.firearms.rack(action),'changed rack helper '..name..' is unsupported');ISRackFirearm[name]=previous
end
for _,name in ipairs({'canRack','setReloadSpeed','getReloadTime'})do
    local s=setup();local action=s.action(s.gun());ISReloadWeaponAction[name]=function()error('must not execute helper')end
    assert(not s.firearms.rack(action),'changed reload helper '..name..' is unsupported')
end
for _,name in ipairs({'instanceItem','syncHandWeaponFields','sendAddItemToContainer','emulateAnimEventOnce','getClassSimpleName'})do
    local s=setup();local action=s.action(s.gun());_G[name]=function()error('must not call replaced global')end
    assert(not s.firearms.rack(action),'changed native global '..name..' is unsupported')
end
for _,field in ipairs({'onStartFunc','onCompleteFunc','onCancelFunc','onFailFunc','additionalTest','retriggerLastAction'})do
    local s=setup();local action=s.action(s.gun());action[field]=function()error('must not execute action callback')end
    assert(not s.firearms.rack(action),'action callback '..field..' is unsupported')
end
for _,change in ipairs({'unknown-ammo','missing-script','lua-create','config','config-key','components','replacement','obsolete','wrong-type'})do
    local s=setup();local gun=s.gun();local action=s.action(gun);local script=s.scripts['Base.Bullets9mm']
    if change=='unknown-ammo'then gun.ammoType={class='AmmoType',getItemKey=function()return 'Base.Bullets9mm'end}
    elseif change=='missing-script'then s.scripts['Base.Bullets9mm']=nil
    elseif change=='lua-create'then script.luaCreate='Unreviewed.Callback'
    elseif change=='config'then script.config={}
    elseif change=='config-key'then script.configKey='ModdedConfig'
    elseif change=='components'then script.components={{}}
    elseif change=='replacement'then script.getReplaceOnUseValue='OtherAmmo'
    elseif change=='obsolete'then script.obsolete=true
    elseif change=='wrong-type'then script.getItemType=function()return 'base:food'end end
    assert(not s.firearms.rack(action),'unsupported output '..change..' retains fallback')
    assert(s.counts()==0)
end
do
    local s=setup();local action=s.action(s.gun())
    s.nativeGlobals[instanceItem]=nil
    assert(not s.firearms.rack(action),'a Lua factory is not native merely because it was captured')
end
for _,id in ipairs({-1,1.5,'17'})do
    local s=setup();local gun=s.gun();local action=s.action(gun);gun.id=id
    assert(not s.firearms.rack(action),'noncanonical gun identity keeps fallback')
end
for _,name in ipairs({'begin','stop'})do
    local s=setup();local action=s.action(s.gun());local previous=ISBaseTimedAction[name]
    local foreign=function()error('unreviewed inherited wrapper')end
    ISBaseTimedAction[name]=foreign
    assert(not s.firearms.adoptBase(name,previous,foreign),'foreign inherited wrapper cannot be adopted')
    assert(not s.firearms.rack(action),'changed base boundary retains fallback')
    local owned=assert(loadstring('return function() end','@media/lua/client/PZSurvivorToolkit/ActionQueue.lua'))()
    ISBaseTimedAction[name]=owned
    local luaRawget=rawget
    rawget=function(owner,key)return owner[key]end -- PZ Kahlua follows inherited fields even for rawget.
    local adopted=s.firearms.adoptBase(name,previous,owned)
    rawget=luaRawget
    assert(adopted,'owned queue base boundary can be adopted with native Kahlua lookup semantics')
    assert(s.firearms.rack(action),'owned base wrapper preserves the narrow rack contract')
end

-- Execute the installed native implementation. Doubles stand in for Java state and transport only.
do
    local s=setup();local gun=s.gun();local action=s.action(gun)
    gun.spent=2;gun.spentChamber=true
    action:start()
    assert(gun.spent==0 and gun.spentChamber,'native spent-count branch does not also clear chamber flag')
    local created,synced=s.counts();assert(created==0 and synced==1,'spent ejection makes no casing item')
    action:ejectSpentRounds();assert(not gun.spentChamber and s.counts()==0)
    action:animEvent('rackBullet')
    local count,_,sent=s.counts()
    assert(count==1 and sent==1 and gun.chamber and gun.ammo==1,'SP event ejects one live round and chambers its replacement')
    action:animEvent('rackingFinished');assert(action.finished==1 and s.counts()==1,'completion does not eject again')
end
do
    local s=setup();local gun=s.gun();gun.chamber=false;gun.ammo=1
    s.action(gun):rackBullet();assert(s.counts()==0 and gun.chamber and gun.ammo==0,'empty chamber consumes internal ammo only')
    gun.have=false;gun.ammo=2
    s.action(gun):animEvent('unloadFinished')
    assert(s.counts()==1 and gun.ammo==1,'non-chamber unload returns exactly one live round')
end
do
    local s=setup();local gun=s.gun();gun.jammed=true;gun.failUnjam=true
    s.action(gun):rackBullet();assert(s.counts()==0 and gun.jammed and gun.ammo==2,'failed unjam leaves gun and ammo intact')
    gun.failUnjam=false;s.action(gun):rackBullet()
    assert(s.counts()==1 and not gun.jammed and gun.ammo==1,'successful unjam follows native live-round branch')
    gun.jamChance=1;s.action(gun):rackBullet()
    assert(s.counts()==2 and gun.jammed and gun.ammo==0,'closing the bolt can jam after live output and internal ammo debit')
end
do
    local s=setup();local gun=s.gun();local action=s.action(gun);s.mode(true,false)
    local replicated=s.gun();replicated.id=gun.id;s.inventory.items={replicated}
    action:start();action:animEvent('rackBullet');action:animEvent('unloadFinished')
    assert(action.gun==replicated,'MP start resolves the live gun by exact ID')
    assert(s.counts()==0 and replicated.ammo==2 and replicated.chamber,'MP client leaves live ammo changes to server')
    s.mode(false,true);action:serverStart()
    assert(#s.scheduled==2 and s.scheduled[1].event=='rackBullet'and s.scheduled[2].event=='rackingFinished')
    assert(s.counts()==0,'serverStart schedules live ejection; it does not perform it early')
    action:animEvent(s.scheduled[1].event);action:animEvent(s.scheduled[2].event)
    local created,_,sent=s.counts();assert(created==1 and sent==1 and replicated.ammo==1,'server event is authoritative and adds one round')
end
do
    local s=setup();s.f.project('ActionQueueOperations');s.f.project('ActionQueueDefinitions')
    local policy=s.f.project('ActionQueuePolicy')
    local gun=s.gun();local pending=s.action(gun);pending.action=nil
    local head=s.f.action(ISReadABook,{item=s.f.item('Base.BookCarpentry1')})
    local function crossing(item)
        local other=s.f.action(ISReadABook,{item=item})
        return policy.moveReason(s.f.queue(head,other,pending),pending,other)
    end
    assert(crossing(gun)=='move_shared_item','policy preserves exact gun identity dependency')
    assert(crossing(s.f.item('Base.Bullets9mm'))=='move_craft_inputs','policy protects possible ammo output by type')
    assert(not crossing(s.f.item('Base.Bullets38')),'different ammo type is independent')
    assert(not crossing(s.f.item('Base.Nails')),'unrelated borrowed material is independent')
end
do
    local s=setup();local action=s.action(s.gun());ISRackFirearm=nil
    local unavailable=s.f.project('ActionQueueFirearms')
    assert(not unavailable.rack(action),'early load without native firearm classes keeps fallback')
    assert(not unavailable.adoptBase('begin',function()end,function()end))
end
print('Firearm native resources, source/helper/output fallback and SP/Host event authority passed.')
