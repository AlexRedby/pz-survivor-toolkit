local Groups=require 'PZSurvivorToolkit/ContainerGroups'
local Config=require 'PZSurvivorToolkit/QuartermasterContainerConfig'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRules'
local F={types={'Base.BookCooking1','Base.BookCooking1','Base.BookCooking2','Base.BookCooking2','Base.BookCooking1'},
 stages={'created','joined','updated','detached','rejoined','unique'}}
function F.equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for key,value in pairs(a)do if not F.equal(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end
 return true
end
function F.configuration(stage,names)
 if stage=='blank'then return {cats={},items={},presets={},priority=0,noDuplicates=false,appearance={}}end
 local first=stage=='created'or stage=='joined'
 local localOnly=stage=='detached'
 local items={[names[1]]=true};if not localOnly then items[names[2]]=true end
 return {cats={},items=items,presets={},priority=localOnly and 4 or first and 6 or stage=='unique'and 9 or 11,
  noDuplicates=stage=='unique',appearance={name=localOnly and 'PZST local cooking'or first and 'PZST cooking group'or 'PZST shared cooking',
   icon={kind='item',value=first and 'Base.BookCooking1'or 'Base.BookCooking2'},
   color=localOnly and {r=.5,g=.75,b=.25,a=1}or first and {r=.25,g=.5,b=.75,a=1}or {r=.75,g=.25,b=.5,a=1}}}
end
function F.rule(stage)
 return {mode='all',include=(stage=='created'or stage=='joined')and {'readable'}or {'experience','readable'},exclude={'writeable'}}
end
function F.prepare(state)
 assert(not state.groupPacket,'duplicate group fixture preparation')
 local square=state.boxes[3]:getSquare()
 square=assert(getCell():getGridSquare(square:getX()+2,square:getY(),square:getZ()))
 assert(square:canStand()and square:isFree(true),'group member tile occupied')
 local box=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
 box:setBlockAllTheSquare(true);box:setIsContainer(true)
 box:getContainer():setType('crate');box:getContainer():setCapacity(100);box:getContainer():setExplored(true)
 box:getModData().PZSTDistributionFixture=true;square:AddSpecialObject(box);state.boxes[4]=box
 if isServer()then box:transmitCompleteItemToClients();box:transmitModData()end
 local ids,names={},{}
 for index,kind in ipairs(F.types)do
  local container=state.boxes[index==5 and 3 or 1]:getContainer()
  local item=assert(container:AddItem(kind));ids[index]=item:getID()
  if index==1 then names[1]=item:getDisplayName()elseif index==3 then names[2]=item:getDisplayName()end
  if isServer()then sendAddItemToContainer(container,item)end
 end
 local packet={ids=ids,types=F.types,names=names,creator=state.player:getUsername(),
  member={x=square:getX(),y=square:getY(),z=square:getZ(),index=box:getObjectIndex()}}
 state.groupPacket=packet;state.groupStage=0
 return packet
end
function F.resolve(boxes,packet)
 if not boxes[4]then
  local p=packet.member;local square=getCell():getGridSquare(p.x,p.y,p.z)
  local box=square and p.index<square:getObjects():size()and square:getObjects():get(p.index)
  if not box or not box:hasModData()or not box:getModData().PZSTDistributionFixture then return false end
  boxes[4]=box
 end
 for index,id in ipairs(packet.ids)do
  local item=boxes[index==5 and 3 or 1]:getContainer():getItemById(id)
  if not item then return false end
  assert(item:getFullType()==F.types[index],'unexpected grouped skill book type')
 end
 return true
end
local function effective(obj,player)
 local group=Groups.resolve(obj,0)
 return group and group.configuration or Config.read(obj,0,player),
  group and group.rule or Rules.getBox(obj,0)or {mode='all',include={},exclude={}}
end
function F.configurationReceipt(state,stage)
 local packet,boxes=state.groupPacket,state.boxes
 assert(F.stages[state.groupStage+1]==stage,'reordered group authority request')
 local group=assert(Groups.resolve(boxes[3],0),'source member lost group')
 if not state.groupId then state.groupId=group.id end
 local revision=(stage=='created'or stage=='joined')and 1 or stage=='unique'and 3 or 2
 assert(group.id==state.groupId and group.rev==revision and group.createdBy==packet.creator,'group identity/revision/creator differs')
 local config3,rule3=effective(boxes[3],state.player)
 local config4,rule4=effective(boxes[4],state.player)
 local sourceStage=(stage=='detached'or stage=='rejoined')and 'updated'or stage
 local targetStage=stage=='created'and 'blank'or stage
 assert(F.equal(config3,F.configuration(sourceStage,packet.names))and F.equal(rule3,F.rule(sourceStage)),
  'source group effective configuration/rule differs: '..stage)
 assert(F.equal(config4,F.configuration(targetStage,packet.names)),'target inherited/local configuration differs: '..stage)
 local targetRule=stage=='created'and {mode='all',include={},exclude={}}or F.rule(targetStage)
 assert(F.equal(rule4,targetRule),'target inherited/local rule differs: '..stage)
 local joined=stage~='created'and stage~='detached'
 assert(Groups.link(boxes[3],0)==group.id and (Groups.link(boxes[4],0)==group.id)==joined,'raw membership links differ')
 assert(Groups.canEdit(group,state.player),'creator cannot edit own group')
 state.groupStage=state.groupStage+1
 return {stage=stage,groupId=group.id,revision=revision,creator=group.createdBy,
  links={group.id,joined and group.id or false},configurations={config3,config4},rules={rule3,rule4}}
end
function F.transferReceipt(player,boxes,packet)
 local pools={boxes[1]:getContainer(),boxes[2]:getContainer(),boxes[3]:getContainer(),boxes[4]:getContainer(),player:getInventory()}
 local rows,destinations={},{}
 for index,id in ipairs(packet.ids)do
  local total,destination,item=0,nil,nil
  for target,container in ipairs(pools)do
   for i=0,container:getItems():size()-1 do
    local found=container:getItems():get(i)
    if found:getID()==id then total=total+1;destination=target;item=found end
   end
  end
  assert(total<=1,'duplicated grouped book '..id)
  if total~=1 or destination==1 or destination==5 then return end
  assert(item:getFullType()==F.types[index],'grouped book type changed')
  destinations[index]=destination;rows[index]={id=id,fullType=F.types[index],container=destination}
 end
 assert(destinations[1]==2 and destinations[2]==2 and destinations[5]==3,'existing group copy admitted a duplicate')
 assert((destinations[3]==2 and (destinations[4]==3 or destinations[4]==4))
  or (destinations[4]==2 and (destinations[3]==3 or destinations[3]==4)),'same-batch group duplicate admitted')
 local group=assert(Groups.resolve(boxes[3],0));local peer=assert(Groups.resolve(boxes[4],0))
 assert(group.id==peer.id and group.rev==3 and peer.rev==3 and group.configuration.noDuplicates,'final group configuration differs')
 return {ids=packet.ids,items=rows,groupId=group.id,groupRevision=3,memberCount=2,noDuplicates=true,
  priorities={9,5},existingGroupCopy=true,sameBatch=true,differentVolume=true,moved=4,conserved=5}
end
return F
