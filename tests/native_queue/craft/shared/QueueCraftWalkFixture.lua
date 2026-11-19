local F={}
local function uses(item)return instanceof(item,'DrainableComboItem')and item:getCurrentUses()or 0 end
local function count(container,id)
 local n=0
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  if item:getID()==id then n=n+1 end
  if instanceof(item,'InventoryContainer')then n=n+count(item:getItemContainer(),id)end
 end
 return n
end
function F.verify(state)
 local root,complete=state.root,state.case=='complete-pinned-tools'
 local material=root:getItemById(state.material:getID())
 if count(root,state.material:getID())~=(complete and 0 or 1)then return nil,'editor-off material conservation differs'end
 if not complete and (not material or material:getContainer()~=root or material:getCondition()~=state.materialCondition
  or uses(material)~=state.materialUses)then return nil,'editor-off exact input changed'end
 local outputs={}
 for id in pairs(state.outputBaseline)do
  local item=root:getItemById(id)
  if not item or item:getContainer()~=root or count(root,id)~=1 then return nil,'editor-off old output changed'end
 end
 for i=0,root:getItems():size()-1 do
  local item=root:getItems():get(i)
  if item:getFullType()=='Base.WoodenStick2'and not state.outputBaseline[item:getID()]then outputs[#outputs+1]=item:getID()end
 end
 table.sort(outputs)
 if #outputs~=(complete and 1 or 0)then return nil,'editor-off native craft output differs'end
 for _,id in ipairs(outputs)do
  if root:getItemById(id):getModData()['Base.Plank']~=1 then return nil,'editor-off output input accounting differs'end
 end
 for _,expected in ipairs(state.sparePlanks)do
  local item=root:getItemById(expected.id)
  if not item or item:getContainer()~=root or count(root,expected.id)~=1
   or item:getCondition()~=expected.condition or uses(item)~=expected.uses then return nil,'editor-off spare input changed'end
 end
 local resources,returned={},0
 for i,meta in ipairs(state.toolMeta)do
  local bag=root:getItemById(state.bags[i]:getID());local tool=root:getItemById(meta.id)
  if not bag or bag:getContainer()~=root or count(root,bag:getID())~=1 or not instanceof(bag,'InventoryContainer')
   or not tool or count(root,meta.id)~=1 or tool:getFullType()~=meta.kind
   or tool:getCondition()~=meta.condition or uses(tool)~=meta.uses then return nil,'editor-off exact tool/source changed'end
  local source=bag:getItemContainer();local blocked=state.case=='walk-pinned-full'and i==1
  local sc,rc=count(source,meta.id),tool:getContainer()==root and 1 or 0
  if sc~=(blocked and 0 or 1)or rc~=(blocked and 1 or 0)then return nil,'editor-off original tool endpoint differs'end
  if blocked and (not state.fullOrigin or source:hasRoomFor(state.player,tool))then return nil,'editor-off blocked source accepted tool'end
  resources[i]={id=meta.id,kind=meta.kind,condition=meta.condition,uses=meta.uses,
   sourceId=bag:getID(),sourceCount=sc,rootCount=rc};returned=returned+sc
 end
 return {case=state.case,materialId=state.material:getID(),materialPresent=not complete,materialCondition=state.materialCondition,
  materialUses=state.materialUses,consumed=complete and 1 or 0,outputs=#outputs,outputIds=outputs,
  toolsReturned=returned,resources=resources,sparePlanks=state.sparePlanks,fullOrigin=state.fullOrigin==true}
end
return F
