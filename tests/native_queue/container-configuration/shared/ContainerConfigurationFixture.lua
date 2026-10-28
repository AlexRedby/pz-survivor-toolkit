local Config=require 'PZSurvivorToolkit/QuartermasterContainerConfig'
local Appearance=require 'PZSurvivorToolkit/ContainerAppearance'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRules'
local F={module='ContainerConfigurationTest',name='QM supplies',tag='food',item='Base.Hammer'}
F.color={r=0.25,g=0.5,b=0.75,a=1}
function F.prepare(player)
 local origin=assert(player:getSquare())
 local square
 for dx=-1,1 do for dy=-1,1 do
  local candidate=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
  if not square and (dx~=0 or dy~=0) and candidate and candidate:canStand() and candidate:isFree(true)
   and candidate:getObjects():size()<=1 then square=candidate end
 end end
 assert(square,'No free adjacent fixture tile')
 local obj=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
 obj:setBlockAllTheSquare(true);obj:setIsContainer(true)
 local container=assert(obj:getContainer());container:setType('crate');container:setCapacity(100);container:setExplored(true)
 obj:getModData().PZSTContainerConfigurationFixture=true
 square:AddSpecialObject(obj)
 local item=assert(instanceItem(F.item))
 local category=assert(item:getDisplayCategory())
 if isServer() then obj:transmitCompleteItemToClients();obj:transmitModData() end
 return obj,{x=square:getX(),y=square:getY(),z=square:getZ(),index=obj:getObjectIndex(),category=category}
end
function F.resolve(packet)
 local square=getCell():getGridSquare(packet.x,packet.y,packet.z)
 if not square or packet.index>=square:getObjects():size() then return end
 local obj=square:getObjects():get(packet.index)
 if obj and obj:hasModData() and obj:getModData().PZSTContainerConfigurationFixture then return obj end
end
function F.blankRead(obj,player)
 local value=Appearance.read(obj,0,player)
 return value and not value.name and not value.icon and not value.color
end
local function count(set) local n=0;for _ in pairs(set or {})do n=n+1 end;return n end
function F.receipt(obj,player,category)
 local value=assert(Config.read(obj,0,player));local a=value.appearance or {};local icon=a.icon or {};local color=a.color or {}
 local rule=Rules.getBox(obj,0) or {}
 local groups={}
 for _,group in ipairs(rule.groups or {})do
  groups[#groups+1]={include=group.include or {},exclude=group.exclude or {}}
 end
 return {name=a.name or '',iconKind=icon.kind or '',iconValue=icon.value or '',
  r=color.r or -1,g=color.g or -1,b=color.b or -1,a=color.a or -1,
  category=category,categorySelected=value.cats[category]==true,categoryCount=count(value.cats),
  itemCount=count(value.items),presetCount=count(value.presets),priority=value.priority,
  ruleMode=rule.mode or '',include=rule.include or {},exclude=rule.exclude or {},groups=groups,
  revision=Rules.getBoxRevision(obj,0)}
end
function F.matches(receipt)
 return receipt.name==F.name and receipt.iconKind=='pzst-tag' and receipt.iconValue==F.tag
  and receipt.r==F.color.r and receipt.g==F.color.g and receipt.b==F.color.b and receipt.a==1
  and receipt.categorySelected and receipt.categoryCount==1 and receipt.itemCount==0 and receipt.presetCount==0
  and receipt.priority==6 and receipt.ruleMode=='' and #receipt.include==0 and #receipt.exclude==0
  and #receipt.groups==2
  and #receipt.groups[1].include==2 and receipt.groups[1].include[1]=='food'
  and receipt.groups[1].include[2]=='perishable' and #receipt.groups[1].exclude==1
  and receipt.groups[1].exclude[1]=='meat'
  and #receipt.groups[2].include==1 and receipt.groups[2].include[1]=='mechanics'
  and #receipt.groups[2].exclude==1 and receipt.groups[2].exclude[1]=='vehiclepart'
  and receipt.revision==1
end
function F.cleanup(obj)
 assert(obj and obj:getModData().PZSTContainerConfigurationFixture,'Refusing foreign object cleanup')
 obj:getSquare():transmitRemoveItemFromSquare(obj)
end
return F
