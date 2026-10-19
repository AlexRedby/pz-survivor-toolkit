if not NativeActionRoot or not NativeQuartermasterLuaRoot then
    print('Quartermaster manifest transfer contracts SKIP (pass native action and Quartermaster roots).');return
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','')end
    local reader=assert(io.open(path));local value=reader:read('*a');reader:close();return value:gsub('\r','')
end
local function source(value,path)return assert(loadstring(value,'@'..path))()end
local compatPath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'
local compatSource=read(compatPath)
local installer=assert(compatSource:match('(local function installManifestTransfers%(%).-\nend)'))
local query=assert(compatSource:match('(function Compat.isTransferPerform%(callback%).-\nend)'))
local adapterSource='local Toolkit,Operations,containerHelpersUnchanged=...\nlocal Compat={}\nlocal ready={}\n'
    ..'local containerTransferPerform,manifestTransferPerform,manifestHelpersUnchanged\n'
    ..installer..'\n'..query
    ..'\nreturn Compat,installManifestTransfers'
local origin=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
local function fixture(mode)
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    getFilenameOfClosure=origin
    local mp=mode=='mp'
    isClient=function()return mp end;isServer=function()return false end
    local handlers={}
    Events=setmetatable({}, {__index=function(self,name)
        local event={Add=function(fn)handlers[name]=handlers[name]or{};handlers[name][#handlers[name]+1]=fn end,Remove=function()end}
        rawset(self,name,event);return event
    end})
    ISCollapsableWindowJoypad={derive=ISBaseObject.derive}
    LootSorter={DBG=function()end}
    local stores={LootSorter_Registry={boxes={['1,2,0']=true,['4,5,0']=true}}}
    ModData={getOrCreate=function(key)stores[key]=stores[key]or{};return stores[key]end}
    local modules={}
    local function loadModule(module)
        if modules[module]then return end
        modules[module]=true
        local path=module=='LootSorter_Core'and'client/LootSorter_Core.lua'or'client/LootSorter_Manifest.lua'
        source(read(NativeQuartermasterLuaRoot..'/'..path),'media/lua/'..path)
    end
    local tags={normalizeRule=function(rule)return rule end,ruleActive=function(rule)return rule and rule.active==true end}
    PZSurvivorToolkit.ItemTags=tags
    local md={PZSTQuartermasterTagRules={['0']={active=true}}}
    local object={hasModData=function()return true end,getModData=function()return md end}
    local square={getObjects=function()return {size=function()return 1 end,get=function()return object end}end}
    local cell={getGridSquare=function()return square end}
    getCell=function()return cell end
    require=function(module)
        if module=='PZSurvivorToolkit/SourceProof' then return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))() end
        if module=='PZSurvivorToolkit/ItemTags'then return tags end
        if module=='PZSurvivorToolkit/QuartermasterTagRules'then return f.rules end
        if module=='LootSorter_Core'or module=='LootSorter_Manifest'then loadModule(module)end
    end
    source(read(NativeQuartermasterLuaRoot..'/shared/LootSorter_Util.lua'),'media/lua/shared/LootSorter_Util.lua')
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local policy=f.project('ActionQueuePolicy')
    local native=ISInventoryTransferAction.perform
    f.rules=source(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/QuartermasterTagRules.lua'),
        'PZSurvivorToolkit/QuartermasterTagRules.lua')
    f.tags,f.tagData=tags,md
    if mode=='preinstalled'then loadModule('LootSorter_Core');loadModule('LootSorter_Manifest')end
    if mode=='foreign-delegate'or mode=='fake-filename'then
        ISInventoryTransferAction.perform=mode=='fake-filename'and source('return function()error("fake manifest delegate")end','media/lua/client/LootSorter_Manifest.lua')
            or function()error('foreign predecessor')end
    end
    local bcSafe=true
    local api,install=assert(loadstring(adapterSource,'@'..compatPath))(PZSurvivorToolkit,PZSurvivorToolkit.ActionQueueOperations,function()return bcSafe end)
    install()
    return f,api,policy,native,stores,function(value)bcSafe=value end,modules
