if not NativeActionRoot then return end
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local f=assert(io.open(path));local s=f:read('*a');f:close();return s:gsub('\r','')
end
local function fixture(change)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/TimedActions/ISEquipWeaponAction.lua');f.native('shared/TimedActions/ISTrimBeard.lua')
 f.native('shared/TimedActions/ISInventoryTransferUtil.lua');f.native('shared/luautils.lua')
 local actor,tool=f.player,f.item('Base.Razor')
 actor.class='IsoPlayer';actor.isLocalPlayer=function()return true end
 actor.getPrimaryHandItem=function()return actor.primary end
 actor.hasTrait=function()return false end;actor.isWearingAwkwardGloves=function()return false end
 CharacterTrait={DEXTROUS={},ALL_THUMBS={}};ItemTag={RAZOR={},SCISSORS={}}
 isClient=function()return false end;isServer=function()return false end
 getTimestampMs=function()return 1 end;getPlayerHotbar=function()return nil end
 local function container()
  return {getType=function()return'inventory'end,getParent=function()end,
   isInCharacterInventory=function()return true end,isVehicleSeat=function()return false end}
 end
 local root,bag=container(),container();actor.inventory=root
 tool.container=bag;tool.getContainer=function()return tool.container end
 tool.isBroken=function()return false end;tool.hasTag=function(_,tag)return tag==ItemTag.RAZOR end
 tool.getType=function()return'Razor'end;tool.getActualWeight=function()return .1 end
 tool.isFavorite=function()return false end;tool.isHumanCorpse=function()return false end
 tool.isRequiresEquippedBothHands=function()return false end;tool.getName=function()return'Razor'end
 root.getFirstEvalRecurse=function(_,predicate)return predicate(tool)and tool or nil end
 local function ranges(relative,spans)
  local source=read(NativeActionRoot..'/'..relative);local parts,at={},1
  for _,span in ipairs(spans)do
   local a=assert(source:find(span[1],at,true));local b=assert(source:find(span[2],a+#span[1],true))
   parts[#parts+1]=source:sub(at,a-1):gsub('[^\n]','')..source:sub(a,b-1);at=b
  end
  return assert(loadstring(table.concat(parts),'@'..relative))()
 end
 ISCharacterScreen={};ISWorldObjectContextMenu={}
 ranges('client/XpSystem/ISUI/ISCharacterScreen.lua',{{'local function predicateRazor','local function predicateDoHairdo'},
  {'ISCharacterScreen.onTrimBeard = function','ISCharacterScreen.onCutHair = function'}})
 ranges('client/ISUI/ISWorldObjectContextMenu.lua',{{'function ISWorldObjectContextMenu.transferIfNeeded','ISWorldObjectContextMenu.equip2 = function'}})
 getFirstLineOfClosure=NativeFirstLineOfClosure or function(cb)
  local first;for line in pairs(debug.getinfo(cb,'L').activelines or {})do if not first or line<first then first=line end end
  return first or debug.getinfo(cb,'S').linedefined
 end
 getFilenameOfClosure=NativeFilenameOfClosure or function(cb)return debug.getinfo(cb,'S').source:gsub('^@','')end
 getGameFilesInput=function(path)
  local source=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''));local at=1
  if change=='source'then source=source..'-- modified\n'end
  return {close=function()end,readLine=function()
   if at>#source then return end
   local b=source:find('\n',at,true)or #source+1;local s=source:sub(at,b-1);at=b+1;return s
  end}
 end
 local selected=false;getActivatedMods=function()return {contains=function()return selected end}end
 P4TidyUpMeister=nil
 getModFileReader=function(_,path)
  local source=read(ProjectRoot..'/PZSurvivorToolkit/42/'..path);local at=1
  return {close=function()end,readLine=function()
   if at>#source then return end
   local b=source:find('\n',at,true)or #source+1;local line=source:sub(at,b-1);at=b+1;return line
  end}
 end
 local operations={};PZSurvivorToolkit.ActionQueueOperations=operations
 local operationSource=read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua')
 local fragments,at={},1
 for _,span in ipairs({{'local function pack(', 'function Operations.run('},
  {'function Operations.producer(', '\nlocal function stamp('}})do
  local a=assert(operationSource:find(span[1],at,true));local b=assert(operationSource:find(span[2],a+#span[1],true))
  fragments[#fragments+1]=operationSource:sub(at,a-1):gsub('[^\n]','')..operationSource:sub(a,b-1);at=b
 end
 local run=assert(loadstring('local Operations,scope,titleScope,producerScope,completionScope,continuationScope=...;'..
  table.concat(fragments)..'\nreturn run','@ActionQueueOperations.lua'))(operations)
 local enabled=true;local seen,finished={},{}
 PZSurvivorToolkit.ActionQueueRazorRestoration={enabled=function()return enabled end}
 local consumer=PZSurvivorToolkit.ActionQueueRazorRestoration
 local producer=f.project('ActionQueueRazorProducer')
 assert(producer.dispatch==nil and not producer.bind(function()end),'a public foreign runner acquired dispatch authority')
 local dispatcher=assert(producer.bind(run),'real private Operations runner did not bind')
 assert(not producer.bind(run),'a second caller replaced the installed private runner')
 consumer.observe=function(episode,action)
  assert(producer.owns(episode));seen[#seen+1]=action
  assert(episode.tool==tool and episode.actor==actor)
 end
 consumer.finish=function(episode)
  assert(producer.owns(episode)and episode.source());finished[#finished+1]=episode
  assert(episode.pickup==seen[1]and episode.equip==seen[2]and episode.body==seen[3])
 end
 local callback=ISCharacterScreen.onTrimBeard
 local record={owner=ISCharacterScreen,method='onTrimBeard',callback=callback}
 local queued={};local token={}
 ISTimedActionQueue.add=function(action)
  action.toolkitQueueOperation=token;queued[#queued+1]=action;producer.observe(action)
 end
 local wrapper=function(...)return dispatcher(run,token,record,callback,...)end
 record.wrapper=wrapper;ISCharacterScreen.onTrimBeard=wrapper
 if change=='metadata-throws'then getFirstLineOfClosure=function()error('metadata unavailable')end
 elseif change=='observer-throws'then consumer.observe=function()error('observer failed')end
 elseif change=='disabled'then enabled=false
 elseif change=='p4-selected'then selected=true
 elseif change=='p4-global'then P4TidyUpMeister={}
 elseif change=='root'then tool.container=root
 elseif change=='held'then actor.primary=tool;tool.container=root
 elseif change=='helper'then ISWorldObjectContextMenu.equip=function()end
 elseif change=='extra'then
  local prior=ISTimedActionQueue.add
  ISTimedActionQueue.add=function(action)prior(action);if action.Type=='ISTrimBeard'then prior({Type='Unknown',character=actor})end end
 end
 wrapper(actor,'Moustache')
 return producer,finished,seen,queued,function()selected=true end
end
local producer,finished,seen,queued,revoke=fixture()
assert(#finished==1 and #seen==3 and #queued==3,'native menu/equip/transfer/trim chain was not qualified')
assert(queued[1].Type=='ISInventoryTransferAction'and queued[2].Type=='ISEquipWeaponAction'and queued[3].Type=='ISTrimBeard')
assert(not producer.owns(finished[1])and finished[1].source(),'synchronous ownership leaked or lasting source lease expired')
revoke();assert(not finished[1].source(),'selected P4 retained lasting source lease')
for _,case in ipairs({'disabled','p4-selected','p4-global','root','held','helper','source','extra','metadata-throws','observer-throws'})do
 local _,done,_,native=fixture(case)
 assert(#done==0,'unsupported producer earned finish: '..case)
 assert(#native>=1,'fallback lost native work: '..case)
end
print('PASS actual native beard producer, transfer/equip/body chain, private scope, source revocation and fallback')