end
for _,mode in ipairs({'sp','mp','preinstalled','foreign-delegate','fake-filename'})do
    local f,api,policy,native,stores,bc,modules=fixture(mode)
    local wrapped=ISInventoryTransferAction.perform
    if mode~='sp'and mode~='preinstalled'then
        assert(not api.isTransferPerform(wrapped),'unobserved/unreviewed manifest delegation remains opaque: '..mode)
        if mode=='mp'then
            assert(wrapped==native and not modules.LootSorter_Manifest,'ineligible source/runtime must not install the SP manifest: '..mode)
        end
    else
        assert(wrapped~=native and api.isTransferPerform(wrapped),'actual reviewed SP manifest is observed and adopted')
        assert(not api.isTransferPerform(function()end),'another wrapper cannot borrow manifest permission')
        local p=f.player
        p.setIsFarming=function(self,value)self.farming=value end
        ISLogSystem={logAction=function(action)action.logged=(action.logged or 0)+1 end}
        local function container(x,y)
            local sq={getX=function()return x end,getY=function()return y end,getZ=function()return 0 end}
            return {class='ItemContainer',getType=function()return'crate'end,getContainingItem=function()end,
                getParent=function()return {getSquare=function()return sq end}end}
        end
        local function perform(callback,cancelled)
            local item=f.item('Base.Bandage');local delta
            item.setJobDelta=function(_,value)delta=value end
            local action=f.action(ISInventoryTransferAction,{item=item,srcContainer=container(1.9,2.2),destContainer=container(4,5),
                queueList={},started=true,action={stopTimedActionAnim=function()end,setLoopedAction=function()end}})
            local tail=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
            local q=f.queue(action,tail);local completed=0
            q.onCompleted=function(self,current)assert(current==action);completed=completed+1;table.remove(self.queue,1);self.current=self.queue[1]end
            assert(policy.inspect(action),'adopted actual native transfer retains its policy contract')
            if cancelled then action.toolkitQueueOperation.toolkitCancelled=true end
            PZSurvivorToolkit.ActionQueueOperations.runWith(action.toolkitQueueOperation,callback,action)
            assert(completed==1 and q.current==tail and #q.queue==1 and action.logged==1 and action.started==false
                and delta==0 and p.farming==false,'manifest must preserve native completion, item cleanup and the unrelated queue tail')
        end
        perform(native,false)
        assert(not LootSorter._manifestDirty['1,2,0'],'native baseline does not add manifest effects')
        perform(wrapped,false)
        assert(LootSorter._manifestDirty['1,2,0']and LootSorter._manifestDirty['4,5,0'],'actual manifest marks both designated container squares')
        LootSorter._manifestDirty={};stores.LootSorter_Registry.boxes['4,5,0']=nil
        perform(wrapped,true)
        assert(LootSorter._manifestDirty['1,2,0']and not LootSorter._manifestDirty['4,5,0'],
            'completed cancelled native work retains manifest cleanup and marks only designated squares')
        local owner,registry,modData,dirty=LootSorter,LootSorter.getRegistry,ModData,LootSorter._manifestDirty
        LootSorter={};assert(not api.isTransferPerform(wrapped),'replaced owner revokes the exact manifest proof');LootSorter=owner
        owner.getRegistry=function()error('foreign registry must not run under rights')end
        assert(not api.isTransferPerform(wrapped),'foreign registry getter revokes proof');owner.getRegistry=registry
        ModData={getOrCreate=modData.getOrCreate};assert(not api.isTransferPerform(wrapped),'replaced ModData owner revokes proof');ModData=modData
        local getter=modData.getOrCreate;modData.getOrCreate=function()error('foreign ModData getter must not run under rights')end
        assert(not api.isTransferPerform(wrapped),'foreign ModData getter revokes proof');modData.getOrCreate=getter
        setmetatable(dirty,{__newindex=function()error('foreign dirty table must not run under rights')end})
        assert(not api.isTransferPerform(wrapped),'dirty metatable revokes proof');setmetatable(dirty,nil)
        owner._receivedRegistry={};assert(not api.isTransferPerform(wrapped),'MP registry state cannot inherit SP manifest proof');owner._receivedRegistry=nil
        bc(false);assert(not api.isTransferPerform(wrapped),'changed predecessor BC helper revokes proof');bc(true)
        assert(api.isTransferPerform(wrapped),'restoring exact dependencies restores observed manifest proof')
        f.rules=source(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/QuartermasterTagRules.lua'),
            'PZSurvivorToolkit/QuartermasterTagRules.lua')
        assert(owner.getRegistry==registry and api.isTransferPerform(wrapped),
            'loading direct tag rules leaves the registry and manifest transfer contract unchanged')
        owner.getRegistry=function(...)return registry(...)end
        assert(not api.isTransferPerform(wrapped),'an unknown registry wrapper remains opaque')
        owner.getRegistry=registry

    end
end
print('Quartermaster manifest: native completion, queue tail, dirty marks, both load orders and changed delegate guards passed.')
